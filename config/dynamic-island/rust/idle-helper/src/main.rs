//! D-Bus part of the idle handling (`modules/services/idle/Idle.qml`).
//!
//! Lives as long as the shell (PDEATHSIG) and speaks line by line:
//!
//! stdout:
//!   ready                 we own the ScreenSaver name
//!   taken                 someone else owns it (hypridle?), retry in 10 s
//!   inhibitors <json>     [{"app", "reason"}] current Inhibit() calls
//!   sleep                 logind is about to sleep, lock now
//!   wake                  back from sleep
//!   lock                  loginctl lock-session or similar, lock now
//!
//! stdin:
//!   locked                lock is up, sleep may continue
//!   sleep-lock on|off     lock before sleeping (holds the delay inhibitor)
//!
//! `org.freedesktop.ScreenSaver`: browsers and players call `Inhibit()` while a
//! video plays. logind: a "delay" inhibitor holds sleep back until the shell has
//! locked (at most `LOCK_WAIT`), otherwise the desktop flashes up on wake.

use std::collections::BTreeMap;
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;
use tokio::time::{Instant, sleep_until};
use zbus::fdo::{DBusProxy, RequestNameFlags, RequestNameReply};
use zbus::message::Header;

use zbus::{Connection, OwnedFd, OwnedObjectPath, interface, proxy};

const NAME: &str = "org.freedesktop.ScreenSaver";
const PATHS: [&str; 2] = ["/org/freedesktop/ScreenSaver", "/ScreenSaver"];
const LOGIND: &str = "org.freedesktop.login1";
const LOCK_WAIT: Duration = Duration::from_secs(3);
const RETRY: Duration = Duration::from_secs(10);

#[proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Manager {
    fn get_session(&self, id: &str) -> zbus::Result<OwnedObjectPath>;

    #[zbus(name = "GetSessionByPID")]
    fn get_session_by_pid(&self, pid: u32) -> zbus::Result<OwnedObjectPath>;

    fn inhibit(&self, what: &str, who: &str, why: &str, mode: &str) -> zbus::Result<OwnedFd>;

    #[zbus(signal)]
    fn prepare_for_sleep(&self, start: bool) -> zbus::Result<()>;
}

#[proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1"
)]
trait Session {
    #[zbus(signal)]
    fn lock(&self) -> zbus::Result<()>;
}

/// Writes one protocol line. A closed pipe is no reason to panic: stdin EOF ends us.
fn emit(line: &str) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

struct Inhibitor {
    sender: String,
    app: String,
    reason: String,
}

/// Cookies only grow, so ascending order is also the order of the `Inhibit()` calls.
#[derive(Default)]
struct Inhibitors {
    by_cookie: BTreeMap<u32, Inhibitor>,
    last_cookie: u32,
}

impl Inhibitors {
    fn report(&self) {
        let list: Vec<_> = self
            .by_cookie
            .values()
            .map(|i| json!({"app": i.app, "reason": i.reason}))
            .collect();
        emit(&format!("inhibitors {}", json!(list)));
    }

    /// An application quit without calling `UnInhibit`.
    fn drop_sender(&mut self, sender: &str) {
        let before = self.by_cookie.len();
        self.by_cookie.retain(|_, i| i.sender != sender);
        if self.by_cookie.len() != before {
            self.report();
        }
    }
}

struct ScreenSaver {
    inhibitors: Arc<Mutex<Inhibitors>>,
}

fn sender_of(header: &Header<'_>) -> String {
    header.sender().map(ToString::to_string).unwrap_or_default()
}

#[interface(name = "org.freedesktop.ScreenSaver")]
impl ScreenSaver {
    fn inhibit(&self, app: String, reason: String, #[zbus(header)] header: Header<'_>) -> u32 {
        let mut state = self.inhibitors.lock().unwrap();
        state.last_cookie += 1;
        let cookie = state.last_cookie;
        let sender = sender_of(&header);
        state.by_cookie.insert(
            cookie,
            Inhibitor {
                sender,
                app,
                reason,
            },
        );
        state.report();
        cookie
    }

    #[zbus(name = "UnInhibit")]
    fn un_inhibit(&self, cookie: u32, #[zbus(header)] header: Header<'_>) {
        let mut state = self.inhibitors.lock().unwrap();
        let sender = sender_of(&header);
        if state
            .by_cookie
            .get(&cookie)
            .is_some_and(|i| i.sender == sender)
        {
            state.by_cookie.remove(&cookie);
            state.report();
        }
    }

    fn get_active(&self) -> bool {
        false
    }

    fn get_active_time(&self) -> u32 {
        0
    }

    fn get_session_idle_time(&self) -> u32 {
        0
    }

    fn simulate_user_activity(&self) {}
}

/// Tries to get the ScreenSaver name, returns true if we own it now.
async fn claim(session: &Connection) -> bool {
    let reply = session
        .request_name_with_flags(NAME, RequestNameFlags::DO_NOT_QUEUE)
        .await;
    let owned = matches!(
        reply,
        Ok(RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner)
    );
    emit(if owned { "ready" } else { "taken" });
    owned
}

/// The delay inhibitor and the timer that gives it up if the shell never reports back.
struct SleepDelay {
    enabled: bool,
    fd: Option<OwnedFd>,
    release_at: Option<Instant>,
}

impl SleepDelay {
    async fn take(&mut self, manager: &ManagerProxy<'_>) {
        if self.fd.is_some() || !self.enabled {
            return;
        }
        match manager
            .inhibit(
                "sleep",
                "dynamic-island",
                "Vor dem Ruhezustand sperren",
                "delay",
            )
            .await
        {
            Ok(fd) => self.fd = Some(fd),
            Err(e) => eprintln!("idlehelper: Inhibit gescheitert: {e}"),
        }
    }

    fn release(&mut self) {
        self.release_at = None;
        self.fd = None;
    }
}

/// Sends every stdin line on, ends with EOF. A separate task, because reading a
/// line must not be cancelled half way by the `select!` in `main`.
fn read_stdin() -> mpsc::UnboundedReceiver<String> {
    let (tx, rx) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        let mut stdin = BufReader::new(tokio::io::stdin());
        let mut line = Vec::new();
        loop {
            line.clear();
            match stdin.read_until(b'\n', &mut line).await {
                Ok(1..) => {
                    if tx
                        .send(String::from_utf8_lossy(&line).trim().to_owned())
                        .is_err()
                    {
                        return;
                    }
                }
                _ => return,
            }
        }
    });
    rx
}

async fn run() -> zbus::Result<()> {
    let session = Connection::session().await?;
    let system = Connection::system().await?;
    let inhibitors = Arc::new(Mutex::new(Inhibitors::default()));

    let bus = DBusProxy::new(&session).await?;
    let mut owner_changes = bus.receive_name_owner_changed().await?;

    // The objects come first, so nobody who sees the name gets "unknown object".
    for path in PATHS {
        let object = ScreenSaver {
            inhibitors: inhibitors.clone(),
        };
        session.object_server().at(path, object).await?;
    }
    let mut retry_at = (!claim(&session).await).then(|| Instant::now() + RETRY);

    // Without logind there is nothing we could do. Exiting lets Idle.qml try again.
    let system_bus = DBusProxy::new(&system).await?;
    if system_bus.get_name_owner(LOGIND.try_into()?).await.is_err() {
        system_bus
            .start_service_by_name(LOGIND.try_into()?, 0)
            .await?;
    }
    let manager = ManagerProxy::new(&system).await?;
    let mut prepare = manager.receive_prepare_for_sleep().await?;

    let session_path = match std::env::var("XDG_SESSION_ID") {
        Ok(id) if !id.is_empty() => manager.get_session(&id).await,
        _ => manager.get_session_by_pid(std::process::id()).await,
    };
    let mut lock = match session_path {
        Ok(path) => {
            let proxy = SessionProxy::builder(&system).path(path).build().await?;
            Some(proxy.receive_lock().await?)
        }
        Err(e) => {
            eprintln!("idlehelper: Session nicht gefunden: {e}");
            None
        }
    };

    let mut delay = SleepDelay {
        enabled: false,
        fd: None,
        release_at: None,
    };
    let mut lines = read_stdin();
    let mut terminate = signal(SignalKind::terminate()).map_err(zbus::Error::from)?;

    loop {
        tokio::select! {
            _ = terminate.recv() => return Ok(()),
            line = lines.recv() => match line.as_deref() {
                None => return Ok(()),
                Some("locked") => delay.release(),
                Some("sleep-lock on") => {
                    delay.enabled = true;
                    delay.take(&manager).await;
                }
                Some("sleep-lock off") => {
                    delay.enabled = false;
                    delay.release();
                }
                Some(_) => {}
            },
            Some(change) = owner_changes.next() => {
                let args = change.args()?;
                if args.new_owner().is_none() && args.name().starts_with(':') {
                    inhibitors.lock().unwrap().drop_sender(args.name());
                }
            }
            Some(signal) = prepare.next() => {
                if signal.args()?.start {
                    emit("sleep");
                    // Several signals in a row: the first deadline stays, sleep is already waiting.
                    if delay.fd.is_some() && delay.release_at.is_none() {
                        delay.release_at = Some(Instant::now() + LOCK_WAIT);
                    }
                } else {
                    emit("wake");
                    delay.take(&manager).await;
                }
            }
            Some(_) = next_or_pending(&mut lock) => emit("lock"),
            () = wait_until(delay.release_at) => delay.release(),
            () = wait_until(retry_at) => {
                retry_at = (!claim(&session).await).then(|| Instant::now() + RETRY);
            }
        }
    }
}

async fn next_or_pending<S: futures_util::Stream + Unpin>(
    stream: &mut Option<S>,
) -> Option<S::Item> {
    match stream {
        Some(stream) => stream.next().await,
        None => std::future::pending().await,
    }
}

async fn wait_until(deadline: Option<Instant>) {
    match deadline {
        Some(at) => sleep_until(at).await,
        None => std::future::pending().await,
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Die with the shell, otherwise an orphan would keep the ScreenSaver name.
    // SAFETY: prctl with these arguments only sets a flag on this process.
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }
    let code = match run().await {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("dynamic-island-idle: {e}");
            1
        }
    };
    // Dropping the runtime would wait for the blocking stdin read, which never ends by itself.
    std::process::exit(code);
}

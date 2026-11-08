//! BlueZ `Agent1` bridge: newline-delimited JSON on stdin and stdout.
//!
//! `BluetoothService.qml` starts it while an adapter is on. Requests from BlueZ
//! wait here until the shell answers, so a method call may stay open for a long time.

use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::oneshot;
use tokio::time::timeout;
use zbus::fdo::DBusProxy;
use zbus::names::BusName;

use zbus::{Connection, DBusError, ObjectPath, OwnedObjectPath, interface};

const BLUEZ: &str = "org.bluez";
const PATH: &str = "/org/quickshell/BluetoothAgent";
const PAIR_TIMEOUT: Duration = Duration::from_secs(90);
const REGISTER_TIMEOUT: Duration = Duration::from_secs(5);
/// Gives the task of a rejected call the time to send its answer before we exit.
const REPLY_GRACE: Duration = Duration::from_millis(50);

#[derive(Debug, DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
}

fn rejected(message: &str) -> AgentError {
    AgentError::Rejected(message.to_owned())
}

enum Answer {
    Accept,
    Pin(String),
    Passkey(u32),
}

/// A request from BlueZ that waits for the shell. Dropping `reply` rejects it.
struct Pending {
    kind: &'static str,
    reply: oneshot::Sender<Answer>,
}

#[derive(Default)]
struct State {
    pending: Option<Pending>,
    active_path: String,
    generation: u64,
    ready: bool,
}

impl State {
    fn reject(&mut self) {
        self.pending = None;
    }

    /// Display requests are also refused while another device is pairing.
    fn check_device(&self, device: &str) -> Result<(), AgentError> {
        if !self.active_path.is_empty() && self.active_path != device {
            return Err(rejected("Another device is pairing"));
        }
        Ok(())
    }
}

/// Writes one event. A closed pipe is no reason to panic: stdin EOF ends us.
fn emit(event: &Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{event}");
    let _ = out.flush();
}

fn emit_ready(ready: bool) {
    emit(&json!({"event": "ready", "ready": ready}));
}

/// Same wording as GDBus, the shell shows this text to the user.
fn describe(error: &zbus::Error) -> String {
    match error {
        zbus::Error::MethodError(name, description, _) => {
            format!(
                "GDBus.Error:{name}: {}",
                description.as_deref().unwrap_or("")
            )
        }
        zbus::Error::FDO(fdo) => {
            format!(
                "GDBus.Error:{}: {}",
                fdo.name(),
                fdo.description().unwrap_or("")
            )
        }
        other => other.to_string(),
    }
}

#[derive(Clone)]
struct Agent {
    state: Arc<Mutex<State>>,
}

impl Agent {
    /// Registers a request and waits for the answer of the shell.
    async fn ask(
        &self,
        kind: &'static str,
        device: &str,
        passkey: String,
        service: &str,
    ) -> Result<Answer, AgentError> {
        let waiting = {
            let mut state = self.state.lock().unwrap();
            state.check_device(device)?;
            if state.pending.is_some() {
                return Err(rejected("Another request is pending"));
            }
            let (reply, waiting) = oneshot::channel();
            state.pending = Some(Pending { kind, reply });
            emit(
                &json!({"event": "request", "kind": kind, "path": device, "passkey": passkey, "service": service}),
            );
            waiting
        };
        waiting.await.map_err(|_| rejected("Rejected by user"))
    }

    fn display(&self, device: &str, passkey: String, entered: u16) -> Result<(), AgentError> {
        self.state.lock().unwrap().check_device(device)?;
        emit(
            &json!({"event": "request", "kind": "display", "path": device, "passkey": passkey, "entered": entered}),
        );
        Ok(())
    }
}

#[interface(name = "org.bluez.Agent1")]
impl Agent {
    fn release(&self) {
        let mut state = self.state.lock().unwrap();
        state.reject();
        state.ready = false;
        emit_ready(false);
        emit(&json!({"event": "canceled"}));
    }

    fn cancel(&self) {
        self.state.lock().unwrap().reject();
        emit(&json!({"event": "canceled"}));
    }

    async fn request_pin_code(&self, device: OwnedObjectPath) -> Result<String, AgentError> {
        match self.ask("pin", device.as_str(), String::new(), "").await? {
            Answer::Pin(pin) => Ok(pin),
            _ => Err(rejected("Rejected by user")),
        }
    }

    async fn request_passkey(&self, device: OwnedObjectPath) -> Result<u32, AgentError> {
        match self
            .ask("passkey", device.as_str(), String::new(), "")
            .await?
        {
            Answer::Passkey(passkey) => Ok(passkey),
            _ => Err(rejected("Rejected by user")),
        }
    }

    async fn request_confirmation(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> Result<(), AgentError> {
        self.ask("confirm", device.as_str(), format!("{passkey:06}"), "")
            .await
            .map(drop)
    }

    async fn request_authorization(&self, device: OwnedObjectPath) -> Result<(), AgentError> {
        self.ask("authorize", device.as_str(), String::new(), "")
            .await
            .map(drop)
    }

    async fn authorize_service(
        &self,
        device: OwnedObjectPath,
        uuid: String,
    ) -> Result<(), AgentError> {
        self.ask("authorize", device.as_str(), String::new(), &uuid)
            .await
            .map(drop)
    }

    fn display_pin_code(&self, device: OwnedObjectPath, pin: String) -> Result<(), AgentError> {
        self.display(device.as_str(), pin, 0)
    }

    fn display_passkey(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
        entered: u16,
    ) -> Result<(), AgentError> {
        self.display(device.as_str(), format!("{passkey:06}"), entered)
    }
}

/// What the old Python helper took as false: the shell only ever sends booleans.
fn is_truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

fn text_of(value: Option<&Value>) -> String {
    match value {
        None => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
    }
}

/// 1 to 16 bytes, as BlueZ expects.
fn parse_pin(value: &str) -> Option<String> {
    ((1..=16).contains(&value.len()) && !value.contains('\0')).then(|| value.to_owned())
}

/// 1 to 6 ASCII digits.
fn parse_passkey(value: &str) -> Option<u32> {
    if !(1..=6).contains(&value.len()) || !value.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    value.parse().ok()
}

async fn device_call(
    conn: &Connection,
    path: &str,
    method: &str,
    wait: Option<Duration>,
) -> Result<(), String> {
    let path = ObjectPath::try_from(path).map_err(|e| e.to_string())?;
    let call = conn.call_method(Some(BLUEZ), &path, Some("org.bluez.Device1"), method, &());
    let reply = match wait {
        Some(limit) => timeout(limit, call)
            .await
            .map_err(|_| "Timeout was reached".to_owned())?,
        None => call.await,
    };
    reply.map(drop).map_err(|e| describe(&e))
}

fn start_pairing(conn: &Connection, agent: &Agent, path: String) {
    let generation = {
        let mut state = agent.state.lock().unwrap();
        state.active_path.clone_from(&path);
        state.generation += 1;
        state.generation
    };
    let conn = conn.clone();
    let agent = agent.clone();
    tokio::spawn(async move {
        let result = device_call(&conn, &path, "Pair", Some(PAIR_TIMEOUT)).await;
        let mut state = agent.state.lock().unwrap();
        // A cancel or a BlueZ restart in between: this result no longer interests anyone.
        if state.generation != generation {
            return;
        }
        state.active_path.clear();
        match result {
            Ok(()) => emit(&json!({"event": "paired", "path": path, "message": ""})),
            Err(message) => emit(&json!({"event": "error", "path": path, "message": message})),
        }
    });
}

fn respond(agent: &Agent, data: &Value) {
    let mut state = agent.state.lock().unwrap();
    let Some(kind) = state.pending.as_ref().map(|p| p.kind) else {
        return;
    };
    if !data.get("accept").is_none_or(is_truthy) {
        state.reject();
        return;
    }
    let value = text_of(data.get("value"));
    let answer = match kind {
        "pin" => match parse_pin(&value) {
            Some(pin) => Answer::Pin(pin),
            None => {
                emit(
                    &json!({"event": "input-error", "kind": "pin", "message": "PIN muss 1–16 Bytes lang sein"}),
                );
                return;
            }
        },
        "passkey" => match parse_passkey(&value) {
            Some(passkey) => Answer::Passkey(passkey),
            None => {
                let message = "Passkey muss aus 1–6 Ziffern bestehen";
                emit(&json!({"event": "input-error", "kind": "passkey", "message": message}));
                return;
            }
        },
        _ => Answer::Accept,
    };
    if let Some(pending) = state.pending.take() {
        let _ = pending.reply.send(answer);
    }
}

fn command(conn: &Connection, agent: &Agent, line: &[u8]) {
    let data: Value = match serde_json::from_slice(line) {
        Ok(data) => data,
        Err(e) => {
            emit(&json!({"event": "error", "message": e.to_string()}));
            return;
        }
    };
    match data.get("action").and_then(Value::as_str) {
        Some("pair") => {
            let Some(path) = data.get("path") else {
                emit(&json!({"event": "error", "message": "'path'"}));
                return;
            };
            let busy = {
                let state = agent.state.lock().unwrap();
                !state.ready || !state.active_path.is_empty() || state.pending.is_some()
            };
            if busy {
                let message = "Bluetooth-Agent ist nicht bereit oder beschäftigt";
                emit(&json!({"event": "error", "path": path, "message": message}));
                return;
            }
            start_pairing(conn, agent, text_of(Some(path)));
        }
        Some("respond") => respond(agent, &data),
        Some("cancel") => {
            let path = {
                let mut state = agent.state.lock().unwrap();
                let path = if state.active_path.is_empty() {
                    text_of(data.get("path"))
                } else {
                    std::mem::take(&mut state.active_path)
                };
                state.reject();
                state.generation += 1;
                path
            };
            if !path.is_empty() {
                let conn = conn.clone();
                tokio::spawn(async move {
                    let _ = device_call(&conn, &path, "CancelPairing", None).await;
                });
            }
        }
        _ => {}
    }
}

async fn register(conn: &Connection) -> zbus::Result<()> {
    let manager = (Some(BLUEZ), "/org/bluez", Some("org.bluez.AgentManager1"));
    let path = ObjectPath::try_from(PATH)?;
    let limit = |e: tokio::time::error::Elapsed| zbus::Error::Failure(e.to_string());
    timeout(
        REGISTER_TIMEOUT,
        conn.call_method(
            manager.0,
            manager.1,
            manager.2,
            "RegisterAgent",
            &(&path, "KeyboardDisplay"),
        ),
    )
    .await
    .map_err(limit)??;
    timeout(
        REGISTER_TIMEOUT,
        conn.call_method(
            manager.0,
            manager.1,
            manager.2,
            "RequestDefaultAgent",
            &(&path,),
        ),
    )
    .await
    .map_err(limit)??;
    Ok(())
}

async fn appeared(conn: &Connection, agent: &Agent) {
    match register(conn).await {
        Ok(()) => {
            agent.state.lock().unwrap().ready = true;
            emit_ready(true);
        }
        Err(e) => {
            agent.state.lock().unwrap().ready = false;
            emit_ready(false);
            emit(&json!({"event": "error", "message": describe(&e)}));
        }
    }
}

fn vanished(agent: &Agent) {
    let mut state = agent.state.lock().unwrap();
    state.ready = false;
    state.reject();
    state.active_path.clear();
    state.generation += 1;
    emit_ready(false);
}

/// Follows BlueZ: registers whenever it appears, like `g_bus_watch_name`.
async fn watch_bluez(conn: Connection, agent: Agent) -> zbus::Result<()> {
    let bus = DBusProxy::new(&conn).await?;
    let mut changes = bus
        .receive_name_owner_changed_with_args(&[(0, BLUEZ)])
        .await?;
    let name = BusName::try_from(BLUEZ)?;
    if bus.get_name_owner(name).await.is_ok() {
        appeared(&conn, &agent).await;
    } else {
        vanished(&agent);
    }
    while let Some(change) = changes.next().await {
        let args = change.args()?;
        if args.old_owner().is_some() {
            vanished(&agent);
        }
        if args.new_owner().is_some() {
            appeared(&conn, &agent).await;
        }
    }
    Ok(())
}

async fn run() -> zbus::Result<()> {
    let conn = Connection::system().await?;
    let agent = Agent {
        state: Arc::default(),
    };
    conn.object_server().at(PATH, agent.clone()).await?;

    let watcher = tokio::spawn(watch_bluez(conn.clone(), agent.clone()));

    let mut stdin = BufReader::new(tokio::io::stdin());
    let mut line = Vec::new();
    loop {
        line.clear();
        let read = stdin.read_until(b'\n', &mut line).await.unwrap_or(0);
        // EOF, a last line without newline was never finished
        if read == 0 || line.last() != Some(&b'\n') {
            break;
        }
        line.pop();
        command(&conn, &agent, &line);
    }

    agent.state.lock().unwrap().reject();
    watcher.abort();
    tokio::time::sleep(REPLY_GRACE).await;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let code = match run().await {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{e}");
            1
        }
    };
    // Dropping the runtime would wait for blocking tasks, nothing is left to do here.
    std::process::exit(code);
}

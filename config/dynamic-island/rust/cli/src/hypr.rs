//! Requests to Hyprland through its socket, see `utils/hypr.py`.

use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use serde_json::Value;

fn socket_path() -> String {
    let part = |name: &str| env::var(name).unwrap_or_else(|_| "None".to_owned());
    format!(
        "{}/hypr/{}/.socket.sock",
        part("XDG_RUNTIME_DIR"),
        part("HYPRLAND_INSTANCE_SIGNATURE")
    )
}

/// Sends a JSON request. Without the timeout the CLI would hang during a theme
/// change as long as Hyprland does not answer, for example during a config reload.
pub fn message(msg: &str) -> Result<Value, String> {
    let mut socket = UnixStream::connect(socket_path()).map_err(|e| format!("Hyprland: {e}"))?;
    let timeout = Some(Duration::from_secs(3));
    socket
        .set_read_timeout(timeout)
        .map_err(|e| e.to_string())?;
    socket
        .set_write_timeout(timeout)
        .map_err(|e| e.to_string())?;
    socket
        .write_all(format!("j/{msg}").as_bytes())
        .map_err(|e| format!("Hyprland: {e}"))?;
    let mut answer = Vec::new();
    socket
        .read_to_end(&mut answer)
        .map_err(|e| format!("Hyprland: {e}"))?;
    serde_json::from_slice(&answer).map_err(|e| format!("Hyprland: {e}"))
}

pub fn is_lua_config() -> bool {
    message("status")
        .is_ok_and(|status| status.get("configProvider").and_then(Value::as_str) == Some("lua"))
}

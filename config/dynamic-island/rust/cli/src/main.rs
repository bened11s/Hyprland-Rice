//! Front of the `dynamic-island` command.
//!
//! Only what is ported runs here. Everything else, every help text and every
//! input we do not understand goes to the Python CLI unchanged, so its behaviour
//! stays what it was.

mod colours;
mod hypr;
mod plugin;
mod theme;

use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;

use clap::Parser;
use di_common::paths;

/// The Python CLI: where the variable points to, next to this binary, or in the config.
pub fn python_cli() -> PathBuf {
    if let Some(cli) = std::env::var_os("DYNAMIC_ISLAND_PYTHON_CLI") {
        return cli.into();
    }
    let sibling = std::env::current_exe()
        .ok()
        .map(|exe| exe.with_file_name("dynamic-island"));
    sibling
        .filter(|cli| cli.is_file())
        .unwrap_or_else(|| paths::c_config_dir().join("bin/dynamic-island"))
}

fn run_python(args: &[OsString]) -> ! {
    let cli = python_cli();
    let error = Command::new(&cli).arg0("dynamic-island").args(args).exec();
    eprintln!("dynamic-island: {} startet nicht: {error}", cli.display());
    std::process::exit(127);
}

/// The exit code if this command is ours. None means Python takes it: not ported,
/// a help text, or something clap does not accept (like an abbreviated option).
fn run_native(args: &[OsString]) -> Option<i32> {
    let command = args.first()?.to_str()?;
    // An empty value is a special case in argparse, Python knows what to do.
    if args.iter().any(|a| a.is_empty()) {
        return None;
    }
    let tail = || args.iter().cloned();
    match command {
        "plugin" => {
            let cli = plugin::Cli::try_parse_from(tail()).ok()?;
            (!cli.action.uses_tilde_user()).then(|| plugin::run(&cli.action))
        }
        "scheme" => {
            let cli = colours::SchemeCli::try_parse_from(tail()).ok()?;
            cli.is_valid().then(|| finish(colours::run_scheme(&cli)))
        }
        "wallpaper" => {
            let cli = colours::WallpaperCli::try_parse_from(tail()).ok()?;
            cli.is_valid().then(|| finish(colours::run_wallpaper(&cli)))
        }
        _ => None,
    }
}

fn finish(result: Result<(), String>) -> i32 {
    match result {
        Ok(()) => 0,
        Err(message) => {
            eprintln!("dynamic-island: {message}");
            1
        }
    }
}

fn main() {
    // A closed pipe (`dynamic-island plugin list | head`) ends us quietly.
    // SAFETY: called before any other thread exists, SIG_DFL needs no handler.
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }

    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    if let Some(code) = run_native(&args) {
        std::process::exit(code);
    }
    run_python(&args);
}

//! What the Rust helpers share with the Python CLI: paths, JSON format, hash index.
//!
//! Files written here are also read by Python and QML. Their format is therefore
//! kept byte for byte, which is why `pyjson` exists instead of serde's printer.

pub mod fsutil;
pub mod hash;
pub mod paths;
pub mod pyjson;

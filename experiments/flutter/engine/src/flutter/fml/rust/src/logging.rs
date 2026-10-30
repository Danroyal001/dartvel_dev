// Partial port of flutter/fml/logging.h and flutter/fml/logging.cc: the
// message format of LogMessage on desktop targets, written to stderr. Log
// settings, capture for tests, the Android/iOS/Fuchsia sinks and FATAL's
// abort are not ported yet.

pub type LogSeverity = i32;

pub const K_LOG_INFO: LogSeverity = 0;
pub const K_LOG_WARNING: LogSeverity = 1;
pub const K_LOG_ERROR: LogSeverity = 2;
pub const K_LOG_IMPORTANT: LogSeverity = 3;
pub const K_LOG_FATAL: LogSeverity = 4;
const K_LOG_NUM_SEVERITIES: LogSeverity = 5;

const K_LOG_SEVERITY_NAMES: [&str; K_LOG_NUM_SEVERITIES as usize] =
    ["INFO", "WARNING", "ERROR", "IMPORTANT", "FATAL"];

fn get_name_for_log_severity(severity: LogSeverity) -> &'static str {
    if (K_LOG_INFO..K_LOG_NUM_SEVERITIES).contains(&severity) {
        return K_LOG_SEVERITY_NAMES[severity as usize];
    }
    "UNKNOWN"
}

fn strip_dots(mut path: &str) -> &str {
    while let Some(rest) = path.strip_prefix("../") {
        path = rest;
    }
    path
}

/// Formats and writes one log line, as `LogMessage`'s constructor and
/// destructor do together.
pub fn log_message(severity: LogSeverity, file: &str, line: u32, message: std::fmt::Arguments<'_>) {
    let mut stream = String::from("[");
    if severity >= K_LOG_INFO {
        stream.push_str(get_name_for_log_severity(severity));
    } else {
        stream.push_str(&format!("VERBOSE{}", -severity));
    }
    stream.push_str(&format!(":{}({})] {}\n", strip_dots(file), line, message));
    use std::io::Write;
    let _ = std::io::stderr().write_all(stream.as_bytes());
}

/// `FML_LOG(severity) << ...` at a given upstream location. Ported files pass
/// the file and line of the upstream statement, so their logs read as
/// upstream's do.
#[macro_export]
macro_rules! fml_log_at {
    ($severity:ident, $file:expr, $line:expr, $($arg:tt)*) => {
        $crate::logging::log_message(
            $crate::logging::$severity, $file, $line, format_args!($($arg)*))
    };
}

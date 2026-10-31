// Port of flutter/fml/logging.h and flutter/fml/logging.cc: LogMessage, log
// capture for tests, the verbosity and severity gates, KillProcess, and the
// macros.
//
// The C++ macros stream into `LogMessage::stream()`; here they take
// `format!`-style arguments, and the `_at` forms take the upstream file and
// line, so that a ported file logs exactly what the C++ does (the oracle
// compares stderr byte for byte). A `FATAL` message, a failed `fml_check!`
// and `fml_unreachable!` write their line and then abort the process, as
// upstream does; they do not panic.
//
// Only the desktop sink (stderr) is ported. The Android (`__android_log_write`),
// iOS (`syslog`) and Fuchsia (structured logger) sinks are not.

use std::cell::RefCell;
use std::fmt::Write as _;
use std::rc::Rc;

pub use crate::log_level::*;
use crate::log_settings::get_min_log_level;

const K_LOG_SEVERITY_NAMES: [&str; kLogNumSeverities as usize] =
    ["INFO", "WARNING", "ERROR", "IMPORTANT", "FATAL"];

fn get_name_for_log_severity(severity: LogSeverity) -> &'static str {
    if (kLogInfo..kLogNumSeverities).contains(&severity) {
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

/// A capture target: `std::ostringstream*` upstream.
pub type CaptureStream = Rc<RefCell<String>>;

thread_local! {
    static CAPTURE_NEXT_LOG_STREAM: RefCell<Option<CaptureStream>> = const { RefCell::new(None) };
}

pub mod testing {
    use super::*;

    /// Captures the next log message on this thread, as long as it lives.
    pub struct LogCapture {
        stream_: CaptureStream,
    }

    impl Default for LogCapture {
        fn default() -> Self {
            Self::new()
        }
    }

    impl LogCapture {
        pub fn new() -> Self {
            let stream_ = CaptureStream::default();
            LogMessage::capture_next_log(Some(stream_.clone()));
            LogCapture { stream_ }
        }

        pub fn str(&self) -> String {
            self.stream_.borrow().clone()
        }
    }

    impl Drop for LogCapture {
        fn drop(&mut self) {
            LogMessage::capture_next_log(None);
        }
    }
}

pub struct LogMessage {
    stream_: String,
    severity_: LogSeverity,
}

impl LogMessage {
    pub fn new(severity: LogSeverity, file: &str, line: i32, condition: Option<&str>) -> Self {
        let file_ = strip_dots(file);
        let mut stream_ = String::from("[");
        if severity >= kLogInfo {
            stream_.push_str(get_name_for_log_severity(severity));
        } else {
            let _ = write!(stream_, "VERBOSE{}", severity.wrapping_neg());
        }
        let _ = write!(stream_, ":{file_}({line})] ");
        if let Some(condition) = condition {
            let _ = write!(stream_, "Check failed: {condition}. ");
        }
        LogMessage { stream_, severity_: severity }
    }

    pub fn stream(&mut self) -> &mut String {
        &mut self.stream_
    }

    /// Sets a stream to capture the next log message on this thread, or
    /// clears it with `None`.
    pub fn capture_next_log(stream: Option<CaptureStream>) {
        CAPTURE_NEXT_LOG_STREAM.with(|s| *s.borrow_mut() = stream);
    }
}

impl Drop for LogMessage {
    fn drop(&mut self) {
        self.stream_.push('\n');
        let captured = CAPTURE_NEXT_LOG_STREAM.with(|s| s.borrow_mut().take());
        if let Some(capture) = captured {
            capture.borrow_mut().push_str(&self.stream_);
        } else {
            use std::io::Write;
            let mut stderr = std::io::stderr().lock();
            let _ = stderr.write_all(self.stream_.as_bytes());
            let _ = stderr.flush();
        }
        if self.severity_ >= kLogFatal {
            kill_process();
        }
    }
}

/// Gets the FML_VLOG default verbosity level.
pub fn get_vlog_verbosity() -> i32 {
    (-1).max(kLogInfo - get_min_log_level())
}

/// Returns true if |severity| is at or above the current minimum log level.
/// kLogFatal and above is always true.
pub fn should_create_log_message(severity: LogSeverity) -> bool {
    severity >= get_min_log_level()
}

/// Kills the process: `abort()`.
pub fn kill_process() -> ! {
    std::process::abort()
}

/// `FML_LOG(severity) << ...` as written at an upstream location: ported files
/// pass the file and line of the upstream statement, so their logs read as
/// upstream's do. `severity` is a `log_level` constant (`kLogWarning`).
#[macro_export]
macro_rules! fml_log_at {
    ($severity:ident, $file:expr, $line:expr, $($arg:tt)*) => {
        if $crate::logging::should_create_log_message($crate::log_level::$severity) {
            let mut message =
                $crate::logging::LogMessage::new($crate::log_level::$severity, $file, $line, None);
            let _ = ::std::fmt::Write::write_fmt(message.stream(), format_args!($($arg)*));
        }
    };
}

/// `FML_LOG(severity)` at the Rust caller's location.
#[macro_export]
macro_rules! fml_log {
    ($severity:ident, $($arg:tt)*) => {
        $crate::fml_log_at!($severity, file!(), line!() as i32, $($arg)*)
    };
}

/// `FML_DLOG`: `FML_LOG` in debug builds; nothing (and nothing evaluated) in
/// release builds.
#[macro_export]
macro_rules! fml_dlog_at {
    ($severity:ident, $file:expr, $line:expr, $($arg:tt)*) => {
        if cfg!(debug_assertions) {
            $crate::fml_log_at!($severity, $file, $line, $($arg)*);
        }
    };
}

/// `FML_VLOG(verbose_level) << ...`, logged at severity `-verbose_level`
/// when `verbose_level <= get_vlog_verbosity()`.
#[macro_export]
macro_rules! fml_vlog_at {
    ($level:expr, $file:expr, $line:expr, $($arg:tt)*) => {
        if ($level) <= $crate::logging::get_vlog_verbosity() {
            let mut message = $crate::logging::LogMessage::new(-($level), $file, $line, None);
            let _ = ::std::fmt::Write::write_fmt(message.stream(), format_args!($($arg)*));
        }
    };
}

/// `FML_CHECK(condition) << ...` as written at an upstream location; the
/// condition's text is passed as upstream stringizes it. A failed check logs
/// at FATAL and aborts.
#[macro_export]
macro_rules! fml_check_at {
    ($file:expr, $line:expr, $text:expr, $cond:expr) => {
        $crate::fml_check_at!($file, $line, $text, $cond, "")
    };
    ($file:expr, $line:expr, $text:expr, $cond:expr, $($arg:tt)*) => {
        if !($cond) {
            let mut message =
                $crate::logging::LogMessage::new($crate::log_level::kLogFatal, $file, $line, Some($text));
            let _ = ::std::fmt::Write::write_fmt(message.stream(), format_args!($($arg)*));
            drop(message);
            unreachable!();
        }
    };
}

/// `FML_DCHECK`: `FML_CHECK` in debug builds; nothing (and the condition not
/// evaluated) in release builds.
#[macro_export]
macro_rules! fml_dcheck_at {
    ($file:expr, $line:expr, $text:expr, $cond:expr) => {
        $crate::fml_dcheck_at!($file, $line, $text, $cond, "")
    };
    ($file:expr, $line:expr, $text:expr, $cond:expr, $($arg:tt)*) => {
        if cfg!(debug_assertions) {
            $crate::fml_check_at!($file, $line, $text, $cond, $($arg)*);
        }
    };
}

/// `FML_UNREACHABLE()`: logs "Reached unreachable code." at ERROR and kills
/// the process.
#[macro_export]
macro_rules! fml_unreachable_at {
    ($file:expr, $line:expr) => {{
        $crate::fml_log_at!(kLogError, $file, $line, "Reached unreachable code.");
        $crate::logging::kill_process()
    }};
}

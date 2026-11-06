// Port of flutter/fml/log_level.h.

pub type LogSeverity = i32;

// Default log levels. Negative values can be used for verbose log levels.
#[allow(non_upper_case_globals)]
pub const kLogInfo: LogSeverity = 0;
#[allow(non_upper_case_globals)]
pub const kLogWarning: LogSeverity = 1;
#[allow(non_upper_case_globals)]
pub const kLogError: LogSeverity = 2;
// A log that is not an error, is important enough to display even if ordinary
// info is hidden.
#[allow(non_upper_case_globals)]
pub const kLogImportant: LogSeverity = 3;
#[allow(non_upper_case_globals)]
pub const kLogFatal: LogSeverity = 4;
#[allow(non_upper_case_globals)]
pub const kLogNumSeverities: LogSeverity = 5;

// DEPRECATED: Use |kLogInfo|.
// Ensure compatibility with glog style macro names.
pub const LOG_INFO: LogSeverity = kLogInfo;
pub const LOG_WARNING: LogSeverity = kLogWarning;
pub const LOG_ERROR: LogSeverity = kLogError;
pub const LOG_IMPORTANT: LogSeverity = kLogImportant;
pub const LOG_FATAL: LogSeverity = kLogFatal;

/// `LOG_DFATAL` is `LOG_FATAL` in debug mode, `LOG_ERROR` in normal mode.
#[allow(non_upper_case_globals)]
pub const kLogDFatal: LogSeverity = if cfg!(debug_assertions) { kLogFatal } else { kLogError };
pub const LOG_DFATAL: LogSeverity = kLogDFatal;

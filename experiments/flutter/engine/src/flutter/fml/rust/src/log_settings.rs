// Port of flutter/fml/log_settings.h, flutter/fml/log_settings.cc and
// flutter/fml/log_settings_state.cc.
//
// `state::g_log_settings` is a plain global struct upstream, read by every
// FML_LOG on any thread; its one field is an atomic here (relaxed, as the
// plain int is in practice).

use std::sync::atomic::{AtomicI32, Ordering};

use crate::log_level::{LogSeverity, kLogFatal, kLogInfo};

/// Settings which control the behavior of FML logging.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LogSettings {
    /// The minimum logging level.
    /// Anything at or above this level will be logged (if applicable).
    /// Anything below this level will be silently ignored.
    ///
    /// The log level defaults to 0 (kLogInfo).
    ///
    /// Log messages for FML_VLOG(x) (from flutter/fml/logging.h) are logged
    /// at level -x, so setting the min log level to negative values enables
    /// verbose logging.
    pub min_log_level: LogSeverity,
}

impl Default for LogSettings {
    fn default() -> Self {
        LogSettings { min_log_level: kLogInfo }
    }
}

mod state {
    use super::*;

    // Defined in log_settings_state.cc so that it is initialized before the
    // static initializers that log.
    pub(super) static G_LOG_SETTINGS: AtomicI32 = AtomicI32::new(kLogInfo);
}

/// Sets the active log settings for the current process.
pub fn set_log_settings(settings: &LogSettings) {
    // Validate the new settings as we set them.
    state::G_LOG_SETTINGS.store(kLogFatal.min(settings.min_log_level), Ordering::Relaxed);
}

/// Gets the active log settings for the current process.
pub fn get_log_settings() -> LogSettings {
    LogSettings { min_log_level: state::G_LOG_SETTINGS.load(Ordering::Relaxed) }
}

/// Gets the minimum log level for the current process. Never returns a value
/// higher than kLogFatal.
pub fn get_min_log_level() -> i32 {
    state::G_LOG_SETTINGS.load(Ordering::Relaxed).min(kLogFatal)
}

/// Sets the log settings for the current scope and restores the previous
/// ones when dropped.
pub struct ScopedSetLogSettings {
    old_settings_: LogSettings,
}

impl ScopedSetLogSettings {
    pub fn new(settings: &LogSettings) -> Self {
        let old_settings_ = get_log_settings();
        set_log_settings(settings);
        ScopedSetLogSettings { old_settings_ }
    }
}

impl Drop for ScopedSetLogSettings {
    fn drop(&mut self) {
        set_log_settings(&self.old_settings_);
    }
}

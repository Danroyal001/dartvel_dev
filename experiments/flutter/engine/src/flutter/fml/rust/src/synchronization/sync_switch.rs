// Port of flutter/fml/synchronization/sync_switch.h and
// flutter/fml/synchronization/sync_switch.cc.
//
// Observers are `Arc<dyn Observer>` compared by address, as upstream compares
// `Observer*`. Upstream's SetSwitch walks `observers_` after releasing the
// lock, racing AddObserver/RemoveObserver; the port copies the list while
// it holds the lock and notifies from the copy, which is what that loop
// does whenever it does not race.

use std::sync::{Arc, RwLock};

/// Observes changes to the SyncSwitch.
pub trait Observer: Send + Sync {
    /// `new_is_disabled` not used.
    fn on_sync_switch_update(&self, new_is_disabled: bool);
}

/// Represents the 2 code paths available when calling `SyncSwitch::execute`.
pub struct Handlers<'a> {
    pub true_handler: Box<dyn Fn() + 'a>,
    pub false_handler: Box<dyn Fn() + 'a>,
}

impl Default for Handlers<'_> {
    fn default() -> Self {
        Handlers { true_handler: Box::new(|| {}), false_handler: Box::new(|| {}) }
    }
}

impl<'a> Handlers<'a> {
    pub fn new() -> Self {
        Self::default()
    }

    /// Sets the handler that will be executed if the `SyncSwitch` is true.
    pub fn set_if_true(mut self, handler: impl Fn() + 'a) -> Self {
        self.true_handler = Box::new(handler);
        self
    }

    /// Sets the handler that will be executed if the `SyncSwitch` is false.
    pub fn set_if_false(mut self, handler: impl Fn() + 'a) -> Self {
        self.false_handler = Box::new(handler);
        self
    }
}

struct State {
    observers_: Vec<Arc<dyn Observer>>,
    value_: bool,
}

/// A threadsafe structure that allows you to switch between 2 different
/// execution paths.
pub struct SyncSwitch {
    mutex_: RwLock<State>,
}

impl Default for SyncSwitch {
    fn default() -> Self {
        Self::new(false)
    }
}

fn same_observer(a: &Arc<dyn Observer>, b: &Arc<dyn Observer>) -> bool {
    std::ptr::eq(Arc::as_ptr(a) as *const (), Arc::as_ptr(b) as *const ())
}

impl SyncSwitch {
    /// Create a `SyncSwitch` with the specified value.
    pub fn new(value: bool) -> Self {
        SyncSwitch { mutex_: RwLock::new(State { observers_: Vec::new(), value_: value }) }
    }

    /// Diverge the execution path depending on the `SyncSwitch` value.
    pub fn execute(&self, handlers: &Handlers<'_>) {
        let lock = self.mutex_.read().unwrap_or_else(|e| e.into_inner());
        if lock.value_ {
            (handlers.true_handler)();
        } else {
            (handlers.false_handler)();
        }
    }

    /// Set the value of the SyncSwitch.
    pub fn set_switch(&self, value: bool) {
        let observers = {
            let mut lock = self.mutex_.write().unwrap_or_else(|e| e.into_inner());
            lock.value_ = value;
            lock.observers_.clone()
        };
        for observer in observers {
            observer.on_sync_switch_update(value);
        }
    }

    /// Threadsafe.
    pub fn add_observer(&self, observer: Arc<dyn Observer>) {
        let mut lock = self.mutex_.write().unwrap_or_else(|e| e.into_inner());
        if !lock.observers_.iter().any(|o| same_observer(o, &observer)) {
            lock.observers_.push(observer);
        }
    }

    /// Threadsafe.
    pub fn remove_observer(&self, observer: &Arc<dyn Observer>) {
        let mut lock = self.mutex_.write().unwrap_or_else(|e| e.into_inner());
        lock.observers_.retain(|o| !same_observer(o, observer));
    }
}

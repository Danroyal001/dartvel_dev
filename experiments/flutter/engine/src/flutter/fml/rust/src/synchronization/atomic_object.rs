// Port of flutter/fml/synchronization/atomic_object.h.

use std::sync::Mutex;

#[derive(Default)]
pub struct AtomicObject<T> {
    object_: Mutex<T>,
}

impl<T: Clone> AtomicObject<T> {
    pub fn new(object: T) -> Self {
        AtomicObject { object_: Mutex::new(object) }
    }

    pub fn load(&self) -> T {
        self.object_.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    pub fn store(&self, object: &T) {
        *self.object_.lock().unwrap_or_else(|e| e.into_inner()) = object.clone();
    }
}

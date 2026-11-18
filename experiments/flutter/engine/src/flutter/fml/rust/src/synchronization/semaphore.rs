// Port of flutter/fml/synchronization/semaphore.h and
// flutter/fml/synchronization/semaphore.cc.
//
// Ports the POSIX `PlatformSemaphore` (sem_t), the one the engine uses on
// Linux, Android and Fuchsia, as a counter under a mutex and a condition
// variable, keeping sem_t's limits: sem_init fails for a count above
// SEM_VALUE_MAX (INT_MAX), which makes the semaphore invalid, and sem_post
// does not raise the count past it.

use std::sync::{Condvar, Mutex, MutexGuard};

const SEM_VALUE_MAX: u32 = i32::MAX as u32;

struct PlatformSemaphore {
    valid_: bool,
    sem_: Mutex<u32>,
    cv_: Condvar,
}

impl PlatformSemaphore {
    fn new(count: u32) -> Self {
        let valid = count <= SEM_VALUE_MAX;
        PlatformSemaphore {
            valid_: valid,
            sem_: Mutex::new(if valid { count } else { 0 }),
            cv_: Condvar::new(),
        }
    }

    fn lock(&self) -> MutexGuard<'_, u32> {
        self.sem_.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn is_valid(&self) -> bool {
        self.valid_
    }

    fn wait(&self) -> bool {
        if !self.valid_ {
            return false;
        }
        let mut value = self.lock();
        while *value == 0 {
            value = self.cv_.wait(value).unwrap_or_else(|e| e.into_inner());
        }
        *value -= 1;
        true
    }

    fn try_wait(&self) -> bool {
        if !self.valid_ {
            return false;
        }
        let mut value = self.lock();
        if *value == 0 {
            return false;
        }
        *value -= 1;
        true
    }

    fn signal(&self) {
        if !self.valid_ {
            return;
        }
        let mut value = self.lock();
        if *value < SEM_VALUE_MAX {
            *value += 1;
            self.cv_.notify_one();
        }
    }
}

pub struct Semaphore {
    impl_: Box<PlatformSemaphore>,
}

impl Semaphore {
    pub fn new(count: u32) -> Self {
        Semaphore { impl_: Box::new(PlatformSemaphore::new(count)) }
    }

    pub fn is_valid(&self) -> bool {
        self.impl_.is_valid()
    }

    #[must_use]
    pub fn wait(&self) -> bool {
        self.impl_.wait()
    }

    #[must_use]
    pub fn try_wait(&self) -> bool {
        self.impl_.try_wait()
    }

    pub fn signal(&self) {
        self.impl_.signal()
    }
}

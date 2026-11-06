// Port of flutter/fml/platform/linux/message_loop_linux.h and
// flutter/fml/platform/linux/message_loop_linux.cc.
//
// `running_` is a plain bool upstream, written by Terminate on whatever
// thread calls it (a data race the WakeUp that follows papers over); it is
// an atomic here.

use std::os::raw::c_int;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Weak};

use super::timerfd::{TFD_CLOEXEC, TFD_NONBLOCK, timer_drain, timer_rearm, timerfd_create};
use crate::eintr_wrapper::handle_eintr;
use crate::message_loop_impl::{MessageLoopImpl, MessageLoopImplBase};
use crate::time::time_point::TimePoint;
use crate::unique_fd::UniqueFD;
use crate::wakeable::Wakeable;
use crate::{fml_check_at, fml_dcheck_at};

const FILE: &str = "flutter/fml/platform/linux/message_loop_linux.cc";

const CLOCK_MONOTONIC: c_int = 1;
const K_CLOCK_TYPE: c_int = CLOCK_MONOTONIC;

const EPOLLIN: u32 = 0x001;
const EPOLLERR: u32 = 0x008;
const EPOLLHUP: u32 = 0x010;
const EPOLL_CTL_ADD: c_int = 1;
const EPOLL_CTL_DEL: c_int = 2;

/// `struct epoll_event`, which the kernel packs on x86-64.
#[allow(non_camel_case_types)]
#[cfg_attr(target_arch = "x86_64", repr(C, packed))]
#[cfg_attr(not(target_arch = "x86_64"), repr(C))]
#[derive(Clone, Copy, Default)]
struct epoll_event {
    events: u32,
    /// `epoll_data_t`; only its `fd` member is used, and the kernel hands
    /// back the bits it was given.
    data: u64,
}

// SAFETY: declarations only, each matching its prototype in <sys/epoll.h>
// for the LP64 Linux/Apple targets this crate builds for; every call
// below is in its own unsafe block that says why it is sound.
unsafe extern "C" {
    fn epoll_create(size: c_int) -> c_int;
    fn epoll_ctl(epfd: c_int, op: c_int, fd: c_int, event: *mut epoll_event) -> c_int;
    fn epoll_wait(epfd: c_int, events: *mut epoll_event, maxevents: c_int, timeout: c_int)
    -> c_int;
}

pub struct MessageLoopLinux {
    epoll_fd_: UniqueFD,
    timer_fd_: UniqueFD,
    running_: AtomicBool,
    // Last, so that it is dropped after the descriptors, as upstream's base
    // class is destroyed after the derived class's members.
    base_: MessageLoopImplBase,
}

impl MessageLoopLinux {
    pub(crate) fn create() -> Arc<MessageLoopLinux> {
        Arc::new_cyclic(|weak: &Weak<MessageLoopLinux>| {
            let base_ = MessageLoopImplBase::new(weak.clone() as Weak<dyn Wakeable>);
            let epoll_fd_ = UniqueFD::new(handle_eintr(|| {
                // SAFETY: epoll_create takes an integer and touches no memory of
                // ours.
                unsafe { epoll_create(1 /* unused */) }
            }));
            let timer_fd_ = UniqueFD::new(timerfd_create(K_CLOCK_TYPE, TFD_NONBLOCK | TFD_CLOEXEC));
            let this = MessageLoopLinux {
                epoll_fd_,
                timer_fd_,
                running_: AtomicBool::new(false),
                base_,
            };
            fml_check_at!(FILE, 20, "epoll_fd_.is_valid()", this.epoll_fd_.is_valid());
            fml_check_at!(FILE, 21, "timer_fd_.is_valid()", this.timer_fd_.is_valid());
            let added_source = this.add_or_remove_timer_source(true);
            fml_check_at!(FILE, 23, "added_source", added_source);
            this
        })
    }

    fn add_or_remove_timer_source(&self, add: bool) -> bool {
        let mut event = epoll_event {
            events: EPOLLIN,
            // The data is just for informational purposes so we know when we
            // were worken by the FD.
            data: self.timer_fd_.get() as u64,
        };
        // SAFETY: `event` is a live `struct epoll_event` with the kernel's
        // layout (packed on x86-64), read by the call; both descriptors are
        // owned by this loop and open.
        let ctl_result = unsafe {
            epoll_ctl(
                self.epoll_fd_.get(),
                if add { EPOLL_CTL_ADD } else { EPOLL_CTL_DEL },
                self.timer_fd_.get(),
                &mut event,
            )
        };
        ctl_result == 0
    }

    fn on_event_fired(&self) {
        if timer_drain(self.timer_fd_.get()) {
            self.run_expired_tasks_now();
        }
    }
}

impl Drop for MessageLoopLinux {
    fn drop(&mut self) {
        let removed_source = self.add_or_remove_timer_source(false);
        fml_check_at!(FILE, 28, "removed_source", removed_source);
    }
}

impl Wakeable for MessageLoopLinux {
    fn wake_up(&self, time_point: TimePoint) {
        let result = timer_rearm(self.timer_fd_.get(), time_point);
        fml_dcheck_at!(FILE, 84, "result", result);
    }
}

impl MessageLoopImpl for MessageLoopLinux {
    fn run(&self) {
        self.running_.store(true, Ordering::SeqCst);

        while self.running_.load(Ordering::SeqCst) {
            let mut event = epoll_event::default();

            let epoll_result = handle_eintr(|| {
                // SAFETY: `event` is a live, writable `struct epoll_event` with
                // the kernel's layout and room for the one event asked for.
                unsafe { epoll_wait(self.epoll_fd_.get(), &mut event, 1, -1 /* timeout */) }
            });

            // Errors are fatal.
            let events = event.events;
            if events & (EPOLLERR | EPOLLHUP) != 0 {
                self.running_.store(false, Ordering::SeqCst);
                continue;
            }

            // Timeouts are fatal since we specified an infinite timeout
            // already. Likewise, > 1 is not possible since we waited for one
            // result.
            if epoll_result != 1 {
                self.running_.store(false, Ordering::SeqCst);
                continue;
            }

            let data = event.data;
            if data == self.timer_fd_.get() as u64 {
                self.on_event_fired();
            }
        }
    }

    fn terminate(&self) {
        self.running_.store(false, Ordering::SeqCst);
        self.wake_up(TimePoint::now());
    }

    fn base(&self) -> &MessageLoopImplBase {
        &self.base_
    }
}

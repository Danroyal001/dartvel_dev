// Port of flutter/fml/synchronization/sync_switch_unittest.cc.

use std::sync::atomic::{AtomicBool, Ordering};

use super::sync_switch::{Handlers, SyncSwitch};

#[test]
fn basic() {
    let sync_switch = SyncSwitch::default();
    let switch_value = AtomicBool::new(false);
    sync_switch.execute(
        &Handlers::new()
            .set_if_true(|| switch_value.store(true, Ordering::SeqCst))
            .set_if_false(|| switch_value.store(false, Ordering::SeqCst)),
    );
    assert!(!switch_value.load(Ordering::SeqCst));
    sync_switch.set_switch(true);
    sync_switch.execute(
        &Handlers::new()
            .set_if_true(|| switch_value.store(true, Ordering::SeqCst))
            .set_if_false(|| switch_value.store(false, Ordering::SeqCst)),
    );
    assert!(switch_value.load(Ordering::SeqCst));
}

#[test]
fn noop_if_undefined() {
    let sync_switch = SyncSwitch::default();
    let switch_value = false;
    sync_switch.execute(&Handlers::new());
    assert!(!switch_value);
}

#[test]
fn shared_lock() {
    let sync_switch = SyncSwitch::default();
    sync_switch.set_switch(true);
    let switch_value1 = AtomicBool::new(false);
    let switch_value2 = AtomicBool::new(false);
    std::thread::scope(|s| {
        s.spawn(|| {
            sync_switch.execute(
                &Handlers::new()
                    .set_if_true(|| {
                        switch_value1.store(true, Ordering::SeqCst);
                        std::thread::scope(|s2| {
                            s2.spawn(|| {
                                sync_switch.execute(
                                    &Handlers::new()
                                        .set_if_true(|| switch_value2.store(true, Ordering::SeqCst))
                                        .set_if_false(|| {
                                            switch_value2.store(false, Ordering::SeqCst)
                                        }),
                                );
                            });
                        });
                    })
                    .set_if_false(|| switch_value1.store(false, Ordering::SeqCst)),
            );
        });
    });
    assert!(switch_value1.load(Ordering::SeqCst));
    assert!(switch_value2.load(Ordering::SeqCst));
}

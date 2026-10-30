// Not an upstream file: ConcurrentMessageLoop's WorkerMain traces each wake
// as "ConcurrentWorkerWake" (TRACE_EVENT0 after it takes its tasks, ended
// when the iteration ends). The port once emitted the event when a task was
// posted to a terminated loop instead, and nothing noticed: the oracle's
// thread suite runs without a trace handler. A test binary of its own, since
// the trace handler is process-wide.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use fml::concurrent_message_loop::ConcurrentMessageLoop;
use fml::synchronization::count_down_latch::CountDownLatch;
use fml::task_runner::BasicTaskRunner;
use fml::trace_event::{Dart_Timeline_Event_Type, trace_set_timeline_event_handler};

static EVENTS: Mutex<Vec<(std::thread::ThreadId, Dart_Timeline_Event_Type)>> = Mutex::new(Vec::new());

fn record(
    label: &str,
    _timestamp0: i64,
    _timestamp1_or_async_id: i64,
    _flow_ids: &[i64],
    type_: Dart_Timeline_Event_Type,
    _argument_names: &[&str],
    _argument_values: &[&str],
) {
    if label == "ConcurrentWorkerWake" {
        EVENTS.lock().unwrap().push((std::thread::current().id(), type_));
    }
}

#[test]
fn workers_trace_each_wake_and_posting_does_not() {
    trace_set_timeline_event_handler(Some(record));
    let poster = std::thread::current().id();
    let ran = Arc::new(AtomicUsize::new(0));
    {
        let loop_ = ConcurrentMessageLoop::create(2);
        let runner = loop_.get_task_runner();
        let latch = Arc::new(CountDownLatch::new(8));
        for _ in 0..8 {
            let (latch, ran) = (latch.clone(), ran.clone());
            runner.post_task(Arc::new(move || {
                ran.fetch_add(1, Ordering::SeqCst);
                latch.count_down();
            }));
        }
        latch.wait();
        // Terminated: a task posted now runs on this thread, untraced.
        loop_.terminate();
        let ran2 = ran.clone();
        runner.post_task(Arc::new(move || {
            ran2.fetch_add(1, Ordering::SeqCst);
        }));
    } // Dropping the loop joins the workers.
    trace_set_timeline_event_handler(None);

    assert_eq!(ran.load(Ordering::SeqCst), 9);
    let events = EVENTS.lock().unwrap();
    let begins = events.iter().filter(|e| e.1 == Dart_Timeline_Event_Type::Dart_Timeline_Event_Begin).count();
    let ends = events.iter().filter(|e| e.1 == Dart_Timeline_Event_Type::Dart_Timeline_Event_End).count();
    // At least one wake per task-carrying wake, and one per worker on
    // shutdown; every begin ended.
    assert!(begins >= 2, "{begins} wakes traced");
    assert_eq!(begins, ends);
    assert!(events.iter().all(|e| e.0 != poster), "the posting thread traced a wake");
}

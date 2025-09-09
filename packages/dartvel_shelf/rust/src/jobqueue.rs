use crate::ffi_types::RequestEnvelope;
use parking_lot::Mutex;
use std::collections::VecDeque;

pub struct JobQueue(Mutex<VecDeque<RequestEnvelope>>);

impl JobQueue {
    pub fn new() -> Self {
        JobQueue(Mutex::new(VecDeque::new()))
    }

    pub fn push(&self, req: RequestEnvelope) {
        self.0.lock().push_back(req);
    }

    pub fn pop(&self, out: &mut RequestEnvelope) -> bool {
        if let Some(r) = self.0.lock().pop_front() {
            *out = r;
            true
        } else {
            false
        }
    }
}

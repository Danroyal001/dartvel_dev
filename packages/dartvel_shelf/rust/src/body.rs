use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Notify;
#[derive(Default)]
pub struct ResponseBuffer {
    pub data: Vec<u8>,
    pub closed: bool,
}
lazy_static::lazy_static! { pub static ref RESPONSE_STREAMS:Mutex<HashMap<u64,ResponseBuffer>>=Mutex::new(HashMap::new()); }
// Response metadata: currently only HTTP status per request_id
lazy_static::lazy_static! { pub static ref RESP_STATUS:Mutex<HashMap<u64,u16>>=Mutex::new(HashMap::new()); }
// Notifiers for response completion per request
lazy_static::lazy_static! { pub static ref RESPONSE_NOTIFIERS:Mutex<HashMap<u64,Arc<Notify>>> = Mutex::new(HashMap::new()); }

// Simple RX buffer for request metadata (URL + headers JSON, etc.).
#[derive(Default)]
pub struct RequestMetadata {
    pub bytes: Vec<u8>,
}

lazy_static::lazy_static! { pub static ref REQUEST_METADATA_MAP:Mutex<HashMap<u64,RequestMetadata>>=Mutex::new(HashMap::new()); }
pub fn open_response_stream_for_request(rid: u64) -> u64 {
    let mut m = RESPONSE_STREAMS.lock();
    m.entry(rid).or_insert_with(Default::default);
    // ensure notifier exists
    let mut n = RESPONSE_NOTIFIERS.lock();
    n.entry(rid).or_insert_with(|| Arc::new(Notify::new()));
    rid
}
pub fn finalize_response_stream(h: u64) -> bool {
    if let Some(stream) = RESPONSE_STREAMS.lock().get_mut(&h) {
        stream.closed = true;
        // notify waiters
        if let Some(notify) = RESPONSE_NOTIFIERS.lock().get(&h) {
            notify.notify_waiters();
        }
        return true;
    }
    false
}
pub fn response_stream_write(h: u64, src: *const u8, len: usize) -> usize {
    if src.is_null() || len == 0 { return 0; }
    if let Some(stream) = RESPONSE_STREAMS.lock().get_mut(&h) {
        // Debug instrumentation to track potential heap issues
        eprintln!("write_chunk handle={} len={} cur={}", h, len, stream.data.len());
        if stream.closed {
            return 0;
        }
        let s = unsafe { std::slice::from_raw_parts(src, len) };
        stream.data.extend_from_slice(s);
        return len;
    }
    0
}
pub fn response_stream_write_for_request(r: u64, src: *const u8, len: usize) -> usize {
    response_stream_write(r, src, len)
}
pub fn request_metadata_read(h: u64, dst: *mut u8, cap: usize) -> usize {
    if dst.is_null() || cap == 0 {
        return 0;
    }
    let m = REQUEST_METADATA_MAP.lock();
    if let Some(rx) = m.get(&h) {
        let n = rx.bytes.len().min(cap);
        if n == 0 {
            return 0;
        }
        unsafe {
            let dst_slice = std::slice::from_raw_parts_mut(dst, n);
            dst_slice.copy_from_slice(&rx.bytes[..n]);
        }
        return n;
    }
    0
}

pub fn set_request_metadata(rid: u64, bytes: Vec<u8>) {
    let mut m = REQUEST_METADATA_MAP.lock();
    m.insert(rid, RequestMetadata { bytes });
}

pub fn clear_request_metadata(rid: u64) {
    let mut m = REQUEST_METADATA_MAP.lock();
    m.remove(&rid);
}

// Helper: take finalized response buffer (and remove entry), if present
pub fn take_response_bytes(rid: u64) -> Option<Vec<u8>> {
    let mut m = RESPONSE_STREAMS.lock();
    if let Some(stream) = m.remove(&rid) {
        return Some(stream.data);
    }
    None
}

// Helper: peek response closed flag (without removing)
pub fn is_response_closed(rid: u64) -> bool {
    let m = RESPONSE_STREAMS.lock();
    m.get(&rid).map(|s| s.closed).unwrap_or(false)
}

pub fn set_response_status(rid: u64, status: u16) {
    let mut m = RESP_STATUS.lock();
    m.insert(rid, status);
}

pub fn take_response_status(rid: u64) -> Option<u16> {
    let mut m = RESP_STATUS.lock();
    m.remove(&rid)
}

pub fn get_response_notifier(rid: u64) -> Arc<Notify> {
    let mut m = RESPONSE_NOTIFIERS.lock();
    m.entry(rid).or_insert_with(|| Arc::new(Notify::new())).clone()
}

pub fn clear_response_notifier(rid: u64) {
    let mut m = RESPONSE_NOTIFIERS.lock();
    m.remove(&rid);
}

mod body;
mod ffi_types;
mod jobqueue;
mod middleware;
mod router;
mod server;
mod util;
pub use ffi_types::{RequestEnvelope, ResponseEnvelope, SliceU8};
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use std::slice;

static LAST_ERROR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

fn set_err(e: impl ToString) {
    *LAST_ERROR.lock() = Some(e.to_string());
}

#[no_mangle]
pub extern "C" fn dv_last_error() -> SliceU8 {
    let g = LAST_ERROR.lock();
    if let Some(s) = &*g {
        SliceU8 {
            ptr: s.as_ptr(),
            len: s.len(),
        }
    } else {
        SliceU8 {
            ptr: std::ptr::null(),
            len: 0,
        }
    }
}

#[no_mangle]
pub extern "C" fn dv_server_bootstrap(cfg_ptr: *const u8, cfg_len: usize) -> u64 {
    let cfg = unsafe { slice::from_raw_parts(cfg_ptr, cfg_len) };
    match server::bootstrap(cfg) {
        Ok(h) => h,
        Err(e) => {
            set_err(e);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn dv_server_poll_job(server: u64, out_req: *mut RequestEnvelope) -> u8 {
    if out_req.is_null() {
        return 0;
    }
    let mut tmp = RequestEnvelope {
        request_id: 0,
        route_id: 0,
        method: 0,
        path_off: 0,
        path_len: 0,
        hdr_off: 0,
        hdr_len: 0,
        body_off: 0,
        body_len: 0,
        body_rx: 0,
        deadline_ns: 0,
    };

    let has = server::poll_job(server, &mut tmp);

    if has {
        unsafe {
            *out_req = tmp;
        }

        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn dv_server_submit_response(
    _server: u64,
    _resp: *const ResponseEnvelope,
) -> u8 {
    if _resp.is_null() { return 0; }
    // Respect finalize flag for empty-body responses: mark TX closed.
    unsafe {
        let env = &_resp.as_ref().unwrap();
        // record status for server response assembly
        eprintln!("submit_response rid={} status={} finalize={} tx={}", env.request_id, env.status, env.finalize, env.body_tx);
        body::set_response_status(env.request_id, env.status);
        if env.finalize != 0 {
            // body_tx equals the handle returned by open_tx(request_id)
            let _ = body::finalize_response_stream(env.body_tx);
        }
    }
    // Do not clear RX here to avoid races with ring_read on the Dart side.
    // The server request handler clears RX after assembling the HTTP response.
    1
}

#[no_mangle]
pub extern "C" fn dv_request_metadata_read(_h: u64, _dst: *mut u8, _cap: usize) -> usize {
    body::request_metadata_read(_h, _dst, _cap)
}

#[no_mangle]
pub extern "C" fn dv_response_write_chunk(h: u64, src: *const u8, len: usize) -> usize {
    body::response_stream_write(h, src, len)
}

#[no_mangle]
pub extern "C" fn dv_response_open_stream(r: u64) -> u64 {
    let h = body::open_response_stream_for_request(r);
    eprintln!("open_response_stream rid={} -> handle={}", r, h);
    h
}

#[no_mangle]
pub extern "C" fn dv_response_finalize_stream(tx: u64) -> u8 {
    eprintln!("finalize_response_stream handle={}", tx);
    body::finalize_response_stream(tx) as u8
}

#[no_mangle]
pub extern "C" fn dv_response_write_for_request(
    r: u64,
    src: *const u8,
    len: usize,
) -> usize {
    body::response_stream_write_for_request(r, src, len)
}

#[no_mangle]
pub extern "C" fn dv_ws_send_text(_ws: u64, _src: *const u8, _len: usize) -> usize {
    0
}

#[no_mangle]
pub extern "C" fn dv_ws_send_bin(_ws: u64, _src: *const u8, _len: usize) -> usize {
    0
}

#[no_mangle]
pub extern "C" fn dv_ws_close(
    _ws: u64,
    _code: u16,
    _reason: *const u8,
    _len: usize,
) -> u8 {
    1
}

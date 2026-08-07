use axum::{
    body::Body,
    http::{header, Method, Request, Response, StatusCode},
    response::IntoResponse,
    routing::get,
    Router,
};
use tower_http::cors::CorsLayer;
use bytes::{Bytes, BytesMut};
use futures_util::StreamExt as _;
use once_cell::sync::OnceCell;
use std::{
    collections::HashMap,
    io::Cursor,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
};
use tokio::sync::{mpsc, oneshot};
use serde::Deserialize;

use rustls::{
    pki_types::{CertificateDer, PrivateKeyDer},
    ServerConfig,
};
use rustls_pemfile::Item;

// ===== C ABI structs =====
#[repr(C)]
pub struct FfiBuf {
    pub ptr: *const u8,
    pub len: usize,
}
#[repr(C)]
pub struct FfiStr {
    pub ptr: *const u8,
    pub len: usize,
}
#[repr(C)]
pub struct FfiResp {
    pub status: u16,
    pub body: FfiBuf,
    pub hdrs: *const u8,
    pub hdrs_len: usize,
    pub is_stream: u8,
}

#[derive(Clone)]
struct CorsOptions {
    allow_any_origin: bool,
    origins: Vec<String>,
    allow_any_method: bool,
    methods: Vec<Method>,
    allow_any_header: bool,
    headers: Vec<header::HeaderName>,
    expose_headers: Vec<header::HeaderName>,
    allow_credentials: bool,
    max_age: Option<u32>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct CorsOptionsRaw {
    #[serde(default)]
    allow_any_origin: bool,
    #[serde(default)]
    origins: Vec<String>,
    #[serde(default)]
    allow_any_method: bool,
    #[serde(default)]
    methods: Vec<String>,
    #[serde(default)]
    allow_any_header: bool,
    #[serde(default)]
    headers: Vec<String>,
    #[serde(default)]
    expose_headers: Vec<String>,
    #[serde(default)]
    allow_credentials: bool,
    #[serde(default)]
    max_age_seconds: Option<u32>,
}

enum CorsConfigError {
    Method(String),
    Header(String),
    CredentialsAnyOrigin,
}

impl CorsConfigError {
    fn code(&self) -> i32 {
        match self {
            CorsConfigError::Method(_) => 4,
            CorsConfigError::Header(_) => 5,
            CorsConfigError::CredentialsAnyOrigin => 6,
        }
    }

    fn message(&self) -> String {
        match self {
            CorsConfigError::Method(method) => {
                format!("invalid HTTP method in CORS config: {method}")
            }
            CorsConfigError::Header(header) => {
                format!("invalid HTTP header in CORS config: {header}")
            }
            CorsConfigError::CredentialsAnyOrigin =>
                "allowCredentials cannot be used with allowAnyOrigin".to_string(),
        }
    }
}

fn parse_cors_options(raw: CorsOptionsRaw) -> Result<CorsOptions, CorsConfigError> {
    if raw.allow_credentials && raw.allow_any_origin {
        return Err(CorsConfigError::CredentialsAnyOrigin);
    }

    let methods = if raw.allow_any_method {
        Vec::new()
    } else {
        let mut out = Vec::new();
        for method in raw.methods {
            let parsed = Method::from_bytes(method.as_bytes())
                .map_err(|_| CorsConfigError::Method(method.clone()))?;
            out.push(parsed);
        }
        out
    };

    let headers = if raw.allow_any_header {
        Vec::new()
    } else {
        let mut out = Vec::new();
        for header_name in raw.headers {
            let parsed = header::HeaderName::try_from(header_name.as_str())
                .map_err(|_| CorsConfigError::Header(header_name.clone()))?;
            out.push(parsed);
        }
        out
    };

    let mut expose_headers = Vec::new();
    for header_name in raw.expose_headers {
        let parsed = header::HeaderName::try_from(header_name.as_str())
            .map_err(|_| CorsConfigError::Header(header_name.clone()))?;
        expose_headers.push(parsed);
    }

    Ok(CorsOptions {
        allow_any_origin: raw.allow_any_origin,
        origins: raw.origins,
        allow_any_method: raw.allow_any_method,
        methods,
        allow_any_header: raw.allow_any_header,
        headers,
        expose_headers,
        allow_credentials: raw.allow_credentials,
        max_age: raw.max_age_seconds,
    })
}

fn build_cors(cfg: &CorsOptions) -> CorsLayer {
    let mut cors = CorsLayer::new();

    if cfg.allow_any_origin {
        cors = cors.allow_origin(tower_http::cors::Any);
    } else {
        let mut origins = Vec::new();
        for origin in &cfg.origins {
            if let Ok(value) = origin.parse::<axum::http::HeaderValue>() {
                origins.push(value);
            }
        }
        if !origins.is_empty() {
            cors = cors.allow_origin(origins);
        }
    }

    if cfg.allow_any_method {
        cors = cors.allow_methods(tower_http::cors::Any);
    } else if !cfg.methods.is_empty() {
        cors = cors.allow_methods(cfg.methods.clone());
    }

    if cfg.allow_any_header {
        cors = cors.allow_headers(tower_http::cors::Any);
    } else if !cfg.headers.is_empty() {
        cors = cors.allow_headers(cfg.headers.clone());
    }

    if !cfg.expose_headers.is_empty() {
        cors = cors.expose_headers(cfg.expose_headers.clone());
    }

    if let Some(max_age) = cfg.max_age {
        cors = cors.max_age(std::time::Duration::from_secs(max_age as u64));
    }

    if cfg.allow_credentials {
        cors = cors.allow_credentials(true);
    }

    cors
}

// Dart request callback: void(req_id, method, target, hdrs_flat, hdrs_len, body)
pub type DartReqHandler = extern "C" fn(u64, FfiStr, FfiStr, *const u8, usize, FfiBuf);
// Dart stream cancel callback: void(req_id)
pub type DartStreamCancelHandler = extern "C" fn(u64);

// ===== Globals =====
// Replaceable rather than set-once: each `serve()` owns its own Dart
// callbacks, and a stale pointer here is a use-after-free the moment the
// server that registered it closes them.
static DART_REQUEST_HANDLER: OnceCell<Mutex<Option<DartReqHandler>>> = OnceCell::new();
static DART_CANCEL_HANDLER: OnceCell<Mutex<Option<DartStreamCancelHandler>>> =
    OnceCell::new();

struct FfiRespOwned {
    status: u16,
    headers: Vec<u8>,
    body: Vec<u8>,
    is_stream: u8,
}
static PENDING_RESPONSES: OnceCell<Mutex<HashMap<u64, oneshot::Sender<FfiRespOwned>>>> =
    OnceCell::new();
/// Unbounded because `aw_stream_send_chunk` is called from Dart's thread,
/// which is not a runtime thread: a bounded sender there can only drop the
/// chunk, block the isolate, or reorder it behind a spawned send. Buffering
/// instead trades memory for a stream that is neither lossy nor reordered.
static PENDING_STREAM_SENDERS:
    OnceCell<Mutex<HashMap<u64, mpsc::UnboundedSender<Result<Bytes, axum::BoxError>>>>> =
    OnceCell::new();
/// Receivers are created when Dart completes the response rather than when the
/// server task builds the body, so a chunk sent immediately after
/// `aw_complete` still has somewhere to go.
static PENDING_STREAM_RECEIVERS:
    OnceCell<Mutex<HashMap<u64, mpsc::UnboundedReceiver<Result<Bytes, axum::BoxError>>>>> =
    OnceCell::new();
/// Server threads, so a stop can wait for one to finish before Dart frees the
/// callbacks its in-flight streams still call.
static SERVER_THREADS: OnceCell<Mutex<HashMap<u64, std::thread::JoinHandle<()>>>> =
    OnceCell::new();
static NEXT_ID: OnceCell<AtomicU64> = OnceCell::new();
static TLS_CONFIG: OnceCell<Arc<ServerConfig>> = OnceCell::new();
static SERVER_HANDLES: OnceCell<Mutex<HashMap<u64, axum_server::Handle>>> = OnceCell::new();
static NEXT_SERVER_ID: OnceCell<AtomicU64> = OnceCell::new();
static CORS_CONFIG: OnceCell<Mutex<Option<Arc<CorsOptions>>>> = OnceCell::new();
static STATIC_DIR: OnceCell<Mutex<Option<String>>> = OnceCell::new();
static SPA_ROOT_DIR: OnceCell<Mutex<Option<String>>> = OnceCell::new();
static COMPRESSION_ENABLED: OnceCell<Mutex<bool>> = OnceCell::new();

// Flags for aw_start
pub const AW_FLAG_H2C: u32 = 0x01;

// Stream wrapper to trigger Dart cancellation on drop
struct CancelOnDropStream<S> {
    inner: S,
    req_id: u64,
}

impl<S> futures_util::stream::Stream for CancelOnDropStream<S>
where
    S: futures_util::stream::Stream + Unpin,
{
    type Item = S::Item;

    fn poll_next(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        use std::pin::Pin;
        Pin::new(&mut self.inner).poll_next(cx)
    }
}

impl<S> Drop for CancelOnDropStream<S> {
    fn drop(&mut self) {
        if let Some(map_mutex) = PENDING_STREAM_SENDERS.get() {
            safe_lock(map_mutex).remove(&self.req_id);
        }
        if let Some(map_mutex) = PENDING_STREAM_RECEIVERS.get() {
            safe_lock(map_mutex).remove(&self.req_id);
        }
        if let Some(slot) = DART_CANCEL_HANDLER.get() {
            let cb = *safe_lock(slot);
            if let Some(cb) = cb {
                (cb)(self.req_id);
            }
        }
    }
}

// ===== FFI Exports =====
#[no_mangle]
pub extern "C" fn aw_register_handler(cb: DartReqHandler) {
    let slot = DART_REQUEST_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let _ = SERVER_THREADS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_RESPONSES.set(Mutex::new(HashMap::new()));
    let _ = NEXT_ID.set(AtomicU64::new(1));
    let _ = SERVER_HANDLES.set(Mutex::new(HashMap::new()));
    let _ = NEXT_SERVER_ID.set(AtomicU64::new(1));
}

#[no_mangle]
pub extern "C" fn aw_register_cancel_handler(cb: DartStreamCancelHandler) {
    let slot = DART_CANCEL_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let _ = PENDING_STREAM_SENDERS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_STREAM_RECEIVERS.set(Mutex::new(HashMap::new()));
}

#[no_mangle]
pub extern "C" fn aw_configure_cors(config_json: FfiStr) -> i32 {
    if config_json.len == 0 {
        if let Some(mutex) = CORS_CONFIG.get() {
            *safe_lock(mutex) = None;
        }
        return 0;
    }

    if config_json.ptr.is_null() {
        return 0;
    }
    // SAFETY: FfiStr contract guarantees ptr is valid for len bytes
    let json_slice = unsafe { std::slice::from_raw_parts(config_json.ptr, config_json.len) };
    let json_str = match std::str::from_utf8(json_slice) {
        Ok(s) => s,
        Err(_) => return 2,
    };

    if json_str.trim().is_empty() {
        if let Some(mutex) = CORS_CONFIG.get() {
            *safe_lock(mutex) = None;
        }
        return 0;
    }

    let raw: CorsOptionsRaw = match serde_json::from_str(json_str) {
        Ok(raw) => raw,
        Err(err) => {
            eprintln!("aw_configure_cors: failed to parse JSON: {err}");
            return 3;
        }
    };

    let parsed = match parse_cors_options(raw) {
        Ok(cfg) => cfg,
        Err(err) => {
            eprintln!("aw_configure_cors: {}", err.message());
            return err.code();
        }
    };

    let mutex = CORS_CONFIG.get_or_init(|| Mutex::new(None));
    *safe_lock(mutex) = Some(Arc::new(parsed));
    0
}

#[no_mangle]
pub extern "C" fn aw_tls_rustls_from_pem(cert_pem: FfiBuf, key_pem: FfiBuf) -> i32 {
    // Parse certificate chain
    let certs = {
        if cert_pem.ptr.is_null() {
            return 2;
        }
        // SAFETY: FfiBuf contract guarantees ptr is valid for len bytes
        let mut r = Cursor::new(unsafe { std::slice::from_raw_parts(cert_pem.ptr, cert_pem.len) });
        let mut out = Vec::<CertificateDer<'static>>::new();
        for item in rustls_pemfile::read_all(&mut r) {
            let item = match item {
                Ok(item) => item,
                Err(_) => return 2,
            };
            if let Item::X509Certificate(cert) = item {
                out.push(cert);
            }
        }
        if out.is_empty() {
            return 2;
        }
        out
    };

    let sk = {
        if key_pem.ptr.is_null() {
            return 3;
        }
        // SAFETY: FfiBuf contract guarantees ptr is valid for len bytes
        let mut r = Cursor::new(unsafe { std::slice::from_raw_parts(key_pem.ptr, key_pem.len) });
        let mut key: Option<PrivateKeyDer<'static>> = None;
        for item in rustls_pemfile::read_all(&mut r) {
            let item = match item {
                Ok(item) => item,
                Err(_) => return 3,
            };
            match item {
                Item::Pkcs8Key(k) => {
                    key = Some(PrivateKeyDer::from(k));
                    break;
                }
                Item::Pkcs1Key(k) => {
                    if key.is_none() {
                        key = Some(PrivateKeyDer::from(k));
                    }
                }
                Item::Sec1Key(k) => {
                    if key.is_none() {
                        key = Some(PrivateKeyDer::from(k));
                    }
                }
                _ => {}
            }
        }
        match key {
            Some(k) => k,
            None => return 3,
        }
    };

    let cfg = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, sk)
        .map_err(|_| 4);
    let cfg = match cfg {
        Ok(c) => c,
        Err(code) => return code,
    };

    let _ = TLS_CONFIG.set(Arc::new(cfg));
    0
}

#[no_mangle]
pub extern "C" fn aw_configure_static(path: FfiStr) -> i32 {
    if path.len == 0 || path.ptr.is_null() {
        // Clear static directory
        if let Some(mutex) = STATIC_DIR.get() {
            *safe_lock(mutex) = None;
        }
        return 0;
    }

    // SAFETY: FfiStr contract guarantees ptr is valid for len bytes
    let path_slice = unsafe { std::slice::from_raw_parts(path.ptr, path.len) };
    let path_string = match std::str::from_utf8(path_slice) {
        Ok(s) => s.to_string(),
        Err(_) => return 1,
    };

    let mutex = STATIC_DIR.get_or_init(|| Mutex::new(None));
    *safe_lock(mutex) = Some(path_string);
    0
}

#[no_mangle]
pub extern "C" fn aw_configure_spa_root(path: FfiStr) -> i32 {
    if path.len == 0 || path.ptr.is_null() {
        if let Some(mutex) = SPA_ROOT_DIR.get() {
            *safe_lock(mutex) = None;
        }
        return 0;
    }

    // SAFETY: FfiStr contract guarantees ptr is valid for len bytes
    let path_slice = unsafe { std::slice::from_raw_parts(path.ptr, path.len) };
    let path_string = match std::str::from_utf8(path_slice) {
        Ok(s) => s.to_string(),
        Err(_) => return 1,
    };

    let mutex = SPA_ROOT_DIR.get_or_init(|| Mutex::new(None));
    *safe_lock(mutex) = Some(path_string);
    0
}

#[no_mangle]
pub extern "C" fn aw_configure_compression(enabled: i32) -> i32 {
    let mutex = COMPRESSION_ENABLED.get_or_init(|| Mutex::new(false));
    *safe_lock(mutex) = enabled != 0;
    0
}

#[no_mangle]
pub extern "C" fn aw_start(host: FfiStr, port: u16, _flags: u32) -> i32 {
    if host.ptr.is_null() {
        return -1;
    }
    // SAFETY: FfiStr contract guarantees ptr is valid for len bytes
    let host_slice = unsafe { std::slice::from_raw_parts(host.ptr, host.len) };
    let host_string = match std::str::from_utf8(host_slice) {
        Ok(s) => s.to_string(),
        Err(_) => return -1,
    };
    let server_id = match NEXT_SERVER_ID.get() {
        Some(id) => id.fetch_add(1, Ordering::Relaxed),
        None => return -1,
    };

    let cors_config = {
        let mutex = CORS_CONFIG.get_or_init(|| Mutex::new(None));
        safe_lock(mutex).clone()
    };
    
    let compression_enabled = {
        let mutex = COMPRESSION_ENABLED.get_or_init(|| Mutex::new(false));
        *safe_lock(mutex)
    };

    let handle = axum_server::Handle::new();
    if let Some(handles) = SERVER_HANDLES.get() {
        safe_lock(handles).insert(server_id, handle.clone());
    }

    let host_clone = host_string.clone();
    let handle_clone = handle.clone();

    let server_thread = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to build Tokio runtime");

        rt.block_on(async move {
            let mut app = Router::new()
                .route("/health", get(health_handler))
                .route("/healthz", get(healthz_handler))
                .route("/healths", get(healths_handler))
                .fallback(catch_all_handler);

            if compression_enabled {
                app = app.layer(tower_http::compression::CompressionLayer::new());
            }

            if let Some(cfg) = cors_config {
                app = app.layer(build_cors(&cfg));
            }

            let addr = format!("{}:{}", host_clone, port);
            let parsed_addr: std::net::SocketAddr = addr.parse().expect("Failed to parse address");

            if let Some(tls_config) = TLS_CONFIG.get() {
                let rustls_config = axum_server::tls_rustls::RustlsConfig::from_config(tls_config.clone());
                axum_server::bind_rustls(parsed_addr, rustls_config)
                    .handle(handle_clone)
                    .serve(app.into_make_service())
                    .await
                    .expect("Failed to start HTTPS server");
            } else {
                axum_server::bind(parsed_addr)
                    .handle(handle_clone)
                    .serve(app.into_make_service())
                    .await
                    .expect("Failed to start HTTP server");
            }

            if let Some(handles) = SERVER_HANDLES.get() {
                safe_lock(handles).remove(&server_id);
            }
        });
    });

    if let Some(threads) = SERVER_THREADS.get() {
        safe_lock(threads).insert(server_id, server_thread);
    }

    server_id as i32
}

#[no_mangle]
pub extern "C" fn aw_stop(server_id: u64) -> i32 {
    if let Some(handles) = SERVER_HANDLES.get() {
        let mut map = safe_lock(handles);
        if let Some(handle) = map.remove(&server_id) {
            handle.graceful_shutdown(Some(std::time::Duration::from_secs(5)));
            // Dropping the lock first: joining below can run stream drops that
            // reach back into these maps.
            drop(map);
            // Waiting for the thread means every in-flight stream has been
            // dropped and every cancel callback delivered, so the caller can
            // safely free the Dart callbacks it registered.
            if let Some(threads) = SERVER_THREADS.get() {
                let thread = safe_lock(threads).remove(&server_id);
                if let Some(thread) = thread {
                    let _ = thread.join();
                }
            }
            return 0;
        }
    }
    1
}

#[no_mangle]
pub extern "C" fn aw_complete(req_id: u64, resp: FfiResp) -> i32 {
    let map_mutex = match PENDING_RESPONSES.get() {
        Some(m) => m,
        None => return 1,
    };
    let mut map = safe_lock(map_mutex);
    if let Some(tx) = map.remove(&req_id) {
        // SAFETY: FfiResp guarantees valid pointers and lengths, data is copied immediately
        let owned = unsafe {
            if resp.hdrs.is_null() && resp.hdrs_len > 0 {
                return 1;
            }
            if resp.body.ptr.is_null() && resp.body.len > 0 && resp.is_stream == 0 {
                return 1;
            }
            let headers = std::slice::from_raw_parts(resp.hdrs, resp.hdrs_len).to_vec();
            let body = if resp.is_stream == 0 {
                std::slice::from_raw_parts(resp.body.ptr, resp.body.len).to_vec()
            } else {
                Vec::new()
            };
            FfiRespOwned {
                status: resp.status,
                headers,
                body,
                is_stream: resp.is_stream,
            }
        };
        if owned.is_stream != 0 {
            let (chunk_tx, chunk_rx) =
                mpsc::unbounded_channel::<Result<Bytes, axum::BoxError>>();
            if let (Some(senders), Some(receivers)) = (
                PENDING_STREAM_SENDERS.get(),
                PENDING_STREAM_RECEIVERS.get(),
            ) {
                safe_lock(senders).insert(req_id, chunk_tx);
                safe_lock(receivers).insert(req_id, chunk_rx);
            } else {
                return 4;
            }
        }
        let _ = tx.send(owned);
        0
    } else {
        1
    }
}

#[no_mangle]
pub extern "C" fn aw_stream_send_chunk(req_id: u64, chunk: FfiBuf) -> i32 {
    if chunk.ptr.is_null() && chunk.len > 0 {
        return 1;
    }
    let bytes_vec = unsafe { std::slice::from_raw_parts(chunk.ptr, chunk.len) }.to_vec();
    let bytes = Bytes::from(bytes_vec);
    if let Some(map_mutex) = PENDING_STREAM_SENDERS.get() {
        let map = safe_lock(map_mutex);
        if let Some(tx) = map.get(&req_id) {
            match tx.send(Ok(bytes)) {
                Ok(()) => 0,
                // The receiver is gone: the client disconnected.
                Err(_) => 2,
            }
        } else {
            2
        }
    } else {
        3
    }
}

#[no_mangle]
pub extern "C" fn aw_stream_complete(req_id: u64) -> i32 {
    if let Some(map_mutex) = PENDING_STREAM_SENDERS.get() {
        let mut map = safe_lock(map_mutex);
        if map.remove(&req_id).is_some() {
            0
        } else {
            1
        }
    } else {
        2
    }
}

// ===== Helpers =====
fn headers_flat(req: &Request<Body>) -> Vec<u8> {
    let mut out = Vec::new();
    for (k, v) in req.headers().iter() {
        out.extend_from_slice(k.as_str().as_bytes());
        out.push(0);
        out.extend_from_slice(v.as_bytes());
        out.push(0);
    }
    out
}

async fn dart_proxy(req: Request<Body>) -> Response<Body> {
    dart_proxy_with_fallback(req, None).await
}

async fn dart_proxy_with_fallback(
    req: Request<Body>,
    fallback: Option<fn() -> Response<Body>>,
) -> Response<Body> {
    let req_id = match NEXT_ID.get() {
        Some(id) => id.fetch_add(1, Ordering::Relaxed),
        None => return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::from("Backend not initialized"))
            .unwrap(),
    };

    let method = req.method().as_str().as_bytes().to_vec();
    let target = req.uri().to_string().into_bytes();
    let flattened_headers = headers_flat(&req);
    
    let mut body_buf = BytesMut::new();
    let mut body_stream = req.into_body().into_data_stream();
    while let Some(chunk) = body_stream.next().await {
        match chunk {
            Ok(bytes) => body_buf.extend_from_slice(&bytes),
            Err(_) => {
                body_buf.clear();
                break;
            }
        }
    }
    let bytes = body_buf.freeze();

    let method_ffi = FfiStr {
        ptr: method.as_ptr(),
        len: method.len(),
    };
    let target_ffi = FfiStr {
        ptr: target.as_ptr(),
        len: target.len(),
    };
    let body_ffi = FfiBuf {
        ptr: bytes.as_ptr(),
        len: bytes.len(),
    };

    let (response_tx, response_rx) = oneshot::channel::<FfiRespOwned>();
    if let Some(mutex) = PENDING_RESPONSES.get() {
        safe_lock(mutex).insert(req_id, response_tx);
    } else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::empty())
            .unwrap();
    }

    let request_handler =
        DART_REQUEST_HANDLER.get().and_then(|slot| *safe_lock(slot));
    if let Some(cb) = request_handler {
        (cb)(
            req_id,
            method_ffi,
            target_ffi,
            flattened_headers.as_ptr(),
            flattened_headers.len(),
            body_ffi,
        );
    } else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::empty())
            .unwrap();
    }

    match tokio::time::timeout(std::time::Duration::from_secs(60), response_rx).await {
        Ok(Ok(resp)) => {
            let status_code = StatusCode::from_u16(resp.status).unwrap_or(StatusCode::OK);
            let mut builder = Response::builder().status(status_code);

            let hdrs = resp.headers;
            let mut i = 0;
            while i < hdrs.len() {
                let ke = hdrs[i..]
                    .iter()
                    .position(|&c| c == 0)
                    .unwrap_or(hdrs.len() - i)
                    + i;
                let key = std::str::from_utf8(&hdrs[i..ke]).unwrap_or_default();
                i = ke + 1;
                let ve = hdrs[i..]
                    .iter()
                    .position(|&c| c == 0)
                    .unwrap_or(hdrs.len() - i)
                    + i;
                let val = std::str::from_utf8(&hdrs[i..ve]).unwrap_or_default();
                i = ve + 1;
                if !key.is_empty() {
                    builder = builder.header(key, val);
                }
            }

            if status_code == StatusCode::NOT_FOUND {
                if let Some(fallback_fn) = fallback {
                    return fallback_fn();
                }
            }

            if resp.is_stream != 0 {
                let rx = PENDING_STREAM_RECEIVERS
                    .get()
                    .and_then(|m| safe_lock(m).remove(&req_id));
                let rx = match rx {
                    Some(rx) => rx,
                    None => {
                        return Response::builder()
                            .status(StatusCode::INTERNAL_SERVER_ERROR)
                            .body(Body::empty())
                            .unwrap()
                    }
                };
                let receiver_stream =
                    tokio_stream::wrappers::UnboundedReceiverStream::new(rx);
                let cancel_stream = CancelOnDropStream {
                    inner: receiver_stream,
                    req_id,
                };
                
                builder.body(Body::from_stream(cancel_stream)).unwrap()
            } else {
                builder.body(Body::from(resp.body)).unwrap()
            }
        }
        _ => {
            if let Some(mutex) = PENDING_RESPONSES.get() {
                safe_lock(mutex).remove(&req_id);
            }
            if let Some(fallback_fn) = fallback {
                fallback_fn()
            } else {
                Response::builder()
                    .status(StatusCode::GATEWAY_TIMEOUT)
                    .body(Body::empty())
                    .unwrap()
            }
        }
    }
}

async fn health_handler(req: Request<Body>) -> Response<Body> {
    dart_proxy_with_fallback(req, Some(default_health_response)).await
}

async fn healthz_handler(req: Request<Body>) -> Response<Body> {
    dart_proxy_with_fallback(req, Some(default_healthz_response)).await
}

async fn healths_handler(req: Request<Body>) -> Response<Body> {
    dart_proxy_with_fallback(req, Some(default_healths_response)).await
}

fn default_health_response() -> Response<Body> {
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/json; charset=utf-8")
        .body(Body::from(r#"{"status":"ok"}"#))
        .unwrap()
}

fn default_healthz_response() -> Response<Body> {
    Response::builder()
        .status(StatusCode::PERMANENT_REDIRECT)
        .header(header::LOCATION, "/health")
        .body(Body::empty())
        .unwrap()
}

fn default_healths_response() -> Response<Body> {
    Response::builder()
        .status(StatusCode::PERMANENT_REDIRECT)
        .header(header::LOCATION, "/health")
        .body(Body::empty())
        .unwrap()
}

async fn catch_all_handler(
    req: Request<Body>,
) -> impl IntoResponse {
    let path = req.uri().path().to_string();
    
    // 1. Static dir check
    let static_dir = {
        let mutex = STATIC_DIR.get_or_init(|| Mutex::new(None));
        safe_lock(mutex).clone()
    };
    if let Some(dir) = static_dir {
        if path.starts_with("/static/") {
            let relative_path = &path["/static".len()..];
            if let Some(file_path) = get_static_file(&dir, relative_path) {
                return serve_file_response(file_path).await;
            }
        }
    }

    // 2. SPA root check
    let spa_root = {
        let mutex = SPA_ROOT_DIR.get_or_init(|| Mutex::new(None));
        safe_lock(mutex).clone()
    };
    if let Some(dir) = spa_root {
        if let Some(file_path) = get_static_file(&dir, &path) {
            return serve_file_response(file_path).await;
        }
        if req.method() == Method::GET {
            let index_path = std::path::PathBuf::from(&dir).join("index.html");
            if index_path.is_file() {
                return serve_file_response(index_path).await;
            }
        }
    }

    // 3. Fallback to Dart
    dart_proxy(req).await
}

fn get_static_file(dir: &str, path: &str) -> Option<std::path::PathBuf> {
    let mut file_path = std::path::PathBuf::from(dir);
    let sanitized = path.trim_start_matches('/');
    if sanitized.contains("..") {
        return None;
    }
    file_path.push(sanitized);
    if file_path.is_file() {
        Some(file_path)
    } else {
        None
    }
}

fn get_mime_type(path: &std::path::Path) -> &'static str {
    match path.extension().and_then(|s| s.to_str()) {
        Some("html") => "text/html",
        Some("css") => "text/css",
        Some("js") => "application/javascript",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("svg") => "image/svg+xml",
        Some("json") => "application/json",
        Some("wasm") => "application/wasm",
        _ => "application/octet-stream",
    }
}

async fn serve_file_response(path: std::path::PathBuf) -> Response<Body> {
    match tokio::fs::read(&path).await {
        Ok(bytes) => {
            let mime = get_mime_type(&path);
            Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, mime)
                .body(Body::from(bytes))
                .unwrap()
        }
        Err(err) => {
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::from(format!("File not found: {}", err)))
                .unwrap()
        }
    }
}

fn safe_lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    match m.lock() {
        Ok(g) => g,
        Err(p) => {
            eprintln!("WARN: Mutex poisoned, recovering");
            p.into_inner()
        }
    }
}

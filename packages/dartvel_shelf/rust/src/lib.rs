use actix_cors::Cors;
use actix_web::http::{header, Method};
use actix_web::{
    dev::ServerHandle as ActixServerHandle, middleware::Condition, rt::System, web, App,
    HttpRequest, HttpResponse, HttpServer,
};
use bytes::{Bytes, BytesMut};
use futures_util::StreamExt as _;
use once_cell::sync::OnceCell;
use std::{
    collections::HashMap,
    ffi::c_void,
    io::Cursor,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
};
use tokio::sync::oneshot;
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

fn build_cors(cfg: &CorsOptions) -> Cors {
    let mut cors = Cors::default();

    if cfg.allow_any_origin {
        cors = cors.allow_any_origin();
    } else {
        for origin in &cfg.origins {
            cors = cors.allowed_origin(origin);
        }
    }

    if cfg.allow_any_method {
        cors = cors.allow_any_method();
    } else if !cfg.methods.is_empty() {
        cors = cors.allowed_methods(cfg.methods.clone());
    }

    if cfg.allow_any_header {
        cors = cors.allow_any_header();
    } else if !cfg.headers.is_empty() {
        for header in &cfg.headers {
            cors = cors.allowed_header(header.clone());
        }
    }

    if !cfg.expose_headers.is_empty() {
        cors = cors.expose_headers(cfg.expose_headers.clone());
    }

    if let Some(max_age) = cfg.max_age {
        cors = cors.max_age(Some(max_age as usize));
    }

    if cfg.allow_credentials {
        cors = cors.supports_credentials();
    }

    cors
}

// Dart request callback: void(req_id, method, target, hdrs_flat, hdrs_len, body)
pub type DartReqHandler = extern "C" fn(u64, FfiStr, FfiStr, *const u8, usize, FfiBuf);

// ===== Globals =====
static DART_REQUEST_HANDLER: OnceCell<DartReqHandler> = OnceCell::new();
struct FfiRespOwned {
    status: u16,
    headers: Vec<u8>,
    body: Vec<u8>,
}

static PENDING_RESPONSES: OnceCell<Mutex<HashMap<u64, oneshot::Sender<FfiRespOwned>>>> =
    OnceCell::new();
static NEXT_ID: OnceCell<AtomicU64> = OnceCell::new();
static TLS_CONFIG: OnceCell<Arc<ServerConfig>> = OnceCell::new();
static SERVER_HANDLES: OnceCell<Mutex<HashMap<u64, ActixServerHandle>>> = OnceCell::new();
static NEXT_SERVER_ID: OnceCell<AtomicU64> = OnceCell::new();
static CORS_CONFIG: OnceCell<Mutex<Option<Arc<CorsOptions>>>> = OnceCell::new();

// Flags for aw_start
pub const AW_FLAG_H2C: u32 = 0x01;

// ===== FFI Exports =====
#[no_mangle]
pub extern "C" fn aw_register_handler(cb: DartReqHandler) {
    let _ = DART_REQUEST_HANDLER.set(cb);
    let _ = PENDING_RESPONSES.set(Mutex::new(HashMap::new()));
    let _ = NEXT_ID.set(AtomicU64::new(1));
    let _ = SERVER_HANDLES.set(Mutex::new(HashMap::new()));
    let _ = NEXT_SERVER_ID.set(AtomicU64::new(1));
}

#[no_mangle]
pub extern "C" fn aw_configure_cors(config_json: FfiStr) -> i32 {
    if config_json.len == 0 {
        if let Some(mutex) = CORS_CONFIG.get() {
            *mutex.lock().unwrap() = None;
        }
        return 0;
    }

    let json_slice = unsafe { std::slice::from_raw_parts(config_json.ptr, config_json.len) };
    let json_str = match std::str::from_utf8(json_slice) {
        Ok(s) => s,
        Err(_) => return 2,
    };

    if json_str.trim().is_empty() {
        if let Some(mutex) = CORS_CONFIG.get() {
            *mutex.lock().unwrap() = None;
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
    *mutex.lock().unwrap() = Some(Arc::new(parsed));
    0
}

#[no_mangle]
pub extern "C" fn aw_tls_rustls_from_pem(cert_pem: FfiBuf, key_pem: FfiBuf) -> i32 {
    // Parse certificate chain
    let certs = {
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
pub extern "C" fn aw_start(host: FfiStr, port: u16, flags: u32) -> i32 {
    let host_string =
        unsafe { std::str::from_utf8_unchecked(std::slice::from_raw_parts(host.ptr, host.len)) }
            .to_string();
    let server_id = NEXT_SERVER_ID
        .get()
        .unwrap()
        .fetch_add(1, Ordering::Relaxed);

    let cors_config = {
        let mutex = CORS_CONFIG.get_or_init(|| Mutex::new(None));
        mutex.lock().unwrap().clone()
    };

    std::thread::spawn(move || {
        System::new().block_on(async move {
            let cors_config = cors_config.clone();
            let app_factory = move || {
                let cors_config = cors_config.clone();
                let (cors_enabled, cors_mw) = match cors_config {
                    Some(cfg) => (true, build_cors(cfg.as_ref())),
                    None => (false, Cors::default()),
                };

                App::new()
                    .wrap(Condition::new(cors_enabled, cors_mw))
                    .route("/health", web::get().to(health_route))
                    .route("/healthz", web::get().to(healthz_route))
                    .route("/healths", web::get().to(healths_route))
                    .default_service(web::to(dart_proxy))
            };

            let mut http_server = HttpServer::new(app_factory).workers(num_cpus::get());

            if let Some(tls_config) = TLS_CONFIG.get() {
                #[allow(deprecated)]
                {
                    http_server = http_server
                        .bind_rustls_0_23((host_string.as_str(), port), (**tls_config).clone())
                        .expect("bind_rustls_0_23 failed");
                }
            } else if (flags & AW_FLAG_H2C) != 0 {
                http_server = http_server
                    .bind_auto_h2c((host_string.as_str(), port))
                    .expect("bind_auto_h2c failed");
            } else {
                http_server = http_server
                    .bind((host_string.as_str(), port))
                    .expect("bind failed");
            }

            let server = http_server.run();
            if let Some(handles) = SERVER_HANDLES.get() {
                handles.lock().unwrap().insert(server_id, server.handle());
            }
            let _ = server.await;
            if let Some(handles) = SERVER_HANDLES.get() {
                handles.lock().unwrap().remove(&server_id);
            }
        });
    });

    server_id as i32
}

#[no_mangle]
pub extern "C" fn aw_stop(server_id: u64) -> i32 {
    if let Some(handles) = SERVER_HANDLES.get() {
        let handle = handles.lock().unwrap().remove(&server_id);
        if let Some(handle) = handle {
            let _ = handle.stop(true);
            return 0;
        }
    }
    1
}

#[no_mangle]
pub extern "C" fn aw_complete(req_id: u64, resp: FfiResp) -> i32 {
    let mut map = PENDING_RESPONSES.get().unwrap().lock().unwrap();
    if let Some(tx) = map.remove(&req_id) {
        let owned = unsafe {
            let headers = std::slice::from_raw_parts(resp.hdrs, resp.hdrs_len).to_vec();
            let body = std::slice::from_raw_parts(resp.body.ptr, resp.body.len).to_vec();
            aw_free(resp.hdrs as *mut c_void, resp.hdrs_len);
            aw_free(resp.body.ptr as *mut c_void, resp.body.len);
            FfiRespOwned {
                status: resp.status,
                headers,
                body,
            }
        };
        let _ = tx.send(owned);
        0
    } else {
        1
    }
}

#[no_mangle]
pub extern "C" fn aw_free(ptr_: *mut c_void, len: usize) {
    if !ptr_.is_null() && len > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(ptr_ as *mut u8, len, len);
        }
    }
}

// ===== Helpers =====
fn headers_flat(req: &HttpRequest) -> Vec<u8> {
    let mut out = Vec::new();
    for (k, v) in req.headers().iter() {
        out.extend_from_slice(k.as_str().as_bytes());
        out.push(0);
        out.extend_from_slice(v.as_bytes());
        out.push(0);
    }
    out
}

async fn dart_proxy(req: HttpRequest, payload: web::Payload) -> HttpResponse {
    dart_proxy_with_fallback(req, payload, None).await
}

async fn dart_proxy_with_fallback(
    req: HttpRequest,
    mut payload: web::Payload,
    fallback: Option<fn() -> HttpResponse>,
) -> HttpResponse {
    let req_id = NEXT_ID.get().unwrap().fetch_add(1, Ordering::Relaxed);

    let method = req.method().as_str().as_bytes().to_vec();
    let target = req.uri().to_string().into_bytes();
    let flattened_headers = headers_flat(&req);
    let mut body_buf = BytesMut::new();
    while let Some(chunk) = payload.next().await {
        match chunk {
            Ok(bytes) => body_buf.extend_from_slice(&bytes),
            Err(_) => {
                body_buf.clear();
                break;
            }
        }
    }
    let bytes: Bytes = body_buf.freeze();

    // Owned buffers live until response is received
    let m = method;
    let t = target;
    let h = flattened_headers;
    let b = bytes.clone();
    let method_ffi = FfiStr {
        ptr: m.as_ptr(),
        len: m.len(),
    };
    let target_ffi = FfiStr {
        ptr: t.as_ptr(),
        len: t.len(),
    };
    let body_ffi = FfiBuf {
        ptr: b.as_ptr(),
        len: b.len(),
    };

    let (response_tx, response_rx) = oneshot::channel::<FfiRespOwned>();
    PENDING_RESPONSES
        .get()
        .unwrap()
        .lock()
        .unwrap()
        .insert(req_id, response_tx);

    if let Some(cb) = DART_REQUEST_HANDLER.get() {
        (cb)(
            req_id,
            method_ffi,
            target_ffi,
            h.as_ptr(),
            h.len(),
            body_ffi,
        );
    } else {
        return HttpResponse::InternalServerError().finish();
    }

    match tokio::time::timeout(std::time::Duration::from_secs(60), response_rx).await {
        Ok(Ok(resp)) => {
            let status_code = actix_web::http::StatusCode::from_u16(resp.status)
                .unwrap_or(actix_web::http::StatusCode::OK);
            let mut builder = HttpResponse::build(status_code);

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
                builder.append_header((key.to_string(), val.to_string()));
            }

            if status_code == actix_web::http::StatusCode::NOT_FOUND {
                if let Some(fallback_fn) = fallback {
                    return fallback_fn();
                }
            }

            builder.body(Bytes::from(resp.body))
        }
        _ => {
            if let Some(fallback_fn) = fallback {
                fallback_fn()
            } else {
                HttpResponse::GatewayTimeout().finish()
            }
        }
    }
}

async fn health_route(req: HttpRequest, payload: web::Payload) -> HttpResponse {
    dart_proxy_with_fallback(req, payload, Some(default_health_response)).await
}

async fn healthz_route(req: HttpRequest, payload: web::Payload) -> HttpResponse {
    dart_proxy_with_fallback(req, payload, Some(default_healthz_response)).await
}

async fn healths_route(req: HttpRequest, payload: web::Payload) -> HttpResponse {
    dart_proxy_with_fallback(req, payload, Some(default_healths_response)).await
}

fn default_health_response() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("application/json; charset=utf-8")
        .body(r#"{"status":"ok"}"#)
}

fn default_healthz_response() -> HttpResponse {
    HttpResponse::PermanentRedirect()
        .append_header(("location", "/health"))
        .finish()
}

fn default_healths_response() -> HttpResponse {
    HttpResponse::PermanentRedirect()
        .append_header(("location", "/health"))
        .finish()
}

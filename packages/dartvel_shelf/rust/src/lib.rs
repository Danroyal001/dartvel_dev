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
/// Installs rustls's ring provider once.
///
/// Moved here when the HTTP client became its own crate: a second provider
/// makes rustls panic rather than choose, so each crate installs the same one
/// exactly once for itself.
fn ensure_crypto_provider() {
    static INSTALLED: std::sync::OnceLock<()> = std::sync::OnceLock::new();
    INSTALLED.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

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

// Dart request callback:
// void(req_id, method, target, hdrs_flat, hdrs_len, body, peer)
//
// `peer` is the connection's remote socket address as text -- `a.b.c.d:port`
// or `[v6]:port` -- taken from the accepted socket, or empty when there is
// none. It is the only thing in a request a client cannot choose, which is
// why it is passed at all: without it every per-source limit in Dart keyed on
// a header.
pub type DartReqHandler = extern "C" fn(u64, FfiStr, FfiStr, *const u8, usize, FfiBuf, FfiStr);

/// The shape of the calls between this library and Dart.
///
/// Raised whenever a callback's signature changes. A Dart side built for one
/// shape calling a library built for another does not fail cleanly: a
/// callback invoked with fewer arguments than Dart expects reads whatever is
/// in the missing argument's register, and a stale committed library would do
/// exactly that. Dart checks this before registering anything.
pub const AW_ABI_VERSION: u32 = 2;

#[no_mangle]
pub extern "C" fn aw_abi_version() -> u32 {
    AW_ABI_VERSION
}

// Dart stream cancel callback: void(req_id)
pub type DartStreamCancelHandler = extern "C" fn(u64);

// ===== Globals =====
// Replaceable rather than set-once: each `serve()` owns its own Dart
// callbacks, and a stale pointer here is a use-after-free the moment the
// server that registered it closes them.
static DART_REQUEST_HANDLER: OnceCell<Mutex<Option<DartReqHandler>>> = OnceCell::new();
/// The Dart request handler belonging to each server.
///
/// DART_REQUEST_HANDLER above is a single slot that every aw_register_handler
/// call overwrote, so with two servers in one process the last one to start
/// answered for all of them — and answered with a plausible 404 from the wrong
/// router rather than an error. dart test runs suites concurrently in one
/// process sharing one loaded library, so this is the ordinary case and not a
/// contrived one.
///
/// The global slot stays as the source aw_start snapshots from, which keeps
/// the FFI call order (register, then start) unchanged.
static SERVER_REQUEST_HANDLERS: OnceCell<Mutex<HashMap<u64, DartReqHandler>>> = OnceCell::new();

/// What a thread registered but has not yet started a server with.
///
/// Registering and starting are two calls, and the global slots between
/// them belong to whichever thread wrote last. Two isolates starting a
/// server at the same moment -- what `dart test` does on an ordinary run,
/// one loaded library and a suite per isolate -- interleave as register A,
/// register B, start A, start B. Server A then takes B's callbacks: it
/// answers its own port out of B's router, which is a plausible 404 rather
/// than an error, and it holds a callback B frees when B stops, so the
/// next request into A invokes a deleted Dart callback and the process
/// aborts on "Callback invoked after it has been deleted".
///
/// Keyed by thread, the two calls cannot interleave: serve() makes both
/// without yielding, and an isolate has a thread of its own.
static PENDING_REQUEST_HANDLERS: OnceCell<Mutex<HashMap<std::thread::ThreadId, DartReqHandler>>> =
    OnceCell::new();
static PENDING_CANCEL_HANDLERS: OnceCell<
    Mutex<HashMap<std::thread::ThreadId, DartStreamCancelHandler>>,
> = OnceCell::new();

/// Each server's own stream-cancel callback, for the reason the request
/// handlers are per server: a stream dropping under one server must not
/// reach for a callback another server has already freed.
static SERVER_CANCEL_HANDLERS: OnceCell<Mutex<HashMap<u64, DartStreamCancelHandler>>> =
    OnceCell::new();

/// Rides along in the request extensions so a handler can tell which server
/// took the request. Cheaper than threading state through every route.
#[derive(Clone, Copy)]
struct ServerId(u64);
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
/// One streamed body chunk, or the error that ended the stream.
type StreamChunkResult = Result<Bytes, axum::BoxError>;
type StreamChunkSender = mpsc::UnboundedSender<StreamChunkResult>;
type StreamChunkReceiver = mpsc::UnboundedReceiver<StreamChunkResult>;

/// Unbounded because `aw_stream_send_chunk` is called from Dart's thread,
/// which is not a runtime thread: a bounded sender there can only drop the
/// chunk, block the isolate, or reorder it behind a spawned send. Buffering
/// instead trades memory for a stream that is neither lossy nor reordered.
static PENDING_STREAM_SENDERS: OnceCell<Mutex<HashMap<u64, StreamChunkSender>>> =
    OnceCell::new();
/// Receivers are created when Dart completes the response rather than when the
/// server task builds the body, so a chunk sent immediately after
/// `aw_complete` still has somewhere to go.
static PENDING_STREAM_RECEIVERS: OnceCell<Mutex<HashMap<u64, StreamChunkReceiver>>> =
    OnceCell::new();
/// Server threads, so a stop can wait for one to finish before Dart frees the
/// callbacks its in-flight streams still call.
static SERVER_THREADS: OnceCell<Mutex<HashMap<u64, std::thread::JoinHandle<()>>>> =
    OnceCell::new();
static NEXT_ID: OnceCell<AtomicU64> = OnceCell::new();
static TLS_CONFIG: OnceCell<Arc<ServerConfig>> = OnceCell::new();
static SERVER_HANDLES: OnceCell<Mutex<HashMap<u64, axum_server::Handle>>> = OnceCell::new();
static NEXT_SERVER_ID: OnceCell<AtomicU64> = OnceCell::new();
/// The port each server is actually listening on.
///
/// Not the port that was asked for: a caller may pass 0 to let the OS assign
/// one, and 0 is not an address anything can connect to. Without this the
/// caller would have no way to find out where its own server ended up.
static SERVER_PORTS: OnceCell<Mutex<HashMap<u64, u16>>> = OnceCell::new();
static CORS_CONFIG: OnceCell<Mutex<Option<Arc<CorsOptions>>>> = OnceCell::new();
static STATIC_DIR: OnceCell<Mutex<Option<String>>> = OnceCell::new();
static SPA_ROOT_DIR: OnceCell<Mutex<Option<String>>> = OnceCell::new();
static COMPRESSION_ENABLED: OnceCell<Mutex<bool>> = OnceCell::new();

/// How long a request may take to arrive and be answered when the caller did
/// not say: reading its headers, reading its body, and waiting for Dart.
const DEFAULT_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// The request timeout each thread configured and has not yet started a
/// server with. Keyed by thread for the reason the pending handlers are: two
/// isolates starting servers at once must not take each other's setting.
static PENDING_REQUEST_TIMEOUTS: OnceCell<
    Mutex<HashMap<std::thread::ThreadId, std::time::Duration>>,
> = OnceCell::new();

/// Rides in the request extensions beside [ServerId].
#[derive(Clone, Copy)]
struct RequestTimeout(std::time::Duration);

/// Bytes a request body may be when the server configured no limit: 1 MiB.
///
/// Every body is held whole in memory, here and again in Dart, so this is
/// the figure one request can cost, times each connection a client opens.
/// 1 MiB is what `bodyLimit` already gives a route in Dart, so declaring it
/// and declaring nothing agree, and what nginx accepts by default, so an
/// application behind one is not refused differently here. A route that
/// takes more says so, and only that route gets it.
const DEFAULT_MAX_BODY_BYTES: u64 = 1024 * 1024;

/// One piece of one segment of a route pattern.
#[derive(Debug)]
enum PatternPiece {
    Literal(String),
    /// One or more characters of a segment, as `[^/]+` in the Dart router.
    Parameter,
}

/// A route as registered in Dart, reduced to what matching a path needs.
#[derive(Debug)]
struct RouteBodyLimit {
    method: String,
    segments: Vec<Vec<PatternPiece>>,
    /// None: the server's limit.
    max_bytes: Option<u64>,
}

/// The limits one server applies, riding in the request extensions.
///
/// The body is read here, before any Dart runs, so a limit Dart checks after
/// the read cannot bound what was buffered. The routes come from Dart's
/// router in its own order, and a request takes the limit of the first one
/// that matches it, as the router dispatches.
#[derive(Clone)]
struct BodyLimits {
    default: u64,
    routes: Arc<Vec<RouteBodyLimit>>,
}

struct PendingBodyLimits {
    default: u64,
    routes: Vec<RouteBodyLimit>,
}

/// What each thread configured and has not yet started a server with, for
/// the reason the pending handlers are keyed by thread.
static PENDING_BODY_LIMITS: OnceCell<Mutex<HashMap<std::thread::ThreadId, PendingBodyLimits>>> =
    OnceCell::new();

fn is_name_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_'
}

fn is_name_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// A route pattern as the Dart router reads it (URLPattern in dartvel_core).
///
/// There, `<name>` is `:name` and `<name|expression>` is `:name(expression)`;
/// a colon followed by a name is a parameter matching one or more characters
/// of a segment; and everything else is text -- including the parentheses,
/// which the router escapes before it looks for parameters, so the
/// expression is never applied. Read the same way here, the two match the
/// same paths.
fn parse_route_pattern(pattern: &str) -> Vec<Vec<PatternPiece>> {
    normalize_angle_parameters(pattern)
        .split('/')
        .map(parse_segment)
        .collect()
}

fn normalize_angle_parameters(pattern: &str) -> String {
    let mut out = String::with_capacity(pattern.len());
    let mut rest = pattern;
    while let Some(open) = rest.find('<') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        let name_len = after
            .chars()
            .enumerate()
            .take_while(|(i, c)| if *i == 0 { is_name_start(*c) } else { is_name_char(*c) })
            .count();
        if name_len > 0 {
            // Names are ASCII, so characters and bytes agree.
            let (name, tail) = after.split_at(name_len);
            if let Some(tail) = tail.strip_prefix('>') {
                out.push(':');
                out.push_str(name);
                rest = tail;
                continue;
            }
            if let Some(expression) = tail.strip_prefix('|') {
                if let Some(close) = expression.find('>').filter(|close| *close > 0) {
                    out.push(':');
                    out.push_str(name);
                    out.push('(');
                    out.push_str(&expression[..close]);
                    out.push(')');
                    rest = &expression[close + 1..];
                    continue;
                }
            }
        }
        out.push('<');
        rest = after;
    }
    out.push_str(rest);
    out
}

fn parse_segment(segment: &str) -> Vec<PatternPiece> {
    let mut pieces = Vec::new();
    let mut literal = String::new();
    let mut chars = segment.chars().peekable();
    while let Some(c) = chars.next() {
        if c != ':' || !chars.peek().is_some_and(|next| is_name_start(*next)) {
            literal.push(c);
            continue;
        }
        while chars.peek().is_some_and(|next| is_name_char(*next)) {
            chars.next();
        }
        if !literal.is_empty() {
            pieces.push(PatternPiece::Literal(std::mem::take(&mut literal)));
        }
        pieces.push(PatternPiece::Parameter);
    }
    if !literal.is_empty() {
        pieces.push(PatternPiece::Literal(literal));
    }
    pieces
}

fn segment_matches(pieces: &[PatternPiece], text: &str) -> bool {
    match pieces.split_first() {
        None => text.is_empty(),
        Some((PatternPiece::Literal(literal), rest)) => text
            .strip_prefix(literal.as_str())
            .is_some_and(|tail| segment_matches(rest, tail)),
        // At least one character, and as many as leave the rest a match.
        Some((PatternPiece::Parameter, rest)) => text
            .char_indices()
            .map(|(i, _)| i)
            .skip(1)
            .chain(std::iter::once(text.len()))
            .filter(|end| *end > 0)
            .any(|end| segment_matches(rest, &text[end..])),
    }
}

/// `.` or `..`, including percent-encoded. Dart resolves these away before it
/// routes, so a route matched with one in the path is not the route that
/// runs.
fn is_dot_segment(segment: &str) -> bool {
    let decoded = segment.to_ascii_lowercase().replace("%2e", ".");
    decoded == "." || decoded == ".."
}

impl BodyLimits {
    /// The limit for a request: the first route matching it decides, and a
    /// request no route matches -- or one whose path has a dot segment --
    /// gets the server's.
    fn for_request(&self, method: &str, path: &str) -> u64 {
        let segments: Vec<&str> = path.split('/').collect();
        if segments.iter().any(|segment| is_dot_segment(segment)) {
            return self.default;
        }
        self.routes
            .iter()
            .find(|route| {
                (route.method == "*" || route.method == method)
                    && route.segments.len() == segments.len()
                    && route
                        .segments
                        .iter()
                        .zip(&segments)
                        .all(|(pieces, segment)| segment_matches(pieces, segment))
            })
            .map_or(self.default, |route| route.max_bytes.unwrap_or(self.default))
    }
}

/// This thread's configured limits, or the default for a server that
/// configured none.
fn take_pending_body_limits() -> BodyLimits {
    let pending = PENDING_BODY_LIMITS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&std::thread::current().id()));
    match pending {
        Some(pending) => BodyLimits {
            default: pending.default,
            routes: Arc::new(pending.routes),
        },
        None => BodyLimits {
            default: DEFAULT_MAX_BODY_BYTES,
            routes: Arc::new(Vec::new()),
        },
    }
}

/// The bytes a request's callback points into.
///
/// The callback is a Dart listener: it runs when the isolate gets to it, not
/// when it is called. The pointers it receives used to point into locals of
/// the proxy future, which dropped them when the wait for Dart timed out -- so
/// an isolate busy past the timeout read freed memory. They are kept here
/// instead until Dart says it has copied them (aw_request_received) or answers
/// (aw_complete), whichever comes first.
struct RequestParts {
    _method: Vec<u8>,
    _target: Vec<u8>,
    _headers: Vec<u8>,
    _body: Bytes,
    _peer: Vec<u8>,
}

static PENDING_REQUEST_PARTS: OnceCell<Mutex<HashMap<u64, RequestParts>>> = OnceCell::new();

fn retain_request_parts(req_id: u64, parts: RequestParts) {
    let map = PENDING_REQUEST_PARTS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(map).insert(req_id, parts);
}

fn release_request_parts(req_id: u64) {
    if let Some(map) = PENDING_REQUEST_PARTS.get() {
        safe_lock(map).remove(&req_id);
    }
}

/// aw_start could not parse host:port into an address.
const AW_START_BAD_ADDRESS: i32 = -2;
/// aw_start parsed the address but could not bind it — in use, or not
/// permitted. Distinct from -1 so a caller can say which happened.
const AW_START_BIND_FAILED: i32 = -3;

// Flags for aw_start
pub const AW_FLAG_H2C: u32 = 0x01;

// Stream wrapper to trigger Dart cancellation on drop
struct CancelOnDropStream<S> {
    inner: S,
    req_id: u64,
    /// The server this stream belongs to, so the cancel goes to that
    /// server's Dart callback rather than to whichever was registered last.
    server_id: Option<u64>,
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
        let cb = self
            .server_id
            .and_then(|id| {
                SERVER_CANCEL_HANDLERS
                    .get()
                    .and_then(|handlers| safe_lock(handlers).get(&id).copied())
            })
            .or_else(|| DART_CANCEL_HANDLER.get().and_then(|slot| *safe_lock(slot)));
        if let Some(cb) = cb {
            (cb)(self.req_id);
        }
    }
}

// ===== FFI Exports =====
#[no_mangle]
pub extern "C" fn aw_register_handler(cb: DartReqHandler) {
    let slot = DART_REQUEST_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    // And against this thread, which is where aw_start takes it from.
    let pending = PENDING_REQUEST_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(std::thread::current().id(), cb);
    let _ = SERVER_THREADS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_RESPONSES.set(Mutex::new(HashMap::new()));
    let _ = NEXT_ID.set(AtomicU64::new(1));
    let _ = SERVER_HANDLES.set(Mutex::new(HashMap::new()));
    let _ = SERVER_PORTS.set(Mutex::new(HashMap::new()));
    let _ = SERVER_REQUEST_HANDLERS.set(Mutex::new(HashMap::new()));
    let _ = NEXT_SERVER_ID.set(AtomicU64::new(1));
}

#[no_mangle]
pub extern "C" fn aw_register_cancel_handler(cb: DartStreamCancelHandler) {
    let slot = DART_CANCEL_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let pending = PENDING_CANCEL_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(std::thread::current().id(), cb);
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
                // Only the first of these wins: a PKCS#8 key later in the
                // file still takes precedence by breaking out above.
                Item::Pkcs1Key(k) if key.is_none() => {
                    key = Some(PrivateKeyDer::from(k));
                }
                Item::Sec1Key(k) if key.is_none() => {
                    key = Some(PrivateKeyDer::from(k));
                }
                _ => {}
            }
        }
        match key {
            Some(k) => k,
            None => return 3,
        }
    };

    // Same ambiguity as the client: with two rustls providers compiled in,
    // builder() panics unless a process default exists.
    ensure_crypto_provider();

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

/// The request timeout for the next server this thread starts, in
/// milliseconds. It bounds reading a request's headers, reading its body,
/// and waiting for Dart's answer; past it the connection is answered (408
/// for a body that never arrived, 504 for Dart) or, with headers unfinished,
/// closed. Zero is refused with 1: a request that may take no time at all is
/// a server that answers nothing.
#[no_mangle]
pub extern "C" fn aw_configure_request_timeout(milliseconds: u64) -> i32 {
    if milliseconds == 0 {
        return 1;
    }
    let pending = PENDING_REQUEST_TIMEOUTS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(
        std::thread::current().id(),
        std::time::Duration::from_millis(milliseconds),
    );
    0
}

/// Dart has copied the request [req_id]'s bytes out of native memory, which
/// may now be freed.
#[no_mangle]
pub extern "C" fn aw_request_received(req_id: u64) {
    release_request_parts(req_id);
}

/// The largest request body the next server this thread starts reads, in
/// bytes, for every request no route limit covers. A body declared larger is
/// answered 413 without being read, and one that grows past it while being
/// read is answered 413 there; both close the connection. Zero is refused
/// with 1: a server that reads no body at all is not a limit anybody means.
///
/// Also forgets any route limits this thread added and never started a
/// server with, so a serve() that failed between the two leaves nothing
/// behind for the next.
#[no_mangle]
pub extern "C" fn aw_configure_max_body_bytes(bytes: u64) -> i32 {
    if bytes == 0 {
        return 1;
    }
    let pending = PENDING_BODY_LIMITS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(
        std::thread::current().id(),
        PendingBodyLimits {
            default: bytes,
            routes: Vec::new(),
        },
    );
    0
}

/// Adds a route to the next server this thread starts, after the ones
/// already added: its method (`*` for any), its pattern as the Dart router
/// registered it, and the largest body it reads in bytes, or 0 for the
/// server's limit. A request takes the limit of the first route that matches
/// it, in the order they were added, which is the order the router
/// dispatches in. Returns 2 when the method or pattern is not text.
#[no_mangle]
pub extern "C" fn aw_configure_route_body_limit(method: FfiStr, pattern: FfiStr, bytes: u64) -> i32 {
    let (Some(method), Some(pattern)) = (ffi_text(&method), ffi_text(&pattern)) else {
        return 2;
    };
    let route = RouteBodyLimit {
        method: method.to_string(),
        segments: parse_route_pattern(pattern),
        max_bytes: (bytes != 0).then_some(bytes),
    };
    let pending = PENDING_BODY_LIMITS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending)
        .entry(std::thread::current().id())
        .or_insert_with(|| PendingBodyLimits {
            default: DEFAULT_MAX_BODY_BYTES,
            routes: Vec::new(),
        })
        .routes
        .push(route);
    0
}

/// The text an [FfiStr] points at, or None when it is not UTF-8.
fn ffi_text(text: &FfiStr) -> Option<&str> {
    if text.ptr.is_null() {
        return (text.len == 0).then_some("");
    }
    // SAFETY: FfiStr contract guarantees ptr is valid for len bytes
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(text.ptr, text.len) }).ok()
}

/// Whether a request's declared Content-Length is already over [limit]. A
/// length too long to be a number is over it; a header that is not a length
/// at all is no information, and the read bounds that request instead.
fn declared_too_large(headers: &axum::http::HeaderMap, limit: u64) -> bool {
    let Some(text) = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
    else {
        return false;
    };
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    match text.parse::<u64>() {
        Ok(declared) => declared > limit,
        Err(_) => true,
    }
}

/// 413, closing the connection so the rest of the body is never read.
///
/// The same words the route checks in Dart answer with, so a client is told
/// the same thing whichever side refused it, and nothing of the request: the
/// limit is the contract, not something the client sent.
fn too_large_response(limit: u64) -> Response<Body> {
    let mut response = closing_response(StatusCode::PAYLOAD_TOO_LARGE);
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        axum::http::HeaderValue::from_static("text/plain; charset=utf-8"),
    );
    *response.body_mut() = Body::from(format!(
        "Request body too large. This endpoint accepts at most {limit} bytes."
    ));
    response
}

/// Bounds reading a request's headers. hyper has a header read timeout, but
/// it does nothing without a timer, and axum-server installs none.
fn bound_header_read(
    builder: &mut hyper_util::server::conn::auto::Builder<hyper_util::rt::TokioExecutor>,
    timeout: std::time::Duration,
) {
    builder
        .http1()
        .timer(hyper_util::rt::TokioTimer::new())
        .header_read_timeout(timeout);
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

    // This thread's, or the default: a server that configured nothing does
    // not inherit what another server asked for.
    let request_timeout = PENDING_REQUEST_TIMEOUTS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&std::thread::current().id()))
        .unwrap_or(DEFAULT_REQUEST_TIMEOUT);
    // Likewise: this thread's body limits, or the default.
    let body_limits = take_pending_body_limits();

    let handle = axum_server::Handle::new();
    if let Some(handles) = SERVER_HANDLES.get() {
        safe_lock(handles).insert(server_id, handle.clone());
    }

    // The bind happens here, on the calling thread, and not inside the thread
    // below. It used to be the last thing a spawned thread did, which meant
    // aw_start returned a positive id before anything had tried to listen: a
    // bind that failed panicked inside a detached thread while the caller held
    // a handle that looked healthy. The first symptom was a connection refused
    // somewhere unrelated, which is the worst place for it to appear.
    // Parsed as an IP first: `format!("{host}:{port}")` is not a socket
    // address for IPv6, where "::1:8080" is ambiguous and "[::1]:8080" is what
    // the parser wants, so every IPv6 host was refused as unparseable.
    let parsed_addr: std::net::SocketAddr = match host_string
        .trim_start_matches('[')
        .trim_end_matches(']')
        .parse::<std::net::IpAddr>()
    {
        Ok(ip) => std::net::SocketAddr::new(ip, port),
        Err(_) => match format!("{}:{}", host_string, port).parse() {
            Ok(parsed) => parsed,
            Err(_) => return AW_START_BAD_ADDRESS,
        },
    };
    let listener = match std::net::TcpListener::bind(parsed_addr) {
        Ok(listener) => listener,
        Err(_) => return AW_START_BIND_FAILED,
    };
    // Port 0 asks the OS to choose, so what was requested and what was bound
    // are different numbers and only this one is callable.
    let bound_port = match listener.local_addr() {
        Ok(local) => local.port(),
        Err(_) => return AW_START_BIND_FAILED,
    };
    if let Some(ports) = SERVER_PORTS.get() {
        safe_lock(ports).insert(server_id, bound_port);
    }
    // This thread's, not the global slot's: another thread registering
    // between our register and this call would otherwise hand this server
    // that thread's router and its callbacks. The global stays as the
    // fallback for a caller that registered on some other thread.
    let this_thread = std::thread::current().id();
    let request_handler = PENDING_REQUEST_HANDLERS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&this_thread))
        .or_else(|| DART_REQUEST_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(handler) = request_handler {
        let handlers = SERVER_REQUEST_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server_id, handler);
    }
    let cancel_handler = PENDING_CANCEL_HANDLERS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&this_thread))
        .or_else(|| DART_CANCEL_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(handler) = cancel_handler {
        let handlers = SERVER_CANCEL_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server_id, handler);
    }

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

            // Tags every request with the server that accepted it, so the
            // proxy can reach this server's Dart handler rather than whichever
            // was registered most recently.
            app = app.layer(axum::Extension(ServerId(server_id)));
            app = app.layer(axum::Extension(RequestTimeout(request_timeout)));
            app = app.layer(axum::Extension(body_limits));
            // Outermost: a panic anywhere in answering a request is a 500
            // rather than a connection dropped with no answer at all.
            app = app.layer(tower_http::catch_panic::CatchPanicLayer::new());

            // Already bound above, so nothing here can fail for want of a
            // port. A serve error now means the loop ended, which is what
            // shutdown looks like too — it is not grounds for a panic in a
            // thread nobody is watching.
            // With connect info, so each request carries the socket address it
            // was accepted from and dart_proxy can hand it to Dart.
            let result = if let Some(tls_config) = TLS_CONFIG.get() {
                let rustls_config = axum_server::tls_rustls::RustlsConfig::from_config(tls_config.clone());
                let mut server = axum_server::from_tcp_rustls(listener, rustls_config);
                bound_header_read(server.http_builder(), request_timeout);
                server
                    .handle(handle_clone)
                    .serve(app.into_make_service_with_connect_info::<std::net::SocketAddr>())
                    .await
            } else {
                let mut server = axum_server::from_tcp(listener);
                bound_header_read(server.http_builder(), request_timeout);
                server
                    .handle(handle_clone)
                    .serve(app.into_make_service_with_connect_info::<std::net::SocketAddr>())
                    .await
            };
            if let Err(error) = result {
                eprintln!("dartvel: server {server_id} stopped: {error}");
            }

            if let Some(handles) = SERVER_HANDLES.get() {
                safe_lock(handles).remove(&server_id);
            }
            if let Some(ports) = SERVER_PORTS.get() {
                safe_lock(ports).remove(&server_id);
            }
            if let Some(handlers) = SERVER_REQUEST_HANDLERS.get() {
                safe_lock(handlers).remove(&server_id);
            }
            if let Some(handlers) = SERVER_CANCEL_HANDLERS.get() {
                safe_lock(handlers).remove(&server_id);
            }
        });
    });

    if let Some(threads) = SERVER_THREADS.get() {
        safe_lock(threads).insert(server_id, server_thread);
    }

    server_id as i32
}

/// The port [server_id] is listening on, or 0 if it is unknown.
///
/// Meaningful because a caller may start a server on port 0 and let the OS
/// choose; without this there is no way to learn where it landed.
#[no_mangle]
pub extern "C" fn aw_server_port(server_id: u64) -> u16 {
    SERVER_PORTS
        .get()
        .and_then(|ports| safe_lock(ports).get(&server_id).copied())
        .unwrap_or(0)
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
    // An answer means Dart read the request, whether or not it said so.
    release_request_parts(req_id);
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
/// The accepted socket's remote address, or an empty string when the request
/// did not come through a listener that records one.
///
/// An IPv4 client of a dual-stack socket is reported as its IPv4 address
/// rather than `::ffff:a.b.c.d`, which compares unequal to the same host in
/// every list and limit. The scope id is dropped: it names an interface on
/// this host, not a different peer.
fn peer_text(req: &Request<Body>) -> String {
    match req
        .extensions()
        .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
    {
        Some(axum::extract::ConnectInfo(addr)) => canonical_peer(*addr).to_string(),
        None => String::new(),
    }
}

fn canonical_peer(addr: std::net::SocketAddr) -> std::net::SocketAddr {
    match addr {
        std::net::SocketAddr::V6(v6) => match v6.ip().to_ipv4_mapped() {
            Some(v4) => std::net::SocketAddr::new(std::net::IpAddr::V4(v4), v6.port()),
            None => std::net::SocketAddr::new(std::net::IpAddr::V6(*v6.ip()), v6.port()),
        },
        v4 => v4,
    }
}

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
    // Read while the request is still whole; the body is taken further down.
    let server_id = req.extensions().get::<ServerId>().map(|ServerId(id)| *id);
    // One deadline for the body and for Dart: a request is bounded as a
    // whole, not per phase, so a client cannot spend the timeout twice.
    let request_timeout = req
        .extensions()
        .get::<RequestTimeout>()
        .map(|RequestTimeout(timeout)| *timeout)
        .unwrap_or(DEFAULT_REQUEST_TIMEOUT);
    let deadline = tokio::time::Instant::now() + request_timeout;
    // Decided before a byte of the body is read. Every body is held whole
    // here and again in Dart, and it was read with no bound at all, so one
    // client could send as much as it liked -- or a chunked body that never
    // ended -- and all of it was kept.
    let body_limit = req
        .extensions()
        .get::<BodyLimits>()
        .map_or(DEFAULT_MAX_BODY_BYTES, |limits| {
            limits.for_request(req.method().as_str(), req.uri().path())
        });
    // A body announced too large is refused without reading any of it.
    if declared_too_large(req.headers(), body_limit) {
        return too_large_response(body_limit);
    }
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
    let peer = peer_text(&req).into_bytes();
    
    let mut body_buf = BytesMut::new();
    let mut body_stream = req.into_body().into_data_stream();
    // Whether the body ended within the limit. A chunk that would take it
    // past is refused before it is kept, so no more than the limit is ever
    // held: a Content-Length that understates what follows ends the body
    // where it said, and a chunked body -- slow, or endless -- stops here.
    let read_body = async {
        while let Some(chunk) = body_stream.next().await {
            match chunk {
                Ok(bytes) => {
                    if (body_buf.len() as u64).saturating_add(bytes.len() as u64) > body_limit {
                        return false;
                    }
                    body_buf.extend_from_slice(&bytes);
                }
                Err(_) => {
                    body_buf.clear();
                    break;
                }
            }
        }
        true
    };
    // A declared body that never arrives held the connection for as long as
    // the client kept it open.
    match tokio::time::timeout_at(deadline, read_body).await {
        Err(_) => return closing_response(StatusCode::REQUEST_TIMEOUT),
        // Closed as well as answered, so the rest is never read.
        Ok(false) => return too_large_response(body_limit),
        Ok(true) => {}
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
    let peer_ffi = FfiStr {
        ptr: peer.as_ptr(),
        len: peer.len(),
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

    // This server's handler first. The global is the fallback, for any path
    // that reaches here without having gone through a server.
    let request_handler = server_id
        .and_then(|id| {
            SERVER_REQUEST_HANDLERS
                .get()
                .and_then(|handlers| safe_lock(handlers).get(&id).copied())
        })
        .or_else(|| DART_REQUEST_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    let Some(cb) = request_handler else {
        if let Some(mutex) = PENDING_RESPONSES.get() {
            safe_lock(mutex).remove(&req_id);
        }
        return plain_response(StatusCode::INTERNAL_SERVER_ERROR);
    };
    let headers_ptr = flattened_headers.as_ptr();
    let headers_len = flattened_headers.len();
    // Moving a Vec or Bytes moves its handle, not its heap buffer, so the
    // pointers above stay valid for as long as the parts are held.
    retain_request_parts(
        req_id,
        RequestParts {
            _method: method,
            _target: target,
            _headers: flattened_headers,
            _body: bytes,
            _peer: peer,
        },
    );
    (cb)(
        req_id,
        method_ffi,
        target_ffi,
        headers_ptr,
        headers_len,
        body_ffi,
        peer_ffi,
    );

    match tokio::time::timeout_at(deadline, response_rx).await {
        Ok(Ok(resp)) => response_from_dart(resp, req_id, server_id, fallback),
        _ => {
            if let Some(mutex) = PENDING_RESPONSES.get() {
                safe_lock(mutex).remove(&req_id);
            }
            if let Some(fallback_fn) = fallback {
                fallback_fn()
            } else {
                // Closed as well as answered: the handler may still be
                // running, and the slot is what a slow request was costing.
                closing_response(StatusCode::GATEWAY_TIMEOUT)
            }
        }
    }
}

fn plain_response(status: StatusCode) -> Response<Body> {
    let mut response = Response::new(Body::empty());
    *response.status_mut() = status;
    response
}

/// [status], and the connection closed after it.
fn closing_response(status: StatusCode) -> Response<Body> {
    let mut response = plain_response(status);
    response
        .headers_mut()
        .insert(header::CONNECTION, axum::http::HeaderValue::from_static("close"));
    response
}

/// Drops a stream Dart opened for a response that will not be sent, which
/// tells Dart to stop producing it.
fn abandon_stream(req_id: u64, server_id: Option<u64>) {
    let rx = PENDING_STREAM_RECEIVERS
        .get()
        .and_then(|m| safe_lock(m).remove(&req_id));
    if let Some(rx) = rx {
        drop(CancelOnDropStream {
            inner: tokio_stream::wrappers::UnboundedReceiverStream::new(rx),
            req_id,
            server_id,
        });
    }
}

/// The response Dart answered with, or 500 when it cannot be sent.
///
/// A header name or value HTTP does not allow -- a newline in a value is the
/// usual one -- panicked on unwrap here, and the connection dropped with no
/// answer; a status outside 100-999 was sent as 200. Logged by what was wrong
/// and never by the header's text, which can be anything the handler put
/// there, including the request.
fn response_from_dart(
    resp: FfiRespOwned,
    req_id: u64,
    server_id: Option<u64>,
    fallback: Option<fn() -> Response<Body>>,
) -> Response<Body> {
    let refuse = |why: &str| {
        eprintln!("dartvel: a handler's response {why}; answered 500");
        if resp.is_stream != 0 {
            abandon_stream(req_id, server_id);
        }
        plain_response(StatusCode::INTERNAL_SERVER_ERROR)
    };
    let Ok(status_code) = StatusCode::from_u16(resp.status) else {
        return refuse("has a status that is not an HTTP status");
    };
    let mut headers = axum::http::HeaderMap::new();
    let mut fields = resp.headers.split(|&c| c == 0);
    while let Some(name) = fields.next() {
        let value = fields.next().unwrap_or_default();
        if name.is_empty() {
            continue;
        }
        let Ok(name) = header::HeaderName::from_bytes(name) else {
            return refuse("has a header name HTTP does not allow");
        };
        let Ok(value) = axum::http::HeaderValue::from_bytes(value) else {
            return refuse("has a header value HTTP does not allow");
        };
        headers.append(name, value);
    }

    if status_code == StatusCode::NOT_FOUND {
        if let Some(fallback_fn) = fallback {
            if resp.is_stream != 0 {
                abandon_stream(req_id, server_id);
            }
            return fallback_fn();
        }
    }

    let body = if resp.is_stream != 0 {
        let rx = PENDING_STREAM_RECEIVERS
            .get()
            .and_then(|m| safe_lock(m).remove(&req_id));
        let Some(rx) = rx else {
            return plain_response(StatusCode::INTERNAL_SERVER_ERROR);
        };
        Body::from_stream(CancelOnDropStream {
            inner: tokio_stream::wrappers::UnboundedReceiverStream::new(rx),
            req_id,
            server_id,
        })
    } else {
        Body::from(resp.body)
    };
    let mut response = Response::new(body);
    *response.status_mut() = status_code;
    *response.headers_mut() = headers;
    response
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

#[cfg(test)]
mod request_tests {
    use super::*;

    fn answered(status: u16, headers: &[u8]) -> FfiRespOwned {
        FfiRespOwned {
            status,
            headers: headers.to_vec(),
            body: b"body".to_vec(),
            is_stream: 0,
        }
    }

    fn held(req_id: u64) -> bool {
        PENDING_REQUEST_PARTS
            .get()
            .is_some_and(|map| safe_lock(map).contains_key(&req_id))
    }

    fn parts() -> RequestParts {
        RequestParts {
            _method: b"GET".to_vec(),
            _target: b"/".to_vec(),
            _headers: Vec::new(),
            _body: Bytes::new(),
            _peer: Vec::new(),
        }
    }

    #[test]
    fn a_header_value_http_does_not_allow_is_a_500_not_a_panic() {
        let response = response_from_dart(answered(200, b"x-a\0line\r\nsplit\0"), 9001, None, None);
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn a_header_name_http_does_not_allow_is_a_500() {
        let response = response_from_dart(answered(200, b"bad name\0v\0"), 9002, None, None);
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn a_status_that_is_not_one_is_a_500_not_a_200() {
        let response = response_from_dart(answered(42, b""), 9003, None, None);
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn a_sendable_response_keeps_its_status_and_every_header() {
        let response = response_from_dart(
            answered(201, b"x-a\0one\0x-a\0two\0content-type\0text/plain\0"),
            9004,
            None,
            None,
        );
        assert_eq!(response.status(), StatusCode::CREATED);
        let values: Vec<_> = response.headers().get_all("x-a").iter().collect();
        assert_eq!(values, ["one", "two"]);
        assert_eq!(response.headers()["content-type"], "text/plain");
    }

    #[test]
    fn a_request_is_held_until_dart_says_it_has_it() {
        retain_request_parts(9101, parts());
        assert!(held(9101));
        aw_request_received(9101);
        assert!(!held(9101));
    }

    #[test]
    fn an_answer_releases_a_request_dart_never_acknowledged() {
        retain_request_parts(9102, parts());
        let empty = FfiResp {
            status: 200,
            body: FfiBuf { ptr: std::ptr::null(), len: 0 },
            hdrs: std::ptr::null(),
            hdrs_len: 0,
            is_stream: 0,
        };
        aw_complete(9102, empty);
        assert!(!held(9102));
    }

    #[test]
    fn a_request_timeout_of_zero_is_refused() {
        assert_ne!(aw_configure_request_timeout(0), 0);
        assert_eq!(aw_configure_request_timeout(1500), 0);
        let pending = PENDING_REQUEST_TIMEOUTS.get().map(|p| {
            safe_lock(p).remove(&std::thread::current().id())
        });
        assert_eq!(pending, Some(Some(std::time::Duration::from_millis(1500))));
    }
}

#[cfg(test)]
mod body_limit_tests {
    use super::*;

    fn limits(routes: &[(&str, &str, Option<u64>)]) -> BodyLimits {
        BodyLimits {
            default: 100,
            routes: Arc::new(
                routes
                    .iter()
                    .map(|(method, pattern, max_bytes)| RouteBodyLimit {
                        method: method.to_string(),
                        segments: parse_route_pattern(pattern),
                        max_bytes: *max_bytes,
                    })
                    .collect(),
            ),
        }
    }

    fn ffi(text: &str) -> FfiStr {
        FfiStr {
            ptr: text.as_ptr(),
            len: text.len(),
        }
    }

    #[test]
    fn a_path_no_route_matches_gets_the_server_limit() {
        let limits = limits(&[("POST", "/upload", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/elsewhere"), 100);
    }

    #[test]
    fn a_route_gets_its_own_limit_for_its_own_method_only() {
        let limits = limits(&[("POST", "/upload", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/upload"), 1000);
        assert_eq!(limits.for_request("PUT", "/upload"), 100);
    }

    #[test]
    fn a_parameter_is_one_segment_that_is_not_empty() {
        let limits = limits(&[("POST", "/files/:id", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/files/42"), 1000);
        assert_eq!(limits.for_request("POST", "/files/"), 100);
        assert_eq!(limits.for_request("POST", "/files"), 100);
        assert_eq!(limits.for_request("POST", "/files/4/2"), 100);
    }

    #[test]
    fn a_parameter_inside_a_segment_keeps_the_literal_around_it() {
        let limits = limits(&[("POST", "/files/:id.json", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/files/a.json"), 1000);
        assert_eq!(limits.for_request("POST", "/files/a.b.json"), 1000);
        assert_eq!(limits.for_request("POST", "/files/.json"), 100);
        assert_eq!(limits.for_request("POST", "/files/a.txt"), 100);
    }

    #[test]
    fn an_angle_bracket_parameter_is_a_parameter() {
        let limits = limits(&[("POST", "/raw/<name>/x", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/raw/abc/x"), 1000);
    }

    #[test]
    fn an_expression_after_a_parameter_is_text_as_in_the_dart_router() {
        // URLPattern escapes the parentheses before it looks for parameters,
        // so the expression is text there. Applied here, this side would
        // match paths the router never gives the route.
        let limits = limits(&[
            ("POST", r"/scans/<id|\d+>", Some(1000)),
            ("POST", r"/other/:id(\d+)", Some(1000)),
        ]);
        assert_eq!(limits.for_request("POST", "/scans/42"), 100);
        assert_eq!(limits.for_request("POST", r"/scans/42(\d+)"), 1000);
        assert_eq!(limits.for_request("POST", "/other/42"), 100);
        assert_eq!(limits.for_request("POST", r"/other/x(\d+)"), 1000);
    }

    #[test]
    fn a_colon_not_followed_by_a_name_is_text() {
        let limits = limits(&[("POST", "/a:/b", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/a:/b"), 1000);
        assert_eq!(limits.for_request("POST", "/ab/b"), 100);
    }

    #[test]
    fn the_first_route_that_matches_decides_even_with_no_limit_of_its_own() {
        let limits = limits(&[
            ("*", "/shadow/:name", None),
            ("POST", "/shadow/upload", Some(1000)),
        ]);
        assert_eq!(limits.for_request("POST", "/shadow/upload"), 100);
    }

    #[test]
    fn a_route_for_any_method_takes_every_method() {
        let limits = limits(&[("*", "/any", Some(1000))]);
        assert_eq!(limits.for_request("DELETE", "/any"), 1000);
    }

    #[test]
    fn a_trailing_slash_is_another_path() {
        let limits = limits(&[("POST", "/upload", Some(1000))]);
        assert_eq!(limits.for_request("POST", "/upload/"), 100);
    }

    #[test]
    fn a_dot_segment_never_reaches_a_route() {
        // Dart resolves these to some other path before routing, so the
        // route matched here would not be the one that runs.
        let limits = limits(&[("POST", "/files/:id", Some(1000)), ("*", "/:a/:b/:c", Some(1000))]);
        for path in ["/files/..", "/files/.", "/files/%2e%2E", "/files/.%2e", "/x/../y"] {
            assert_eq!(limits.for_request("POST", path), 100, "{path}");
        }
    }

    #[test]
    fn a_declared_length_over_the_limit_is_too_large() {
        let mut headers = axum::http::HeaderMap::new();
        assert!(!declared_too_large(&headers, 100));
        headers.insert(header::CONTENT_LENGTH, axum::http::HeaderValue::from_static("100"));
        assert!(!declared_too_large(&headers, 100));
        headers.insert(header::CONTENT_LENGTH, axum::http::HeaderValue::from_static("101"));
        assert!(declared_too_large(&headers, 100));
        headers.insert(
            header::CONTENT_LENGTH,
            axum::http::HeaderValue::from_static("99999999999999999999999"),
        );
        assert!(declared_too_large(&headers, 100));
    }

    #[tokio::test]
    async fn the_refusal_closes_and_names_the_limit_and_nothing_else() {
        let response = too_large_response(4096);
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
        assert_eq!(response.headers()[header::CONNECTION], "close");
        assert_eq!(response.headers()[header::CONTENT_TYPE], "text/plain; charset=utf-8");
        let body = axum::body::to_bytes(response.into_body(), 1024).await.unwrap();
        assert_eq!(
            &body[..],
            b"Request body too large. This endpoint accepts at most 4096 bytes."
        );
    }

    #[test]
    fn configuring_refuses_zero_and_starts_the_route_list_afresh() {
        assert_ne!(aw_configure_max_body_bytes(0), 0);
        assert_eq!(aw_configure_max_body_bytes(500), 0);
        // Zero is a route with no limit of its own, which still has to be
        // listed: it may come before a route with one.
        assert_eq!(aw_configure_route_body_limit(ffi("*"), ffi("/upload/:x"), 0), 0);
        assert_eq!(aw_configure_route_body_limit(ffi("POST"), ffi("/upload"), 9000), 0);
        let bad = [0xff_u8, 0xfe];
        let not_text = FfiStr {
            ptr: bad.as_ptr(),
            len: bad.len(),
        };
        assert_eq!(aw_configure_route_body_limit(ffi("POST"), not_text, 9000), 2);
        let started = take_pending_body_limits();
        assert_eq!(started.default, 500);
        assert_eq!(started.for_request("POST", "/upload"), 9000);
        assert_eq!(started.for_request("POST", "/upload/a"), 500);
        assert_eq!(started.routes.len(), 2);

        // A serve() that failed before starting leaves nothing behind for the
        // next server this thread starts.
        assert_eq!(aw_configure_route_body_limit(ffi("POST"), ffi("/stale"), 9000), 0);
        assert_eq!(aw_configure_max_body_bytes(700), 0);
        let next = take_pending_body_limits();
        assert_eq!(next.default, 700);
        assert_eq!(next.for_request("POST", "/stale"), 700);

        // And a server that configured nothing gets the default.
        assert_eq!(take_pending_body_limits().default, DEFAULT_MAX_BODY_BYTES);
    }
}

#[cfg(test)]
mod peer_tests {
    use super::canonical_peer;
    use std::net::SocketAddr;

    #[test]
    fn an_ipv4_client_of_a_dual_stack_socket_is_its_ipv4_address() {
        let mapped: SocketAddr = "[::ffff:203.0.113.7]:5100".parse().unwrap();
        assert_eq!(canonical_peer(mapped).to_string(), "203.0.113.7:5100");
    }

    #[test]
    fn ipv6_keeps_its_address_and_loses_its_scope() {
        let scoped = SocketAddr::V6(std::net::SocketAddrV6::new(
            "fe80::1".parse().unwrap(),
            443,
            0,
            3,
        ));
        assert_eq!(canonical_peer(scoped).to_string(), "[fe80::1]:443");
        let v4: SocketAddr = "198.51.100.4:80".parse().unwrap();
        assert_eq!(canonical_peer(v4), v4);
    }
}

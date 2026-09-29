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
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
};
use tokio::sync::{mpsc, oneshot, Notify};
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

// Dart stream ack callback: void(req_id)
pub type DartStreamAckHandler = extern "C" fn(u64);

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

static PENDING_STREAM_ACK_HANDLERS: OnceCell<
    Mutex<HashMap<std::thread::ThreadId, DartStreamAckHandler>>,
> = OnceCell::new();
static SERVER_STREAM_ACK_HANDLERS: OnceCell<Mutex<HashMap<u64, DartStreamAckHandler>>> =
    OnceCell::new();
static DART_STREAM_ACK_HANDLER: OnceCell<Mutex<Option<DartStreamAckHandler>>> =
    OnceCell::new();

pub type DartWsWakeupHandler = extern "C" fn(u64);

static DART_WS_WAKEUP_HANDLER: OnceCell<Mutex<Option<DartWsWakeupHandler>>> = OnceCell::new();
static PENDING_WS_WAKEUP_HANDLERS: OnceCell<
    Mutex<HashMap<std::thread::ThreadId, DartWsWakeupHandler>>,
> = OnceCell::new();
static SERVER_WS_WAKEUP_HANDLERS: OnceCell<Mutex<HashMap<u64, DartWsWakeupHandler>>> =
    OnceCell::new();

/// Rides along in the request extensions so a handler can tell which server
/// took the request. Cheaper than threading state through every route.
#[derive(Clone, Copy)]
struct ServerId(u64);
static DART_CANCEL_HANDLER: OnceCell<Mutex<Option<DartStreamCancelHandler>>> =
    OnceCell::new();

/// A request body chunk, or the event that ended it.
///
/// The direction is Rust to Dart, one chunk at a time and only when Dart has
/// asked for the next one, so a handler reading a body decides how far ahead
/// of it a client may get.
pub type DartBodyChunkHandler = extern "C" fn(u64, FfiBuf, u8);

static DART_BODY_CHUNK_HANDLER: OnceCell<Mutex<Option<DartBodyChunkHandler>>> = OnceCell::new();
/// Per thread, for the reason the request and cancel handlers are: a chunk
/// belonging to one server must not reach for a callback another has already
/// freed.
static PENDING_BODY_CHUNK_HANDLERS: OnceCell<
    Mutex<HashMap<std::thread::ThreadId, DartBodyChunkHandler>>,
> = OnceCell::new();
/// Each server's own body-chunk callback.
static SERVER_BODY_CHUNK_HANDLERS: OnceCell<Mutex<HashMap<u64, DartBodyChunkHandler>>> =
    OnceCell::new();
/// The bodies still being read, by request. A request is in here from the
/// moment its Dart callback is called until its proxy future ends, which is
/// also when it stops being pullable.
static REQUEST_BODIES: OnceCell<Mutex<HashMap<u64, Arc<BodyState>>>> = OnceCell::new();

struct FfiRespOwned {
    status: u16,
    headers: Vec<u8>,
    body: Vec<u8>,
    is_stream: u8,
}
static PENDING_RESPONSES: OnceCell<Mutex<HashMap<u64, oneshot::Sender<FfiRespOwned>>>> =
    OnceCell::new();
/// Capacity for the bounded response stream channel.
const RESPONSE_STREAM_CAPACITY: usize = 64;

/// One streamed body chunk, or the error that ended the stream.
type StreamChunkResult = Result<Bytes, axum::BoxError>;
type StreamChunkSender = mpsc::Sender<StreamChunkResult>;
type StreamChunkReceiver = mpsc::Receiver<StreamChunkResult>;

/// Bounded to [RESPONSE_STREAM_CAPACITY] chunks with backpressure signaled
/// to Dart via `aw_register_stream_ack_handler`. A fast Dart producer pauses
/// when in-flight chunks reach the window, preventing unbounded native buffering.
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
#[derive(Clone, Default)]
struct StaticPaths { directory: Option<String>, spa: Option<String> }
static PENDING_STATIC: OnceCell<Mutex<HashMap<std::thread::ThreadId, StaticPaths>>> = OnceCell::new();
static COMPRESSION_ENABLED: OnceCell<Mutex<bool>> = OnceCell::new();

/// How long a request may take to arrive and be answered when the caller did
/// not say: reading its headers, reading its body, and waiting for Dart.
const DEFAULT_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// How long a refused body is drained before the connection closes.
///
/// A client that passes the limit is answered 413 with the connection told to
/// close, but it is likely still writing. Dropping the body stream as the
/// response goes out lets hyper stop reading the socket, the client's send
/// buffer fills, its flush blocks, and it never sees the 413 (up to minutes
/// of hang). Draining for this short a grace instead keeps the client
/// unblocked long enough for the refusal to reach it; the stream is then
/// dropped and the connection closes as it would have.
const REFUSAL_DRAIN_GRACE: std::time::Duration = std::time::Duration::from_millis(250);

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

fn stream_ack(req_id: u64, server_id: Option<u64>) {
    let cb = server_id
        .and_then(|id| {
            SERVER_STREAM_ACK_HANDLERS
                .get()
                .and_then(|handlers| safe_lock(handlers).get(&id).copied())
        })
        .or_else(|| DART_STREAM_ACK_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(cb) = cb {
        (cb)(req_id);
    }
}

fn ws_wakeup(req_id: u64, server_id: Option<u64>) {
    let cb = server_id
        .and_then(|id| {
            SERVER_WS_WAKEUP_HANDLERS
                .get()
                .and_then(|handlers| safe_lock(handlers).get(&id).copied())
        })
        .or_else(|| DART_WS_WAKEUP_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(cb) = cb {
        (cb)(req_id);
    }
}

// Stream wrapper to trigger Dart cancellation on drop and backpressure acks on read
struct CancelOnDropStream<S> {
    inner: S,
    req_id: u64,
    /// The server this stream belongs to, so the cancel goes to that
    /// server's Dart callback rather than to whichever was registered last.
    server_id: Option<u64>,
    ack_counter: u32,
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
        let item = Pin::new(&mut self.inner).poll_next(cx);
        match &item {
            std::task::Poll::Ready(Some(_)) => {
                self.ack_counter += 1;
                if self.ack_counter >= 8 {
                    self.ack_counter = 0;
                    stream_ack(self.req_id, self.server_id);
                }
            }
            std::task::Poll::Ready(None) => {
                if self.ack_counter > 0 {
                    self.ack_counter = 0;
                    stream_ack(self.req_id, self.server_id);
                }
            }
            _ => {}
        }
        item
    }
}

impl<S> Drop for CancelOnDropStream<S> {
    fn drop(&mut self) {
        if self.ack_counter > 0 {
            stream_ack(self.req_id, self.server_id);
        }
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
pub extern "C" fn aw_register_stream_ack_handler(cb: DartStreamAckHandler) {
    let slot = DART_STREAM_ACK_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let pending = PENDING_STREAM_ACK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(std::thread::current().id(), cb);
}

#[no_mangle]
pub extern "C" fn aw_register_ws_wakeup_handler(cb: DartWsWakeupHandler) {
    let slot = DART_WS_WAKEUP_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let pending = PENDING_WS_WAKEUP_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(std::thread::current().id(), cb);
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

fn configure_static_path(path: FfiStr, spa: bool) -> i32 {
    let value = if path.len == 0 || path.ptr.is_null() { None } else {
        match std::str::from_utf8(unsafe { std::slice::from_raw_parts(path.ptr, path.len) }) {
            Ok(path) => Some(path.to_owned()), Err(_) => return 1,
        }
    };
    let mut pending = safe_lock(PENDING_STATIC.get_or_init(Default::default));
    let paths = pending.entry(std::thread::current().id()).or_default();
    if spa { paths.spa = value; } else { paths.directory = value; }
    0
}
#[no_mangle]
pub extern "C" fn aw_configure_static(path: FfiStr) -> i32 { configure_static_path(path, false) }
#[no_mangle]
pub extern "C" fn aw_configure_spa_root(path: FfiStr) -> i32 { configure_static_path(path, true) }

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

// ===== Streaming request bodies =====

/// A chunk of the request body [req_id] is here.
pub const AW_BODY_CHUNK: u8 = 0;
/// The whole body arrived, within its limit.
pub const AW_BODY_END: u8 = 1;
/// The client stopped sending, or sent something that is not a body. The
/// stream ends and the request is answered as it is for a request with no
/// body, which is what it used to be read as.
pub const AW_BODY_UNREADABLE: u8 = 2;
/// The body passed its limit, or the request ran out of time with it
/// unfinished. The stream fails and the request is answered 413 or 408 and
/// the connection closed, whatever the handler answered.
pub const AW_BODY_REFUSED: u8 = 3;

/// The ask was recorded, or answered. A chunk may still be on its way.
pub const AW_BODY_PULL_TAKEN: i32 = 0;
/// [req_id] is not a request with a body being read: one that was never
/// streamed, one already finished and released, or one the library was never
/// given a callback for.
pub const AW_BODY_PULL_UNKNOWN: i32 = 1;

/// How far a request's body has got, and what the request is answered with.
/// None while it is still arriving.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum BodyTerminal {
    /// The whole body arrived, within the limit.
    End,
    /// The client stopped sending. The answer is the handler's.
    Unreadable,
    /// A chunk would take the body past its limit, so it was dropped rather
    /// than kept. The answer is 413 and the connection is closed.
    TooLarge,
    /// The request ran out of time with the body still arriving. The answer
    /// is 408 and the connection is closed.
    TimedOut,
}

impl BodyTerminal {
    /// How the terminal is reported to Dart, once a pull asks for it.
    fn event(self) -> u8 {
        match self {
            BodyTerminal::End => AW_BODY_END,
            BodyTerminal::Unreadable => AW_BODY_UNREADABLE,
            // TooLarge and TimedOut are refusals, and a handler told only
            // "ended" would have folded a truncated body and answered with a
            // length for it.
            BodyTerminal::TooLarge | BodyTerminal::TimedOut => AW_BODY_REFUSED,
        }
    }

    /// Whether the terminal overrides whatever the handler answered.
    fn is_refusal(self) -> bool {
        matches!(self, BodyTerminal::TooLarge | BodyTerminal::TimedOut)
    }
}

/// How much of a request's body has been read, and what is wanted next.
///
/// A plain lock rather than an async one: a pull arrives on Dart's thread,
/// which is not a runtime thread, so anything that could only be awaited from
/// inside a runtime task would make a body unreachable.
#[derive(Default)]
struct BodyProgress {
    /// A chunk has been read and is waiting for Dart to ask for it.
    pending_chunk: bool,
    /// Dart has asked and has not been given one.
    waiting: bool,
    /// Dart has answered, so the rest of the body is read only to reach its
    /// end: no handler is left to hand it to.
    answered: bool,
    /// How the body ended, while it is still arriving.
    terminal: Option<BodyTerminal>,
    /// The terminal has been delivered. Nobody may be waiting when a body
    /// ends -- a handler that answered without reading it, or one that has
    /// stopped pulling -- and the pull that comes afterwards is what it is
    /// delivered to, so it is delivered once rather than to whoever happened
    /// to be there.
    terminal_sent: bool,
}

/// What a request's body reader shares with the rest of this library.
///
/// The reader task owns the stream itself; everything the FFI side touches
/// lives here, so a pull is a flag and a wake rather than a second reader.
struct BodyState {
    progress: Mutex<BodyProgress>,
    /// Wakes the reader when Dart asks for a chunk, or has answered.
    pull: Notify,
    /// The Dart callback an event goes to, captured when the body starts:
    /// by the time an event is delivered the server's entry may be gone, and
    /// the global slot may already name another server's callback.
    handler: DartBodyChunkHandler,
    /// The chunk last read, kept until the next one replaces it.
    ///
    /// The chunk callback is a Dart listener: it runs when the isolate gets
    /// to it, not when it is called, so a `Bytes` dropped when the call
    /// returned is freed memory the listener then reads. The same discipline
    /// as [RequestParts], and sound for the same reason: Dart asks for the
    /// next chunk only after it has this one.
    chunk: Mutex<Bytes>,
}

impl BodyState {
    /// [server]'s callback for bodies, or the one that was registered
    /// globally, resolved now rather than when a chunk is due.
    fn new(registered: DartBodyChunkHandler, server: Option<u64>) -> Self {
        let handler = server
            .and_then(|id| {
                SERVER_BODY_CHUNK_HANDLERS
                    .get()
                    .and_then(|handlers| safe_lock(handlers).get(&id).copied())
            })
            .unwrap_or(registered);
        Self {
            progress: Mutex::new(BodyProgress::default()),
            pull: Notify::new(),
            handler,
            chunk: Mutex::new(Bytes::new()),
        }
    }
}

/// Forgets a request's body, so a pull after it cannot find one.
///
/// Dropped with the proxy future, which is what a server stopping mid-request
/// does: nothing waits for that future to end on its own.
struct BodyRegistration(u64);

impl Drop for BodyRegistration {
    fn drop(&mut self) {
        release_request_body(self.0);
    }
}

fn request_body(req_id: u64) -> Option<Arc<BodyState>> {
    let map = REQUEST_BODIES.get()?;
    safe_lock(map).get(&req_id).cloned()
}

fn register_request_body(req_id: u64, state: Arc<BodyState>) {
    let map = REQUEST_BODIES.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(map).insert(req_id, state);
}

fn release_request_body(req_id: u64) {
    if let Some(map) = REQUEST_BODIES.get() {
        safe_lock(map).remove(&req_id);
    }
}

/// Registers the callback request-body chunks and the ends of bodies are
/// delivered to, and pulls for them are answered through.
///
/// On this thread, and taken by `aw_start` into a per-server slot the way the
/// request and cancel handlers are: two isolates starting a server at the same
/// moment interleave as register A, register B, start A, start B, and A would
/// otherwise hand its requests to B's isolate.
#[no_mangle]
pub extern "C" fn aw_register_body_chunk_handler(cb: DartBodyChunkHandler) {
    let slot = DART_BODY_CHUNK_HANDLER.get_or_init(|| Mutex::new(None));
    *safe_lock(slot) = Some(cb);
    let pending = PENDING_BODY_CHUNK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
    safe_lock(pending).insert(std::thread::current().id(), cb);
    // Created here for a server that is already running: this is what a
    // second serve() in an isolate that already started one does, and a body
    // that arrives between the two is still read a chunk at a time.
    let _ = SERVER_BODY_CHUNK_HANDLERS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_BODY_CHUNK_HANDLERS.set(Mutex::new(HashMap::new()));
}

/// Dart asks for the next chunk of request [req_id]'s body.
///
/// The chunk does not arrive here: the reader sends it, from its own task, to
/// the registered callback. That is the backpressure — nothing is read from
/// the socket until Dart asks, so a handler that stops reading stops the
/// client, and at most one chunk is ever in flight or waiting.
///
/// Returns [AW_BODY_PULL_TAKEN] for an ask that was recorded and
/// [AW_BODY_PULL_UNKNOWN] for a request with no body to pull, which is how a
/// caller learns it is not holding a body rather than being told it is empty.
#[no_mangle]
pub extern "C" fn aw_body_next_chunk(req_id: u64) -> i32 {
    let Some(state) = request_body(req_id) else {
        return AW_BODY_PULL_UNKNOWN;
    };
    // A chunk the reader had already read is handed over here, and a body
    // that has ended is reported here: the reader sends an event only to
    // somebody who has asked, so an ask after it is the ask that the event
    // goes to.
    enum Next {
        Send(FfiBuf, u8),
        Park,
    }
    let next = {
        let mut progress = safe_lock(&state.progress);
        match progress.terminal {
            Some(terminal) if !progress.terminal_sent => {
                progress.terminal_sent = true;
                progress.pending_chunk = false;
                Next::Send(empty_ffi_buf(), terminal.event())
            }
            // Already told: a handler pulling past the last chunk it was
            // given, which it has the end of for.
            Some(_) => Next::Park,
            None if progress.pending_chunk => {
                progress.pending_chunk = false;
                Next::Send(ffi_buf(&state.chunk), AW_BODY_CHUNK)
            }
            None => {
                progress.waiting = true;
                Next::Park
            }
        }
    };
    // Whether the ask was answered here or parked on, the reader is woken: it
    // is either already waiting for the chunk this asks for, or it has one
    // ready and has gone back to sleep knowing this one was taken. A
    // notification with nobody waiting is kept, so this is not lost when it
    // lands between the two.
    state.pull.notify_one();
    if let Next::Send(buf, kind) = next {
        (state.handler)(req_id, buf, kind);
    }
    AW_BODY_PULL_TAKEN
}

fn empty_ffi_buf() -> FfiBuf {
    FfiBuf {
        ptr: std::ptr::null(),
        len: 0,
    }
}

fn ffi_buf(chunk: &Mutex<Bytes>) -> FfiBuf {
    let chunk = safe_lock(chunk);
    FfiBuf {
        ptr: chunk.as_ptr(),
        len: chunk.len(),
    }
}

/// The end of a request's body, and what its answer is because of it.
///
/// Called by the reader when the body ended, and by the proxy when the
/// request ran out of time with it still arriving.
fn finish_body(req_id: u64, state: &Arc<BodyState>, terminal: BodyTerminal) {
    let event = {
        let mut progress = safe_lock(&state.progress);
        if progress.terminal.is_some() {
            return;
        }
        progress.terminal = Some(terminal);
        // Only to somebody who is waiting for it: the reader does not read
        // past what Dart asked for, and an event to nobody is not read.
        // A pull that arrives afterwards is answered with the terminal, so it
        // is delivered once either way.
        if progress.waiting && !progress.terminal_sent {
            progress.waiting = false;
            progress.pending_chunk = false;
            progress.terminal_sent = true;
            Some(terminal.event())
        } else {
            None
        }
    };
    if let Some(kind) = event {
        (state.handler)(req_id, empty_ffi_buf(), kind);
    }
}

/// Dart answered request [req_id], so the rest of its body is read only to
/// reach its end and free the connection.
fn mark_body_answered(req_id: u64) {
    let Some(state) = request_body(req_id) else {
        return;
    };
    {
        let mut progress = safe_lock(&state.progress);
        if progress.terminal.is_some() {
            return;
        }
        progress.answered = true;
        // The chunk already read is not wanted either, whatever Dart does
        // with its body now.
        progress.pending_chunk = false;
    }
    *safe_lock(&state.chunk) = Bytes::new();
    state.pull.notify_one();
}

/// Whether there is a reason to read another chunk of this body: Dart has
/// asked for one, or has answered and the rest is being taken only to reach
/// its end.
///
/// A function rather than a lock held in the reader, because a guard that
/// lives across the wait would make the reader's future unSendable and take
/// the whole handler with it.
fn body_wanted(state: &Arc<BodyState>) -> bool {
    let progress = safe_lock(&state.progress);
    progress.waiting || progress.answered
}

/// Reads request [req_id]'s body, one chunk at a time, as far as it is asked
/// for.
///
/// The first read is not waited for: a request with no body has to be known
/// to have none without a handler pulling for it, or a request Dart never
/// answers would be answered 408 for a body that had already ended rather
/// than 504 for the handler. After that nothing is read until Dart asks for
/// the next chunk, or has answered and the rest of the body is being taken
/// only to let the connection be reused.
async fn read_request_body(
    req_id: u64,
    state: Arc<BodyState>,
    mut body: axum::body::BodyDataStream,
    limit: u64,
) {
    let mut received: u64 = 0;
    let mut first = true;
    loop {
        if !first {
            // The wake is taken before the flags are read, so an ask that
            // lands between the two is not lost.
            let asked = state.pull.notified();
            if !body_wanted(&state) {
                asked.await;
                continue;
            }
        }
        first = false;

        let Some(item) = body.next().await else {
            finish_body(req_id, &state, BodyTerminal::End);
            return;
        };
        let bytes = match item {
            Ok(bytes) => bytes,
            // What a body that could not be read ends as it always did: an
            // empty one, with the request answered as a request with no body.
            Err(_) => {
                finish_body(req_id, &state, BodyTerminal::Unreadable);
                return;
            }
        };
        // Dropped before it is kept, so no more than the limit is ever held
        // and nothing past it is handed to a handler: a Content-Length that
        // understates what follows ends the body where it said, and a chunked
        // body that never ends stops here.
        if received.saturating_add(bytes.len() as u64) > limit {
            finish_body(req_id, &state, BodyTerminal::TooLarge);
            if let Ok(runtime) = tokio::runtime::Handle::try_current() {
                runtime.spawn(async move {
                    let deadline = tokio::time::Instant::now() + REFUSAL_DRAIN_GRACE;
                    while let Ok(Some(_)) = tokio::time::timeout_at(deadline, body.next()).await {}
                });
            }
            return;
        }
        received += bytes.len() as u64;

        let mut bytes = bytes;
        if bytes.len() >= 1024 && bytes.len() < 256 * 1024 {
            let mut buf = bytes::BytesMut::from(bytes);
            use futures_util::FutureExt;
            while buf.len() < 256 * 1024 {
                match body.next().now_or_never() {
                    Some(Some(Ok(more))) => {
                        if received.saturating_add(more.len() as u64) > limit {
                            finish_body(req_id, &state, BodyTerminal::TooLarge);
                            return;
                        }
                        received += more.len() as u64;
                        buf.extend_from_slice(&more);
                    }
                    _ => break,
                }
            }
            bytes = buf.freeze();
        }

        deliver_chunk(req_id, &state, bytes);
    }
}

/// Hands a chunk to Dart if one is waiting for it, keeps it for the next
/// pull, or drops it if the request has been answered.
fn deliver_chunk(req_id: u64, state: &Arc<BodyState>, bytes: Bytes) {
    let send = {
        let mut progress = safe_lock(&state.progress);
        if progress.answered {
            false
        } else if progress.waiting {
            progress.waiting = false;
            *safe_lock(&state.chunk) = bytes;
            true
        } else {
            // Read ahead of the ask by at most this one chunk, which is what
            // a pull after it is answered from without touching the socket.
            progress.pending_chunk = true;
            *safe_lock(&state.chunk) = bytes;
            false
        }
    };
    if send {
        (state.handler)(req_id, ffi_buf(&state.chunk), AW_BODY_CHUNK);
    }
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

/// 413, closing the connection as a body that refused does.
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
    let static_paths = safe_lock(PENDING_STATIC.get_or_init(Default::default))
        .remove(&std::thread::current().id()).unwrap_or_default();

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
    // Likewise, so a body chunk goes to the isolate that took the request
    // rather than to whichever one registered last.
    let body_chunk_handler = PENDING_BODY_CHUNK_HANDLERS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&this_thread))
        .or_else(|| DART_BODY_CHUNK_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(handler) = body_chunk_handler {
        let handlers = SERVER_BODY_CHUNK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server_id, handler);
    }
    let stream_ack_handler = PENDING_STREAM_ACK_HANDLERS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&this_thread))
        .or_else(|| DART_STREAM_ACK_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(handler) = stream_ack_handler {
        let handlers = SERVER_STREAM_ACK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server_id, handler);
    }
    let ws_wakeup_handler = PENDING_WS_WAKEUP_HANDLERS
        .get()
        .and_then(|pending| safe_lock(pending).remove(&this_thread))
        .or_else(|| DART_WS_WAKEUP_HANDLER.get().and_then(|slot| *safe_lock(slot)));
    if let Some(handler) = ws_wakeup_handler {
        let handlers = SERVER_WS_WAKEUP_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
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
            app = app.layer(axum::Extension(static_paths));
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
            if let Some(handlers) = SERVER_BODY_CHUNK_HANDLERS.get() {
                safe_lock(handlers).remove(&server_id);
            }
            if let Some(handlers) = SERVER_STREAM_ACK_HANDLERS.get() {
                safe_lock(handlers).remove(&server_id);
            }
            if let Some(handlers) = SERVER_WS_WAKEUP_HANDLERS.get() {
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
    safe_lock(WS_BRIDGES.get_or_init(Default::default)).retain(|_, bridge| bridge.server != Some(server_id));
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
                mpsc::channel::<Result<Bytes, axum::BoxError>>(RESPONSE_STREAM_CAPACITY);
            let senders = PENDING_STREAM_SENDERS.get_or_init(|| Mutex::new(HashMap::new()));
            let receivers = PENDING_STREAM_RECEIVERS.get_or_init(|| Mutex::new(HashMap::new()));
            safe_lock(senders).insert(req_id, chunk_tx);
            safe_lock(receivers).insert(req_id, chunk_rx);
        }
        let _ = tx.send(owned);
        // No handler is left to read this request's body, so the rest of it
        // is read only to reach its end and free the connection.
        mark_body_answered(req_id);
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
            match tx.try_send(Ok(bytes)) {
                Ok(()) => 0,
                Err(mpsc::error::TrySendError::Full(_)) => 1,
                Err(mpsc::error::TrySendError::Closed(_)) => 2,
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
    // Decided before a byte of the body is read. A body is read as far as it
    // is asked for rather than held whole, but nothing past the limit is
    // ever kept, so one client still cannot name a body as large as it
    // liked -- or a chunked body that never ended -- and have it held.
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

    let (mut parts, body) = req.into_parts();
    let upgrade = WebSocketUpgrade::from_request_parts(&mut parts, &()).await.ok();
    let req = Request::from_parts(parts, body);
    let method = req.method().as_str().as_bytes().to_vec();
    let target = req.uri().to_string().into_bytes();
    let flattened_headers = headers_flat(&req);
    let peer = peer_text(&req).into_bytes();

    // Dart is given the body when it is able to pull one. A library that was
    // never told how to receive chunks reads the body here, whole, as it
    // always did -- which is also what a Dart that has not been rebuilt
    // reads, and the two halves check for each other on purpose: a mismatched
    // pair holds a body rather than losing it.
    let mut streamed: Option<(Arc<BodyState>, axum::body::BodyDataStream)> = None;
    let bytes = match body_chunk_handler(server_id) {
        Some(cb) => {
            let state = Arc::new(BodyState::new(cb, server_id));
            let data = req.into_body().into_data_stream();
            register_request_body(req_id, state.clone());
            streamed = Some((state, data));
            // Dart pulls the rest of it, so it is handed an empty body rather
            // than the first chunk.
            Bytes::new()
        }
        None => {
            let mut body_buf = BytesMut::new();
            let mut body_stream = req.into_body().into_data_stream();
            // Whether the body ended within the limit. A chunk that would
            // take it past is refused before it is kept, so no more than the
            // limit is ever held: a Content-Length that understates what
            // follows ends the body where it said, and a chunked body --
            // slow, or endless -- stops here.
            let read_body = async {
                while let Some(chunk) = body_stream.next().await {
                    match chunk {
                        Ok(bytes) => {
                            if (body_buf.len() as u64)
                                .saturating_add(bytes.len() as u64)
                                > body_limit
                            {
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
            // A declared body that never arrives held the connection for as
            // long as the client kept it open.
            match tokio::time::timeout_at(deadline, read_body).await {
                Err(_) => return closing_response(StatusCode::REQUEST_TIMEOUT),
                // Closed as well as answered, so the rest is never read.
                Ok(false) => return too_large_response(body_limit),
                Ok(true) => {}
            }
            body_buf.freeze()
        }
    };
    // Forgets the body when this future is dropped, which is what a server
    // stopping mid-request does: nothing waits for that to end on its own.
    let _registration = BodyRegistration(req_id);

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

    // The body and the answer are waited for together, under the one
    // deadline a request has. A refusal is the body saying the request may
    // not be answered at all, so it has to reach a client that is still
    // sending -- which it cannot while the answer it overrules is still
    // outstanding.
    let (answered, terminal) = match streamed {
        Some((state, body)) => {
            let read = read_request_body(req_id, state.clone(), body, body_limit);
            let (answer, finished) = tokio::join!(
                tokio::time::timeout_at(deadline, response_rx),
                tokio::time::timeout_at(deadline, read),
            );
            // A body still arriving when the request ran out of time is
            // refused rather than left open, and the handler is told so: a
            // stream it is still reading fails instead of waiting for a chunk
            // that is never coming.
            if finished.is_err() {
                finish_body(req_id, &state, BodyTerminal::TimedOut);
            }
            let terminal = safe_lock(&state.progress)
                .terminal
                .unwrap_or(BodyTerminal::TimedOut);
            (answer, terminal)
        }
        None => (
            tokio::time::timeout_at(deadline, response_rx).await,
            BodyTerminal::End,
        ),
    };

    if terminal.is_refusal() {
        aw_ws_dispose(req_id);
        if let Some(mutex) = PENDING_RESPONSES.get() {
            safe_lock(mutex).remove(&req_id);
        }
        // A handler still producing an answer will be refused it, so its
        // stream is dropped now rather than left in a table nothing reads.
        abandon_stream(req_id, server_id);
        return if terminal == BodyTerminal::TooLarge {
            too_large_response(body_limit)
        } else {
            closing_response(StatusCode::REQUEST_TIMEOUT)
        };
    }

    match answered {
        Ok(Ok(resp)) => {
            let pending = safe_lock(WS_PENDING.get_or_init(Default::default)).remove(&req_id);
            if let Some(mut pending) = pending {
                if resp.status == 101 {
                    if let Some(upgrade) = upgrade {
                        if let Some(bridge) = safe_lock(WS_BRIDGES.get_or_init(Default::default)).get_mut(&req_id) {
                            bridge.server = server_id;
                        }
                        pending.server = server_id;
                        let upgrade = upgrade.max_message_size(pending.max).max_frame_size(pending.max);
                        let upgrade = if pending.protocol.is_empty() { upgrade } else {
                            upgrade.protocols([pending.protocol.clone()])
                        };
                        return upgrade.on_upgrade(move |socket| run_websocket(socket, pending));
                    }
                }
                aw_ws_dispose(req_id);
                return plain_response(StatusCode::BAD_REQUEST);
            }
            response_from_dart(resp, req_id, server_id, fallback)
        },
        Ok(Err(_)) => plain_response(StatusCode::INTERNAL_SERVER_ERROR),
        Err(_) => {
            aw_ws_dispose(req_id);
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

/// The Dart callback request-body chunks are delivered to, or None for a
/// request that arrives through a server nobody registered one with -- which
/// is a Dart that has not been rebuilt, and is answered a whole body.
fn body_chunk_handler(server_id: Option<u64>) -> Option<DartBodyChunkHandler> {
    server_id.and_then(|id| {
        SERVER_BODY_CHUNK_HANDLERS
            .get()
            .and_then(|handlers| safe_lock(handlers).get(&id).copied())
    })
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
            inner: tokio_stream::wrappers::ReceiverStream::new(rx),
            req_id,
            server_id,
            ack_counter: 0,
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
            inner: tokio_stream::wrappers::ReceiverStream::new(rx),
            req_id,
            server_id,
            ack_counter: 0,
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
    let paths = req.extensions().get::<StaticPaths>().cloned().unwrap_or_default();
    let static_dir = paths.directory;
    if let Some(dir) = static_dir {
        if path.starts_with("/static/") {
            let relative_path = &path["/static".len()..];
            if let Some(file_path) = get_static_file(&dir, relative_path) {
                return serve_file_response(file_path, req).await;
            }
        }
    }

    // 2. SPA root check
    let spa_root = paths.spa;
    if let Some(dir) = spa_root {
        if let Some(file_path) = get_static_file(&dir, &path) {
            return serve_file_response(file_path, req).await;
        }
        if req.method() == Method::GET {
            if let Some(index_path) = get_static_file(&dir, "/index.html") {
                return serve_file_response(index_path, req).await;
            }
        }
    }

    // 3. Fallback to Dart
    dart_proxy(req).await
}

fn get_static_file(dir: &str, path: &str) -> Option<std::path::PathBuf> {
    let root = std::fs::canonicalize(dir).ok()?;
    let path = root.join(path.trim_start_matches('/'));
    let resolved = std::fs::canonicalize(path).ok()?;
    if resolved.starts_with(&root) && resolved.is_file() { Some(resolved) } else { None }
}

async fn serve_file_response(path: std::path::PathBuf, mut req: Request<Body>) -> Response<Body> {
    use tower::ServiceExt;
    use tower_http::services::ServeFile;
    // A weak validator: metadata identifies a version, not byte equality.
    let etag = tokio::fs::metadata(&path).await.ok().and_then(|meta| {
        let modified = meta.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?;
        Some(format!("W/\"{:x}-{:x}\"", meta.len(), modified.as_nanos()))
    });
    let retrieval = req.method() == Method::GET || req.method() == Method::HEAD;
    if retrieval {
        if let Some(condition) = req.headers().get(header::IF_NONE_MATCH) {
            let matches = etag.as_ref().map_or(false, |etag| {
                condition.to_str().ok().map_or(false, |value| value.split(',').any(|item| {
                    let item = item.trim();
                    item == "*" || item.trim_start_matches("W/") == etag.trim_start_matches("W/")
                }))
            });
            if matches {
                return Response::builder().status(StatusCode::NOT_MODIFIED)
                    .header(header::ETAG, etag.unwrap()).body(Body::empty()).unwrap();
            }
            // If-None-Match takes precedence over a date, including a miss.
            req.headers_mut().remove(header::IF_MODIFIED_SINCE);
        }
    }
    // ServeFile streams from disk and implements byte ranges, HEAD, MIME,
    // Last-Modified and date preconditions. Do not read a file into one Vec.
    let response = ServeFile::new(path).oneshot(req).await.unwrap();
    let (mut parts, body) = response.into_parts();
    if let Some(etag) = etag {
        if let Ok(value) = etag.parse() { parts.headers.insert(header::ETAG, value); }
    }
    Response::from_parts(parts, Body::new(body))
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

#[cfg(test)]
mod body_stream_tests {
    use super::*;
    use futures_util::task::noop_waker;
    use std::future::Future;
    use std::pin::Pin;
    use std::sync::atomic::AtomicUsize;
    use std::task::{Context, Poll};

    type Reader = Pin<Box<dyn Future<Output = ()> + Send>>;

    /// Every event the library hands over, in order: which request, which
    /// kind, and the bytes of the chunk that came with it.
    static EVENTS: OnceCell<Mutex<Vec<(u64, u8, Vec<u8>)>>> = OnceCell::new();

    /// These tests share the one event log a callback can write to, and each
    /// of them reads it whole, so they run one at a time.
    static SERIAL: OnceCell<Mutex<()>> = OnceCell::new();

    fn events() -> &'static Mutex<Vec<(u64, u8, Vec<u8>)>> {
        EVENTS.get_or_init(|| Mutex::new(Vec::new()))
    }

    fn alone() -> std::sync::MutexGuard<'static, ()> {
        safe_lock(SERIAL.get_or_init(|| Mutex::new(())))
    }

    fn take_events() -> Vec<(u64, u8, Vec<u8>)> {
        std::mem::take(&mut *safe_lock(events()))
    }

    /// Stands in for the Dart listener. Copies the chunk, because the bytes
    /// behind the pointer belong to the library and are replaced on the next
    /// pull -- the same thing the Dart side does before the isolate gets to it.
    extern "C" fn record(req_id: u64, chunk: FfiBuf, kind: u8) {
        let bytes = if chunk.ptr.is_null() || chunk.len == 0 {
            Vec::new()
        } else {
            // SAFETY: the library keeps the chunk it is delivering until the
            // next one replaces it.
            unsafe { std::slice::from_raw_parts(chunk.ptr, chunk.len) }.to_vec()
        };
        safe_lock(events()).push((req_id, kind, bytes));
    }

    fn chunks(parts: &[&'static [u8]]) -> Vec<Result<Bytes, axum::BoxError>> {
        parts
            .iter()
            .map(|part| Ok(Bytes::from_static(part)))
            .collect()
    }

    /// A reader over [items], counting what it takes off the stream.
    fn reader_with(
        state: Arc<BodyState>,
        req_id: u64,
        items: Vec<Result<Bytes, axum::BoxError>>,
        limit: u64,
    ) -> (Reader, Arc<AtomicUsize>) {
        register_request_body(req_id, state.clone());
        let reads = Arc::new(AtomicUsize::new(0));
        let counted = reads.clone();
        let stream = futures_util::stream::iter(items).inspect(move |_| {
            counted.fetch_add(1, Ordering::SeqCst);
        });
        let body = Body::from_stream(stream).into_data_stream();
        (
            Box::pin(read_request_body(req_id, state, body, limit)),
            reads,
        )
    }

    fn reader(
        req_id: u64,
        items: Vec<Result<Bytes, axum::BoxError>>,
        limit: u64,
    ) -> (Reader, Arc<AtomicUsize>) {
        reader_with(Arc::new(BodyState::new(record, None)), req_id, items, limit)
    }

    fn read_count(reads: &AtomicUsize) -> usize {
        reads.load(Ordering::SeqCst)
    }

    /// One poll of the reader, by hand: what matters here is what it does
    /// between two asks, which a runtime would otherwise decide for us.
    fn step(reader: &mut Reader) -> bool {
        let waker = noop_waker();
        let mut cx = Context::from_waker(&waker);
        matches!(reader.as_mut().poll(&mut cx), Poll::Ready(()))
    }

    /// Steps until the reader is done, or gives up: one that cannot finish
    /// fails the test instead of hanging it.
    fn finish(reader: &mut Reader) -> bool {
        (0..64).any(|_| step(reader))
    }

    #[test]
    fn a_chunk_is_read_when_it_is_asked_for_and_not_before() {
        let _alone = alone();
        let (mut reader, reads) = reader(9201, chunks(&[b"one", b"two", b"three"]), 1024);

        // The first read is not waited for: a request with no body has to be
        // known to have none without a handler pulling for one, or a request
        // Dart never answers is answered 408 for a body that had ended rather
        // than 504 for the handler.
        step(&mut reader);
        // Read ahead of the ask by the one chunk, and never more: what is not
        // asked for is not held either, so a client cannot send faster than a
        // handler reads and have it all kept.
        assert_eq!(read_count(&reads), 1);
        assert_eq!(take_events(), [], "a chunk nobody asked for is not handed over");

        for expected in [&b"one"[..], b"two", b"three"] {
            // A chunk the reader had already read is handed over by the pull
            // itself; one it has not read yet is read because of it, and
            // handed over in the same step. Either way one pull is one chunk.
            // A chunk the reader had already read is handed over by the pull
            // itself; one it has not read yet is read because of the pull and
            // handed over in the step that follows. Either way one pull is one
            // chunk, and one step is enough to get it.
            assert_eq!(aw_body_next_chunk(9201), AW_BODY_PULL_TAKEN);
            step(&mut reader);
            assert_eq!(
                take_events(),
                vec![(9201, AW_BODY_CHUNK, expected.to_vec())]
            );
        }
        assert_eq!(
            read_count(&reads),
            3,
            "nothing is read off the body past what is asked for"
        );
        release_request_body(9201);
    }

    #[test]
    fn the_end_of_a_body_goes_to_the_pull_after_it_and_only_once() {
        let _alone = alone();
        let (mut reader, _) = reader(9202, chunks(&[b"only"]), 1024);

        step(&mut reader);
        aw_body_next_chunk(9202);
        assert_eq!(take_events(), vec![(9202, AW_BODY_CHUNK, b"only".to_vec())]);

        // The handler answered without asking for the rest: the body is read
        // to its end so the connection can be used again, and it ends with
        // nobody waiting for the end of it.
        mark_body_answered(9202);
        assert!(step(&mut reader));
        assert_eq!(take_events(), [], "the end is not handed to nobody");

        // The pull after it is answered with the end rather than left waiting
        // for a chunk that is never coming.
        assert_eq!(aw_body_next_chunk(9202), AW_BODY_PULL_TAKEN);
        assert_eq!(take_events(), vec![(9202, AW_BODY_END, Vec::new())]);

        // And a handler that pulls again is parked, not told the end twice.
        assert_eq!(aw_body_next_chunk(9202), AW_BODY_PULL_TAKEN);
        assert_eq!(take_events(), []);
        release_request_body(9202);
    }

    #[test]
    fn a_chunk_that_would_pass_the_limit_is_neither_kept_nor_handed_over() {
        let _alone = alone();
        let (mut reader, reads) = reader(9203, chunks(&[b"abcd", b"efgh"]), 5);

        step(&mut reader);
        aw_body_next_chunk(9203);
        assert_eq!(take_events(), vec![(9203, AW_BODY_CHUNK, b"abcd".to_vec())]);

        // The next chunk is read to find out it is too much, and dropped rather
        // than kept or handed over: a Content-Length that understates what
        // follows ends the body where it said, and a chunked body that never
        // ends stops here.
        assert_eq!(aw_body_next_chunk(9203), AW_BODY_PULL_TAKEN);
        assert!(step(&mut reader));
        assert_eq!(read_count(&reads), 2);
        assert_eq!(take_events(), vec![(9203, AW_BODY_REFUSED, Vec::new())]);

        // A refusal is what the request is answered from, over whatever the
        // handler answered.
        let state = request_body(9203).expect("the body is still held");
        assert_eq!(
            safe_lock(&state.progress).terminal,
            Some(BodyTerminal::TooLarge)
        );
        release_request_body(9203);
    }

    #[test]
    fn a_handler_that_answers_without_reading_is_handed_nothing_further() {
        let _alone = alone();
        let (mut reader, reads) = reader(9204, chunks(&[b"one", b"two"]), 1024);

        step(&mut reader);
        // The handler answered without ever pulling, so the chunk read ahead
        // of its ask is not wanted either.
        mark_body_answered(9204);

        // The rest is read only to reach the end, so the connection the body
        // is on can be used again rather than left mid-body.
        assert!(finish(&mut reader));
        assert_eq!(read_count(&reads), 2);
        assert_eq!(take_events(), [], "an answered request gets no more body");
        release_request_body(9204);
    }

    #[test]
    fn a_body_that_cannot_be_read_ends_the_way_one_that_never_came_did() {
        let _alone = alone();
        let items: Vec<Result<Bytes, axum::BoxError>> = vec![
            Ok(Bytes::from_static(b"one")),
            Err(std::io::Error::other("client went away").into()),
        ];
        let (mut reader, _) = reader(9207, items, 1024);

        step(&mut reader);
        aw_body_next_chunk(9207);
        assert_eq!(take_events(), vec![(9207, AW_BODY_CHUNK, b"one".to_vec())]);

        // A second pull takes the error, because a body that stops being
        // readable is only found out by reading it.
        assert_eq!(aw_body_next_chunk(9207), AW_BODY_PULL_TAKEN);
        assert!(step(&mut reader));
        // The end a body that could not be read gets is the one a request with
        // no body gets, and the request is answered as it always was.
        assert_eq!(take_events(), vec![(9207, AW_BODY_UNREADABLE, Vec::new())]);
        release_request_body(9207);
    }

    #[test]
    fn a_pull_for_a_request_with_no_body_is_refused() {
        let _alone = alone();
        // One that was never streamed.
        assert_eq!(aw_body_next_chunk(9205), AW_BODY_PULL_UNKNOWN);
        // And one whose body was given up on, which is what a server stopping
        // mid-request does.
        let (mut reader, _) = reader(9206, chunks(&[b"one"]), 1024);
        step(&mut reader);
        release_request_body(9206);
        assert_eq!(aw_body_next_chunk(9206), AW_BODY_PULL_UNKNOWN);
        // Neither is a body handed over as an empty one, which a caller would
        // fold into an answer as though the request had sent nothing.
        assert_eq!(take_events(), []);
    }

    #[test]
    fn only_a_refusal_overrules_the_answer_a_handler_gave() {
        assert_eq!(BodyTerminal::End.event(), AW_BODY_END);
        assert!(!BodyTerminal::End.is_refusal());
        // A body that could not be read ends, it is not refused: the request
        // is answered as a request with no body always was.
        assert_eq!(BodyTerminal::Unreadable.event(), AW_BODY_UNREADABLE);
        assert!(!BodyTerminal::Unreadable.is_refusal());
        // Too large and out of time are the two that are refused, and both
        // reach Dart as the same failure, because a handler told only that a
        // body ended would fold a truncated one and answer a length for it.
        assert_eq!(BodyTerminal::TooLarge.event(), AW_BODY_REFUSED);
        assert!(BodyTerminal::TooLarge.is_refusal());
        assert_eq!(BodyTerminal::TimedOut.event(), AW_BODY_REFUSED);
        assert!(BodyTerminal::TimedOut.is_refusal());
    }

    #[test]
    fn a_body_goes_to_the_callback_it_started_with() {
        let _alone = alone();
        extern "C" fn second(req_id: u64, _chunk: FfiBuf, kind: u8) {
            safe_lock(events()).push((req_id, kind, b"second".to_vec()));
        }

        let server = 7_700_000_007;
        let handlers = SERVER_BODY_CHUNK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server, record);
        // This body starts while the server holds the first callback.
        let in_flight = Arc::new(BodyState::new(second, Some(server)));
        // Which is not the one it goes to: the server's own entry is taken
        // first, and the one registered globally is only a fallback.
        // Then another server stops and another takes its place, which is what
        // two isolates starting and stopping at the same moment look like
        // from here.
        safe_lock(handlers).insert(server, second);

        register_request_body(server, in_flight.clone());
        assert_eq!(aw_body_next_chunk(server), AW_BODY_PULL_TAKEN);
        assert_eq!(take_events(), []);
        finish_body(server, &in_flight, BodyTerminal::End);
        assert_eq!(
            take_events(),
            vec![(server, AW_BODY_END, Vec::new())],
            "a callback registered after the body started does not get it"
        );

        // A request that arrives without a server behind it takes the one
        // that was registered.
        let global = Arc::new(BodyState::new(second, None));
        register_request_body(9209, global.clone());
        aw_body_next_chunk(9209);
        finish_body(9209, &global, BodyTerminal::End);
        assert_eq!(take_events(), vec![(9209, AW_BODY_END, b"second".to_vec())]);

        safe_lock(handlers).remove(&server);
        release_request_body(server);
        release_request_body(9209);
    }

    #[test]
    fn a_server_with_no_callback_of_its_own_streams_no_body() {
        let _alone = alone();
        let server = 7_700_000_009;
        let handlers = SERVER_BODY_CHUNK_HANDLERS.get_or_init(|| Mutex::new(HashMap::new()));
        safe_lock(handlers).insert(server, record);

        assert!(body_chunk_handler(Some(server)).is_some());
        // Another server's callback is never used for it, and a request that
        // arrives without a server is answered a whole body as it always was:
        // a Dart that has not been rebuilt reads none of this.
        assert_eq!(body_chunk_handler(Some(server + 1)), None);
        assert_eq!(body_chunk_handler(None), None);
        safe_lock(handlers).remove(&server);
    }
}

// WebSocket messages cross the ABI through bounded queues, never a callback
// that could outlive an isolate. Dart pulls only while its stream is resumed.
use axum::extract::{FromRequestParts, ws::{WebSocketUpgrade, WebSocket, Message, CloseFrame}};
use futures_util::SinkExt;

struct WsBridge {
    server: Option<u64>,
    max: usize,
    pongs: Arc<AtomicU64>,
    incoming: Mutex<mpsc::Receiver<Message>>,
    outgoing: mpsc::Sender<Message>,
    backpressure: Arc<AtomicBool>,
}
struct WsPending {
    id: u64,
    server: Option<u64>,
    pongs: Arc<AtomicU64>,
    max: usize,
    protocol: String,
    incoming: mpsc::Sender<Message>,
    outgoing: mpsc::Receiver<Message>,
    backpressure: Arc<AtomicBool>,
}
static WS_BRIDGES: OnceCell<Mutex<HashMap<u64, WsBridge>>> = OnceCell::new();
static WS_PENDING: OnceCell<Mutex<HashMap<u64, WsPending>>> = OnceCell::new();

/// Creates bounded queues before completing an HTTP upgrade response.
#[no_mangle]
pub extern "C" fn aw_ws_prepare(id: u64, max: usize, protocol: FfiStr) -> i32 {
    if max == 0 || max > 64 * 1024 * 1024 { return -1; }
    let protocol = if protocol.len == 0 { String::new() } else {
        String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(protocol.ptr, protocol.len) }).into_owned()
    };
    let pongs = Arc::new(AtomicU64::new(0));
    let backpressure = Arc::new(AtomicBool::new(false));
    let (in_tx, in_rx) = mpsc::channel(64);
    let (out_tx, out_rx) = mpsc::channel(64);
    safe_lock(WS_BRIDGES.get_or_init(Default::default)).insert(id, WsBridge {
        server: None, max, pongs: pongs.clone(), incoming: Mutex::new(in_rx), outgoing: out_tx,
        backpressure: backpressure.clone(),
    });
    safe_lock(WS_PENDING.get_or_init(Default::default)).insert(id, WsPending {
        id, server: None, max, protocol, pongs, incoming: in_tx, outgoing: out_rx,
        backpressure,
    });
    0
}

/// The native task has ended; remaining received messages are bounded.
#[no_mangle]
pub extern "C" fn aw_ws_closed(id: u64) -> i32 {
    safe_lock(WS_BRIDGES.get_or_init(Default::default)).get(&id)
        .map_or(1, |bridge| if bridge.outgoing.is_closed() { 1 } else { 0 })
}

/// Heartbeat acknowledgements do not depend on a Dart data-stream listener.
#[no_mangle]
pub extern "C" fn aw_ws_pong_count(id: u64) -> u64 {
    safe_lock(WS_BRIDGES.get_or_init(Default::default)).get(&id)
        .map_or(0, |bridge| bridge.pongs.load(Ordering::Relaxed))
}

/// 0 accepted, 1 backpressure, -1 closed/invalid. Never blocks the Dart thread.
#[no_mangle]
pub extern "C" fn aw_ws_send(id: u64, kind: i32, data: FfiBuf) -> i32 {
    let bridges = safe_lock(WS_BRIDGES.get_or_init(Default::default));
    let Some(bridge) = bridges.get(&id) else { return -1; };
    if (matches!(kind, 1 | 2) && data.len > bridge.max) || (matches!(kind, 8 | 9 | 10) && data.len > 125) { return -1; }
    let message = match kind {
        1 => {
            let bytes = if data.len == 0 {
                Vec::new()
            } else {
                unsafe { std::slice::from_raw_parts(data.ptr, data.len) }.to_vec()
            };
            // String::from_utf8 takes ownership of the bytes, avoiding an extra copy.
            match String::from_utf8(bytes) {
                Ok(s) => Message::Text(s),
                Err(_) => return -1,
            }
        }
        2 => {
            let bytes = if data.len == 0 {
                Vec::new()
            } else {
                unsafe { std::slice::from_raw_parts(data.ptr, data.len) }.to_vec()
            };
            Message::Binary(bytes)
        }
        9 => {
            let bytes = if data.len == 0 {
                Vec::new()
            } else {
                unsafe { std::slice::from_raw_parts(data.ptr, data.len) }.to_vec()
            };
            Message::Ping(bytes)
        }
        10 => {
            let bytes = if data.len == 0 {
                Vec::new()
            } else {
                unsafe { std::slice::from_raw_parts(data.ptr, data.len) }.to_vec()
            };
            Message::Pong(bytes)
        }
        8 => {
            let bytes = if data.len == 0 {
                Vec::new()
            } else {
                unsafe { std::slice::from_raw_parts(data.ptr, data.len) }.to_vec()
            };
            if bytes.len() < 2 {
                Message::Close(None)
            } else {
                let code = u16::from_be_bytes([bytes[0], bytes[1]]);
                let Ok(reason) = String::from_utf8(bytes[2..].to_vec()) else { return -1; };
                Message::Close(Some(CloseFrame { code, reason: reason.into() }))
            }
        }
        _ => return -1,
    };
    match bridge.outgoing.try_send(message) {
        Ok(()) => 0,
        Err(mpsc::error::TrySendError::Full(_)) => {
            bridge.backpressure.store(true, Ordering::Release);
            1
        }
        Err(_) => -1,
    }
}

#[repr(C)]
pub struct FfiWsFrame { pub kind: i32, pub data: FfiBuf }

/// 0 means pending, -1 closed. Positive kinds own data until aw_ws_free.
#[no_mangle]
pub extern "C" fn aw_ws_receive(id: u64) -> FfiWsFrame {
    let bridges = safe_lock(WS_BRIDGES.get_or_init(Default::default));
    let empty = |kind| FfiWsFrame { kind, data: FfiBuf { ptr: std::ptr::null(), len: 0 } };
    let Some(bridge) = bridges.get(&id) else { return empty(-1); };
    let result = safe_lock(&bridge.incoming).try_recv();
    let message = match result {
        Ok(message) => message,
        Err(mpsc::error::TryRecvError::Empty) => return empty(0),
        Err(_) => return empty(-1),
    };
    let (kind, bytes) = match message {
        Message::Text(text) => (1, text.into_bytes()),
        Message::Binary(bytes) => (2, bytes),
        Message::Ping(bytes) => (9, bytes),
        Message::Pong(bytes) => (10, bytes),
        Message::Close(frame) => (8, frame.map(|f| {
            let mut bytes = f.code.to_be_bytes().to_vec();
            bytes.extend_from_slice(f.reason.as_bytes()); bytes
        }).unwrap_or_default()),
    };
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    FfiWsFrame { kind, data: FfiBuf { ptr: Box::into_raw(boxed) as *const u8, len } }
}

#[no_mangle]
pub extern "C" fn aw_ws_free(data: FfiBuf) {
    if !data.ptr.is_null() {
        unsafe { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data.ptr as *mut u8, data.len))); }
    }
}

#[no_mangle]
pub extern "C" fn aw_ws_dispose(id: u64) {
    safe_lock(WS_PENDING.get_or_init(Default::default)).remove(&id);
    safe_lock(WS_BRIDGES.get_or_init(Default::default)).remove(&id);
}

async fn run_websocket(socket: WebSocket, pending: WsPending) {
    let req_id = pending.id;
    let server_id = pending.server;
    let (mut sink, mut stream) = socket.split();
    let mut outgoing = pending.outgoing;
    let incoming = pending.incoming;
    let pongs = pending.pongs;
    let backpressure = pending.backpressure;
    // A blocked incoming queue must not prevent outgoing traffic (or closure).
    let read = async {
        // Process incoming frames with minimal overhead.
        // Call ws_wakeup once per frame for now; optimize later if needed.
        while let Some(message) = stream.next().await {
            let message = match message {
                Ok(message) => message,
                Err(error) => {
                    let code = match error.into_inner().downcast::<tungstenite::Error>() {
                        Ok(error) if matches!(*error, tungstenite::Error::Capacity(_)) => 1009,
                        _ => 1002,
                    };
                    return Some(Message::Close(Some(CloseFrame { code, reason: "".into() })));
                }
            };
            match &message {
                // The next tungstenite read flushes its automatic pong.
                Message::Ping(_) => continue,
                Message::Pong(_) => { pongs.fetch_add(1, Ordering::Relaxed); continue; },
                _ => {},
            }
            let closed = matches!(message, Message::Close(_));
            // Tungstenite queues automatic pong/close replies when reading.
            if incoming.send(message).await.is_err() || closed {
                ws_wakeup(req_id, server_id);
                break;
            }
            ws_wakeup(req_id, server_id);
        }
        ws_wakeup(req_id, server_id);
        None
    };
    let write = async {
        while let Some(message) = outgoing.recv().await {
            let mut closed = matches!(message, Message::Close(_));
            if sink.feed(message).await.is_err() || closed { break; }
            // Batch more aggressively: drain up to 64 frames before flush
            const WRITE_BATCH: usize = 64;
            let mut write_batch = 1;
            while write_batch < WRITE_BATCH {
                if let Ok(next) = outgoing.try_recv() {
                    closed = matches!(next, Message::Close(_));
                    if sink.feed(next).await.is_err() || closed { break; }
                    write_batch += 1;
                } else {
                    break;
                }
            }
            if sink.flush().await.is_err() || closed { break; }
            if backpressure.swap(false, Ordering::AcqRel) {
                ws_wakeup(req_id, server_id);
            }
        }
        None
    };
    let close = tokio::select! { close = read => close, close = write => close };
    if let Some(close) = close { let _ = sink.send(close).await; }
    let _ = sink.flush().await;
    ws_wakeup(req_id, server_id);
}

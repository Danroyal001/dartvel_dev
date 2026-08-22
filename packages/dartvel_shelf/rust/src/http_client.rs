//! Outbound HTTP client with HTTP/2 and 103 Early Hints.
//!
//! Built on the `h2` crate directly rather than on `reqwest` or `hyper`, for
//! one reason: `h2::client::ResponseFuture::poll_informational` is the only
//! place in the Rust ecosystem where 1xx informational responses surface.
//! hyper supports 103 in neither direction — HTTP/2 is an open pull request,
//! and server-side sending has been open and blocked since 2021 — so
//! everything built on hyper inherits that gap. See `docs/http-transport.md`.
//!
//! The FFI shape is a handle plus an event pump rather than a callback,
//! because Dart callbacks invoked from arbitrary native threads are awkward
//! and because early hints, streamed body chunks and the final response are
//! all the same kind of thing: something that arrives later. A Dart helper
//! isolate blocks on `dv_http_next_event` and forwards what it gets.

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::task::{Context, Poll};

use bytes::Bytes;
use serde::Deserialize;
use serde_json::json;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_rustls::TlsConnector;

use rustls::pki_types::ServerName;
use rustls::ClientConfig;

use crate::{FfiBuf, FfiStr};

// ===== Event kinds crossing the FFI boundary =====

/// The request finished; no more events.
pub const DV_HTTP_EVENT_DONE: i32 = 0;
/// A 103 Early Hints response. Payload is JSON headers.
pub const DV_HTTP_EVENT_EARLY_HINTS: i32 = 1;
/// The final response head. Payload is JSON: status, protocol, headers.
pub const DV_HTTP_EVENT_HEAD: i32 = 2;
/// A body chunk. Payload is the raw bytes, not JSON — base64 through a JSON
/// envelope would cost a third of every response body for nothing.
pub const DV_HTTP_EVENT_BODY: i32 = 3;
/// The request failed. Payload is JSON: message, protocol, retryable.
pub const DV_HTTP_EVENT_ERROR: i32 = -1;
/// The handle is unknown, already drained, or the argument was invalid.
pub const DV_HTTP_EVENT_INVALID: i32 = -2;

enum ClientEvent {
    EarlyHints(String),
    Head(String),
    Body(Bytes),
    Error(String),
}

struct PendingRequest {
    events: mpsc::UnboundedReceiver<ClientEvent>,
    cancel: Option<tokio::sync::oneshot::Sender<()>>,
}

static CLIENT_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static REQUESTS: OnceLock<Mutex<HashMap<u64, PendingRequest>>> = OnceLock::new();
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);
static TLS_ROOTS: OnceLock<Arc<rustls::RootCertStore>> = OnceLock::new();

/// A runtime of its own, separate from the server's.
///
/// A client request must not be able to starve the server, and the server
/// runtime is only created when a server starts — an app that only makes
/// outbound calls never starts one.
fn runtime() -> &'static tokio::runtime::Runtime {
    CLIENT_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("dartvel http client runtime")
    })
}

fn requests() -> &'static Mutex<HashMap<u64, PendingRequest>> {
    REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Trust anchors, preferring the platform store.
///
/// The OS store is what an enterprise TLS-inspecting proxy installs into, so
/// bundling Mozilla's roots alone would fail exactly where a developer cannot
/// change the network. The bundled set is the fallback for platforms with no
/// usable store rather than the first choice.
fn tls_roots() -> Arc<rustls::RootCertStore> {
    TLS_ROOTS
        .get_or_init(|| {
            let mut store = rustls::RootCertStore::empty();
            let mut loaded = 0usize;
            if let Ok(result) = rustls_native_certs::load_native_certs() {
                for cert in result {
                    if store.add(cert).is_ok() {
                        loaded += 1;
                    }
                }
            }
            if loaded == 0 {
                store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            }
            Arc::new(store)
        })
        .clone()
}

// ===== Request description =====

#[derive(Deserialize)]
struct ClientRequest {
    url: String,
    #[serde(default = "default_method")]
    method: String,
    #[serde(default)]
    headers: HashMap<String, String>,
    /// ALPN token: `h2` or `http/1.1`. The caller has already chosen, because
    /// protocol fallback is Dart's job — this client attempts exactly one.
    #[serde(default = "default_alpn")]
    alpn: String,
    #[serde(default)]
    timeout_ms: u64,
}

fn default_method() -> String {
    "GET".to_string()
}

fn default_alpn() -> String {
    "h2".to_string()
}

// ===== FFI =====

/// Starts a request and returns a handle, or 0 if it could not be started.
///
/// # Safety
/// `request_json` and `body` must be valid for their stated lengths for the
/// duration of this call. Both are copied before returning, so the caller may
/// free them immediately afterwards.
#[no_mangle]
pub unsafe extern "C" fn dv_http_send(request_json: FfiStr, body: FfiBuf) -> u64 {
    if request_json.ptr.is_null() || request_json.len == 0 {
        return 0;
    }
    let json_bytes = std::slice::from_raw_parts(request_json.ptr, request_json.len);
    let request: ClientRequest = match serde_json::from_slice(json_bytes) {
        Ok(parsed) => parsed,
        Err(_) => return 0,
    };
    let body_bytes = if body.ptr.is_null() || body.len == 0 {
        Bytes::new()
    } else {
        Bytes::copy_from_slice(std::slice::from_raw_parts(body.ptr, body.len))
    };

    let (event_tx, event_rx) = mpsc::unbounded_channel();
    let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
    let id = NEXT_REQUEST_ID.fetch_add(1, Ordering::SeqCst);

    if let Ok(mut map) = requests().lock() {
        map.insert(
            id,
            PendingRequest {
                events: event_rx,
                cancel: Some(cancel_tx),
            },
        );
    }

    runtime().spawn(async move {
        let work = perform(request, body_bytes, event_tx.clone());
        tokio::select! {
            result = work => {
                if let Err(failure) = result {
                    let _ = event_tx.send(ClientEvent::Error(failure.to_json()));
                }
            }
            _ = cancel_rx => {
                let _ = event_tx.send(ClientEvent::Error(
                    Failure::new("cancelled", false).to_json(),
                ));
            }
        }
    });

    id
}

/// Blocks until the next event for [handle].
///
/// Returns one of the `DV_HTTP_EVENT_*` codes and writes the payload to `out`.
/// A payload with a non-null pointer must be released with
/// [`dv_http_free_buf`]; `DONE`, `INVALID` and any empty payload write a null
/// pointer and need no release.
///
/// # Safety
/// `out` must point to a writable `FfiBuf`.
#[no_mangle]
pub unsafe extern "C" fn dv_http_next_event(handle: u64, out: *mut FfiBuf) -> i32 {
    if out.is_null() {
        return DV_HTTP_EVENT_INVALID;
    }
    *out = FfiBuf {
        ptr: std::ptr::null(),
        len: 0,
    };

    // The receiver is taken out of the map for the duration of the wait, so a
    // blocking recv never holds the map lock — otherwise one in-flight request
    // would block every other request's bookkeeping.
    let mut pending = match requests().lock().ok().and_then(|mut m| m.remove(&handle)) {
        Some(pending) => pending,
        None => return DV_HTTP_EVENT_INVALID,
    };

    let event = pending.events.blocking_recv();

    match event {
        Some(event) => {
            if let Ok(mut map) = requests().lock() {
                map.insert(handle, pending);
            }
            let (code, payload) = match event {
                ClientEvent::EarlyHints(json) => {
                    (DV_HTTP_EVENT_EARLY_HINTS, Bytes::from(json))
                }
                ClientEvent::Head(json) => (DV_HTTP_EVENT_HEAD, Bytes::from(json)),
                ClientEvent::Body(bytes) => (DV_HTTP_EVENT_BODY, bytes),
                ClientEvent::Error(json) => (DV_HTTP_EVENT_ERROR, Bytes::from(json)),
            };
            *out = leak_buf(payload);
            code
        }
        // The sender dropped: the task finished and every event has been
        // delivered. The handle is dropped here rather than re-inserted, so a
        // caller that stops pumping cannot leak it.
        None => DV_HTTP_EVENT_DONE,
    }
}

/// Releases a payload returned by [`dv_http_next_event`].
///
/// # Safety
/// `buf` must be a buffer this library produced and not already freed.
#[no_mangle]
pub unsafe extern "C" fn dv_http_free_buf(buf: FfiBuf) {
    if buf.ptr.is_null() || buf.len == 0 {
        return;
    }
    drop(Vec::from_raw_parts(buf.ptr as *mut u8, buf.len, buf.len));
}

/// Asks an in-flight request to stop. Safe to call on an unknown handle.
#[no_mangle]
pub extern "C" fn dv_http_cancel(handle: u64) -> i32 {
    let Ok(mut map) = requests().lock() else {
        return 0;
    };
    match map.get_mut(&handle).and_then(|p| p.cancel.take()) {
        Some(cancel) => {
            let _ = cancel.send(());
            1
        }
        None => 0,
    }
}

fn leak_buf(bytes: Bytes) -> FfiBuf {
    let mut vec = bytes.to_vec();
    vec.shrink_to_fit();
    let len = vec.len();
    let ptr = vec.as_ptr();
    std::mem::forget(vec);
    FfiBuf { ptr, len }
}

// ===== Failure reporting =====

struct Failure {
    message: String,
    /// Whether another protocol could plausibly succeed. A refused handshake
    /// is worth retrying; a response the origin actually sent is not.
    retryable: bool,
}

impl Failure {
    fn new(message: impl Into<String>, retryable: bool) -> Self {
        Failure {
            message: message.into(),
            retryable,
        }
    }

    fn to_json(&self) -> String {
        json!({ "message": self.message, "retryable": self.retryable }).to_string()
    }
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

/// Connection-level problems are retryable on another protocol; anything the
/// origin answered is not.
fn connect_failure(error: impl std::fmt::Display) -> Failure {
    Failure::new(format!("connect: {error}"), true)
}

// ===== The request itself =====

async fn perform(
    request: ClientRequest,
    body: Bytes,
    events: mpsc::UnboundedSender<ClientEvent>,
) -> Result<(), Failure> {
    let url: http::Uri = request
        .url
        .parse()
        .map_err(|e| Failure::new(format!("bad url: {e}"), false))?;

    if url.scheme_str() != Some("https") {
        // ALPN happens in the TLS handshake, so there is no cleartext path to
        // HTTP/2 here. Saying so beats failing later with a parse error.
        return Err(Failure::new(
            "only https is supported by the native client",
            false,
        ));
    }

    let host = url
        .host()
        .ok_or_else(|| Failure::new("url has no host", false))?
        .to_string();
    let port = url.port_u16().unwrap_or(443);

    let timeout = if request.timeout_ms == 0 {
        std::time::Duration::from_secs(30)
    } else {
        std::time::Duration::from_millis(request.timeout_ms)
    };

    let work = async {
        let tcp = TcpStream::connect((host.as_str(), port))
            .await
            .map_err(connect_failure)?;
        // Nagle costs a round trip on small request bodies, which is most of
        // what a provider API sends.
        let _ = tcp.set_nodelay(true);

        let mut config = ClientConfig::builder()
            .with_root_certificates(tls_roots())
            .with_no_client_auth();
        config.alpn_protocols = vec![request.alpn.as_bytes().to_vec()];

        let server_name = ServerName::try_from(host.clone())
            .map_err(|e| Failure::new(format!("bad server name: {e}"), false))?;
        let tls = TlsConnector::from(Arc::new(config))
            .connect(server_name, tcp)
            .await
            .map_err(connect_failure)?;

        let negotiated = tls
            .get_ref()
            .1
            .alpn_protocol()
            .map(|p| String::from_utf8_lossy(p).to_string())
            .unwrap_or_default();

        if request.alpn == "h2" && negotiated != "h2" {
            // The peer would not speak HTTP/2. That is precisely the case the
            // Dart fallback chain exists to handle, so it is retryable.
            return Err(Failure::new(
                format!("peer did not negotiate h2 (got {negotiated:?})"),
                true,
            ));
        }

        send_http2(tls, url, request, body, events, negotiated).await
    };

    match tokio::time::timeout(timeout, work).await {
        Ok(result) => result,
        Err(_) => Err(Failure::new("timed out", true)),
    }
}

async fn send_http2<S>(
    stream: S,
    url: http::Uri,
    request: ClientRequest,
    body: Bytes,
    events: mpsc::UnboundedSender<ClientEvent>,
    negotiated: String,
) -> Result<(), Failure>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let (mut send_request, connection) = h2::client::handshake(stream)
        .await
        .map_err(|e| Failure::new(format!("h2 handshake: {e}"), true))?;

    // The connection future drives all IO for this stream. Without a task
    // polling it nothing moves, including the informational responses below.
    tokio::spawn(async move {
        let _ = connection.await;
    });

    let method = http::Method::from_bytes(request.method.as_bytes())
        .map_err(|e| Failure::new(format!("bad method: {e}"), false))?;

    let mut builder = http::Request::builder().method(method).uri(url);
    for (name, value) in &request.headers {
        builder = builder.header(name.as_str(), value.as_str());
    }
    let outgoing = builder
        .body(())
        .map_err(|e| Failure::new(format!("bad request: {e}"), false))?;

    let has_body = !body.is_empty();
    let (mut response_future, mut request_body) = send_request
        .send_request(outgoing, !has_body)
        .map_err(|e| Failure::new(format!("send: {e}"), true))?;

    if has_body {
        request_body
            .send_data(body, true)
            .map_err(|e| Failure::new(format!("send body: {e}"), true))?;
    }

    // Early hints, then the response — in one poll so informational frames are
    // drained before the main future each time it is woken, which is the order
    // h2 documents. Emitting from inside the closure is what makes them early:
    // collecting them to deliver alongside the response would defeat the point.
    let hint_sink = events.clone();
    let response = std::future::poll_fn(|cx: &mut Context<'_>| {
        loop {
            match response_future.poll_informational(cx) {
                Poll::Ready(Some(Ok(informational))) => {
                    let _ = hint_sink.send(ClientEvent::EarlyHints(headers_json(
                        informational.headers(),
                    )));
                }
                // An error polling informational responses is not fatal to the
                // request: the real response may still arrive, and early hints
                // are an optimisation. Stop draining and let the main future
                // report whatever actually happens.
                Poll::Ready(Some(Err(_))) | Poll::Ready(None) => break,
                Poll::Pending => break,
            }
        }
        Pin::new(&mut response_future).poll(cx)
    })
    .await
    .map_err(|e| Failure::new(format!("response: {e}"), true))?;

    let status = response.status().as_u16();
    let head = json!({
        "status": status,
        "protocol": negotiated,
        "headers": serde_json::from_str::<serde_json::Value>(
            &headers_json(response.headers())
        ).unwrap_or_else(|_| json!({})),
    })
    .to_string();
    let _ = events.send(ClientEvent::Head(head));

    let mut body_stream = response.into_body();
    while let Some(chunk) = body_stream.data().await {
        let chunk = chunk.map_err(|e| {
            // The head already reached the caller, so the origin answered.
            // Retrying on another protocol would ask a question that was
            // already answered.
            Failure::new(format!("body: {e}"), false)
        })?;
        // Releasing capacity is what lets the peer keep sending. Skipping it
        // stalls the stream after the initial window.
        let _ = body_stream.flow_control().release_capacity(chunk.len());
        if !chunk.is_empty() {
            let _ = events.send(ClientEvent::Body(chunk));
        }
    }

    Ok(())
}

fn headers_json(headers: &http::HeaderMap) -> String {
    let mut map = serde_json::Map::new();
    for (name, value) in headers {
        let text = match value.to_str() {
            Ok(text) => text.to_string(),
            Err(_) => continue,
        };
        // A repeated header is joined with ", ", which is the field-value
        // concatenation HTTP already defines. Set-Cookie is the exception that
        // must not be joined, and it does not appear on these responses.
        map.entry(name.as_str().to_ascii_lowercase())
            .and_modify(|existing| {
                if let Some(current) = existing.as_str() {
                    *existing = json!(format!("{current}, {text}"));
                }
            })
            .or_insert_with(|| json!(text));
    }
    serde_json::Value::Object(map).to_string()
}

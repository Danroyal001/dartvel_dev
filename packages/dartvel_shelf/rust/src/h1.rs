//! Plain HTTP/1.1 requests served without hyper on the hot path.
//!
//! A driven server (`AW_FLAG_DRIVEN`) on plain TCP accepts its own
//! connections. Each connection's requests are read here and classified:
//!
//! - a `GET` over HTTP/1.1 in origin form, with no body (no
//!   `Transfer-Encoding`, `Content-Length` absent or exactly `0`), no
//!   `Upgrade`, no `Expect`, and `Connection` absent or `keep-alive`, is
//!   served here: handed to the isolate's request queue straight from the
//!   bytes it arrived in, and its answer written by this module;
//! - anything else -- a body, an upgrade, HTTP/1.0, a head this module
//!   cannot parse or that is larger than it keeps -- hands the connection,
//!   with every byte already read, to hyper, which serves the rest of that
//!   connection exactly as it served every connection before. Each refusal,
//!   400 and edge case is still hyper's.
//!
//! So the only framing decision this module makes alone is "this request has
//! no body", and it makes it only when the head leaves no other reading:
//! a conflicting `Content-Length`, any `Transfer-Encoding`, or an obsolete
//! line fold all go to hyper. That is the part request smuggling lives in.
//!
//! No unsafe code: the pointers handed to Dart are taken with safe calls and
//! point into bytes kept in `PENDING_REQUEST_PARTS` until Dart has read them.
#![forbid(unsafe_code)]

use std::ops::Range;
use std::pin::Pin;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use axum::body::Body;
use axum::http::{header, HeaderValue, Request, Response, StatusCode};
use bytes::{Bytes, BytesMut};
use http_body_util::BodyExt as _;
use tokio::io::{AsyncRead, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio::sync::watch;

use super::{
    abandon_stream, aw_ws_dispose, canonical_peer, closing_response, plain_response,
    response_from_dart, safe_lock, FfiBuf, FfiRequest, FfiRespOwned,
    FfiStr, Reply, RequestParts, ServerContext, ServerRequestQueue, NEXT_ID, PENDING_RESPONSES,
    WS_PENDING,
};

/// The largest request head kept here. A head still incomplete at this size
/// goes to hyper, which applies its own (larger) limit and answers it.
pub(crate) const MAX_HEAD_BYTES: usize = 64 * 1024;

/// Header fields parsed here. A request with more goes to hyper.
pub(crate) const MAX_HEADERS: usize = 64;

/// What [classify] made of the start of a connection's unread bytes.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Classified {
    /// The head is not complete yet.
    Partial,
    /// Not a request this module serves: hyper takes the connection.
    Fallback,
    /// A bodiless GET this module serves.
    Fast(FastHead),
}

/// Where a served request's parts lie in the bytes it was classified from.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct FastHead {
    /// Bytes of the head, final blank line included; the next request starts
    /// right after.
    pub head_len: usize,
    pub method: Range<usize>,
    pub target: Range<usize>,
    pub headers: Vec<(Range<usize>, Range<usize>)>,
    /// The request said which encodings it accepts, so a server that
    /// compresses has to look at its answer.
    pub accept_encoding: Option<Range<usize>>,
}

fn offset(base: &[u8], part: &[u8]) -> Range<usize> {
    let start = part.as_ptr() as usize - base.as_ptr() as usize;
    start..start + part.len()
}

/// Classifies the request at the start of [buf].
pub(crate) fn classify(buf: &[u8]) -> Classified {
    let mut slots = [httparse::EMPTY_HEADER; MAX_HEADERS];
    let mut request = httparse::Request::new(&mut slots);
    let head_len = match request.parse(buf) {
        Ok(httparse::Status::Complete(length)) => length,
        Ok(httparse::Status::Partial) => {
            return if buf.len() >= MAX_HEAD_BYTES { Classified::Fallback } else { Classified::Partial };
        }
        // Malformed, or more fields than kept: hyper answers it.
        Err(_) => return Classified::Fallback,
    };
    if head_len > MAX_HEAD_BYTES {
        return Classified::Fallback;
    }
    let (Some(method), Some(path), Some(1)) = (request.method, request.path, request.version) else {
        return Classified::Fallback;
    };
    if method != "GET" || !path.starts_with('/') {
        return Classified::Fallback;
    }
    let mut headers = Vec::with_capacity(request.headers.len());
    let mut accept_encoding = None;
    let mut content_length_seen = false;
    for field in request.headers.iter() {
        let name = field.name.as_bytes();
        let value = field.value;
        if name.eq_ignore_ascii_case(b"content-length") {
            // Exactly one, exactly "0". Anything else -- a length, a list,
            // a second field -- is a body or a conflict, and hyper's.
            if content_length_seen || value != b"0" {
                return Classified::Fallback;
            }
            content_length_seen = true;
        } else if name.eq_ignore_ascii_case(b"transfer-encoding")
            || name.eq_ignore_ascii_case(b"upgrade")
            || name.eq_ignore_ascii_case(b"expect")
            || name.eq_ignore_ascii_case(b"http2-settings")
        {
            return Classified::Fallback;
        } else if name.eq_ignore_ascii_case(b"connection") {
            if !value.eq_ignore_ascii_case(b"keep-alive") {
                return Classified::Fallback;
            }
        } else if name.eq_ignore_ascii_case(b"accept-encoding") {
            accept_encoding = Some(offset(buf, value));
        }
        headers.push((offset(buf, name), offset(buf, value)));
    }
    Classified::Fast(FastHead {
        head_len,
        method: offset(buf, method.as_bytes()),
        target: offset(buf, path.as_bytes()),
        headers,
        accept_encoding,
    })
}

/// What a lean server needs besides its listener.
pub(crate) struct Lean {
    pub context: ServerContext,
    /// The context's default fields, rendered once for write_whole.
    pub defaults: RenderedDefaults,
    /// The server's full axum service, for the connections handed to hyper.
    pub app: axum::Router,
    pub compression: bool,
    pub header_timeout: Duration,
    pub shutdown: watch::Receiver<bool>,
}

/// Accepts [listener]'s connections until the server stops, then gives the
/// open ones five seconds to finish and closes the rest, as the graceful
/// shutdown of the hyper server did.
pub(crate) async fn serve(listener: std::net::TcpListener, lean: Arc<Lean>) -> std::io::Result<()> {
    listener.set_nonblocking(true)?;
    let listener = tokio::net::TcpListener::from_std(listener)?;
    let mut connections = tokio::task::JoinSet::new();
    let mut shutdown = lean.shutdown.clone();
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                connections.spawn(connection(stream, peer, lean.clone()));
            }
            // Finished connections are collected as they end.
            Some(_) = connections.join_next(), if !connections.is_empty() => {}
            _ = shutdown.changed() => break,
        }
    }
    drop(listener);
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        match tokio::time::timeout_at(deadline, connections.join_next()).await {
            Ok(Some(_)) => {}
            Ok(None) => break,
            Err(_) => {
                // Past the grace period: closed, so a client waiting on an
                // answer that will never be written is told so.
                connections.abort_all();
                while connections.join_next().await.is_some() {}
                break;
            }
        }
    }
    Ok(())
}

fn stopping(shutdown: &watch::Receiver<bool>) -> bool {
    *shutdown.borrow()
}

/// One lean connection's socket and the answer it waits for, shared between
/// its task and aw_complete.
///
/// A whole answer used to cross to the connection's task: aw_complete copied
/// it into owned buffers, sent it down a oneshot channel, and the task was
/// woken, polled, wrote it, and went back to reading. Under load that wakeup
/// was most of the native cost of a request. Now aw_complete writes the
/// answer to the socket itself, from Dart's buffer, and the task is woken only
/// when there is something left for it: the rest of an answer the socket
/// would not take, a connection to close, or an answer of the kind the
/// generic path writes (streamed, compressed, an upgrade). The task meanwhile
/// waits for the client's next request, which is the one wakeup left.
pub(crate) struct DirectConn {
    write: tokio::net::tcp::OwnedWriteHalf,
    lean: Arc<Lean>,
    state: std::sync::Mutex<DirectState>,
    /// Wakes the task for an answer it has to act on.
    act: tokio::sync::Notify,
}

struct DirectState {
    /// What aw_complete writes from: an answer's bytes, kept between answers
    /// so none allocates, and what the socket did not take of the last one.
    out: Vec<u8>,
    phase: Phase,
    /// The task is waiting for this answer, so aw_complete wakes it however
    /// the answer went.
    task_waits: bool,
}

enum Phase {
    /// No request of this connection's is with Dart.
    Idle,
    /// Dart has the request; [direct] when its answer may be written from
    /// aw_complete (not when it has to be compressed).
    Waiting { direct: bool },
    /// The answer is written, at [at]: the next head is timed from then.
    Written { keep_alive: bool, at: tokio::time::Instant },
    /// The answer is in `out`, and the socket took it only up to [from].
    Partial { from: usize, keep_alive: bool },
    /// An answer the generic path writes.
    Answer(FfiRespOwned),
    /// An answer that cannot be sent as given: the task answers 500.
    Refused,
    /// The socket failed.
    Broken,
}

/// The request a connection has with Dart. Dropped unanswered -- the task
/// aborted when the server stops past its grace period -- it takes the
/// connection out of the table aw_complete looks in, so the socket closes
/// with the task rather than when Dart answers.
struct Flight {
    req_id: u64,
    accept_encoding: Option<HeaderValue>,
    landed: bool,
}

impl Drop for Flight {
    fn drop(&mut self) {
        if !self.landed {
            if let Some(pending) = PENDING_RESPONSES.get() {
                safe_lock(pending).remove(&self.req_id);
            }
        }
    }
}

/// Writes a whole answer for [conn]'s request from aw_complete, from the
/// bytes Dart gave. False when this answer is not one written here (the
/// caller hands it over owned, with [answer_owned]).
pub(crate) fn answer_direct(conn: &DirectConn, status: u16, headers: &[u8], body: &[u8]) -> bool {
    let mut guard = safe_lock(&conn.state);
    // 101 is an upgrade, which the task checks against the request.
    if status == 101 || !matches!(guard.phase, Phase::Waiting { direct: true }) {
        return false;
    }
    let state = &mut *guard;
    let (second, date) = http_now();
    let written = HEADS.with(|cache| {
        cache.borrow_mut().write(&mut state.out, status, headers, body, &conn.lean.defaults, second, &date)
    });
    state.phase = match written {
        Err(why) => {
            eprintln!("dartvel: a handler's response {why}; answered 500");
            Phase::Refused
        }
        Ok(keep_alive) => {
            let socket: &tokio::net::TcpStream = conn.write.as_ref();
            let mut from = 0;
            loop {
                match socket.try_write(&state.out[from..]) {
                    Ok(0) => break Phase::Broken,
                    Ok(written) => {
                        from += written;
                        if from == state.out.len() {
                            break Phase::Written { keep_alive, at: tokio::time::Instant::now() };
                        }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        break Phase::Partial { from, keep_alive }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
                    Err(_) => break Phase::Broken,
                }
            }
        }
    };
    // The one case the task need not hear about: written whole, and the
    // connection stays open. It finds out when it next looks.
    let wake = state.task_waits || !matches!(state.phase, Phase::Written { keep_alive: true, .. });
    if wake {
        state.task_waits = false;
        drop(guard);
        conn.act.notify_one();
    }
    true
}

/// Hands [conn]'s task an answer the generic path writes.
pub(crate) fn answer_owned(conn: &DirectConn, answer: FfiRespOwned) {
    {
        let mut state = safe_lock(&conn.state);
        state.phase = Phase::Answer(answer);
        state.task_waits = false;
    }
    conn.act.notify_one();
}

/// Tells [conn]'s task its answer could not be read: it answers 500.
pub(crate) fn answer_refused(conn: &DirectConn) {
    {
        let mut state = safe_lock(&conn.state);
        state.phase = Phase::Refused;
        state.task_waits = false;
    }
    conn.act.notify_one();
}

/// What became of the connection's answer, taken; None while Dart still has
/// the request (and, with [wait], the task is then woken when it has not).
fn settled(conn: &DirectConn, wait: bool) -> Option<Phase> {
    let mut state = safe_lock(&conn.state);
    if matches!(state.phase, Phase::Waiting { .. }) {
        if wait {
            state.task_waits = true;
        }
        return None;
    }
    Some(std::mem::replace(&mut state.phase, Phase::Idle))
}

/// A connection's socket for the task's own writes, which aw_complete never
/// overlaps: it writes only while the task waits for it to.
struct SharedWrite<'a>(&'a tokio::net::TcpStream);

impl AsyncWrite for SharedWrite<'_> {
    fn poll_write(self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &[u8]) -> Poll<std::io::Result<usize>> {
        loop {
            match self.0.poll_write_ready(cx) {
                Poll::Ready(Ok(())) => {}
                Poll::Ready(Err(error)) => return Poll::Ready(Err(error)),
                Poll::Pending => return Poll::Pending,
            }
            match self.0.try_write(buf) {
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                result => return Poll::Ready(result),
            }
        }
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

/// The connection's stream whole again, for hyper: once no answer holds the
/// shared half. Only an aw_complete that has just settled the answer on the
/// helper thread can still hold it, for as long as it takes to return.
async fn reclaim(mut conn: Arc<DirectConn>, read: tokio::net::tcp::OwnedReadHalf) -> Option<tokio::net::TcpStream> {
    loop {
        match Arc::try_unwrap(conn) {
            Ok(owned) => return read.reunite(owned.write).ok(),
            Err(shared) => {
                conn = shared;
                tokio::task::yield_now().await;
            }
        }
    }
}

async fn connection(stream: tokio::net::TcpStream, peer: std::net::SocketAddr, lean: Arc<Lean>) {
    use tokio::io::AsyncReadExt as _;
    let _ = stream.set_nodelay(true);
    let peer_text = Bytes::from(canonical_peer(peer).to_string());
    let mut buf = BytesMut::with_capacity(8 * 1024);
    let mut out = Vec::new();
    let mut shutdown = lean.shutdown.clone();
    let mut head_deadline = LazyDeadline::new();
    let mut answer_deadline = LazyDeadline::new();
    let (mut read, write) = stream.into_split();
    let conn = Arc::new(DirectConn {
        write,
        lean: lean.clone(),
        state: std::sync::Mutex::new(DirectState {
            out: Vec::with_capacity(4 * 1024),
            phase: Phase::Idle,
            task_waits: false,
        }),
        act: tokio::sync::Notify::new(),
    });
    let mut flight: Option<Flight> = None;
    // The whole head within the header timeout, as hyper bounds it; a
    // connection that sends part of one and stops is closed. Timed from when
    // the connection is ready for it: its first byte here, the answer before
    // it on a kept-alive connection.
    head_deadline.set(tokio::time::Instant::now() + lean.header_timeout);
    loop {
        let head = loop {
            if !buf.is_empty() {
                match classify(&buf) {
                    Classified::Partial => {}
                    other => break other,
                }
            } else if flight.is_none() && stopping(&shutdown) {
                return;
            }
            if buf.capacity() - buf.len() < 1024 {
                buf.reserve(8 * 1024);
            }
            tokio::select! {
                biased;
                // The answer needs the task, or its deadline passed.
                () = conn.act.notified(), if flight.is_some() => {
                    match land(&conn, &mut flight, &mut answer_deadline, &mut out).await {
                        Some(at) => head_deadline.set(at + lean.header_timeout),
                        None => return,
                    }
                }
                () = answer_deadline.passed(), if flight.is_some() => {
                    match land(&conn, &mut flight, &mut answer_deadline, &mut out).await {
                        Some(at) => head_deadline.set(at + lean.header_timeout),
                        None => return,
                    }
                }
                read = read.read_buf(&mut buf) => match read {
                    Ok(0) | Err(_) => {
                        // The client is gone; an answer Dart still owes it is
                        // waited for, as before, so its request is cleaned up.
                        if flight.is_some() {
                            land(&conn, &mut flight, &mut answer_deadline, &mut out).await;
                        }
                        return;
                    }
                    Ok(_) => {}
                },
                () = head_deadline.passed() => {
                    if flight.is_some() {
                        // Timed from the answer, which may have gone since.
                        match settled(&conn, false) {
                            None => head_deadline.set(tokio::time::Instant::now() + lean.header_timeout),
                            Some(phase) => match finish(&conn, phase, &mut flight, &mut out).await {
                                Some(at) => head_deadline.set(at + lean.header_timeout),
                                None => return,
                            },
                        }
                    } else {
                        return;
                    }
                }
                // An idle keep-alive connection closes when the server stops;
                // one partway through a head is finished first.
                _ = shutdown.changed(), if buf.is_empty() && flight.is_none() => return,
            }
        };
        // Answers go out in order: the one before this head first.
        if flight.is_some() {
            match land(&conn, &mut flight, &mut answer_deadline, &mut out).await {
                Some(at) => head_deadline.set(at + lean.header_timeout),
                None => return,
            }
        }
        let fast = match head {
            Classified::Fast(fast) if served_here(&buf, &fast, &lean.context) => fast,
            _ => {
                let upgrade = asks_for_upgrade(&buf);
                let Some(stream) = reclaim(conn, read).await else { return };
                if upgrade {
                    // A WebSocket streams frames both ways: the kernel
                    // coalescing small writes is worth more there than the
                    // latency no-delay saves a request and its answer, so an
                    // upgraded connection keeps the socket as hyper had it.
                    let _ = stream.set_nodelay(false);
                }
                return hand_to_hyper(stream, buf.freeze(), peer, lean).await;
            }
        };
        let head_bytes = buf.split_to(fast.head_len).freeze();
        match send_fast(&conn, &mut out, head_bytes, fast, &peer_text, &mut answer_deadline).await {
            Some(sent) => flight = Some(sent),
            None => return,
        }
        // Until the answer says when it went.
        head_deadline.set(tokio::time::Instant::now() + lean.header_timeout);
    }
}

/// Waits for [flight]'s answer, or its deadline, and finishes it: when the
/// answer went and the connection stays open, or None to close it.
async fn land(
    conn: &DirectConn,
    flight: &mut Option<Flight>,
    answer_deadline: &mut LazyDeadline,
    out: &mut Vec<u8>,
) -> Option<tokio::time::Instant> {
    loop {
        if let Some(phase) = settled(conn, true) {
            return finish(conn, phase, flight, out).await;
        }
        tokio::select! {
            biased;
            () = conn.act.notified() => {}
            () = answer_deadline.passed() => {
                let req_id = flight.as_ref().map(|flight| flight.req_id)?;
                let ours = PENDING_RESPONSES
                    .get()
                    .and_then(|pending| safe_lock(pending).remove(&req_id))
                    .is_some();
                if !ours {
                    // aw_complete has the answer: it settles it in a moment.
                    continue;
                }
                if let Some(flight) = flight.as_mut() {
                    flight.landed = true;
                }
                *flight = None;
                safe_lock(&conn.state).phase = Phase::Idle;
                aw_ws_dispose(req_id);
                let ServerContext(context) = &conn.lean.context;
                abandon_stream(req_id, Some(context.id));
                let _ = write_response(&mut SharedWrite(conn.write.as_ref()), out, closing_response(StatusCode::GATEWAY_TIMEOUT)).await;
                return None;
            }
        }
    }
}

/// Writes what is left of [flight]'s answer, given how it [phase]d.
async fn finish(
    conn: &DirectConn,
    phase: Phase,
    flight: &mut Option<Flight>,
    out: &mut Vec<u8>,
) -> Option<tokio::time::Instant> {
    let Some(mut done) = flight.take() else { return None };
    done.landed = true;
    let lean = &*conn.lean;
    let ServerContext(context) = &lean.context;
    let socket: &tokio::net::TcpStream = conn.write.as_ref();
    let kept = |keep_alive: bool| keep_alive.then(tokio::time::Instant::now);
    let response = match phase {
        Phase::Written { keep_alive, at } => return keep_alive.then_some(at),
        Phase::Idle | Phase::Waiting { .. } | Phase::Broken => return None,
        Phase::Partial { from, keep_alive } => {
            let rest = std::mem::take(&mut safe_lock(&conn.state).out);
            let written = SharedWrite(socket).write_all(&rest[from..]).await.is_ok();
            safe_lock(&conn.state).out = rest;
            return kept(written && keep_alive);
        }
        Phase::Refused => plain_response(StatusCode::INTERNAL_SERVER_ERROR),
        Phase::Answer(answer) => {
            let pending_upgrade = WS_PENDING
                .get()
                .and_then(|pending| safe_lock(pending).remove(&done.req_id));
            if pending_upgrade.is_some() {
                // An upgrade answer to a request that asked for none.
                aw_ws_dispose(done.req_id);
                plain_response(StatusCode::BAD_REQUEST)
            } else if answer.is_stream == 0 && done.accept_encoding.is_none() {
                match write_whole(out, answer.status, &answer.headers, &answer.body, &lean.defaults, &http_date()) {
                    Ok(keep_alive) => {
                        let written = SharedWrite(socket).write_all(out).await.is_ok();
                        return kept(written && keep_alive);
                    }
                    Err(why) => {
                        eprintln!("dartvel: a handler's response {why}; answered 500");
                        plain_response(StatusCode::INTERNAL_SERVER_ERROR)
                    }
                }
            } else {
                response_from_dart(answer, done.req_id, Some(context.id), None, context.defaults.as_ref())
            }
        }
    };
    let response = match done.accept_encoding.take() {
        Some(accepted) => compressed(response, accepted).await,
        None => response,
    };
    kept(write_response(&mut SharedWrite(socket), out, response).await.unwrap_or(false))
}

/// One connection's deadline of one kind (its next head, or Dart's next
/// answer), on one timer that is armed again only when it rings early.
///
/// A tokio timeout per read and per answer put a timer into the wheel and
/// took it out again for every request, a large share of the native cost of
/// one. These deadlines only move forward, so the timer set for an earlier
/// one rings first; it then checks the deadline now in force and, when that
/// has not passed, sleeps on until it. A deadline still passes exactly when
/// it is due.
pub(crate) struct LazyDeadline {
    timer: std::pin::Pin<Box<tokio::time::Sleep>>,
    /// When the timer rings; None before the first deadline.
    armed: Option<tokio::time::Instant>,
    deadline: tokio::time::Instant,
}

impl LazyDeadline {
    pub(crate) fn new() -> LazyDeadline {
        let now = tokio::time::Instant::now();
        // Not in the wheel until first polled, and armed before that.
        LazyDeadline { timer: Box::pin(tokio::time::sleep_until(now)), armed: None, deadline: now }
    }

    /// Makes [deadline] the one in force.
    pub(crate) fn set(&mut self, deadline: tokio::time::Instant) {
        self.deadline = deadline;
        // A timer set for later than the new deadline would ring too late.
        if self.armed.is_none_or(|armed| armed > deadline) {
            self.timer.as_mut().reset(deadline);
            self.armed = Some(deadline);
        }
    }

    /// Completes when the deadline in force passes. Cancel-safe.
    pub(crate) async fn passed(&mut self) {
        loop {
            self.timer.as_mut().await;
            if tokio::time::Instant::now() >= self.deadline {
                return;
            }
            self.timer.as_mut().reset(self.deadline);
            self.armed = Some(self.deadline);
        }
    }
}

/// Whether the request at the start of [buf] asks to upgrade the connection.
fn asks_for_upgrade(buf: &[u8]) -> bool {
    let mut slots = [httparse::EMPTY_HEADER; MAX_HEADERS];
    let mut request = httparse::Request::new(&mut slots);
    if request.parse(buf).is_err() {
        return false;
    }
    request
        .headers
        .iter()
        .any(|field| field.name.eq_ignore_ascii_case("upgrade"))
}

/// Whether a request classified fast is one this server answers here: its
/// built-in health routes and its own files are the axum router's.
fn served_here(buf: &[u8], fast: &FastHead, context: &ServerContext) -> bool {
    let target = &buf[fast.target.clone()];
    let path = match target.iter().position(|&b| b == b'?') {
        Some(query) => &target[..query],
        None => target,
    };
    if matches!(path, b"/health" | b"/healthz" | b"/healths") {
        return false;
    }
    let ServerContext(inner) = context;
    if inner.static_paths.spa.is_some() {
        return false;
    }
    if inner.static_paths.directory.is_some() && path.starts_with(b"/static/") {
        return false;
    }
    true
}

fn ffi_str(bytes: &[u8]) -> FfiStr {
    FfiStr { ptr: bytes.as_ptr(), len: bytes.len() }
}

/// Hands one fast request to the isolate's queue. None when it could not be
/// (answered 500 already; the connection closes).
async fn send_fast(
    conn: &Arc<DirectConn>,
    out: &mut Vec<u8>,
    head: Bytes,
    fast: FastHead,
    peer: &Bytes,
    answer_deadline: &mut LazyDeadline,
) -> Option<Flight> {
    let lean = &*conn.lean;
    let ServerContext(context) = &lean.context;
    let socket: &tokio::net::TcpStream = conn.write.as_ref();
    let Some(ServerRequestQueue(queue)) = &context.queue else {
        // Lean servers are driven, and a driven server has a queue.
        let _ = write_response(&mut SharedWrite(socket), out, plain_response(StatusCode::INTERNAL_SERVER_ERROR)).await;
        return None;
    };
    let Some(req_id) = NEXT_ID.get().map(|id| id.fetch_add(1, Ordering::Relaxed)) else {
        let _ = write_response(&mut SharedWrite(socket), out, plain_response(StatusCode::INTERNAL_SERVER_ERROR)).await;
        return None;
    };
    // The same NUL-separated form the hyper path hands Dart.
    let mut flat = Vec::with_capacity(head.len());
    for (name, value) in &fast.headers {
        flat.extend_from_slice(&head[name.clone()]);
        flat.push(0);
        flat.extend_from_slice(&head[value.clone()]);
        flat.push(0);
    }
    let request = FfiRequest {
        id: req_id,
        method: ffi_str(&head[fast.method.clone()]),
        target: ffi_str(&head[fast.target.clone()]),
        hdrs: flat.as_ptr(),
        hdrs_len: flat.len(),
        // A fast request never has a body.
        body: FfiBuf { ptr: super::AW_BODY_NONE as *const u8, len: 0 },
        peer: ffi_str(peer),
    };
    let accept_encoding = if lean.compression {
        fast.accept_encoding
            .clone()
            .and_then(|range| HeaderValue::from_bytes(&head[range]).ok())
    } else {
        None
    };
    safe_lock(&conn.state).phase = Phase::Waiting { direct: accept_encoding.is_none() };
    if let Some(pending) = PENDING_RESPONSES.get() {
        safe_lock(pending).insert(req_id, Reply::Direct(conn.clone()));
    }
    answer_deadline.set(tokio::time::Instant::now() + context.timeout);
    // Moving the Vec and the Bytes moves their handles, not their bytes: the
    // pointers above stay valid while the queue holds them, until Dart has
    // read them.
    queue.push(
        request,
        RequestParts {
            _method: Vec::new(),
            _target: Vec::new(),
            _headers: flat,
            _body: Bytes::new(),
            _peer: Vec::new(),
            _head: Some(head),
            _peer_bytes: Some(peer.clone()),
        },
    );
    Some(Flight { req_id, accept_encoding, landed: false })
}

/// [response] through the same compression layer the axum router applies,
/// for the request's `Accept-Encoding`.
async fn compressed(response: Response<Body>, accepted: HeaderValue) -> Response<Body> {
    use tower::{Layer as _, ServiceExt as _};
    let mut once = Some(response);
    let service = tower::service_fn(move |_request: Request<Body>| {
        let answer = once.take().unwrap_or_else(|| plain_response(StatusCode::INTERNAL_SERVER_ERROR));
        async move { Ok::<_, std::convert::Infallible>(answer) }
    });
    let mut request = Request::new(Body::empty());
    request.headers_mut().insert(header::ACCEPT_ENCODING, accepted);
    match tower_http::compression::CompressionLayer::new()
        .layer(service)
        .oneshot(request)
        .await
    {
        Ok(response) => response.map(Body::new),
        Err(never) => match never {},
    }
}

thread_local! {
    static DATE: std::cell::Cell<(u64, [u8; 29])> = const { std::cell::Cell::new((0, [0; 29])) };
}

/// [n] in decimal, appended to [out] without allocating.
fn write_decimal(out: &mut Vec<u8>, mut n: usize) {
    let mut digits = [0u8; 20];
    let mut at = digits.len();
    loop {
        at -= 1;
        digits[at] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(&digits[at..]);
}

/// The server's default fields (serve()'s securityHeaders), rendered once
/// as response lines: an answer that sets none of them gets the whole block
/// in one copy, where each was compared with each of the answer's fields
/// and written out on every response.
pub(crate) struct RenderedDefaults {
    /// Which server's defaults these are, for HeadCache: never reused.
    id: u64,
    block: Vec<u8>,
    /// Each default's lowercase name and where its line lies in [block].
    lines: Vec<(Vec<u8>, std::ops::Range<usize>)>,
}

impl RenderedDefaults {
    pub(crate) fn new(defaults: Option<&axum::http::HeaderMap>) -> RenderedDefaults {
        let mut block = Vec::new();
        let mut lines = Vec::new();
        if let Some(defaults) = defaults {
            for (name, value) in defaults.iter() {
                let start = block.len();
                block.extend_from_slice(name.as_str().as_bytes());
                block.extend_from_slice(b": ");
                block.extend_from_slice(value.as_bytes());
                block.extend_from_slice(b"\r\n");
                lines.push((name.as_str().as_bytes().to_vec(), start..block.len()));
            }
        }
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        RenderedDefaults { id: NEXT.fetch_add(1, Ordering::Relaxed), block, lines }
    }

    /// Which of the first 64 defaults [name] stands for, as bits of a mask:
    /// a default whose bit is set is not written.
    fn matching(&self, name: &[u8]) -> u64 {
        let mut mask = 0u64;
        for (index, (default, _)) in self.lines.iter().take(64).enumerate() {
            if default.len() == name.len() && default.eq_ignore_ascii_case(name) {
                mask |= 1u64 << index;
            }
        }
        mask
    }

    /// Writes every default the answer ([headers], NUL-separated pairs) did
    /// not set itself: the first 64 by [overridden], any further ones by
    /// looking for them among [headers].
    fn write_except(&self, out: &mut Vec<u8>, overridden: u64, headers: &[u8]) {
        if overridden == 0 && self.lines.len() <= 64 {
            out.extend_from_slice(&self.block);
            return;
        }
        for (index, (name, line)) in self.lines.iter().enumerate() {
            let given = if index < 64 {
                overridden & (1u64 << index) != 0
            } else {
                headers.split(|&b| b == 0).step_by(2).any(|given| given.eq_ignore_ascii_case(name))
            };
            if !given {
                out.extend_from_slice(&self.block[line.clone()]);
            }
        }
    }
}

thread_local! {
    static HEADS: std::cell::RefCell<HeadCache> = std::cell::RefCell::new(HeadCache::default());
}

/// The head of the last whole answer this thread wrote, and what it was
/// written from.
///
/// A route answers with the same status, the same fields and a body of the
/// same length request after request, so within one second (the Date) its
/// head is the same bytes every time. Checking and formatting it again was
/// most of what writing an answer cost; now an answer whose head is the
/// last one's costs a comparison of its fields and a copy.
#[derive(Default)]
pub(crate) struct HeadCache {
    /// RenderedDefaults::id; 0 before the first answer.
    defaults: u64,
    status: u16,
    headers: Vec<u8>,
    body_len: usize,
    second: u64,
    head: Vec<u8>,
    keep_alive: bool,
    bodiless: bool,
}

impl HeadCache {
    /// [write_whole], from the last head when it is this answer's.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn write(
        &mut self,
        out: &mut Vec<u8>,
        status: u16,
        headers: &[u8],
        body: &[u8],
        defaults: &RenderedDefaults,
        second: u64,
        date: &[u8],
    ) -> Result<bool, &'static str> {
        if self.defaults == defaults.id
            && self.status == status
            && self.body_len == body.len()
            && self.second == second
            && self.headers == headers
        {
            out.clear();
            out.extend_from_slice(&self.head);
            if !self.bodiless {
                out.extend_from_slice(body);
            }
            return Ok(self.keep_alive);
        }
        let keep_alive = write_whole(out, status, headers, body, defaults, date)?;
        let bodiless = (100..200).contains(&status) || status == 204 || status == 304;
        let head_len = out.len() - if bodiless { 0 } else { body.len() };
        self.defaults = defaults.id;
        self.status = status;
        self.body_len = body.len();
        self.second = second;
        self.headers.clear();
        self.headers.extend_from_slice(headers);
        self.head.clear();
        self.head.extend_from_slice(&out[..head_len]);
        self.keep_alive = keep_alive;
        self.bodiless = bodiless;
        Ok(keep_alive)
    }
}

/// The `Date` header's value for now, formatted once a second per thread
/// (an HTTP date is always 29 bytes).
fn http_date() -> [u8; 29] {
    http_now().1
}

/// The current second, and [http_date] for it.
fn http_now() -> (u64, [u8; 29]) {
    let now = std::time::SystemTime::now();
    let second = now
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0);
    DATE.with(|cell| {
        let (cached_second, cached) = cell.get();
        if cached_second == second && cached[0] != 0 {
            return (second, cached);
        }
        let mut bytes = [0u8; 29];
        let text = httpdate::fmt_http_date(now);
        let len = text.len().min(29);
        bytes[..len].copy_from_slice(&text.as_bytes()[..len]);
        cell.set((second, bytes));
        (second, bytes)
    })
}

/// Writes [response] as HTTP/1.1 and says whether the connection stays open.
///
/// Framing as hyper does it: no body for 1xx, 204 and 304; a length the
/// response gives is kept and the body sent as it comes; otherwise a body of
/// known size gets a `Content-Length` and one of unknown size is chunked. A
/// `Date` is added when the response has none. `Connection: close` ends the
/// connection after this response.
pub(crate) async fn write_response<W: AsyncWrite + Unpin>(
    stream: &mut W,
    out: &mut Vec<u8>,
    response: Response<Body>,
) -> std::io::Result<bool> {
    let (parts, mut body) = response.into_parts();
    let status = parts.status;
    let headers = &parts.headers;
    let close = headers
        .get_all(header::CONNECTION)
        .iter()
        .any(|value| value.as_bytes().eq_ignore_ascii_case(b"close"));
    let bodiless = status.is_informational()
        || status == StatusCode::NO_CONTENT
        || status == StatusCode::NOT_MODIFIED;
    out.clear();
    out.extend_from_slice(b"HTTP/1.1 ");
    out.extend_from_slice(status.as_str().as_bytes());
    out.push(b' ');
    out.extend_from_slice(status.canonical_reason().unwrap_or("").as_bytes());
    out.extend_from_slice(b"\r\n");
    for (name, value) in headers.iter() {
        if name == header::TRANSFER_ENCODING {
            // Framing is decided below, never taken from a handler.
            continue;
        }
        if bodiless && status == StatusCode::NO_CONTENT && name == header::CONTENT_LENGTH {
            continue;
        }
        out.extend_from_slice(name.as_str().as_bytes());
        out.extend_from_slice(b": ");
        out.extend_from_slice(value.as_bytes());
        out.extend_from_slice(b"\r\n");
    }
    if !headers.contains_key(header::DATE) {
        out.extend_from_slice(b"date: ");
        out.extend_from_slice(&http_date());
        out.extend_from_slice(b"\r\n");
    }
    let given_length = headers.contains_key(header::CONTENT_LENGTH);
    let exact = http_body::Body::size_hint(&body).exact();
    let chunked = !bodiless && !given_length && exact.is_none();
    if !bodiless && !given_length {
        if let Some(length) = exact {
            out.extend_from_slice(b"content-length: ");
            out.extend_from_slice(length.to_string().as_bytes());
            out.extend_from_slice(b"\r\n");
        } else {
            out.extend_from_slice(b"transfer-encoding: chunked\r\n");
        }
    }
    out.extend_from_slice(b"\r\n");
    if bodiless {
        stream.write_all(out).await?;
        return Ok(!close);
    }
    // The head and the first piece of the body in one write, which for a
    // body already in memory is the whole response.
    let mut first = true;
    loop {
        let frame = match body.frame().await {
            Some(Ok(frame)) => frame,
            Some(Err(_)) => return Ok(false),
            None => break,
        };
        let Ok(data) = frame.into_data() else { continue };
        if data.is_empty() {
            continue;
        }
        if !first {
            out.clear();
        }
        if chunked {
            out.extend_from_slice(format!("{:x}\r\n", data.len()).as_bytes());
            out.extend_from_slice(&data);
            out.extend_from_slice(b"\r\n");
        } else {
            out.extend_from_slice(&data);
        }
        stream.write_all(out).await?;
        first = false;
    }
    if first {
        if chunked {
            out.extend_from_slice(b"0\r\n\r\n");
        }
        stream.write_all(out).await?;
    } else if chunked {
        stream.write_all(b"0\r\n\r\n").await?;
    }
    Ok(!close)
}

/// A field name HTTP allows: one or more token characters (RFC 9110 5.6.2).
#[cfg(test)]
fn is_token(name: &[u8]) -> bool {
    !name.is_empty()
        && name.iter().all(|&b| {
            b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b)
        })
}

/// Each byte's lowercase form where a field name may hold it (a token
/// character, RFC 9110 5.6.2), and 0 where it may not: the check and the
/// lowercasing of a name in one lookup a byte.
static TOKEN_LOWER: [u8; 256] = {
    let mut table = [0u8; 256];
    let mut index = 0;
    while index < 256 {
        let byte = index as u8;
        if byte.is_ascii_alphanumeric()
            || matches!(byte, b'!' | b'#' | b'$' | b'%' | b'&' | b'\'' | b'*' | b'+' | b'-' | b'.' | b'^' | b'_' | b'`' | b'|' | b'~')
        {
            table[index] = byte.to_ascii_lowercase();
        }
        index += 1;
    }
    table
};

/// A field value HTTP allows: no control characters but tab, no DEL
/// (RFC 9110 5.5) -- what `HeaderValue::from_bytes` accepts.
fn is_field_value(value: &[u8]) -> bool {
    value.iter().all(|&b| b == b'\t' || (b >= 0x20 && b != 0x7f))
}

/// Writes a whole answer Dart gave -- status, NUL-separated fields, body --
/// as an HTTP/1.1 response into [out], with the server's default fields the
/// answer did not set, a `Date`, and its length; true when the connection
/// stays open. The checks and framing are the ones the hyper path applies
/// to the same answer: a status or field HTTP does not allow is refused
/// (and answered 500 by the caller), names are written in lowercase, no body
/// goes with 1xx, 204 or 304, and a `Content-Length` the answer gave is kept.
pub(crate) fn write_whole(
    out: &mut Vec<u8>,
    status: u16,
    headers: &[u8],
    body: &[u8],
    defaults: &RenderedDefaults,
    date: &[u8],
) -> Result<bool, &'static str> {
    let Ok(status) = StatusCode::from_u16(status) else {
        return Err("has a status that is not an HTTP status");
    };
    let bodiless = status.is_informational()
        || status == StatusCode::NO_CONTENT
        || status == StatusCode::NOT_MODIFIED;
    out.clear();
    out.extend_from_slice(b"HTTP/1.1 ");
    out.extend_from_slice(status.as_str().as_bytes());
    out.push(b' ');
    out.extend_from_slice(status.canonical_reason().unwrap_or("").as_bytes());
    out.extend_from_slice(b"\r\n");
    // Which of the server's default fields this answer sets itself.
    let mut overridden: u64 = 0;
    let mut has_date = false;
    let mut has_length = false;
    let mut close = false;
    let mut fields = headers.split(|&b| b == 0);
    while let Some(name) = fields.next() {
        let value = fields.next().unwrap_or_default();
        if name.is_empty() {
            continue;
        }
        if !name.iter().all(|&b| TOKEN_LOWER[b as usize] != 0) {
            return Err("has a header name HTTP does not allow");
        }
        if !is_field_value(value) {
            return Err("has a header value HTTP does not allow");
        }
        if name.eq_ignore_ascii_case(b"transfer-encoding") {
            continue;
        }
        if name.eq_ignore_ascii_case(b"content-length") {
            if status == StatusCode::NO_CONTENT {
                continue;
            }
            has_length = true;
        } else if name.eq_ignore_ascii_case(b"date") {
            has_date = true;
        } else if name.eq_ignore_ascii_case(b"connection") && value.eq_ignore_ascii_case(b"close") {
            close = true;
        }
        overridden |= defaults.matching(name);
        out.extend(name.iter().map(|&b| TOKEN_LOWER[b as usize]));
        out.extend_from_slice(b": ");
        out.extend_from_slice(value);
        out.extend_from_slice(b"\r\n");
    }
    defaults.write_except(out, overridden, headers);
    if !has_date {
        out.extend_from_slice(b"date: ");
        out.extend_from_slice(date);
        out.extend_from_slice(b"\r\n");
    }
    if !bodiless && !has_length {
        out.extend_from_slice(b"content-length: ");
        write_decimal(out, body.len());
        out.extend_from_slice(b"\r\n");
    }
    out.extend_from_slice(b"\r\n");
    if !bodiless {
        out.extend_from_slice(body);
    }
    Ok(!close)
}

/// A connection's stream with the bytes this module already read put back
/// in front, for hyper.
pub(crate) struct Rewind<S> {
    prefix: Bytes,
    inner: S,
}

impl<S: AsyncRead + Unpin> AsyncRead for Rewind<S> {
    fn poll_read(mut self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &mut ReadBuf<'_>) -> Poll<std::io::Result<()>> {
        if !self.prefix.is_empty() {
            let take = self.prefix.len().min(buf.remaining());
            let piece = self.prefix.split_to(take);
            buf.put_slice(&piece);
            return Poll::Ready(Ok(()));
        }
        Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for Rewind<S> {
    fn poll_write(mut self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &[u8]) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.inner).poll_write(cx, buf)
    }
    fn poll_write_vectored(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.inner).poll_write_vectored(cx, bufs)
    }
    fn is_write_vectored(&self) -> bool {
        self.inner.is_write_vectored()
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

/// Serves the rest of the connection with hyper and the server's axum
/// service, as every connection was served before this module.
async fn hand_to_hyper(stream: tokio::net::TcpStream, prefix: Bytes, peer: std::net::SocketAddr, lean: Arc<Lean>) {
    let io = hyper_util::rt::TokioIo::new(Rewind { prefix, inner: stream });
    let app = lean
        .app
        .clone()
        .layer(axum::Extension(axum::extract::ConnectInfo(peer)));
    let service = hyper_util::service::TowerToHyperService::new(app);
    let mut builder = hyper_util::server::conn::auto::Builder::new(hyper_util::rt::TokioExecutor::new());
    super::bound_header_read(&mut builder, lean.header_timeout);
    let connection = builder.serve_connection_with_upgrades(io, service);
    tokio::pin!(connection);
    let mut shutdown = lean.shutdown.clone();
    if stopping(&shutdown) {
        connection.as_mut().graceful_shutdown();
        let _ = connection.await;
        return;
    }
    tokio::select! {
        _ = connection.as_mut() => {}
        _ = shutdown.changed() => {
            connection.as_mut().graceful_shutdown();
            let _ = connection.await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn fast(bytes: &[u8]) -> FastHead {
        match classify(bytes) {
            Classified::Fast(head) => head,
            other => panic!("expected a fast request, got {other:?} for {:?}", String::from_utf8_lossy(bytes)),
        }
    }

    fn fallback(bytes: &[u8]) {
        assert_eq!(classify(bytes), Classified::Fallback, "{:?}", String::from_utf8_lossy(bytes));
    }

    #[test]
    fn a_plain_get_is_served_here_with_its_parts_in_place() {
        let bytes = b"GET /plaintext?x=1 HTTP/1.1\r\nHost: a\r\nAccept-Encoding: gzip\r\n\r\nGET /next";
        let head = fast(bytes);
        assert_eq!(&bytes[head.method.clone()], b"GET");
        assert_eq!(&bytes[head.target.clone()], b"/plaintext?x=1");
        assert_eq!(head.headers.len(), 2);
        assert_eq!(&bytes[head.headers[1].0.clone()], b"Accept-Encoding");
        assert_eq!(&bytes[head.accept_encoding.clone().unwrap()], b"gzip");
        assert_eq!(&bytes[head.head_len..], b"GET /next");
    }

    #[test]
    fn an_incomplete_head_waits_for_more() {
        assert_eq!(classify(b"GET / HTTP/1.1\r\nHost: a\r\n"), Classified::Partial);
        assert_eq!(classify(b"GE"), Classified::Partial);
    }

    #[test]
    fn a_head_past_the_limit_goes_to_hyper() {
        let mut bytes = b"GET / HTTP/1.1\r\nX-Long: ".to_vec();
        bytes.resize(MAX_HEAD_BYTES + 10, b'a');
        fallback(&bytes);
    }

    #[test]
    fn anything_with_a_body_or_a_conflict_goes_to_hyper() {
        // Request smuggling lives in these: hyper decides every one.
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 7\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 0, 0\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 00\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: +0\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nTransfer-Encoding: identity\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\ntransfer-encoding: CHUNKED\r\n\r\n");
        // A space before the colon is not a field name HTTP allows.
        fallback(b"GET / HTTP/1.1\r\nTransfer-Encoding : chunked\r\n\r\n");
        // An obsolete line fold.
        fallback(b"GET / HTTP/1.1\r\nX-A: b\r\n c\r\n\r\n");
    }

    #[test]
    fn an_upgrade_request_is_recognised_for_its_socket_setting() {
        assert!(asks_for_upgrade(b"GET /ws HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"));
        assert!(!asks_for_upgrade(b"GET / HTTP/1.1\r\nHost: a\r\n\r\n"));
        assert!(!asks_for_upgrade(b"POST / HTTP/1.1\r\nContent-Length: 2\r\n\r\nhi"));
    }

    #[test]
    fn content_length_zero_once_is_no_body() {
        let head = fast(b"GET / HTTP/1.1\r\nContent-Length: 0\r\n\r\n");
        assert_eq!(head.headers.len(), 1);
    }

    #[test]
    fn other_methods_versions_and_forms_go_to_hyper() {
        fallback(b"POST / HTTP/1.1\r\n\r\n");
        fallback(b"HEAD / HTTP/1.1\r\n\r\n");
        fallback(b"CONNECT a:443 HTTP/1.1\r\n\r\n");
        fallback(b"GET / HTTP/1.0\r\n\r\n");
        fallback(b"GET http://a/ HTTP/1.1\r\n\r\n");
        fallback(b"OPTIONS * HTTP/1.1\r\n\r\n");
        fallback(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
        fallback(b"get / HTTP/1.1\r\n\r\n");
    }

    #[test]
    fn upgrades_expectations_and_closing_go_to_hyper() {
        fallback(b"GET /ws HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nConnection: close\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nConnection: keep-alive, Upgrade\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nExpect: 100-continue\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nHTTP2-Settings: AAA\r\n\r\n");
        fast(b"GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n");
    }

    #[test]
    fn malformed_heads_go_to_hyper() {
        fallback(b"GET / HTTP/1.1\r\nBad Name: x\r\n\r\n");
        fallback(b"GET / HTTP/1.1\r\nX: a\0b\r\n\r\n");
        fallback(b"GET /a b HTTP/1.1\r\n\r\n");
        fallback(b"GET / HTTP/9.9\r\n\r\n");
        let mut many = b"GET / HTTP/1.1\r\n".to_vec();
        for i in 0..=MAX_HEADERS {
            many.extend_from_slice(format!("X-{i}: v\r\n").as_bytes());
        }
        many.extend_from_slice(b"\r\n");
        fallback(&many);
    }

    fn written(response: Response<Body>) -> (String, bool) {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        runtime.block_on(async {
            let mut out = Vec::new();
            let mut sink = Vec::new();
            let keep = write_response(&mut sink, &mut out, response).await.unwrap();
            (String::from_utf8(sink).unwrap(), keep)
        })
    }

    #[test]
    fn a_body_in_memory_gets_its_length_and_a_date() {
        let mut response = Response::new(Body::from("Hello, World!"));
        response.headers_mut().insert("content-type", HeaderValue::from_static("text/plain"));
        let (text, keep) = written(response);
        assert!(keep);
        assert!(text.starts_with("HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ndate: "), "{text}");
        assert!(text.ends_with("\r\ncontent-length: 13\r\n\r\nHello, World!"), "{text}");
    }

    #[test]
    fn a_stream_of_unknown_length_is_chunked() {
        let chunks = futures_util::stream::iter(vec![
            Ok::<_, std::io::Error>(Bytes::from_static(b"ab")),
            Ok(Bytes::from_static(b"cde")),
        ]);
        let (text, _) = written(Response::new(Body::from_stream(chunks)));
        assert!(text.contains("transfer-encoding: chunked\r\n\r\n2\r\nab\r\n3\r\ncde\r\n0\r\n\r\n"), "{text}");
    }

    #[test]
    fn a_length_the_handler_gave_is_kept_and_the_body_sent_as_is() {
        let chunks = futures_util::stream::iter(vec![Ok::<_, std::io::Error>(Bytes::from_static(b"abc"))]);
        let mut response = Response::new(Body::from_stream(chunks));
        response.headers_mut().insert("content-length", HeaderValue::from_static("3"));
        let (text, _) = written(response);
        assert!(text.ends_with("content-length: 3\r\ndate: ") == false);
        assert!(text.ends_with("\r\n\r\nabc"), "{text}");
        assert!(!text.contains("chunked"));
        assert_eq!(text.matches("content-length").count(), 1);
    }

    #[test]
    fn no_content_and_not_modified_carry_no_body() {
        let mut response = Response::new(Body::from("ignored"));
        *response.status_mut() = StatusCode::NO_CONTENT;
        let (text, _) = written(response);
        assert!(text.starts_with("HTTP/1.1 204 No Content\r\n"));
        assert!(!text.contains("content-length") && text.ends_with("\r\n\r\n"), "{text}");
        let mut response = Response::new(Body::empty());
        *response.status_mut() = StatusCode::NOT_MODIFIED;
        let (text, _) = written(response);
        assert!(text.ends_with("\r\n\r\n") && !text.contains("content-length"), "{text}");
    }

    #[test]
    fn a_closing_response_closes_and_a_handler_cannot_set_framing() {
        let (text, keep) = written(closing_response(StatusCode::GATEWAY_TIMEOUT));
        assert!(!keep);
        assert!(text.starts_with("HTTP/1.1 504 Gateway Timeout\r\n"), "{text}");
        let mut response = Response::new(Body::from("x"));
        response.headers_mut().insert("transfer-encoding", HeaderValue::from_static("chunked"));
        let (text, _) = written(response);
        assert!(!text.contains("transfer-encoding"), "{text}");
        assert!(text.ends_with("content-length: 1\r\n\r\nx"), "{text}");
    }

    fn answer(status: u16, headers: &[u8], body: &[u8]) -> FfiRespOwned {
        FfiRespOwned { status, headers: headers.to_vec(), body: body.to_vec(), is_stream: 0 }
    }

    fn whole(answer: &FfiRespOwned, defaults: Option<&axum::http::HeaderMap>) -> Result<(String, bool), &'static str> {
        let mut out = Vec::new();
        write_whole(&mut out, answer.status, &answer.headers, &answer.body, &RenderedDefaults::new(defaults), b"Tue, 18 Nov 2026 05:00:00 GMT")
            .map(|keep| (String::from_utf8(out).unwrap(), keep))
    }

    #[test]
    fn a_whole_answer_is_written_as_the_hyper_path_writes_it() {
        let mut defaults = axum::http::HeaderMap::new();
        defaults.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
        defaults.insert("x-frame-options", HeaderValue::from_static("SAMEORIGIN"));
        let (text, keep) = whole(
            &answer(200, b"Content-Type\0text/plain\0x-frame-options\0DENY\0set-cookie\0a=1\0set-cookie\0b=2\0", b"Hello"),
            Some(&defaults),
        )
        .unwrap();
        assert!(keep);
        assert_eq!(
            text,
            "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\nx-frame-options: DENY\r\nset-cookie: a=1\r\n\
             set-cookie: b=2\r\nx-content-type-options: nosniff\r\ndate: Tue, 18 Nov 2026 05:00:00 GMT\r\n\
             content-length: 5\r\n\r\nHello"
        );
    }

    #[test]
    fn what_hyper_refuses_is_refused() {
        assert!(whole(&answer(42, b"", b""), None).is_err());
        assert!(whole(&answer(1000, b"", b""), None).is_err());
        assert!(whole(&answer(200, b"bad name\0v\0", b""), None).is_err());
        assert!(whole(&answer(200, b"x-a\0line\r\nsplit\0", b""), None).is_err());
        assert!(whole(&answer(200, b"x-a\0nul\x01\0", b""), None).is_err());
        assert!(whole(&answer(200, b"x-a\0del\x7f\0", b""), None).is_err());
        assert!(whole(&answer(200, b"x-a\0tab\there \xe2\x9c\x93\0", b""), None).is_ok());
    }

    #[test]
    fn framing_of_a_whole_answer() {
        let (text, _) = whole(&answer(204, b"content-length\x000\0", b"x"), None).unwrap();
        assert!(!text.contains("content-length") && text.ends_with("\r\n\r\n"), "{text}");
        let (text, _) = whole(&answer(304, b"etag\0\"a\"\0", b""), None).unwrap();
        assert!(!text.contains("content-length") && text.ends_with("\r\n\r\n"), "{text}");
        let (text, _) = whole(&answer(200, b"content-length\x003\0transfer-encoding\0chunked\0", b"abc"), None).unwrap();
        assert_eq!(text.matches("content-length").count(), 1);
        assert!(!text.contains("transfer-encoding") && text.ends_with("\r\n\r\nabc"), "{text}");
        let (_, keep) = whole(&answer(200, b"connection\0close\0", b""), None).unwrap();
        assert!(!keep);
        let (text, _) = whole(&answer(200, b"date\0yesterday\0", b""), None).unwrap();
        assert_eq!(text.matches("date: ").count(), 1);
    }

    fn cached(
        cache: &mut HeadCache,
        status: u16,
        headers: &[u8],
        body: &[u8],
        defaults: &RenderedDefaults,
        second: u64,
    ) -> (String, bool) {
        let date: &[u8; 29] = if second % 2 == 0 { b"Tue, 18 Nov 2026 05:00:00 GMT" } else { b"Tue, 18 Nov 2026 05:00:01 GMT" };
        let mut out = Vec::new();
        let keep = cache.write(&mut out, status, headers, body, defaults, second, date).unwrap();
        (String::from_utf8(out).unwrap(), keep)
    }

    #[test]
    fn a_cached_head_is_the_head_write_whole_writes() {
        let mut map = axum::http::HeaderMap::new();
        map.insert("x-frame-options", HeaderValue::from_static("SAMEORIGIN"));
        let defaults = RenderedDefaults::new(Some(&map));
        let other_defaults = RenderedDefaults::new(None);
        let mut cache = HeadCache::default();
        let plain = b"content-type\0text/plain\0";
        let fresh = |status: u16, headers: &[u8], body: &[u8], defaults: &RenderedDefaults, second: u64| {
            let date: &[u8; 29] = if second % 2 == 0 { b"Tue, 18 Nov 2026 05:00:00 GMT" } else { b"Tue, 18 Nov 2026 05:00:01 GMT" };
            let mut out = Vec::new();
            let keep = write_whole(&mut out, status, headers, body, defaults, date).unwrap();
            (String::from_utf8(out).unwrap(), keep)
        };
        // The same answer twice: the second from the cache, byte for byte.
        let first = cached(&mut cache, 200, plain, b"hello", &defaults, 0);
        assert_eq!(first, fresh(200, plain, b"hello", &defaults, 0));
        assert_eq!(cached(&mut cache, 200, plain, b"world", &defaults, 0), fresh(200, plain, b"world", &defaults, 0));
        // Anything the head depends on, changed: never the old head.
        assert_eq!(cached(&mut cache, 201, plain, b"world", &defaults, 0), fresh(201, plain, b"world", &defaults, 0));
        assert_eq!(cached(&mut cache, 201, b"content-type\0text/html\0", b"world", &defaults, 0), fresh(201, b"content-type\0text/html\0", b"world", &defaults, 0));
        assert_eq!(cached(&mut cache, 201, plain, b"a longer body", &defaults, 0), fresh(201, plain, b"a longer body", &defaults, 0));
        assert_eq!(cached(&mut cache, 201, plain, b"a longer body", &other_defaults, 0), fresh(201, plain, b"a longer body", &other_defaults, 0));
        assert_eq!(cached(&mut cache, 201, plain, b"a longer body", &other_defaults, 1), fresh(201, plain, b"a longer body", &other_defaults, 1));
        // No body for a 304, and Connection: close still closes.
        assert_eq!(cached(&mut cache, 304, plain, b"", &defaults, 1), fresh(304, plain, b"", &defaults, 1));
        let closing = b"connection\0close\0";
        assert!(!cached(&mut cache, 200, closing, b"x", &defaults, 1).1);
        assert!(!cached(&mut cache, 200, closing, b"x", &defaults, 1).1);
    }

    #[test]
    fn an_answer_that_cannot_be_sent_is_refused_from_the_cache_too() {
        let defaults = RenderedDefaults::new(None);
        let mut cache = HeadCache::default();
        let bad = b"x-bad\0line\r\nsplit\0";
        let mut out = Vec::new();
        assert!(cache.write(&mut out, 200, bad, b"", &defaults, 0, b"Tue, 18 Nov 2026 05:00:00 GMT").is_err());
        assert!(cache.write(&mut out, 200, bad, b"", &defaults, 0, b"Tue, 18 Nov 2026 05:00:00 GMT").is_err());
    }

    #[test]
    fn the_name_table_agrees_with_is_token_on_every_byte() {
        for byte in 0..=255u8 {
            let in_table = TOKEN_LOWER[byte as usize] != 0;
            assert_eq!(in_table, is_token(&[byte]), "byte {byte}");
            if in_table {
                assert_eq!(TOKEN_LOWER[byte as usize], byte.to_ascii_lowercase(), "byte {byte}");
            }
        }
    }

    #[test]
    fn more_than_sixty_four_defaults_suppress_only_the_ones_set() {
        let mut defaults = axum::http::HeaderMap::new();
        for index in 0..70 {
            defaults.insert(
                axum::http::HeaderName::from_bytes(format!("x-default-{index}").as_bytes()).unwrap(),
                HeaderValue::from_static("d"),
            );
        }
        // Setting the first and the 66th leaves every other default in place.
        let (text, _) = whole(&answer(200, b"x-default-0\0mine\0x-default-65\0mine\0", b""), Some(&defaults)).unwrap();
        for index in 0..70 {
            let line = format!("x-default-{index}: ");
            let count = text.matches(&format!("\r\n{line}")).count();
            assert_eq!(count, 1, "{line} once in {text}");
            let expected = if index == 0 || index == 65 { "mine" } else { "d" };
            assert!(text.contains(&format!("\r\n{line}{expected}\r\n")), "{line}{expected} in {text}");
        }
    }

    #[test]
    fn many_fields_still_suppress_their_defaults() {
        let mut defaults = axum::http::HeaderMap::new();
        defaults.insert("x-last", HeaderValue::from_static("default"));
        let mut fields = Vec::new();
        for i in 0..40 {
            fields.extend_from_slice(format!("x-{i}\0v\0").as_bytes());
        }
        fields.extend_from_slice(b"x-last\0mine\0");
        let (text, _) = whole(&answer(200, &fields, b""), Some(&defaults)).unwrap();
        assert!(text.contains("x-last: mine") && !text.contains("x-last: default"), "{text}");
    }

    #[test]
    fn rewind_replays_what_was_read_first() {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        runtime.block_on(async {
            use tokio::io::AsyncReadExt as _;
            let inner: &[u8] = b" world";
            let mut rewind = Rewind { prefix: Bytes::from_static(b"hello"), inner };
            let mut all = String::new();
            rewind.read_to_string(&mut all).await.unwrap();
            assert_eq!(all, "hello world");
        });
    }

    proptest! {
        #![proptest_config(ProptestConfig {
            cases: std::env::var("PROPTEST_CASES").ok().and_then(|v| v.parse().ok()).unwrap_or(4096),
            ..ProptestConfig::default()
        })]

        /// Any bytes: no panic, and a request served here is one that has
        /// no other reading.
        #[test]
        fn any_bytes_are_classified_safely(bytes in proptest::collection::vec(any::<u8>(), 0..2048)) {
            if let Classified::Fast(head) = classify(&bytes) {
                prop_assert!(head.head_len <= bytes.len());
                prop_assert_eq!(&bytes[head.method.clone()], b"GET");
                prop_assert!(bytes[head.target.clone()].starts_with(b"/"));
                prop_assert!(bytes[..head.head_len].ends_with(b"\n"));
                let mut content_length = 0;
                for (name, value) in &head.headers {
                    prop_assert!(name.end <= head.head_len && value.end <= head.head_len);
                    let name = &bytes[name.clone()];
                    prop_assert!(!name.eq_ignore_ascii_case(b"transfer-encoding"));
                    prop_assert!(!name.eq_ignore_ascii_case(b"upgrade"));
                    prop_assert!(!name.eq_ignore_ascii_case(b"expect"));
                    if name.eq_ignore_ascii_case(b"content-length") {
                        content_length += 1;
                        prop_assert_eq!(&bytes[value.clone()], b"0");
                    }
                }
                prop_assert!(content_length <= 1);
            }
        }

        /// Well-formed GETs with arbitrary fields are served here, and the
        /// next request starts exactly where the head ends.
        #[test]
        fn well_formed_gets_are_served_and_pipelining_splits_exactly(
            path in "/[a-zA-Z0-9/._~-]{0,40}",
            fields in proptest::collection::vec(("[A-Za-z][A-Za-z0-9-]{0,20}", "[ -~]{0,40}"), 0..20),
            next in proptest::collection::vec(any::<u8>(), 0..64),
        ) {
            let mut bytes = format!("GET {path} HTTP/1.1\r\n").into_bytes();
            let mut expect_fast = true;
            for (name, value) in &fields {
                let lower = name.to_ascii_lowercase();
                if ["transfer-encoding", "upgrade", "expect", "http2-settings", "connection", "content-length"].contains(&lower.as_str()) {
                    expect_fast = false;
                }
                bytes.extend_from_slice(format!("{name}: {}\r\n", value.trim()).as_bytes());
            }
            bytes.extend_from_slice(b"\r\n");
            let head_len = bytes.len();
            bytes.extend_from_slice(&next);
            match classify(&bytes) {
                Classified::Fast(head) => {
                    prop_assert!(expect_fast);
                    prop_assert_eq!(head.head_len, head_len);
                    prop_assert_eq!(&bytes[head.target.clone()], path.as_bytes());
                    prop_assert_eq!(head.headers.len(), fields.len());
                }
                Classified::Fallback => prop_assert!(!expect_fast),
                Classified::Partial => prop_assert!(false, "a complete head read as partial"),
            }
        }

        /// A head cut anywhere before its end is never served.
        /// Whatever Dart answers, the written head is well formed or refused:
        /// no field can add a line of its own.
        #[test]
        fn no_answer_can_split_the_response(
            status in 0u16..1100,
            fields in proptest::collection::vec((proptest::collection::vec(any::<u8>(), 0..12), proptest::collection::vec(any::<u8>(), 0..24)), 0..8),
            body in proptest::collection::vec(any::<u8>(), 0..64),
        ) {
            let mut flat = Vec::new();
            for (name, value) in &fields {
                let name: Vec<u8> = name.iter().copied().filter(|&b| b != 0).collect();
                let value: Vec<u8> = value.iter().copied().filter(|&b| b != 0).collect();
                flat.extend_from_slice(&name);
                flat.push(0);
                flat.extend_from_slice(&value);
                flat.push(0);
            }
            let given = answer(status, &flat, &body);
            let mut out = Vec::new();
            if write_whole(&mut out, given.status, &given.headers, &given.body, &RenderedDefaults::new(None), b"d").is_ok() {
                let head_end = out.windows(4).position(|w| w == b"\r\n\r\n").unwrap() + 4;
                let head = &out[..head_end];
                // Every line but the last two is "name: value" with no bare
                // CR or LF inside it.
                let lines: Vec<&[u8]> = head[..head.len() - 4].split(|&b| b == b'\n').collect();
                for line in &lines {
                    prop_assert!(line.ends_with(b"\r") || line.is_empty() || line == lines.last().unwrap());
                    let inner = line.strip_suffix(b"\r").unwrap_or(line);
                    prop_assert!(!inner.contains(&b'\r'));
                }
                prop_assert_eq!(lines.len(), 1 + (head[..head.len() - 4].iter().filter(|&&b| b == b'\n').count()));
            }
        }

        #[test]
        fn a_truncated_head_is_never_served(cut in 0usize..60) {
            let bytes = b"GET /p HTTP/1.1\r\nHost: example\r\nAccept: */*\r\n\r\n";
            let cut = cut.min(bytes.len() - 1);
            prop_assert_eq!(classify(&bytes[..cut]), Classified::Partial);
        }
    }
}

#[cfg(test)]
mod cost {
    use super::*;

    /// `cargo test --release cost -- --ignored`, under `perf stat`: the
    /// instructions one typical whole answer costs to serialise.
    #[test]
    #[ignore]
    fn write_whole_a_million_times() {
        let mut defaults = axum::http::HeaderMap::new();
        defaults.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
        defaults.insert("x-frame-options", HeaderValue::from_static("SAMEORIGIN"));
        defaults.insert("referrer-policy", HeaderValue::from_static("strict-origin-when-cross-origin"));
        let rendered = RenderedDefaults::new(Some(&defaults));
        let headers = b"content-type\0text/plain; charset=utf-8\0";
        let mut out = Vec::with_capacity(4096);
        let mut total = 0usize;
        for _ in 0..1_000_000 {
            let date = http_date();
            let _ = std::hint::black_box(write_whole(&mut out, 200, std::hint::black_box(headers), b"Hello, World!", &rendered, &date));
            total += out.len();
        }
        assert!(total > 0);
    }

    /// The same, from the head cache, as aw_complete writes it.
    #[test]
    #[ignore]
    fn cached_whole_answer_a_million_times() {
        let mut defaults = axum::http::HeaderMap::new();
        defaults.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
        defaults.insert("x-frame-options", HeaderValue::from_static("SAMEORIGIN"));
        defaults.insert("referrer-policy", HeaderValue::from_static("strict-origin-when-cross-origin"));
        let rendered = RenderedDefaults::new(Some(&defaults));
        let headers = b"content-type\0text/plain; charset=utf-8\0";
        let mut out = Vec::with_capacity(4096);
        let mut total = 0usize;
        for _ in 0..1_000_000 {
            let (second, date) = http_now();
            let _ = std::hint::black_box(HEADS.with(|cache| {
                cache.borrow_mut().write(&mut out, 200, std::hint::black_box(headers), b"Hello, World!", &rendered, second, &date)
            }));
            total += out.len();
        }
        assert!(total > 0);
    }
}

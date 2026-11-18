#ifndef DARTVEL_SHELF_H
#define DARTVEL_SHELF_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * The shape of the calls between this library and Dart.
 *
 * Raised whenever a callback's signature changes. A Dart side built for one
 * shape calling a library built for another does not fail cleanly: a
 * callback invoked with fewer arguments than Dart expects reads whatever is
 * in the missing argument's register, and a stale committed library would do
 * exactly that. Dart checks this before registering anything.
 */
#define AW_ABI_VERSION 2

#define AW_FLAG_H2C 1

/**
 * Listen with SO_REUSEPORT, so servers in several isolates that all ask for
 * it share one address and the kernel spreads connections over them, as
 * dart:io does for `HttpServer.bind(shared: true)`.
 */
#define AW_FLAG_SHARED 2

/**
 * The isolate drives the server's runtime itself, on its own thread, while
 * it has requests to take (aw_drive), and a helper thread drives it while
 * the isolate is idle (aw_park). A request then reaches Dart, and its answer
 * reaches the socket, with no thread hand-off at all under load.
 */
#define AW_FLAG_DRIVEN 4

/**
 * The address a request's body buffer carries, with length 0, when the
 * request has no body at all: Dart then makes no body stream for it. Never
 * read from. Not 1: that is the address an empty byte buffer carries (the
 * alignment of a byte), which is what a streamed body passes. No real
 * buffer lies below 4096. An older Dart reads it as an empty body.
 */
#define AW_BODY_NONE 2

/**
 * A chunk of the request body [req_id] is here.
 */
#define AW_BODY_CHUNK 0

/**
 * The whole body arrived, within its limit.
 */
#define AW_BODY_END 1

/**
 * The client stopped sending, or sent something that is not a body. The
 * stream ends and the request is answered as it is for a request with no
 * body, which is what it used to be read as.
 */
#define AW_BODY_UNREADABLE 2

/**
 * The body passed its limit, or the request ran out of time with it
 * unfinished. The stream fails and the request is answered 413 or 408 and
 * the connection closed, whatever the handler answered.
 */
#define AW_BODY_REFUSED 3

/**
 * The ask was recorded, or answered. A chunk may still be on its way.
 */
#define AW_BODY_PULL_TAKEN 0

/**
 * [req_id] is not a request with a body being read: one that was never
 * streamed, one already finished and released, or one the library was never
 * given a callback for.
 */
#define AW_BODY_PULL_UNKNOWN 1

/**
 * Brotli, `Content-Encoding: br`.
 */
#define AW_CODEC_BROTLI 1

/**
 * Zstandard, `Content-Encoding: zstd`.
 */
#define AW_CODEC_ZSTD 2

/**
 * The encoding did not fit in the output buffer.
 */
#define AW_CODEC_TOO_LARGE -2

/**
 * An unknown codec, a level out of range, or a null buffer.
 */
#define AW_CODEC_BAD_ARGUMENT -3

/**
 * The input is not a valid stream of the codec, or decodes to a different
 * length than the caller said.
 */
#define AW_CODEC_CORRUPT -4

/**
 * Wakes a server's isolate to take the requests queued for it.
 */
typedef void (*DartRequestWakeup)(void);

typedef struct FfiStr {
  const uint8_t *ptr;
  size_t len;
} FfiStr;

typedef struct FfiBuf {
  const uint8_t *ptr;
  size_t len;
} FfiBuf;

/**
 * One request as `aw_take_requests` hands it over: the arguments the
 * request handler takes, in one struct. The bytes stay where they are,
 * retained as they are for the handler, until Dart acknowledges or answers.
 */
typedef struct FfiRequest {
  uint64_t id;
  struct FfiStr method;
  struct FfiStr target;
  const uint8_t *hdrs;
  size_t hdrs_len;
  struct FfiBuf body;
  struct FfiStr peer;
} FfiRequest;

typedef void (*DartReqHandler)(uint64_t,
                               struct FfiStr,
                               struct FfiStr,
                               const uint8_t*,
                               size_t,
                               struct FfiBuf,
                               struct FfiStr);

typedef void (*DartStreamCancelHandler)(uint64_t);

typedef void (*DartStreamAckHandler)(uint64_t);

typedef void (*DartWsWakeupHandler)(uint64_t);

/**
 * A request body chunk, or the event that ended it.
 *
 * The direction is Rust to Dart, one chunk at a time and only when Dart has
 * asked for the next one, so a handler reading a body decides how far ahead
 * of it a client may get.
 */
typedef void (*DartBodyChunkHandler)(uint64_t, struct FfiBuf, uint8_t);

typedef struct FfiResp {
  uint16_t status;
  struct FfiBuf body;
  const uint8_t *hdrs;
  size_t hdrs_len;
  uint8_t is_stream;
} FfiResp;

typedef struct FfiWsFrame {
  int32_t kind;
  struct FfiBuf data;
} FfiWsFrame;

typedef void *DartHandle;

/**
 * The wakeup for the next server this thread starts. A server started with
 * one queues its requests for `aw_take_requests` rather than calling the
 * request handler with each.
 */
void aw_register_request_wakeup_handler(DartRequestWakeup cb);

/**
 * Moves up to [max] of [server_id]'s queued requests into [out] and returns
 * how many. Fewer than [max] means the queue is empty, and the next request
 * wakes the isolate again.
 */
size_t aw_take_requests(uint64_t server_id, struct FfiRequest *out, size_t max);

uint32_t aw_abi_version(void);

const char *aw_source_revision(void);

/**
 * The default headers for the next server this thread starts, as NUL-
 * separated name and value pairs. 1 when a name or value is not one HTTP
 * allows, and nothing is kept.
 */
int32_t aw_configure_default_headers(const uint8_t *hdrs, size_t len);

void aw_register_handler(DartReqHandler cb);

void aw_register_cancel_handler(DartStreamCancelHandler cb);

void aw_register_stream_ack_handler(DartStreamAckHandler cb);

void aw_register_ws_wakeup_handler(DartWsWakeupHandler cb);

int32_t aw_configure_cors(struct FfiStr config_json);

int32_t aw_tls_rustls_from_pem(struct FfiBuf cert_pem, struct FfiBuf key_pem);

int32_t aw_configure_static(struct FfiStr path);

int32_t aw_configure_spa_root(struct FfiStr path);

int32_t aw_configure_compression(int32_t enabled);

/**
 * The request timeout for the next server this thread starts, in
 * milliseconds. It bounds reading a request's headers, reading its body,
 * and waiting for Dart's answer; past it the connection is answered (408
 * for a body that never arrived, 504 for Dart) or, with headers unfinished,
 * closed. Zero is refused with 1: a request that may take no time at all is
 * a server that answers nothing.
 */
int32_t aw_configure_request_timeout(uint64_t milliseconds);

/**
 * Dart has copied the request [req_id]'s bytes out of native memory, which
 * may now be freed.
 */
void aw_request_received(uint64_t req_id);

/**
 * Registers the callback request-body chunks and the ends of bodies are
 * delivered to, and pulls for them are answered through.
 *
 * On this thread, and taken by `aw_start` into a per-server slot the way the
 * request and cancel handlers are: two isolates starting a server at the same
 * moment interleave as register A, register B, start A, start B, and A would
 * otherwise hand its requests to B's isolate.
 */
void aw_register_body_chunk_handler(DartBodyChunkHandler cb);

/**
 * Dart asks for the next chunk of request [req_id]'s body.
 *
 * The chunk does not arrive here: the reader sends it, from its own task, to
 * the registered callback. That is the backpressure — nothing is read from
 * the socket until Dart asks, so a handler that stops reading stops the
 * client, and at most one chunk is ever in flight or waiting.
 *
 * Returns [AW_BODY_PULL_TAKEN] for an ask that was recorded and
 * [AW_BODY_PULL_UNKNOWN] for a request with no body to pull, which is how a
 * caller learns it is not holding a body rather than being told it is empty.
 */
int32_t aw_body_next_chunk(uint64_t req_id);

/**
 * The largest request body the next server this thread starts reads, in
 * bytes, for every request no route limit covers. A body declared larger is
 * answered 413 without being read, and one that grows past it while being
 * read is answered 413 there; both close the connection. Zero is refused
 * with 1: a server that reads no body at all is not a limit anybody means.
 *
 * Also forgets any route limits this thread added and never started a
 * server with, so a serve() that failed between the two leaves nothing
 * behind for the next.
 */
int32_t aw_configure_max_body_bytes(uint64_t bytes);

/**
 * Adds a route to the next server this thread starts, after the ones
 * already added: its method (`*` for any), its pattern as the Dart router
 * registered it, and the largest body it reads in bytes, or 0 for the
 * server's limit. A request takes the limit of the first route that matches
 * it, in the order they were added, which is the order the router
 * dispatches in. Returns 2 when the method or pattern is not text.
 */
int32_t aw_configure_route_body_limit(struct FfiStr method, struct FfiStr pattern, uint64_t bytes);

int32_t aw_start(struct FfiStr host, uint16_t port, uint32_t flags);

/**
 * The port [server_id] is listening on, or 0 if it is unknown.
 *
 * Meaningful because a caller may start a server on port 0 and let the OS
 * choose; without this there is no way to learn where it landed.
 */
uint16_t aw_server_port(uint64_t server_id);

int32_t aw_stop(uint64_t server_id);

int32_t aw_complete(uint64_t req_id, struct FfiResp resp);

int32_t aw_stream_send_chunk(uint64_t req_id, struct FfiBuf chunk);

int32_t aw_stream_complete(uint64_t req_id);

/**
 * Creates bounded queues before completing an HTTP upgrade response.
 */
int32_t aw_ws_prepare(uint64_t id, size_t max, struct FfiStr protocol);

/**
 * The native task has ended; remaining received messages are bounded.
 */
int32_t aw_ws_closed(uint64_t id);

/**
 * Heartbeat acknowledgements do not depend on a Dart data-stream listener.
 * 1 while [id]'s reader is partway through a burst -- it has more to parse
 * before it would wait on the socket -- on a thread other than the
 * caller's; 0 otherwise, and for a connection that is gone. A Dart drain
 * that finds the queue empty keeps taking while it is 1. On a server whose
 * isolate drives the runtime itself the reader only runs when that isolate
 * does, so it is 0 there: waiting for it would wait for ever.
 */
int32_t aw_ws_reader_busy(uint64_t id);

/**
 * 1 when a frame is waiting for Dart on [id] (or held from a batch), 0
 * otherwise: a cheap look that takes nothing.
 */
int32_t aw_ws_pending(uint64_t id);

uint64_t aw_ws_pong_count(uint64_t id);

/**
 * Queues one frame without sending it; aw_ws_flush sends what is queued.
 * 0 accepted, 1 backpressure (a wakeup follows when there is room),
 * -1 closed/invalid. Never blocks the Dart thread.
 */
int32_t aw_ws_queue(uint64_t id, int32_t kind, struct FfiBuf data);

/**
 * Sends what is queued. When the socket takes it all at once, it is written
 * from this thread; otherwise the connection's writer task finishes it.
 * 0 everything was written, 1 the writer task has the rest, -1 closed.
 */
int32_t aw_ws_flush(uint64_t id);

/**
 * Queues and sends one frame: aw_ws_queue then aw_ws_flush.
 * 0 accepted, 1 backpressure, -1 closed/invalid. Never blocks the Dart thread.
 */
int32_t aw_ws_send(uint64_t id, int32_t kind, struct FfiBuf data);

/**
 * 0 means pending, -1 closed. Positive kinds own data until aw_ws_free.
 */
struct FfiWsFrame aw_ws_receive(uint64_t id);

void aw_ws_free(struct FfiBuf data);

void aw_ws_dispose(uint64_t id);

/**
 * One turn of [server_id]'s runtime on the calling thread, which must be
 * the isolate that started it: what is ready runs, the sockets are polled
 * without waiting, and what that made ready runs. Requests it read are
 * queued for aw_take_requests.
 *
 * 0 after a turn; 1 when the helper drives (or the server is stopping) and
 * nothing was run; -1 for a server that is not driven.
 */
int32_t aw_drive(uint64_t server_id);

/**
 * Gives [server_id]'s runtime to its helper thread, for an isolate with
 * nothing left to take: the helper waits for the next request and wakes the
 * isolate for it. 0, or -1 for a server that is not driven.
 */
int32_t aw_park(uint64_t server_id);

/**
 * Turns [server_id]'s runtime on the calling thread, which must be the
 * isolate that drives it, until a request is queued or [micros] have passed.
 *
 * For an isolate whose last turn found nothing: the next request on a busy
 * server is usually that close, and waiting for it in the kernel here costs
 * less than parking -- handing the runtime to the helper, which wakes this
 * isolate with a message when it comes. The isolate's event loop is held for
 * at most [micros], which is how late a timer can be while it waits.
 *
 * 0 a request was queued; 2 none came; 1 the helper drives or the server is
 * stopping; -1 a server that is not driven.
 */
int32_t aw_linger(uint64_t server_id, uint32_t micros);

/**
 * Compresses `input_len` bytes at `input` with `codec` at `level` into the
 * `out_cap` bytes at `out`. Returns the length written, or a negative
 * `AW_CODEC_*`.
 *
 * # Safety
 * `input` must be valid for `input_len` bytes and `out` for `out_cap`.
 */
int64_t aw_codec_encode(int32_t codec,
                        int32_t level,
                        const uint8_t *input,
                        size_t input_len,
                        uint8_t *out,
                        size_t out_cap);

/**
 * Decompresses `input_len` bytes at `input`, encoded with `codec`, into
 * exactly the `out_len` bytes at `out`. Returns `out_len`, or a negative
 * `AW_CODEC_*` -- a stream that decodes to any other length is corrupt.
 *
 * # Safety
 * `input` must be valid for `input_len` bytes and `out` for `out_len`.
 */
int64_t aw_codec_decode(int32_t codec,
                        const uint8_t *input,
                        size_t input_len,
                        uint8_t *out,
                        size_t out_len);

/**
 * Whether this process's runtime exports what loading a unit takes.
 */
int32_t aw_units_supported(void);

/**
 * Records that unit `id` is the ELF at `offset` in the file `path` (UTF-8,
 * `path_len` bytes). Returns 0, or 1 for a path that is not a C string.
 *
 * # Safety
 * `path` must be valid for `path_len` bytes.
 */
int32_t aw_units_register(ptrdiff_t id, const uint8_t *path, size_t path_len, uint64_t offset);

/**
 * How many units have been mapped so far.
 */
int32_t aw_units_loaded(void);

/**
 * The VM's deferred-load handler: maps unit `id` from the executable the
 * first time any isolate asks, and completes that isolate's load with it.
 *
 * Another isolate of the same group that asks later is also sent here --
 * the VM keeps whether a prefix is loaded per isolate, and whether a unit
 * is loaded per group -- and the VM refuses to take the same unit twice
 * ("Unit already loaded"). The group already has the code, so that isolate
 * only needs its own pending `loadLibrary()` completed: this calls its
 * `dart:core` `_completeLoads(id, null, false)`, which is what the VM
 * itself calls after taking a unit.
 *
 * Serialized: an isolate asking while another is still taking the unit
 * waits until it has, rather than running code the group does not yet have.
 *
 * # Safety
 * Called by the VM, on the isolate that asked, with that isolate entered
 * and an API scope open.
 */
DartHandle aw_units_load(ptrdiff_t id);

/**
 * Whether unit `id` has been taken by the VM.
 */
int32_t aw_units_completed(ptrdiff_t id);

#endif  /* DARTVEL_SHELF_H */

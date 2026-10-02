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

typedef struct FfiStr {
  const uint8_t *ptr;
  size_t len;
} FfiStr;

typedef struct FfiBuf {
  const uint8_t *ptr;
  size_t len;
} FfiBuf;

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

uint32_t aw_abi_version(void);

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

int32_t aw_start(struct FfiStr host, uint16_t port, uint32_t _flags);

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
 */
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

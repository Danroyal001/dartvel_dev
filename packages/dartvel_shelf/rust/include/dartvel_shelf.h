#ifndef DARTVEL_SHELF_H
#define DARTVEL_SHELF_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define AW_FLAG_H2C 1

/**
 * The request finished; no more events.
 */
#define DV_HTTP_EVENT_DONE 0

/**
 * A 103 Early Hints response. Payload is JSON headers.
 */
#define DV_HTTP_EVENT_EARLY_HINTS 1

/**
 * The final response head. Payload is JSON: status, protocol, headers.
 */
#define DV_HTTP_EVENT_HEAD 2

/**
 * A body chunk. Payload is the raw bytes, not JSON — base64 through a JSON
 * envelope would cost a third of every response body for nothing.
 */
#define DV_HTTP_EVENT_BODY 3

/**
 * The request failed. Payload is JSON: message, protocol, retryable.
 */
#define DV_HTTP_EVENT_ERROR -1

/**
 * The handle is unknown, already drained, or the argument was invalid.
 */
#define DV_HTTP_EVENT_INVALID -2

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
                               struct FfiBuf);

typedef void (*DartStreamCancelHandler)(uint64_t);

typedef struct FfiResp {
  uint16_t status;
  struct FfiBuf body;
  const uint8_t *hdrs;
  size_t hdrs_len;
  uint8_t is_stream;
} FfiResp;

void aw_register_handler(DartReqHandler cb);

void aw_register_cancel_handler(DartStreamCancelHandler cb);

int32_t aw_configure_cors(struct FfiStr config_json);

int32_t aw_tls_rustls_from_pem(struct FfiBuf cert_pem, struct FfiBuf key_pem);

int32_t aw_configure_static(struct FfiStr path);

int32_t aw_configure_spa_root(struct FfiStr path);

int32_t aw_configure_compression(int32_t enabled);

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
 * Starts a request and returns a handle, or 0 if it could not be started.
 *
 * # Safety
 * `request_json` and `body` must be valid for their stated lengths for the
 * duration of this call. Both are copied before returning, so the caller may
 * free them immediately afterwards.
 */
uint64_t dv_http_send(struct FfiStr request_json, struct FfiBuf body);

/**
 * Blocks until the next event for [handle].
 *
 * Returns one of the `DV_HTTP_EVENT_*` codes and writes the payload to `out`.
 * A payload with a non-null pointer must be released with
 * [`dv_http_free_buf`]; `DONE`, `INVALID` and any empty payload write a null
 * pointer and need no release.
 *
 * # Safety
 * `out` must point to a writable `FfiBuf`.
 */
int32_t dv_http_next_event(uint64_t handle, struct FfiBuf *out);

/**
 * Releases a payload returned by [`dv_http_next_event`].
 *
 * # Safety
 * `buf` must be a buffer this library produced and not already freed.
 */
void dv_http_free_buf(struct FfiBuf buf);

/**
 * Asks an in-flight request to stop. Safe to call on an unknown handle.
 */
int32_t dv_http_cancel(uint64_t handle);

#endif  /* DARTVEL_SHELF_H */

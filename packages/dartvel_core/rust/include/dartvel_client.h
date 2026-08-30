#ifndef DARTVEL_CLIENT_H
#define DARTVEL_CLIENT_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

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

#endif  /* DARTVEL_CLIENT_H */

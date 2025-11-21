#ifndef DARTVEL_SHELF_H
#define DARTVEL_SHELF_H

#pragma once

/* Generated with cbindgen:0.29.0 */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct SliceU8 {
  const uint8_t *ptr;
  uintptr_t len;
} SliceU8;

typedef struct RequestEnvelope {
  uint64_t request_id;
  uint32_t route_id;
  uint8_t method;
  uint32_t path_off;
  uint32_t path_len;
  uint32_t hdr_off;
  uint32_t hdr_len;
  uint32_t body_off;
  uint32_t body_len;
  uint64_t body_rx;
  uint64_t deadline_ns;
} RequestEnvelope;

typedef struct ResponseEnvelope {
  uint64_t request_id;
  uint16_t status;
  uint32_t hdr_off;
  uint32_t hdr_len;
  uint64_t body_tx;
  uint64_t content_len;
  uint8_t finalize;
} ResponseEnvelope;

struct SliceU8 dv_last_error(void);

uint64_t dv_server_bootstrap(const uint8_t *cfg_ptr, uintptr_t cfg_len);

uint8_t dv_server_poll_job(uint64_t server, struct RequestEnvelope *out_req);

uint8_t dv_server_submit_response(uint64_t _server, const struct ResponseEnvelope *_resp);

uintptr_t dv_request_metadata_read(uint64_t _h, uint8_t *_dst, uintptr_t _cap);

uintptr_t dv_response_write_chunk(uint64_t h, const uint8_t *src, uintptr_t len);

uint64_t dv_response_open_stream(uint64_t r);

uint8_t dv_response_finalize_stream(uint64_t tx);

uintptr_t dv_response_write_for_request(uint64_t r, const uint8_t *src, uintptr_t len);

uintptr_t dv_ws_send_text(uint64_t _ws, const uint8_t *_src, uintptr_t _len);

uintptr_t dv_ws_send_bin(uint64_t _ws, const uint8_t *_src, uintptr_t _len);

uint8_t dv_ws_close(uint64_t _ws, uint16_t _code, const uint8_t *_reason, uintptr_t _len);

#endif  /* DARTVEL_SHELF_H */

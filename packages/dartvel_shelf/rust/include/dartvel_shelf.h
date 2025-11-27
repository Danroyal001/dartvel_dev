#ifndef DARTVEL_SHELF_H
#define DARTVEL_SHELF_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define AW_FLAG_H2C 1

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

typedef struct FfiResp {
  uint16_t status;
  struct FfiBuf body;
  const uint8_t *hdrs;
  size_t hdrs_len;
} FfiResp;

void aw_register_handler(DartReqHandler cb);

int32_t aw_configure_cors(struct FfiStr config_json);

int32_t aw_tls_rustls_from_pem(struct FfiBuf cert_pem, struct FfiBuf key_pem);

int32_t aw_configure_static(struct FfiStr path);

int32_t aw_configure_compression(int32_t enabled);

int32_t aw_start(struct FfiStr host, uint16_t port, uint32_t flags);

int32_t aw_stop(uint64_t server_id);

int32_t aw_complete(uint64_t req_id, struct FfiResp resp);

#endif  /* DARTVEL_SHELF_H */

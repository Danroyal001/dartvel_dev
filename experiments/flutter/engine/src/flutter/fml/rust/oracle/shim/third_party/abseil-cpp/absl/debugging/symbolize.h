// Not an upstream file: stands in for abseil's absl/debugging/symbolize.h
// when the oracle is built; this checkout does not carry abseil.
//
// flutter/fml/backtrace.cc names each frame with absl::Symbolize. The names a
// C++ binary and a Rust binary give their frames cannot be compared, so the
// oracle checks only the shape of a backtrace (see the backtrace suite in
// fml_dump.cc), and this stand-in names a frame with dladdr's nearest
// dynamic symbol, failing (so that the frame reads "Unknown") where there is
// none, as absl::Symbolize fails where it finds no symbol.

#ifndef ABSL_DEBUGGING_SYMBOLIZE_H_
#define ABSL_DEBUGGING_SYMBOLIZE_H_

#include <dlfcn.h>

#include <cstring>

namespace absl {

inline void InitializeSymbolizer(const char*) {}

inline bool Symbolize(const void* pc, char* out, int out_size) {
  Dl_info info;
  if (dladdr(pc, &info) == 0 || info.dli_sname == nullptr || out_size <= 0) {
    return false;
  }
  std::strncpy(out, info.dli_sname, out_size - 1);
  out[out_size - 1] = '\0';
  return true;
}

}  // namespace absl

#endif  // ABSL_DEBUGGING_SYMBOLIZE_H_

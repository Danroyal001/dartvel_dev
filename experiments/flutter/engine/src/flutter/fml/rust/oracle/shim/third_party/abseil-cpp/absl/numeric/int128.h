// Not an upstream file: stands in for abseil's absl/numeric/int128.h when the
// oracle is built; this checkout does not carry abseil.
//
// flutter/fml/safe_math.cc uses three things from it: the uint128 type, and
// the high and low 64-bit halves. On the compilers the engine supports,
// absl::uint128 is the builtin unsigned __int128 (ABSL_HAVE_INTRINSIC_INT128),
// whose multiplication wraps modulo 2^128 as abseil's does.

#ifndef ABSL_NUMERIC_INT128_H_
#define ABSL_NUMERIC_INT128_H_

#include <cstdint>

namespace absl {

using uint128 = unsigned __int128;

constexpr uint64_t Uint128Low64(uint128 v) {
  return static_cast<uint64_t>(v);
}

constexpr uint64_t Uint128High64(uint128 v) {
  return static_cast<uint64_t>(v >> 64);
}

}  // namespace absl

#endif  // ABSL_NUMERIC_INT128_H_

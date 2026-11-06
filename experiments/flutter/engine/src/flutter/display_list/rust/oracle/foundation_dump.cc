// Not an upstream file: real-C++ oracle for display_list foundation.
#include <bit>
#include <cstdint>
#include <cstdio>
#include <iostream>
#include <string>
#include "flutter/display_list/dl_sampling_options.h"
#include "flutter/display_list/dl_tile_mode.h"
#include "flutter/display_list/dl_types.h"
#include "flutter/display_list/utils/dl_accumulation_rect.h"
using namespace flutter;
static float scalar() {
  uint32_t bits;
  if (!(std::cin >> bits)) std::exit(2);
  return std::bit_cast<float>(bits);
}
static DlRect rect() {
  float l = scalar(); float t = scalar();
  float r = scalar(); float b = scalar();
  return DlRect::MakeLTRB(l, t, r, b);
}
int main() {
  AccumulationRect acc;
  std::string op;
  while (std::cin >> op) {
    if (op == "reset") acc.reset();
    else if (op == "point") {
      float x = scalar(); float y = scalar(); acc.accumulate(x, y);
    } else if (op == "rect") acc.accumulate(rect());
    else if (op == "merge") {
      unsigned n; if (!(std::cin >> n)) return 2;
      AccumulationRect other;
      for (unsigned i = 0; i < n; i++) other.accumulate(rect());
      acc.accumulate(other);
    } else if (op == "overlap") acc.record_overlapping_bounds();
    else if (op == "enums") {
      std::printf("enums %zu %zu %zu %zu %zu %zu %d %d %d %d %d %d\n",
        sizeof(DlClipOp), sizeof(DlPointMode), sizeof(DlSrcRectConstraint),
        sizeof(DlFilterMode), sizeof(DlImageSampling), sizeof(DlTileMode),
        int(DlClipOp::kIntersect), int(DlPointMode::kPolygon),
        int(DlSrcRectConstraint::kFast), int(DlFilterMode::kLast),
        int(DlImageSampling::kCubic), int(DlTileMode::kDecal));
      continue;
    } else return 2;
    const auto r = acc.GetBounds();
    std::printf("%08x %08x %08x %08x %d %d %d\n",
      std::bit_cast<uint32_t>(r.GetLeft()), std::bit_cast<uint32_t>(r.GetTop()),
      std::bit_cast<uint32_t>(r.GetRight()), std::bit_cast<uint32_t>(r.GetBottom()),
      acc.is_empty(), acc.is_not_empty(), acc.overlap_detected());
  }
}

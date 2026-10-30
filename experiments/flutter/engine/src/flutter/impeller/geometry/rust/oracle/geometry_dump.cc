// Not an upstream file: the oracle driver for the Rust port of
// flutter/impeller/geometry.
//
// Links the upstream C++ (the files named in ../tests/oracle.rs) and prints
// what it does on seeded random inputs. src/bin/geometry_dump.rs is the same
// program over the port; the two outputs must be byte-identical.
//
//   geometry_dump <suite> <seed> <cases>     suite: see main()
//   geometry_dump bench <suite> <rounds>     a suite with its output discarded
//
// Every float is printed as its exact bit pattern (%08x, doubles %016llx),
// never as decimal, so a difference in the last bit is a difference.
//
// Both drivers draw every input from the same splitmix64 stream, so a suite's
// output is a function of (suite, seed, cases) alone.

#include <cinttypes>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "impeller/geometry/constants.h"
#include "impeller/geometry/saturated_math.h"
#include "impeller/geometry/scalar.h"

using namespace impeller;

// ---------------------------------------------------------------- rng ------

struct Rng {
  uint64_t s;
  uint64_t Next() {
    uint64_t z = (s += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
  }
  uint64_t Below(uint64_t n) { return Next() % n; }
  bool Chance(uint64_t one_in) { return Below(one_in) == 0; }
  // A uniform double in [0, 1).
  double Unit() { return (Next() >> 11) / 9007199254740992.0; }
};

static float FromBits(uint32_t b) {
  float f;
  std::memcpy(&f, &b, 4);
  return f;
}
static uint32_t Bits(float f) {
  uint32_t b;
  std::memcpy(&b, &f, 4);
  return b;
}
static double FromBits64(uint64_t b) {
  double d;
  std::memcpy(&d, &b, 8);
  return d;
}
static uint64_t Bits64(double d) {
  uint64_t b;
  std::memcpy(&b, &d, 8);
  return b;
}

// Edge and ordinary floats: zeros of both signs, ±1, ±inf, NaN, the extremes,
// denormals, huge and tiny values, integers past 2^24, and (most often)
// moderate random values.
static float EdgeF(Rng& r) {
  switch (r.Below(32)) {
    case 0: return 0.0f;
    case 1: return -0.0f;
    case 2: return 1.0f;
    case 3: return -1.0f;
    case 4: return std::numeric_limits<float>::infinity();
    case 5: return -std::numeric_limits<float>::infinity();
    case 6: return std::numeric_limits<float>::quiet_NaN();
    case 7: return std::numeric_limits<float>::max();
    case 8: return std::numeric_limits<float>::lowest();
    case 9: return std::numeric_limits<float>::min();
    case 10: return std::numeric_limits<float>::denorm_min();
    case 11: return -std::numeric_limits<float>::denorm_min();
    case 12: return FromBits(static_cast<uint32_t>(r.Below(0x800000)));  // denormal
    case 13: return 1e30f;
    case 14: return -1e30f;
    case 15: return 1e-30f;
    case 16: return 16777216.0f + static_cast<float>(r.Below(5)) * 2.0f;
    case 17: return 0.5f;
    case 18: return static_cast<float>(static_cast<int>(r.Below(21)) - 10);
    case 19: return static_cast<float>(static_cast<int>(r.Below(721)) - 360);
    case 20: return FromBits(static_cast<uint32_t>(r.Next()));  // any bits
    case 21:
    case 22: return static_cast<float>((r.Unit() * 2.0 - 1.0) * 1e6);
    default: return static_cast<float>((r.Unit() * 2.0 - 1.0) * 1000.0);
  }
}

// Moderate finite floats (sometimes zero or tiny), for the operations whose
// inputs upstream assumes sane.
static float SaneF(Rng& r) {
  switch (r.Below(16)) {
    case 0: return 0.0f;
    case 1: return -0.0f;
    case 2: return 1.0f;
    case 3: return static_cast<float>(static_cast<int>(r.Below(21)) - 10);
    case 4: return static_cast<float>((r.Unit() * 2.0 - 1.0) * 1e-3);
    default: return static_cast<float>((r.Unit() * 2.0 - 1.0) * 200.0);
  }
}

static double EdgeD(Rng& r) {
  switch (r.Below(20)) {
    case 0: return 0.0;
    case 1: return -0.0;
    case 2: return 1.0;
    case 3: return -1.0;
    case 4: return std::numeric_limits<double>::infinity();
    case 5: return -std::numeric_limits<double>::infinity();
    case 6: return std::numeric_limits<double>::quiet_NaN();
    case 7: return std::numeric_limits<double>::max();
    case 8: return std::numeric_limits<double>::lowest();
    case 9: return std::numeric_limits<double>::denorm_min();
    case 10: return static_cast<double>(std::numeric_limits<float>::max()) * (1.0 + r.Unit());
    case 11: return -static_cast<double>(std::numeric_limits<float>::max()) * (1.0 + r.Unit());
    case 12: return FromBits64(r.Next());
    case 13: return 1e-300;
    default: return (r.Unit() * 2.0 - 1.0) * 1e6;
  }
}

// Edge integers of the given width: zero, ±1, the limits and their
// neighbours, values near half the limits, small and full-range randoms.
static int64_t EdgeI(Rng& r, int bits) {
  int64_t max = bits == 64 ? std::numeric_limits<int64_t>::max()
                           : (int64_t{1} << (bits - 1)) - 1;
  int64_t min = -max - 1;
  switch (r.Below(12)) {
    case 0: return 0;
    case 1: return 1;
    case 2: return -1;
    case 3: return min;
    case 4: return max;
    case 5: return min + 1;
    case 6: return max - 1;
    case 7: return max / 2 + static_cast<int64_t>(r.Below(5)) - 2;
    case 8: return min / 2 + static_cast<int64_t>(r.Below(5)) - 2;
    case 9: return static_cast<int64_t>(r.Below(201)) - 100;
    default: {
      uint64_t v = r.Next();
      if (bits < 64) {
        v &= (uint64_t{1} << bits) - 1;
        // Sign-extend.
        if (v & (uint64_t{1} << (bits - 1))) {
          v |= ~((uint64_t{1} << bits) - 1);
        }
      }
      return static_cast<int64_t>(v);
    }
  }
}

// --------------------------------------------------------------- output -----

static std::string line;

static void Tag(const char* t) { line = t; }
static void F(float v) {
  char b[16];
  std::snprintf(b, sizeof b, " %08x", Bits(v));
  line += b;
}
static void D(double v) {
  char b[24];
  std::snprintf(b, sizeof b, " %016" PRIx64, Bits64(v));
  line += b;
}
static void I(int64_t v) {
  char b[24];
  std::snprintf(b, sizeof b, " %" PRId64, v);
  line += b;
}
static void U(uint64_t v) {
  char b[24];
  std::snprintf(b, sizeof b, " %" PRIu64, v);
  line += b;
}
static void B(bool v) { line += v ? " T" : " F"; }
static void S(const char* s) {
  line += ' ';
  line += s;
}
static void Arrow() { line += " ->"; }
static void End() {
  line += '\n';
  std::fwrite(line.data(), 1, line.size(), stdout);
}

template <class T>
static void Ord(T a, T b) {
  auto o = a <=> b;
  if (o < 0) {
    S("<");
  } else if (o > 0) {
    S(">");
  } else if (o == 0) {
    S("=");
  } else {
    S("?");
  }
}

// ---------------------------------------------------------------- scalar ---

template <class SI>
static void SatInt(Rng& r, const char* name, int bits) {
  SI a = static_cast<SI>(EdgeI(r, bits));
  SI b = static_cast<SI>(EdgeI(r, bits));
  Tag(name);
  I(a);
  I(b);
  Arrow();
  I(saturated::Add(a, b));
  I(saturated::Sub(a, b));
  F(saturated::AverageScalar(a, b));
  I(saturated::Cast<SI, SI>(a));
  End();
}

template <class FP, class SI>
static void CastToInt(const char* name, FP v) {
  // NaN converts with static_cast upstream, which is undefined; not fed.
  if (std::isnan(v)) {
    return;
  }
  Tag(name);
  if constexpr (sizeof(FP) == 4) {
    F(v);
  } else {
    D(v);
  }
  Arrow();
  I(saturated::Cast<FP, SI>(v));
  End();
}

static void SuiteScalar(Rng& r, int cases) {
  Tag("constants");
  F(kE);
  F(kLog2E);
  F(kLog10E);
  F(kLogE2);
  F(kLogE10);
  F(kPi);
  F(k2Pi);
  F(kPiOver2);
  F(kPiOver4);
  F(k1OverPi);
  F(k2OverPi);
  F(k2OverSqrtPi);
  F(kSqrt2);
  F(k1OverSqrt2);
  F(kSqrt2Over2);
  F(kPhi);
  F(kEhCloseEnough);
  End();
  for (int c = 0; c < cases; c++) {
    float a = EdgeF(r);
    float b = EdgeF(r);
    float tol = r.Chance(2) ? kEhCloseEnough : EdgeF(r);
    double da = EdgeD(r);
    int64_t ia = EdgeI(r, 64);
    int32_t ib = static_cast<int32_t>(EdgeI(r, 32));

    Tag("abs");
    F(a);
    D(da);
    I(ia);
    I(ib);
    Arrow();
    F(Absolute(a));
    D(Absolute(da));
    I(Absolute(ia));
    I(Absolute(ib));
    End();

    Tag("near");
    F(a);
    F(b);
    F(tol);
    Arrow();
    B(ScalarNearlyZero(a));
    B(ScalarNearlyZero(a, tol));
    B(ScalarNearlyEqual(a, b));
    B(ScalarNearlyEqual(a, b, tol));
    End();

    Radians ra(a), rb(b);
    Tag("radians");
    F(a);
    F(b);
    Arrow();
    B(ra.IsFinite());
    F((-ra).radians);
    F((ra + rb).radians);
    F((ra - rb).radians);
    Ord(ra, rb);
    B(ra == rb);
    B(ra < rb);
    B(ra >= rb);
    F(Radians().radians);
    End();

    Degrees dg(a), dh(b);
    Tag("degrees");
    F(a);
    F(b);
    Arrow();
    B(dg.IsFinite());
    F(Radians(dg).radians);
    F((-dg).degrees);
    F((dg + dh).degrees);
    F((dg - dh).degrees);
    Ord(dg, dh);
    B(dg == dh);
    B(dg > dh);
    F(dg.GetPositive().degrees);
    End();

    SatInt<int8_t>(r, "sat8", 8);
    SatInt<int16_t>(r, "sat16", 16);
    SatInt<int32_t>(r, "sat32", 32);
    SatInt<int64_t>(r, "sat64", 64);

    float fa = EdgeF(r), fb = EdgeF(r);
    double db = EdgeD(r);
    Tag("satf");
    F(fa);
    F(fb);
    D(da);
    D(db);
    Arrow();
    F(saturated::Add(fa, fb));
    F(saturated::Sub(fa, fb));
    F(saturated::AverageScalar(fa, fb));
    F(saturated::Cast<float, float>(fa));
    D(saturated::Add(da, db));
    D(saturated::Sub(da, db));
    F(saturated::AverageScalar(da, db));
    D(saturated::Cast<double, double>(da));
    F(saturated::Cast<double, float>(da));
    D(saturated::Cast<float, double>(fa));
    End();

    CastToInt<float, int8_t>("cast_f_i8", fa);
    CastToInt<float, int16_t>("cast_f_i16", fa);
    CastToInt<float, int32_t>("cast_f_i32", fa);
    CastToInt<float, int64_t>("cast_f_i64", fa);
    CastToInt<double, int32_t>("cast_d_i32", da);
    CastToInt<double, int64_t>("cast_d_i64", da);
    // Values near the limits of each width, where the float form of the
    // limit rounds up.
    float near = static_cast<float>(EdgeI(r, 32)) * (r.Chance(2) ? 1.0f : 2.0f);
    CastToInt<float, int32_t>("cast_near_i32", near);
    CastToInt<float, int64_t>("cast_near_i64",
                              static_cast<float>(EdgeI(r, 64)));
    CastToInt<double, int64_t>("cast_near_d_i64",
                               static_cast<double>(EdgeI(r, 64)));
  }
}

// ----------------------------------------------------------------- main ----

typedef void (*Suite)(Rng&, int);
struct NamedSuite {
  const char* name;
  Suite suite;
};
static const NamedSuite kSuites[] = {
    {"scalar", SuiteScalar},
};

int main(int argc, char** argv) {
  if (argc != 4) {
    std::fprintf(stderr,
                 "usage: geometry_dump <suite> <seed> <cases> | bench <suite> "
                 "<rounds>\n");
    return 2;
  }
  std::string suite = argv[1];
  if (suite == "bench") {
    std::freopen("/dev/null", "w", stdout);
    std::string name = argv[2];
    int rounds = std::atoi(argv[3]);
    for (const auto& s : kSuites) {
      if (name == s.name) {
        for (int i = 0; i < rounds; i++) {
          Rng r{static_cast<uint64_t>(i + 1)};
          s.suite(r, 20000);
        }
        return 0;
      }
    }
    std::fprintf(stderr, "unknown suite %s\n", argv[2]);
    return 2;
  }
  Rng r{std::strtoull(argv[2], nullptr, 10)};
  int cases = std::atoi(argv[3]);
  bool known = false;
  for (const auto& s : kSuites) {
    if (suite == "all" || suite == s.name) {
      known = true;
      s.suite(r, cases);
    }
  }
  if (!known) {
    std::fprintf(stderr, "unknown suite %s\n", argv[1]);
    return 2;
  }
  return 0;
}

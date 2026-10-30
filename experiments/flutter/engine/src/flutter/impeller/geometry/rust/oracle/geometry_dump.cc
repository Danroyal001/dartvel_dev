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

#include "impeller/geometry/color.h"
#include "impeller/geometry/constants.h"
#include "impeller/geometry/gradient.h"
#include "impeller/geometry/half.h"
#include "impeller/geometry/matrix.h"
#include "impeller/geometry/matrix_decomposition.h"
#include "impeller/geometry/quaternion.h"
#include "impeller/geometry/rational.h"
#include "impeller/geometry/rect.h"
#include "impeller/geometry/rstransform.h"
#include "impeller/geometry/separated_vector.h"
#include "impeller/geometry/sigma.h"
#include "impeller/geometry/stroke_parameters.h"
#include "impeller/geometry/trig.h"
#include "impeller/geometry/wangs_formula.h"
#include "impeller/geometry/shear.h"
#include "impeller/geometry/point.h"
#include "impeller/geometry/size.h"
#include "impeller/geometry/vector.h"
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
  // IEEE 754 leaves the sign and payload of an arithmetic NaN unspecified
  // and LLVM treats them as nondeterministic (it may rewrite a - b as
  // a + -b), so a NaN prints as its class; every other value as its bits.
  if (std::isnan(v)) {
    line += " nan";
    return;
  }
  char b[16];
  std::snprintf(b, sizeof b, " %08x", Bits(v));
  line += b;
}
static void D(double v) {
  if (std::isnan(v)) {
    line += " nan";
    return;
  }
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
    float near = static_cast<float>(EdgeI(r, 32));
    if (r.Chance(2)) {
      near *= 2.0f;
    }
    CastToInt<float, int32_t>("cast_near_i32", near);
    CastToInt<float, int64_t>("cast_near_i64",
                              static_cast<float>(EdgeI(r, 64)));
    CastToInt<double, int64_t>("cast_near_d_i64",
                               static_cast<double>(EdgeI(r, 64)));
  }
}

// ------------------------------------------------------- point and size ---

// A finite float in (-0.5, 0.5), for scaling integer points without leaving
// their range (out-of-range float-to-integer conversion is undefined).
static float SmallF(Rng& r) {
  return static_cast<float>(r.Unit() - 0.5);
}

// An integer that is a safe divisor: never 0, and never -1 (INT_MIN / -1
// traps).
static int64_t DivisorI(Rng& r, int bits) {
  int64_t v = EdgeI(r, bits);
  return (v == 0 || v == -1) ? 2 : v;
}

// An integer within ±2^28, whose squares and products of two stay exact.
static int64_t ModI(Rng& r) {
  return static_cast<int64_t>(r.Below(1 << 29)) - (1 << 28);
}

static Point EdgeP(Rng& r) {
  float x = EdgeF(r);
  float y = EdgeF(r);
  return {x, y};
}
static Size EdgeS(Rng& r) {
  float w = EdgeF(r);
  float h = EdgeF(r);
  return {w, h};
}
template <class T>
static TPoint<T> EdgeIP(Rng& r, int bits) {
  T x = static_cast<T>(EdgeI(r, bits));
  T y = static_cast<T>(EdgeI(r, bits));
  return {x, y};
}
template <class T>
static TPoint<T> DivisorIP(Rng& r, int bits) {
  T x = static_cast<T>(DivisorI(r, bits));
  T y = static_cast<T>(DivisorI(r, bits));
  return {x, y};
}
static IPoint ModIP(Rng& r) {
  int64_t x = ModI(r);
  int64_t y = ModI(r);
  return {x, y};
}

static void P(Point p) {
  F(p.x);
  F(p.y);
}
template <class T>
static void IP(TPoint<T> p) {
  I(static_cast<int64_t>(p.x));
  I(static_cast<int64_t>(p.y));
}
static void SZ(Size s) {
  F(s.width);
  F(s.height);
}
template <class T>
static void ISZ(TSize<T> s) {
  I(static_cast<int64_t>(s.width));
  I(static_cast<int64_t>(s.height));
}

static void SuitePoint(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    Point a = EdgeP(r);
    Point b = EdgeP(r);
    Point pc = EdgeP(r);
    float s = EdgeF(r);
    double ds = EdgeD(r);
    int32_t is = static_cast<int32_t>(EdgeI(r, 32));
    Size sz = EdgeS(r);

    Tag("pt_ops");
    P(a);
    P(b);
    F(s);
    D(ds);
    I(is);
    SZ(sz);
    Arrow();
    P(-a);
    P(a + b);
    P(a - b);
    P(a * b);
    P(a / b);
    P(a * s);
    P(a * ds);
    P(a * is);
    P(a / s);
    P(a / ds);
    P(a / is);
    P(s * a);
    P(ds * a);
    P(is * a);
    P(s / a);
    P(ds / a);
    P(is / a);
    P(a + sz);
    P(a - sz);
    P(a * sz);
    P(a / sz);
    P(sz + a);
    P(sz - a);
    P(sz * a);
    P(sz / a);
    P(a - s);
    B(a == b);
    B(a != b);
    B(a == a);
    B(a != a);
    End();

    Tag("pt_assign");
    Point t = a;
    t += b;
    P(t);
    t = a;
    t += sz;
    P(t);
    t = a;
    t -= b;
    P(t);
    t = a;
    t -= sz;
    P(t);
    t = a;
    t *= b;
    P(t);
    t = a;
    t *= sz;
    P(t);
    t = a;
    t *= s;
    P(t);
    t = a;
    t *= ds;
    P(t);
    t = a;
    t *= is;
    P(t);
    t = a;
    t /= b;
    P(t);
    t = a;
    t /= sz;
    P(t);
    t = a;
    t /= s;
    P(t);
    t = a;
    t /= ds;
    P(t);
    t = a;
    t /= is;
    P(t);
    End();

    Tag("pt_methods");
    P(a);
    P(b);
    P(pc);
    F(s);
    Arrow();
    F(a.GetDistanceSquared(b));
    P(a.Min(b));
    P(a.Max(b));
    P(a.Floor());
    P(a.Ceil());
    P(a.Round());
    F(a.GetDistance(b));
    F(a.GetLengthSquared());
    F(a.GetLength());
    F(a.GetDistanceToSegmentSquared(b, pc));
    F(a.GetDistanceToSegment(b, pc));
    P(a.Normalize());
    P(a.Abs());
    F(a.Cross(b));
    F(Point::Cross(a, b, pc));
    F(a.Dot(b));
    P(a.Reflect(b));
    P(a.Rotate(Radians(s)));
    P(a.PerpendicularRight());
    P(a.PerpendicularLeft());
    F(a.AngleTo(b).radians);
    P(a.Lerp(b, s));
    B(a.IsZero());
    B(a.IsFinite());
    P(Point::Round(a));
    P(Point::MakeXY(a.y, a.x));
    P(Point(sz));
    End();

    // Segments with sane coordinates, where the three branches are all
    // taken.
    {
      float x0 = SaneF(r), y0 = SaneF(r), x1 = SaneF(r), y1 = SaneF(r),
            x2 = SaneF(r), y2 = SaneF(r);
      Point p{x0, y0}, p0{x1, y1}, p1{x2, y2};
      Tag("pt_segment");
      P(p);
      P(p0);
      P(p1);
      Arrow();
      F(p.GetDistanceToSegmentSquared(p0, p1));
      F(p.GetDistanceToSegment(p0, p1));
      F(p.GetDistance(p0));
      P(p.Normalize());
      F(p.AngleTo(p0).radians);
      End();
    }

    // int64_t points.
    IPoint ia = EdgeIP<int64_t>(r, 64);
    IPoint ib = EdgeIP<int64_t>(r, 64);
    IPoint id = DivisorIP<int64_t>(r, 64);
    IPoint ma = ModIP(r);
    IPoint mb = ModIP(r);
    IPoint mc = ModIP(r);
    int64_t dv = DivisorI(r, 64);
    int32_t dv32 = static_cast<int32_t>(DivisorI(r, 32));
    float fs = SmallF(r);
    double dfs = SmallF(r);
    float fd = static_cast<float>(1.0 + r.Unit());
    ISize isz = {EdgeI(r, 64), EdgeI(r, 64)};
    ISize idsz = {DivisorI(r, 64), DivisorI(r, 64)};
    float mfx = SaneF(r) * 1000.0f;
    float mfy = SaneF(r) * 1000.0f;
    Point mf{mfx, mfy};

    Tag("ipt_ops");
    IP(ia);
    IP(ib);
    IP(id);
    I(dv);
    I(dv32);
    F(fs);
    D(dfs);
    F(fd);
    ISZ(isz);
    Arrow();
    IP(-ia);
    IP(ia + ib);
    IP(ia - ib);
    IP(ia * ib);
    IP(ia / id);
    IP(ia * dv);
    IP(ia * dv32);
    IP(ia * fs);
    IP(ia * dfs);
    IP(ia / dv);
    IP(ia / dv32);
    IP(ma / fd);
    IP(dv * ia);
    IP(fs * ia);
    IP(dv / id);
    IP(ia + isz);
    IP(ia - isz);
    IP(ia * isz);
    IP(ia / idsz);
    IP(isz + ia);
    IP(isz - ia);
    IP(isz / id);
    IP(ia - dv);
    B(ia == ib);
    B(ia != ib);
    P(a + ia);
    P(ia + a);
    P(a - ia);
    P(ia - a);
    P(a * ia);
    P(ia * a);
    P(a / ia);
    P(ia / a);
    P(Point(ia));
    IP(IPoint(mf));
    IP(IPoint::Round(mf));
    P(Point::Round(ia));
    End();

    Tag("ipt_assign");
    IPoint it = ia;
    it += ib;
    IP(it);
    it = ia;
    it += isz;
    IP(it);
    it = ia;
    it -= ib;
    IP(it);
    it = ia;
    it *= ib;
    IP(it);
    it = ia;
    it *= dv32;
    IP(it);
    it = ia;
    it /= id;
    IP(it);
    it = ia;
    it /= dv;
    IP(it);
    it = ia;
    it /= idsz;
    IP(it);
    End();

    Tag("ipt_methods");
    IP(ma);
    IP(mb);
    IP(mc);
    F(fs);
    Arrow();
    I(ma.GetDistanceSquared(mb));
    I(ma.GetDistance(mb));
    I(ma.GetDistanceToSegmentSquared(mb, mc));
    I(ma.GetDistanceToSegment(mb, mc));
    IP(ma.Lerp(mb, fs));
    IP(ia.Min(ib));
    IP(ia.Max(ib));
    F(ia.GetLengthSquared());
    F(ia.GetLength());
    I(ia.Cross(ib));
    I(IPoint::Cross(ia, ib, id));
    I(ia.Dot(ib));
    IP(ia.Reflect(ib));
    IP(ia.PerpendicularRight());
    IP(ia.PerpendicularLeft());
    B(ia.IsZero());
    B(IPoint().IsZero());
    End();

    // int32_t and uint32_t points.
    IPoint32 ja = EdgeIP<int32_t>(r, 32);
    IPoint32 jb = EdgeIP<int32_t>(r, 32);
    IPoint32 jd = DivisorIP<int32_t>(r, 32);
    UintPoint32 ua = EdgeIP<uint32_t>(r, 32);
    UintPoint32 ub = EdgeIP<uint32_t>(r, 32);
    UintPoint32 ud = DivisorIP<uint32_t>(r, 32);
    int64_t j64 = EdgeI(r, 64);
    Tag("ipt32");
    IP(ja);
    IP(jb);
    IP(jd);
    IP(ua);
    IP(ub);
    IP(ud);
    I(j64);
    Arrow();
    IP(-ja);
    IP(ja + jb);
    IP(ja - jb);
    IP(ja * jb);
    IP(ja / jd);
    IP(ja * j64);
    IP(ja * dv32);
    IP(ja * fs);
    IP(ja / dv32);
    IP(ja - jb.x);
    I(ja.Cross(jb));
    I(ja.Dot(jb));
    F(ja.GetLengthSquared());
    IP(ja.Min(jb));
    IP(ja.Max(jb));
    P(a + ja);
    P(ja - a);
    P(a / ja);
    IP(-ua);
    IP(ua + ub);
    IP(ua - ub);
    IP(ua * ub);
    IP(ua / ud);
    IP(ua * dv32);
    IP(ua / dv32);
    IP(ua * j64);
    I(ua.Cross(ub));
    I(ua.Dot(ub));
    F(ua.GetLengthSquared());
    IP(ua.Min(ub));
    IP(ua.Max(ub));
    IP(ua.PerpendicularLeft());
    P(a * ua);
    P(Point(ua));
    IP(IPoint32(ia));
    IP(UintPoint32(ja));
    End();
  }
}

static bool MipCountDefined(Size s) {
  // log2 of a size below 0.5 is -1 or less, and of an infinite one inf;
  // either converted to size_t is undefined.
  return s.IsEmpty() ||
         (std::min(s.width, s.height) > 0.5f &&
          !(std::isinf(s.width) && std::isinf(s.height)));
}

static void SuiteSize(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    Size a = EdgeS(r);
    Size b = EdgeS(r);
    float s = EdgeF(r);
    double ds = EdgeD(r);
    int32_t is = static_cast<int32_t>(EdgeI(r, 32));

    Tag("size_ops");
    SZ(a);
    SZ(b);
    F(s);
    D(ds);
    I(is);
    Arrow();
    SZ(a * s);
    SZ(a / s);
    SZ(a / b);
    SZ(a + b);
    SZ(a - b);
    SZ(-a);
    SZ(s * a);
    SZ(ds * a);
    SZ(is * a);
    SZ(s / a);
    SZ(ds / a);
    SZ(is / a);
    Size t = a;
    t *= s;
    SZ(t);
    t = a;
    t *= ds;
    SZ(t);
    t = a;
    t *= is;
    SZ(t);
    B(a == b);
    B(a != b);
    B(a == a);
    End();

    Tag("size_methods");
    SZ(a);
    SZ(b);
    Arrow();
    SZ(a.Min(b));
    SZ(a.Max(b));
    F(a.MinDimension());
    F(a.MaxDimension());
    SZ(a.Abs());
    SZ(a.Floor());
    SZ(a.Ceil());
    SZ(a.Round());
    F(a.Area());
    B(a.IsEmpty());
    B(a.IsFinite());
    B(a.IsSquare());
    SZ(Size::Ceil(a));
    if (MipCountDefined(a)) {
      U(a.MipCount());
    }
    SZ(Size(s));
    SZ(Size::MakeWH(s, a.width));
    SZ(Size::Infinite());
    SZ(Size());
    End();

    ISize ia = {EdgeI(r, 64), EdgeI(r, 64)};
    ISize ib = {EdgeI(r, 64), EdgeI(r, 64)};
    ISize id = {DivisorI(r, 64), DivisorI(r, 64)};
    int64_t mw = ModI(r);
    int64_t mh = ModI(r);
    ISize32 ja = {static_cast<int32_t>(EdgeI(r, 32)),
                  static_cast<int32_t>(EdgeI(r, 32))};
    ISize32 jb = {static_cast<int32_t>(EdgeI(r, 32)),
                  static_cast<int32_t>(EdgeI(r, 32))};
    float mfw = SaneF(r) * 1000.0f;
    float mfh = SaneF(r) * 1000.0f;
    Tag("isize");
    ISZ(ia);
    ISZ(ib);
    ISZ(id);
    I(mw);
    I(mh);
    ISZ(ja);
    ISZ(jb);
    F(mfw);
    F(mfh);
    Arrow();
    ISZ(ia + ib);
    ISZ(ia - ib);
    ISZ(-ia);
    ISZ(ia / id);
    I(ia.Area());
    ISZ(ia.Min(ib));
    ISZ(ia.Max(ib));
    I(ia.MinDimension());
    I(ia.MaxDimension());
    B(ia.IsEmpty());
    B(ia.IsSquare());
    B(ia == ib);
    B(ia != ib);
    U(ia.MipCount());
    U(ISize(mw, mh).MipCount());
    ISize it = ia;
    it *= is;
    ISZ(it);
    ISZ(ISize::Ceil(Size(mfw, mfh)));
    ISZ(ISize(Size(mfw, mfh)));
    SZ(Size(ia));
    ISZ(ISize::Infinite());
    ISZ(ja + jb);
    ISZ(ja - jb);
    I(ja.Area());
    ISZ(ISize32(ia));
    U(ja.MipCount());
    End();
  }
}

// ------------------------------------------------- vector, color, half ---

static Vector3 EdgeV3(Rng& r) {
  float x = EdgeF(r);
  float y = EdgeF(r);
  float z = EdgeF(r);
  return Vector3(x, y, z);
}
static Vector4 EdgeV4(Rng& r) {
  float x = EdgeF(r);
  float y = EdgeF(r);
  float z = EdgeF(r);
  float w = EdgeF(r);
  return Vector4(x, y, z, w);
}
static void V3(Vector3 v) {
  F(v.x);
  F(v.y);
  F(v.z);
}
static void V4(Vector4 v) {
  F(v.x);
  F(v.y);
  F(v.z);
  F(v.w);
}

static void SuiteVector(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    Vector3 a = EdgeV3(r);
    Vector3 b = EdgeV3(r);
    float s = EdgeF(r);
    double ds = EdgeD(r);
    int32_t is = static_cast<int32_t>(EdgeI(r, 32));
    Point p = EdgeP(r);
    Size sz = EdgeS(r);
    Tag("v3_ops");
    V3(a);
    V3(b);
    F(s);
    D(ds);
    I(is);
    Arrow();
    V3(-a);
    V3(a + b);
    V3(a - b);
    V3(a + s);
    V3(a - s);
    V3(a * b);
    V3(a * s);
    V3(a * ds);
    V3(a * is);
    V3(a / b);
    V3(a / s);
    V3(a / ds);
    V3(a / is);
    V3(s * a);
    V3(ds * a);
    V3(is * a);
    V3(s + a);
    V3(ds + a);
    V3(is + a);
    V3(s - a);
    V3(ds - a);
    V3(is - a);
    V3(s / a);
    V3(ds / a);
    V3(is / a);
    Vector3 t = a;
    t += b;
    V3(t);
    t = a;
    t -= b;
    V3(t);
    t = a;
    t *= b;
    V3(t);
    t = a;
    t *= s;
    V3(t);
    t = a;
    t *= ds;
    V3(t);
    t = a;
    t *= is;
    V3(t);
    t = a;
    t /= b;
    V3(t);
    t = a;
    t /= s;
    V3(t);
    t = a;
    t /= ds;
    V3(t);
    t = a;
    t /= is;
    V3(t);
    B(a == b);
    B(a != b);
    B(a == a);
    End();

    Tag("v3_methods");
    V3(a);
    V3(b);
    F(s);
    Arrow();
    F(a.GetLength());
    V3(a.Normalize());
    F(a.Dot(b));
    V3(a.Abs());
    V3(a.Cross(b));
    V3(a.Min(b));
    V3(a.Max(b));
    V3(a.Floor());
    V3(a.Ceil());
    V3(a.Round());
    V3(a.Lerp(b, s));
    V3(Vector3::Combine(a, s, b, b.x));
    V3(Vector3(p));
    V3(Vector3(sz));
    V3(Vector3(s, a.x));
    V3(Vector3());
    End();

    Vector4 u = EdgeV4(r);
    Vector4 v = EdgeV4(r);
    float f0 = EdgeF(r);
    float f1 = EdgeF(r);
    float f2 = EdgeF(r);
    float f3 = EdgeF(r);
    Tag("v4");
    V4(u);
    V4(v);
    F(s);
    Arrow();
    B(u.IsFinite());
    V4(u.Normalize());
    B(u == v);
    B(u != v);
    B(u == u);
    V4(u + v);
    V4(u - v);
    V4(u * s);
    V4(u * v);
    V4(u.Min(v));
    V4(u.Max(v));
    V4(u.Floor());
    V4(u.Ceil());
    V4(u.Round());
    V4(u.Lerp(v, s));
    P(u.xy());
    V4(Vector4());
    V4(Vector4(a));
    V4(Vector4(p));
    V4(Vector4(std::array<Scalar, 4>{f0, f1, f2, f3}));
    End();
  }
}

// A color component: usually in [0, 1], sometimes an edge value.
static float CompF(Rng& r) {
  switch (r.Below(10)) {
    case 0: return 0.0f;
    case 1: return 1.0f;
    case 2: return EdgeF(r);
    case 3: return static_cast<float>(r.Unit() * 3.0 - 1.0);
    default: return static_cast<float>(r.Unit());
  }
}
static Color CompC(Rng& r) {
  float red = CompF(r);
  float green = CompF(r);
  float blue = CompF(r);
  float alpha = CompF(r);
  return Color(red, green, blue, alpha);
}
// A color in [0, 1], for the conversions to 8 bits (upstream's implicit
// float-to-uint8_t conversion is undefined outside [0, 255]).
static Color UnitC(Rng& r) {
  float red = static_cast<float>(r.Unit());
  float green = static_cast<float>(r.Unit());
  float blue = static_cast<float>(r.Unit());
  float alpha = static_cast<float>(r.Unit());
  return Color(red, green, blue, alpha);
}
static void C(Color c) {
  F(c.red);
  F(c.green);
  F(c.blue);
  F(c.alpha);
}

static void SuiteColor(Rng& r, int cases) {
  Tag("named");
  C(Color::White());
  C(Color::Black());
  C(Color::WhiteTransparent());
  C(Color::BlackTransparent());
  C(Color::Red());
  C(Color::Green());
  C(Color::Blue());
  C(Color::AliceBlue());
  C(Color::AntiqueWhite());
  C(Color::Aqua());
  C(Color::AquaMarine());
  C(Color::Azure());
  C(Color::Beige());
  C(Color::Bisque());
  C(Color::BlanchedAlmond());
  C(Color::BlueViolet());
  C(Color::Brown());
  C(Color::BurlyWood());
  C(Color::CadetBlue());
  C(Color::Chartreuse());
  C(Color::Chocolate());
  C(Color::Coral());
  C(Color::CornflowerBlue());
  C(Color::Cornsilk());
  C(Color::Crimson());
  C(Color::Cyan());
  C(Color::DarkBlue());
  C(Color::DarkCyan());
  C(Color::DarkGoldenrod());
  C(Color::DarkGray());
  C(Color::DarkGreen());
  C(Color::DarkGrey());
  C(Color::DarkKhaki());
  C(Color::DarkMagenta());
  C(Color::DarkOliveGreen());
  C(Color::DarkOrange());
  C(Color::DarkOrchid());
  C(Color::DarkRed());
  C(Color::DarkSalmon());
  C(Color::DarkSeagreen());
  C(Color::DarkSlateBlue());
  C(Color::DarkSlateGray());
  C(Color::DarkSlateGrey());
  C(Color::DarkTurquoise());
  C(Color::DarkViolet());
  C(Color::DeepPink());
  C(Color::DeepSkyBlue());
  C(Color::DimGray());
  C(Color::DimGrey());
  C(Color::DodgerBlue());
  C(Color::Firebrick());
  C(Color::FloralWhite());
  C(Color::ForestGreen());
  C(Color::Fuchsia());
  C(Color::Gainsboro());
  C(Color::Ghostwhite());
  C(Color::Gold());
  C(Color::Goldenrod());
  C(Color::Gray());
  C(Color::GreenYellow());
  C(Color::Grey());
  C(Color::Honeydew());
  C(Color::HotPink());
  C(Color::IndianRed());
  C(Color::Indigo());
  C(Color::Ivory());
  C(Color::Khaki());
  C(Color::Lavender());
  C(Color::LavenderBlush());
  C(Color::LawnGreen());
  C(Color::LemonChiffon());
  C(Color::LightBlue());
  C(Color::LightCoral());
  C(Color::LightCyan());
  C(Color::LightGoldenrodYellow());
  C(Color::LightGray());
  C(Color::LightGreen());
  C(Color::LightGrey());
  C(Color::LightPink());
  C(Color::LightSalmon());
  C(Color::LightSeaGreen());
  C(Color::LightSkyBlue());
  C(Color::LightSlateGray());
  C(Color::LightSlateGrey());
  C(Color::LightSteelBlue());
  C(Color::LightYellow());
  C(Color::Lime());
  C(Color::LimeGreen());
  C(Color::Linen());
  C(Color::Magenta());
  C(Color::Maroon());
  C(Color::MediumAquamarine());
  C(Color::MediumBlue());
  C(Color::MediumOrchid());
  C(Color::MediumPurple());
  C(Color::MediumSeagreen());
  C(Color::MediumSlateBlue());
  C(Color::MediumSpringGreen());
  C(Color::MediumTurquoise());
  C(Color::MediumVioletRed());
  C(Color::MidnightBlue());
  C(Color::MintCream());
  C(Color::MistyRose());
  C(Color::Moccasin());
  C(Color::NavajoWhite());
  C(Color::Navy());
  C(Color::OldLace());
  C(Color::Olive());
  C(Color::OliveDrab());
  C(Color::Orange());
  C(Color::OrangeRed());
  C(Color::Orchid());
  C(Color::PaleGoldenrod());
  C(Color::PaleGreen());
  C(Color::PaleTurquoise());
  C(Color::PaleVioletRed());
  C(Color::PapayaWhip());
  C(Color::Peachpuff());
  C(Color::Peru());
  C(Color::Pink());
  C(Color::Plum());
  C(Color::PowderBlue());
  C(Color::Purple());
  C(Color::RosyBrown());
  C(Color::RoyalBlue());
  C(Color::SaddleBrown());
  C(Color::Salmon());
  C(Color::SandyBrown());
  C(Color::Seagreen());
  C(Color::Seashell());
  C(Color::Sienna());
  C(Color::Silver());
  C(Color::SkyBlue());
  C(Color::SlateBlue());
  C(Color::SlateGray());
  C(Color::SlateGrey());
  C(Color::Snow());
  C(Color::SpringGreen());
  C(Color::SteelBlue());
  C(Color::Tan());
  C(Color::Teal());
  C(Color::Thistle());
  C(Color::Tomato());
  C(Color::Turquoise());
  C(Color::Violet());
  C(Color::Wheat());
  C(Color::Whitesmoke());
  C(Color::Yellow());
  C(Color::YellowGreen());
  End();
  Tag("blend_modes");
  for (int m = 0; m <= static_cast<int>(BlendMode::kLastMode); m++) {
    S(BlendModeToString(static_cast<BlendMode>(m)));
  }
  I(static_cast<int>(BlendMode::kDefaultMode));
  End();
  for (int c = 0; c < cases; c++) {
    Color a = CompC(r);
    Color b = CompC(r);
    float s = EdgeF(r);
    double ds = EdgeD(r);
    int32_t is = static_cast<int32_t>(EdgeI(r, 32));
    Tag("color_ops");
    C(a);
    C(b);
    F(s);
    D(ds);
    I(is);
    Arrow();
    C(a + b);
    C(a + s);
    C(a + ds);
    C(a + is);
    C(a - b);
    C(a - s);
    C(a - is);
    C(a * b);
    C(a * s);
    C(a * ds);
    C(a * is);
    C(a / b);
    C(a / s);
    C(a / is);
    C(s + a);
    C(ds - a);
    C(is * a);
    C(s / a);
    B(a == b);
    B(a == a);
    C(a.Premultiply());
    C(a.Unpremultiply());
    B(a.IsWideGamut());
    C(Color::Lerp(a, b, s));
    C(a.Clamp01());
    C(a.WithAlpha(s));
    U(Color::ToIColor(a));
    C(a.LinearToSRGB());
    C(a.SRGBToLinear());
    B(a.IsTransparent());
    B(a.IsOpaque());
    C(Color(Vector4(a)));
    V3(Vector3(a));
    End();

    Tag("blend");
    C(a);
    C(b);
    Arrow();
    for (int m = 0; m <= static_cast<int>(BlendMode::kLastMode); m++) {
      C(a.Blend(b, static_cast<BlendMode>(m)));
    }
    End();

    ColorMatrix cm;
    for (int i = 0; i < 20; i++) {
      cm.array[i] = r.Chance(4) ? EdgeF(r) : static_cast<float>(r.Unit() * 2.0 - 1.0);
    }
    Tag("matrix");
    for (int i = 0; i < 20; i++) {
      F(cm.array[i]);
    }
    Arrow();
    C(a.ApplyColorMatrix(cm));
    End();

    Color u = UnitC(r);
    uint8_t r8 = static_cast<uint8_t>(r.Below(256));
    uint8_t g8 = static_cast<uint8_t>(r.Below(256));
    uint8_t b8 = static_cast<uint8_t>(r.Below(256));
    uint8_t a8 = static_cast<uint8_t>(r.Below(256));
    Tag("color8");
    C(u);
    I(r8);
    I(g8);
    I(b8);
    I(a8);
    Arrow();
    auto bytes = u.ToR8G8B8A8();
    I(bytes[0]);
    I(bytes[1]);
    I(bytes[2]);
    I(bytes[3]);
    U(u.ToARGB());
    U(Color::ToIColor(u));
    C(Color::MakeRGBA8(r8, g8, b8, a8));
    End();

    // Half: the non-Apple branch, an integer conversion; fed values whose
    // truncation fits in uint16_t.
    float h0 = static_cast<float>(r.Unit() * 65536.0 - 0.99);
    float h1 = static_cast<float>(r.Unit() * 65536.0);
    float h2 = static_cast<float>(r.Unit() * 100.0);
    float h3 = static_cast<float>(r.Unit());
    double hd = r.Unit() * 65535.0;
    int hi = static_cast<int>(r.Below(65536));
    Tag("half");
    F(h0);
    F(h1);
    F(h2);
    F(h3);
    D(hd);
    I(hi);
    Arrow();
    I(ScalarToHalf(h0));
    I(Half(h1).x);
    I(Half(hd).x);
    I(Half(hi).x);
    I(Half(static_cast<InternalHalf>(hi)).x);
    B(Half(h1) == Half(h2));
    HalfVector4 hv4(Color(h0, h1, h2, h3));
    HalfVector4 hw4(Vector4(h3, h2, h1, h0));
    HalfVector3 hv3(Vector3(h0, h1, h2));
    HalfVector2 hv2(Vector2(h2, h3));
    I(hv4.x);
    I(hv4.y);
    I(hv4.z);
    I(hv4.w);
    I(hw4.x);
    I(hw4.w);
    I(hv3.x);
    I(hv3.y);
    I(hv3.z);
    I(hv2.x);
    I(hv2.y);
    B(hv4 == hw4);
    B(hv4 != hw4);
    B(hv3 == HalfVector3(hv3.x, hv3.y, hv3.z));
    B(hv2 != HalfVector2(hv2.y, hv2.x));
    End();
  }
}

// ---------------------------------------------------------------- matrix ---

static void M(const Matrix& m) {
  for (int i = 0; i < 16; i++) {
    F(m.m[i]);
  }
}
static void Q(const Quaternion& q) {
  F(q.x);
  F(q.y);
  F(q.z);
  F(q.w);
}
static void OptF(std::optional<Scalar> v) {
  if (v.has_value()) {
    F(*v);
  } else {
    S("none");
  }
}
static void Decomp(const MatrixDecomposition& d) {
  V3(d.translation);
  V3(d.scale);
  D(d.shear.xy);
  D(d.shear.xz);
  D(d.shear.yz);
  V4(d.perspective);
  Q(d.rotation);
  U(d.GetComponentsMask());
}

static Point SaneP(Rng& r) {
  float x = SaneF(r);
  float y = SaneF(r);
  return Point(x, y);
}

static Vector3 SaneV3(Rng& r) {
  float x = SaneF(r);
  float y = SaneF(r);
  float z = SaneF(r);
  return Vector3(x, y, z);
}

// Matrices of every shape: wild bits, sane entries, compositions of the
// constructors (affine, rotated, skewed, with perspective), and singular or
// nearly singular ones.
static Matrix GenM(Rng& r) {
  Matrix m;
  switch (r.Below(10)) {
    case 0:
      for (int i = 0; i < 16; i++) {
        m.m[i] = EdgeF(r);
      }
      return m;
    case 1:
      for (int i = 0; i < 16; i++) {
        m.m[i] = SaneF(r);
      }
      return m;
    case 2: {
      // 2D affine.
      float a = SaneF(r), b = SaneF(r), c = SaneF(r), d = SaneF(r),
            tx = SaneF(r), ty = SaneF(r);
      return Matrix(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
    }
    case 3: {
      // Scale and translate (sometimes negative or zero scales).
      Vector3 s = SaneV3(r);
      Vector3 t = SaneV3(r);
      return Matrix::MakeTranslateScale(s, t);
    }
    case 4: {
      // A composition.
      Vector3 t = SaneV3(r);
      float angle = SaneF(r);
      Vector3 s = SaneV3(r);
      float kx = SaneF(r) * 0.01f;
      float ky = SaneF(r) * 0.01f;
      return Matrix::MakeTranslation(t) * Matrix::MakeRotationZ(Radians(angle)) *
             Matrix::MakeScale(s) * Matrix::MakeSkew(kx, ky);
    }
    case 5: {
      // With perspective.
      for (int i = 0; i < 16; i++) {
        m.m[i] = SaneF(r) * 0.01f;
      }
      m.m[0] += 1;
      m.m[5] += 1;
      m.m[10] += 1;
      m.m[15] += 1;
      return m;
    }
    case 6: {
      // Singular: one column a multiple of another.
      for (int i = 0; i < 16; i++) {
        m.m[i] = SaneF(r);
      }
      int a = static_cast<int>(r.Below(4));
      int b = static_cast<int>(r.Below(4));
      float k = SaneF(r);
      for (int j = 0; j < 4; j++) {
        m.e[a][j] = m.e[b][j] * k;
      }
      return m;
    }
    case 7: {
      // Nearly singular.
      for (int i = 0; i < 16; i++) {
        m.m[i] = SaneF(r);
      }
      int a = static_cast<int>(r.Below(4));
      int b = (a + 1 + static_cast<int>(r.Below(3))) % 4;
      for (int j = 0; j < 4; j++) {
        float eps = static_cast<float>((r.Unit() - 0.5) * 1e-5);
        m.e[a][j] = m.e[b][j] + eps;
      }
      return m;
    }
    case 8: {
      // A rotation about an axis, then translated.
      float angle = EdgeF(r);
      float x = SaneF(r), y = SaneF(r), z = SaneF(r);
      Vector3 t = SaneV3(r);
      return Matrix::MakeTranslation(t) *
             Matrix::MakeRotation(Radians(angle), Vector4(x, y, z, 1.0f));
    }
    default: {
      // The identity with a few entries replaced.
      int n = static_cast<int>(r.Below(4));
      for (int i = 0; i < n; i++) {
        int k = static_cast<int>(r.Below(16));
        m.m[k] = r.Chance(2) ? EdgeF(r) : 0.0f;
      }
      return m;
    }
  }
}

static Quaternion GenQ(Rng& r) {
  if (r.Chance(4)) {
    float x = EdgeF(r), y = EdgeF(r), z = EdgeF(r), w = EdgeF(r);
    return Quaternion(x, y, z, w);
  }
  Vector3 axis = SaneV3(r);
  float angle = SaneF(r);
  return Quaternion(axis.Normalize(), angle);
}

static void SuiteMatrix(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    Matrix a = GenM(r);
    Matrix b = GenM(r);
    Vector3 v3 = r.Chance(3) ? EdgeV3(r) : SaneV3(r);
    Vector4 v4 = EdgeV4(r);
    Point p = r.Chance(3) ? EdgeP(r) : SaneP(r);
    float s = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float tol = r.Chance(2) ? kEhCloseEnough : SaneF(r);

    Tag("mx_ops");
    M(a);
    M(b);
    V3(v3);
    V4(v4);
    P(p);
    Arrow();
    M(a.Basis());
    M(a.To3x3());
    M(a.Translate(v3));
    M(a.Scale(v3));
    M(a.Multiply(b));
    M(a * b);
    M(a + b);
    M(a + v3);
    M(a - v3);
    M(a.Transpose());
    M(a.Invert());
    F(a.GetDeterminant());
    B(a.IsInvertible());
    V4(a * v4);
    V3(a * v3);
    P(a * p);
    V3(a.TransformHomogenous(p));
    V4(a.TransformDirection(v4));
    V3(a.TransformDirection(v3));
    P(a.TransformDirection(p));
    Quad quad = {p, Point(v3.x, v3.y), Point(v4.x, v4.y), Point(s, s)};
    Quad tq = a.Transform(quad);
    for (const auto& qp : tq) {
      P(qp);
    }
    B(a == b);
    B(a != b);
    B(a == a);
    B(a.Equals(b));
    B(a.Equals(b, tol));
    End();

    Tag("mx_query");
    M(a);
    F(tol);
    V3(v3);
    Arrow();
    F(a.GetMaxBasisLengthXY());
    OptF(a.GetMinScale2D());
    OptF(a.GetMaxScale2D());
    auto scales = a.GetScales2D();
    if (scales.has_value()) {
      F(scales->first);
      F(scales->second);
    } else {
      S("none");
    }
    V3(a.GetBasisX());
    V3(a.GetBasisY());
    V3(a.GetBasisZ());
    V3(a.GetScale());
    P(a.GetBasisX2D());
    P(a.GetBasisY2D());
    P(a.GetBasisScaleXY());
    P(a.GetTransformedPixelSize());
    F(a.GetDirectionScale(v3));
    B(a.IsFinite());
    B(a.IsAffine());
    B(a.HasPerspective2D());
    B(a.HasPerspective());
    B(a.HasTranslation());
    B(a.IsAligned2D());
    B(a.IsAligned2D(tol));
    B(a.IsAligned());
    B(a.IsAligned(tol));
    B(a.IsIdentity());
    B(a.IsTranslationOnly());
    B(a.IsTranslationScaleOnly());
    End();

    Tag("mx_decompose");
    M(a);
    Arrow();
    auto d = a.Decompose();
    if (d.has_value()) {
      Decomp(*d);
      M(Matrix(*d));
    } else {
      S("none");
    }
    End();

    // A random decomposition, recomposed.
    MatrixDecomposition rd;
    rd.translation = SaneV3(r);
    rd.scale = SaneV3(r);
    {
      double xy = r.Chance(2) ? 0.0 : (r.Unit() - 0.5);
      double xz = r.Chance(2) ? 0.0 : (r.Unit() - 0.5);
      double yz = r.Chance(2) ? 0.0 : (r.Unit() - 0.5);
      rd.shear = Shear(xy, xz, yz);
    }
    if (r.Chance(2)) {
      float px = SaneF(r) * 0.01f, py = SaneF(r) * 0.01f, pz = SaneF(r) * 0.01f;
      rd.perspective = Vector4(px, py, pz, 1.0f);
    }
    rd.rotation = GenQ(r);
    Tag("mx_recompose");
    Decomp(rd);
    Arrow();
    M(Matrix(rd));
    U(MatrixDecomposition().GetComponentsMask());
    B(Shear(rd.shear.xy, 0, 0) == rd.shear);
    End();

    float f[16];
    for (int i = 0; i < 16; i++) {
      f[i] = EdgeF(r);
    }
    Quaternion q = GenQ(r);
    Quaternion q2 = GenQ(r);
    float angle = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float sx = SaneF(r), sy = SaneF(r);
    Vector3 eye = SaneV3(r);
    Vector3 target = SaneV3(r);
    Vector3 up = SaneV3(r);
    float fov = SaneF(r), aspect = SaneF(r), znear = SaneF(r), zfar = SaneF(r);
    Size osz = EdgeS(r);
    ISize iosz = {EdgeI(r, 64), EdgeI(r, 64)};
    double t = r.Chance(4) ? EdgeD(r) : r.Unit();
    Tag("mx_make");
    for (int i = 0; i < 16; i++) {
      F(f[i]);
    }
    Q(q);
    Q(q2);
    F(angle);
    Arrow();
    M(Matrix::MakeColumn(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8],
                         f[9], f[10], f[11], f[12], f[13], f[14], f[15]));
    M(Matrix::MakeRow(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8],
                      f[9], f[10], f[11], f[12], f[13], f[14], f[15]));
    M(Matrix::MakeTranslation(v3));
    M(Matrix::MakeScale(v3));
    M(Matrix::MakeTranslateScale(v3, Vector3(f[0], f[1], f[2])));
    M(Matrix::MakeScale(Vector2(f[3], f[4])));
    M(Matrix::MakeSkew(sx, sy));
    M(Matrix::MakeRotation(q));
    M(Matrix::MakeRotation(Radians(angle), v4));
    M(Matrix::MakeRotationX(Radians(angle)));
    M(Matrix::MakeRotationY(Radians(angle)));
    M(Matrix::MakeRotationZ(Radians(angle)));
    P(Matrix::CosSin(Radians(angle)));
    M(Matrix::MakeOrthographic(osz));
    M(Matrix::MakeOrthographic(iosz));
    M(Matrix::MakePerspective(Radians(fov), aspect, znear, zfar));
    M(Matrix::MakePerspective(Radians(fov), osz, znear, zfar));
    M(Matrix::MakePerspective(Radians(fov), iosz, znear, zfar));
    M(Matrix::MakeLookAt(eye, target, up));
    M(Matrix());
    End();

    Tag("quaternion");
    Q(q);
    Q(q2);
    V3(v3);
    F(s);
    D(t);
    Arrow();
    F(q.Dot(q2));
    F(q.Length());
    Q(q.Normalize());
    Q(q.Invert());
    Q(q.Slerp(q2, t));
    Q(q * q2);
    Q(q * s);
    V3(q * v3);
    Q(q + q2);
    Q(q - q2);
    B(q == q2);
    B(q != q2);
    B(q == q);
    Q(Quaternion());
    Q(Quaternion(v3, s));
    End();
  }
}

// ------------------------------------------------------------------ rect ---

static Rect GenR(Rng& r) {
  switch (r.Below(6)) {
    case 0: {
      float l = EdgeF(r), t = EdgeF(r), rr = EdgeF(r), b = EdgeF(r);
      return Rect::MakeLTRB(l, t, rr, b);
    }
    case 1: {
      float x = SaneF(r), y = SaneF(r), w = SaneF(r), h = SaneF(r);
      return Rect::MakeXYWH(x, y, w, h);
    }
    case 2: {
      // Shares edges with a sane rect: integers in a small range.
      float l = static_cast<float>(r.Below(11)) - 5.0f;
      float t = static_cast<float>(r.Below(11)) - 5.0f;
      float rr = static_cast<float>(r.Below(11)) - 5.0f;
      float b = static_cast<float>(r.Below(11)) - 5.0f;
      return Rect::MakeLTRB(l, t, rr, b);
    }
    case 3:
      return Rect::MakeMaximum();
    default: {
      float l = SaneF(r), t = SaneF(r);
      float w = static_cast<float>(r.Unit() * 100.0);
      float h = static_cast<float>(r.Unit() * 100.0);
      return Rect::MakeXYWH(l, t, w, h);
    }
  }
}

template <class T>
static TRect<T> GenIR(Rng& r, int bits) {
  switch (r.Below(4)) {
    case 0: {
      T l = static_cast<T>(EdgeI(r, bits));
      T t = static_cast<T>(EdgeI(r, bits));
      T rr = static_cast<T>(EdgeI(r, bits));
      T b = static_cast<T>(EdgeI(r, bits));
      return TRect<T>::MakeLTRB(l, t, rr, b);
    }
    case 1: {
      T x = static_cast<T>(EdgeI(r, bits));
      T y = static_cast<T>(EdgeI(r, bits));
      T w = static_cast<T>(EdgeI(r, bits));
      T h = static_cast<T>(EdgeI(r, bits));
      return TRect<T>::MakeXYWH(x, y, w, h);
    }
    case 2: {
      T l = static_cast<T>(r.Below(11)) - 5;
      T t = static_cast<T>(r.Below(11)) - 5;
      T rr = static_cast<T>(r.Below(11)) - 5;
      T b = static_cast<T>(r.Below(11)) - 5;
      return TRect<T>::MakeLTRB(l, t, rr, b);
    }
    default:
      return TRect<T>::MakeMaximum();
  }
}

static void R(const Rect& r) {
  F(r.GetLeft());
  F(r.GetTop());
  F(r.GetRight());
  F(r.GetBottom());
}
template <class T>
static void IR(const TRect<T>& r) {
  I(r.GetLeft());
  I(r.GetTop());
  I(r.GetRight());
  I(r.GetBottom());
}
static void OptR(const std::optional<Rect>& r) {
  if (r.has_value()) {
    R(*r);
  } else {
    S("none");
  }
}
template <class T>
static void OptIR(const std::optional<TRect<T>>& r) {
  if (r.has_value()) {
    IR(*r);
  } else {
    S("none");
  }
}

// A float without NaN (rounding a NaN to an integer type is undefined).
static float NoNaN(float v) {
  return std::isnan(v) ? 0.0f : v;
}

template <class T>
static void IntRects(Rng& r, int bits, const char* tag, const Rect& fr) {
  TRect<T> a = GenIR<T>(r, bits);
  TRect<T> b = GenIR<T>(r, bits);
  T dx = static_cast<T>(EdgeI(r, bits));
  T dy = static_cast<T>(EdgeI(r, bits));
  T px = static_cast<T>(EdgeI(r, bits));
  T py = static_cast<T>(EdgeI(r, bits));
  T sc = static_cast<T>(EdgeI(r, bits));
  Rect nr = Rect::MakeLTRB(NoNaN(fr.GetLeft()), NoNaN(fr.GetTop()),
                           NoNaN(fr.GetRight()), NoNaN(fr.GetBottom()));
  Tag(tag);
  IR(a);
  IR(b);
  I(dx);
  I(dy);
  I(px);
  I(py);
  I(sc);
  R(nr);
  Arrow();
  B(a == b);
  B(a.IsEmpty());
  B(a.IsSquare());
  B(a.IsMaximum());
  IP(a.GetOrigin());
  ISZ(a.GetSize());
  I(a.GetX());
  I(a.GetY());
  I(a.GetWidth());
  I(a.GetHeight());
  IP(a.GetLeftTop());
  IP(a.GetRightTop());
  IP(a.GetLeftBottom());
  IP(a.GetRightBottom());
  I(a.Area());
  P(a.GetCenter());
  for (T v : a.GetXYWH()) {
    I(v);
  }
  IR(a.GetPositive());
  for (const auto& p : a.GetPoints()) {
    IP(p);
  }
  IR(a.Scale(sc));
  IR(a.Scale(dx, dy));
  IR(a.Scale(TPoint<T>(dx, dy)));
  IR(a.Scale(TSize<T>(dx, dy)));
  B(a.Contains(TPoint<T>(px, py)));
  B(a.ContainsInclusive(TPoint<T>(px, py)));
  B(a.Contains(b));
  IR(a.Union(b));
  OptIR(a.Intersection(b));
  IR(a.IntersectionOrEmpty(b));
  B(a.IntersectsWithRect(b));
  OptIR(a.Cutout(b));
  IR(a.CutoutOrEmpty(b));
  IR(a.Shift(dx, dy));
  IR(a.Shift(TPoint<T>(dx, dy)));
  IR(a.Expand(dx, dy, px, py));
  IR(a.Expand(dx));
  IR(a.Expand(dx, dy));
  IR(a.Expand(TPoint<T>(dx, dy)));
  IR(a.Expand(TSize<T>(px, py)));
  IR(a.Project(b));
  IR(TRect<T>::MakeXYWH(dx, dy, px, py));
  IR(TRect<T>::MakeWH(dx, dy));
  IR(TRect<T>::MakeOriginSize(TPoint<T>(dx, dy), TSize<T>(px, py)));
  IR(TRect<T>::MakeSize(TSize<T>(px, py)));
  IR(TRect<T>::MakeCircleBounds(TPoint<T>(dx, dy), sc));
  IR(TRect<T>::MakeEllipseBounds(TPoint<T>(dx, dy), TSize<T>(px, py)));
  IR(TRect<T>::MakeEllipseBounds(TPoint<T>(dx, dy), TPoint<T>(px, py)));
  IR(TRect<T>::MakeMaximum());
  IR(TRect<T>());
  IR(TRect<T>::RoundOut(nr));
  IR(TRect<T>::RoundIn(nr));
  IR(TRect<T>::Round(nr));
  R(Rect::Make(a));
  B(nr.Contains(a));
  std::vector<TPoint<T>> pts;
  int n = static_cast<int>(r.Below(6));
  for (int i = 0; i < n; i++) {
    T x = static_cast<T>(EdgeI(r, bits));
    T y = static_cast<T>(EdgeI(r, bits));
    pts.push_back({x, y});
  }
  OptIR(TRect<T>::MakePointBounds(pts.begin(), pts.end()));
  End();
}

static void SuiteRect(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    Rect a = GenR(r);
    Rect b = GenR(r);
    float dx = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float dy = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float px = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float py = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float sc = r.Chance(3) ? EdgeF(r) : SaneF(r);
    Size sz = EdgeS(r);
    ISize isz = {EdgeI(r, 64), EdgeI(r, 64)};

    Tag("rect");
    R(a);
    R(b);
    F(dx);
    F(dy);
    F(px);
    F(py);
    F(sc);
    SZ(sz);
    ISZ(isz);
    Arrow();
    B(a == b);
    B(a == a);
    B(a.IsFinite());
    B(a.IsEmpty());
    B(a.IsSquare());
    B(a.IsMaximum());
    P(a.GetOrigin());
    SZ(a.GetSize());
    F(a.GetX());
    F(a.GetY());
    F(a.GetWidth());
    F(a.GetHeight());
    P(a.GetLeftTop());
    P(a.GetRightTop());
    P(a.GetLeftBottom());
    P(a.GetRightBottom());
    F(a.Area());
    P(a.GetCenter());
    for (float v : a.GetLTRB()) {
      F(v);
    }
    for (float v : a.GetXYWH()) {
      F(v);
    }
    R(a.GetPositive());
    for (const auto& p : a.GetPoints()) {
      P(p);
    }
    R(a.Scale(sc));
    R(a.Scale(dx, dy));
    R(a.Scale(Point(dx, dy)));
    R(a.Scale(Size(px, py)));
    B(a.Contains(Point(px, py)));
    B(a.ContainsInclusive(Point(px, py)));
    B(a.Contains(b));
    R(a.Union(b));
    OptR(a.Intersection(b));
    R(a.IntersectionOrEmpty(b));
    B(a.IntersectsWithRect(b));
    OptR(a.Cutout(b));
    R(a.CutoutOrEmpty(b));
    R(a.Shift(dx, dy));
    R(a.Shift(Point(dx, dy)));
    R(a.Expand(dx, dy, px, py));
    R(a.Expand(dx));
    R(a.Expand(dx, dy));
    R(a.Expand(Point(dx, dy)));
    R(a.Expand(Size(px, py)));
    R(a.Project(b));
    R(Rect::MakeXYWH(dx, dy, px, py));
    R(Rect::MakeWH(dx, dy));
    R(Rect::MakeOriginSize(Point(dx, dy), Size(px, py)));
    R(Rect::MakeSize(sz));
    R(Rect::MakeSize(isz));
    R(Rect::MakeCircleBounds(Point(dx, dy), sc));
    R(Rect::MakeEllipseBounds(Point(dx, dy), Size(px, py)));
    R(Rect::MakeEllipseBounds(Point(dx, dy), Point(px, py)));
    R(Rect::MakeMaximum());
    R(Rect());
    R(Rect::RoundOut(a));
    R(Rect::RoundIn(a));
    R(Rect::Round(a));
    R(Rect::Make(a));
    std::optional<Rect> oa = r.Chance(3) ? std::nullopt : std::optional<Rect>(a);
    std::optional<Rect> ob = r.Chance(3) ? std::nullopt : std::optional<Rect>(b);
    R(Rect::Union(a, ob));
    R(Rect::Union(oa, b));
    OptR(Rect::Union(oa, ob));
    OptR(Rect::Intersection(a, ob));
    OptR(Rect::Intersection(oa, b));
    OptR(Rect::Intersection(oa, ob));
    std::vector<Point> pts;
    int n = static_cast<int>(r.Below(6));
    for (int i = 0; i < n; i++) {
      pts.push_back(r.Chance(4) ? EdgeP(r) : SaneP(r));
    }
    OptR(Rect::MakePointBounds(pts.begin(), pts.end()));
    OptR(Rect::MakePointBounds(pts));
    End();

    Matrix m = GenM(r);
    float mw = r.Chance(4) ? EdgeF(r) : static_cast<float>(r.Unit() * 20.0);
    float mh = r.Chance(4) ? EdgeF(r) : static_cast<float>(r.Unit() * 20.0);
    Tag("rect_xform");
    R(a);
    M(m);
    F(mw);
    F(mh);
    Arrow();
    for (const auto& p : a.GetTransformedPoints(m)) {
      P(p);
    }
    R(a.TransformBounds(m));
    R(a.TransformAndClipBounds(m));
    M(a.GetNormalizingTransform());
    OptR(a.ExpandToMinTransformedSize(Size(mw, mh), m));
    End();

    IntRects<int64_t>(r, 64, "irect64", a);
    IntRects<int32_t>(r, 32, "irect32", b);
  }
}

// ------------------------------------------------------------------ misc ---

static void SuiteMisc(Rng& r, int cases) {
  for (int c = 0; c < cases; c++) {
    float angle = r.Chance(3) ? EdgeF(r) : SaneF(r);
    double tc = EdgeD(r);
    double ts = EdgeD(r);
    Point v = r.Chance(3) ? EdgeP(r) : SaneP(r);
    double rad = EdgeD(r);
    Size sz = EdgeS(r);
    Tag("trig");
    F(angle);
    D(tc);
    D(ts);
    P(v);
    D(rad);
    SZ(sz);
    Arrow();
    Trig t(Radians{angle});
    D(t.cos);
    D(t.sin);
    P(t * v);
    P(t * rad);
    P(t * sz);
    Trig n = -t;
    D(n.cos);
    D(n.sin);
    Trig u(tc, ts);
    P(u * v);
    P(u * rad);
    P(u * sz);
    End();

    float sg = EdgeF(r);
    Tag("sigma");
    F(sg);
    Arrow();
    F(Radius(Sigma(sg)).radius);
    F(Sigma(Radius(sg)).sigma);
    F(Sigma().sigma);
    F(Radius().radius);
    F(kKernelRadiusPerSigma);
    End();

    Point d0 = r.Chance(3) ? EdgeP(r) : SaneP(r);
    Point d1 = r.Chance(3) ? EdgeP(r) : SaneP(r);
    float mag = EdgeF(r);
    Tag("separated");
    P(d0);
    P(d1);
    F(mag);
    Arrow();
    SeparatedVector2 s0(d0);
    SeparatedVector2 s1(d1);
    SeparatedVector2 s2(d0, mag);
    SeparatedVector2 s3;
    P(s0.direction);
    F(s0.magnitude);
    P(s0.GetVector());
    P(s0.GetDirection());
    F(s0.GetAlignment(s1));
    F(s0.AngleTo(s1).radians);
    F(s0.Cross(s1));
    P(s2.GetVector());
    F(s2.GetAlignment(s0));
    P(s3.direction);
    F(s3.magnitude);
    End();

    int32_t num = static_cast<int32_t>(EdgeI(r, 32));
    uint32_t den = static_cast<uint32_t>(EdgeI(r, 32));
    int32_t num2 = r.Chance(2) ? num * static_cast<int32_t>(r.Below(5))
                               : static_cast<int32_t>(EdgeI(r, 32));
    uint32_t den2 = r.Chance(2) ? den * static_cast<uint32_t>(r.Below(5))
                                : static_cast<uint32_t>(EdgeI(r, 32));
    if (r.Chance(4)) {
      num = static_cast<int32_t>(r.Below(21)) - 10;
      den = static_cast<uint32_t>(r.Below(10));
      num2 = static_cast<int32_t>(r.Below(21)) - 10;
      den2 = static_cast<uint32_t>(r.Below(10));
    }
    Rational ra(num, den);
    Rational rb(num2, den2);
    Tag("rational");
    I(num);
    U(den);
    I(num2);
    U(den2);
    Arrow();
    I(ra.GetNumerator());
    U(ra.GetDenominator());
    B(ra == rb);
    B(ra < rb);
    B(rb < ra);
    U(ra.GetHash());
    F(static_cast<Scalar>(ra));
    Rational inv = ra.Invert();
    I(inv.GetNumerator());
    U(inv.GetDenominator());
    Rational one(num);
    U(one.GetDenominator());
    End();

    Point origin = r.Chance(3) ? EdgeP(r) : SaneP(r);
    float scale = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float w = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float h = r.Chance(3) ? EdgeF(r) : SaneF(r);
    float c0 = EdgeF(r), c1 = EdgeF(r);
    Tag("rstransform");
    P(origin);
    F(scale);
    F(angle);
    F(w);
    F(h);
    F(c0);
    F(c1);
    Arrow();
    RSTransform rst = RSTransform::Make(origin, scale, Radians{angle});
    F(rst.scaled_cos);
    F(rst.scaled_sin);
    F(rst.translate_x);
    F(rst.translate_y);
    B(rst.IsAxisAligned());
    M(rst.GetMatrix());
    for (const auto& p : rst.GetQuad(w, h)) {
      P(p);
    }
    for (const auto& p : rst.GetQuad(Size(h, w))) {
      P(p);
    }
    OptR(rst.GetBounds(w, h));
    OptR(rst.GetBounds(Size(h, w)));
    RSTransform raw(c0, c1, w, h);
    B(raw.IsAxisAligned());
    M(raw.GetMatrix());
    OptR(raw.GetBounds(scale, scale));
    RSTransform def;
    F(def.scaled_cos);
    F(def.scaled_sin);
    End();

    Point p0 = r.Chance(4) ? EdgeP(r) : SaneP(r);
    Point p1 = r.Chance(4) ? EdgeP(r) : SaneP(r);
    Point p2 = r.Chance(4) ? EdgeP(r) : SaneP(r);
    Point p3 = r.Chance(4) ? EdgeP(r) : SaneP(r);
    float sf = r.Chance(4) ? EdgeF(r) : static_cast<float>(r.Unit() * 4.0);
    float cw = r.Chance(4) ? EdgeF(r) : static_cast<float>(r.Unit() * 2.0);
    Tag("wangs");
    P(p0);
    P(p1);
    P(p2);
    P(p3);
    F(sf);
    F(cw);
    Arrow();
    F(ComputeCubicSubdivisions(sf, p0, p1, p2, p3));
    F(ComputeQuadradicSubdivisions(sf, p0, p1, p2));
    F(ComputeConicSubdivisions(sf, p0, p1, p2, cw));
    End();

    // Gradients: 2 to 8 colors; stops sorted, from 0 to 1 when there are
    // more than two (upstream reads past the colors otherwise).
    int nc = 2 + static_cast<int>(r.Below(7));
    std::vector<Color> colors;
    std::vector<Scalar> stops;
    for (int i = 0; i < nc; i++) {
      colors.push_back(CompC(r));
    }
    if (nc == 2 && r.Chance(2)) {
      float s0 = EdgeF(r);
      float s1 = EdgeF(r);
      stops = {s0, s1};
    } else {
      stops.push_back(0.0f);
      for (int i = 1; i < nc - 1; i++) {
        float prev = stops.back();
        float step;
        switch (r.Below(4)) {
          case 0: step = 0.0f; break;
          case 1: step = static_cast<float>(r.Unit() * 1e-3); break;
          default: step = static_cast<float>(r.Unit() * (1.0 - prev) * 0.5); break;
        }
        stops.push_back(std::min(1.0f, prev + step));
      }
      stops.push_back(1.0f);
    }
    Tag("gradient");
    for (size_t i = 0; i < colors.size(); i++) {
      C(colors[i]);
      F(stops[i]);
    }
    Arrow();
    GradientData g = CreateGradientBuffer(colors, stops);
    U(g.colors.size());
    for (const auto& col : g.colors) {
      C(col);
    }
    End();

    StrokeParameters sp;
    StrokeParameters sq{.width = w, .cap = Cap::kRound, .join = Join::kBevel,
                        .miter_limit = h};
    Tag("stroke");
    F(sp.width);
    I(static_cast<int>(sp.cap));
    I(static_cast<int>(sp.join));
    F(sp.miter_limit);
    B(sp == sq);
    B(sq == sq);
    End();
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
    {"point", SuitePoint},
    {"size", SuiteSize},
    {"vector", SuiteVector},
    {"color", SuiteColor},
    {"matrix", SuiteMatrix},
    {"rect", SuiteRect},
    {"misc", SuiteMisc},
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

// Not an upstream file: the oracle driver for the Rust port of flutter/fml.
//
// Links the upstream C++ (the files named in ../README.md) and prints what it
// does on seeded random inputs. src/bin/fml_dump.rs is the same program over
// the port; the two outputs must be byte-identical.
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues loop merger thread
//                                              logging file mapping paths
//                                              cmdline misc affinity native
//                                              trace backtrace all
//   fml_dump bench <name> <iterations>  name: queues time strings hash
//                                              dispatch loop thread concurrent
//                                              merger file mapping paths
//                                              cmdline trace
//   fml_dump fatal <seed> 0             (internal) the logging suite's child,
//                                       which logs at FATAL and dies
//   fml_dump crash <signal> 0           (internal) the backtrace suite's
//                                       child, which installs the crash
//                                       handler and raises <signal>
//
// Both drivers draw every input from the same splitmix64 stream, so a suite's
// output is a function of (suite, seed, cases) alone.

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <csignal>
#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <condition_variable>
#include <cstring>
#include <filesystem>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <pthread.h>
#include <sys/wait.h>
#include <unistd.h>

#include "flutter/fml/ascii_trie.h"
#include "flutter/fml/backtrace.h"
#include "flutter/fml/base32.h"
#include "flutter/fml/command_line.h"
#include "flutter/fml/container.h"
#include "flutter/fml/cpu_affinity.h"
#include "flutter/fml/concurrent_message_loop.h"
#include "flutter/fml/endianness.h"
#include "flutter/fml/file.h"
#include "flutter/fml/hash_combine.h"
#include "flutter/fml/hex_codec.h"
#include "flutter/fml/log_settings.h"
#include "flutter/fml/logging.h"
#include "flutter/fml/mapping.h"
#include "flutter/fml/memory/task_runner_checker.h"
#include "flutter/fml/message_loop.h"
#include "flutter/fml/message_loop_task_queues.h"
#include "flutter/fml/native_library.h"
#include "flutter/fml/paths.h"
#include "flutter/fml/posix_wrappers.h"
#include "flutter/fml/process.h"
#include "flutter/fml/raster_thread_merger.h"
#include "flutter/fml/safe_math.h"
#include "flutter/fml/string_conversion.h"
#include "flutter/fml/synchronization/count_down_latch.h"
#include "flutter/fml/synchronization/waitable_event.h"
#include "flutter/fml/task_runner.h"
#include "flutter/fml/task_runner_util.h"
#include "flutter/fml/thread.h"
#include "flutter/fml/time/time_delta.h"
#include "flutter/fml/time/time_point.h"
#include "flutter/fml/trace_event.h"

namespace {

// ---------------------------------------------------------------- rng ------

// ------------------------------------------------------- bench clock ------
//
// In bench mode the suites run against a stopwatch that only the ported code
// should run under (src/bin/fml_dump.rs mirrors this): output is not
// formatted at all (g_quiet: the QPRINTF family does not even evaluate its
// arguments), the random stream is read from a tape that is refilled with
// the clock stopped, and the driver's own set-up (input generators, threads
// it spawns) pauses the clock. Pauses nest.

bool g_quiet = false;
#define QPRINTF(...) (g_quiet ? 0 : std::printf(__VA_ARGS__))
#define QFPUTS(...) (g_quiet ? 0 : std::fputs(__VA_ARGS__))
#define QFPUTC(...) (g_quiet ? 0 : std::fputc(__VA_ARGS__))

std::atomic<size_t> g_sw_depth{1};
std::atomic<uint64_t> g_sw_total_ns{0};
std::atomic<uint64_t> g_sw_start_ns{0};

uint64_t SwNowNs() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

void SwReset() {
  g_sw_depth.store(1, std::memory_order_relaxed);
  g_sw_total_ns.store(0, std::memory_order_relaxed);
}

// Stops the clock (it may already be stopped; pauses nest).
void SwPause() {
  if (g_sw_depth.load(std::memory_order_relaxed) == 0) {
    uint64_t elapsed = SwNowNs() - g_sw_start_ns.load(std::memory_order_relaxed);
    g_sw_total_ns.store(g_sw_total_ns.load(std::memory_order_relaxed) + elapsed,
                        std::memory_order_relaxed);
  }
  g_sw_depth.store(g_sw_depth.load(std::memory_order_relaxed) + 1,
                   std::memory_order_relaxed);
}

// Undoes one SwPause; the clock runs again when none is left.
void SwResume() {
  size_t depth = g_sw_depth.load(std::memory_order_relaxed) - 1;
  g_sw_depth.store(depth, std::memory_order_relaxed);
  if (depth == 0) {
    g_sw_start_ns.store(SwNowNs(), std::memory_order_relaxed);
  }
}

uint64_t SplitMix(uint64_t& s) {
  uint64_t z = (s += 0x9e3779b97f4a7c15ULL);
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
  return z ^ (z >> 31);
}

constexpr size_t kTapeLen = 4096;
bool g_tape_on = false;
uint64_t g_tape[kTapeLen];
size_t g_tape_pos = kTapeLen;
uint64_t g_tape_seed = 0;
// Draws taken from the tape this round, reported to check that both drivers
// took the same path.
uint64_t g_tape_draws = 0;

void TapeStart(uint64_t seed) {
  g_tape_seed = seed;
  g_tape_pos = kTapeLen;
  g_tape_draws = 0;
  g_tape_on = true;
}

[[gnu::cold, gnu::noinline]] void TapeRefill() {
  SwPause();
  for (auto& slot : g_tape) {
    slot = SplitMix(g_tape_seed);
  }
  g_tape_pos = 0;
  g_tape_draws += kTapeLen;
  SwResume();
}

uint64_t TapeNext() {
  if (g_tape_pos == kTapeLen) {
    TapeRefill();
  }
  return g_tape[g_tape_pos++];
}

uint64_t TapeUsed() {
  return g_tape_draws - (kTapeLen - g_tape_pos);
}

struct Rng {
  uint64_t s;
  uint64_t Next() {
    if (g_tape_on) {
      return TapeNext();
    }
    return SplitMix(s);
  }
  uint64_t Below(uint64_t n) { return Next() % n; }
  bool Chance(uint64_t one_in) { return Below(one_in) == 0; }
};

constexpr int64_t kI64Min = std::numeric_limits<int64_t>::min();
constexpr int64_t kI64Max = std::numeric_limits<int64_t>::max();

int64_t EdgeI64(Rng& r) {
  switch (r.Below(12)) {
    case 0: return 0;
    case 1: return 1;
    case 2: return -1;
    case 3: return kI64Min;
    case 4: return kI64Max;
    case 5: return kI64Min + 1;
    case 6: return kI64Max - 1;
    case 7: return 1000000000;
    case 8: return static_cast<int64_t>(r.Below(2001)) - 1000;
    case 9: return static_cast<int64_t>(r.Below(20000000001ULL)) - 10000000000LL;
    case 10: return kI64Max / 1000 + static_cast<int64_t>(r.Below(3)) - 1;
    default: return static_cast<int64_t>(r.Next());
  }
}

// A double in [-bound, bound] built from 53 random bits, or a fixed edge.
double BoundedF64(Rng& r, double bound) {
  switch (r.Below(8)) {
    case 0: return 0.0;
    case 1: return -0.0;
    case 2: return 0.5;
    case 3: return -1e-9;
    default: {
      double unit = static_cast<double>(r.Next() >> 11) / 9007199254740992.0;
      double v = unit * bound;
      return r.Chance(2) ? -v : v;
    }
  }
}

uint64_t Bits(double d) {
  uint64_t b;
  std::memcpy(&b, &d, sizeof b);
  return b;
}

void PrintHex(const std::string& s) {
  if (g_quiet) {
    return;
  }
  if (s.empty()) {
    QFPUTS("-", stdout);
    return;
  }
  for (unsigned char c : s) {
    QPRINTF("%02x", c);
  }
}

void PrintHex16(const std::u16string& s) {
  if (g_quiet) {
    return;
  }
  if (s.empty()) {
    QFPUTS("-", stdout);
    return;
  }
  for (char16_t c : s) {
    QPRINTF("%04x", static_cast<unsigned>(c));
  }
}

int Cmp(auto a, auto b) {
  auto c = a <=> b;
  return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

// --------------------------------------------------------------- time ------

void SuiteTime(Rng& r, int cases) {
  using fml::TimeDelta;
  using fml::TimePoint;
  QPRINTF("frame_budget %016" PRIx64 "\n",
              Bits(fml::kDefaultFrameBudget.count()));
  for (int i = 0; i < cases; i++) {
    int64_t a = EdgeI64(r);
    int64_t b = EdgeI64(r);
    QPRINTF("case %d a=%" PRId64 " b=%" PRId64 "\n", i, a, b);
    QPRINTF("from %" PRId64 " %" PRId64 " %" PRId64 " %" PRId64 "\n",
                TimeDelta::FromNanoseconds(a).ToNanoseconds(),
                TimeDelta::FromMicroseconds(a).ToNanoseconds(),
                TimeDelta::FromMilliseconds(a).ToNanoseconds(),
                TimeDelta::FromSeconds(a).ToNanoseconds());
    TimeDelta da = TimeDelta::FromNanoseconds(a);
    TimeDelta db = TimeDelta::FromNanoseconds(b);
    QPRINTF("to %" PRId64 " %" PRId64 " %" PRId64 "\n",
                da.ToMicroseconds(), da.ToMilliseconds(), da.ToSeconds());
    QPRINTF("tof %016" PRIx64 " %016" PRIx64 " %016" PRIx64
                " %016" PRIx64 "\n",
                Bits(da.ToNanosecondsF()), Bits(da.ToMicrosecondsF()),
                Bits(da.ToMillisecondsF()), Bits(da.ToSecondsF()));
    QPRINTF("add %" PRId64 " sub %" PRId64 " mul %" PRId64 "\n",
                (da + db).ToNanoseconds(), (da - db).ToNanoseconds(),
                (da * b).ToNanoseconds());
    if (b != 0 && !(a == kI64Min && b == -1)) {
      QPRINTF("div %" PRId64 " divd %" PRId64 " mod %" PRId64 "\n",
                  (da / b).ToNanoseconds(), da / db, (da % db).ToNanoseconds());
    } else {
      QPRINTF("div skip\n");
    }
    QPRINTF("cmp %d %d %d %d\n", Cmp(da, db), da == db ? 1 : 0,
                da < db ? 1 : 0, da >= db ? 1 : 0);
    struct timespec ts{};
    ts.tv_sec = static_cast<time_t>(a);
    ts.tv_nsec = static_cast<long>(b % 1000000000);
    QPRINTF("fromts %" PRId64 "\n",
                TimeDelta::FromTimespec(ts).ToNanoseconds());
    struct timespec out = da.ToTimespec();
    QPRINTF("tots %" PRId64 " %" PRId64 "\n",
                static_cast<int64_t>(out.tv_sec),
                static_cast<int64_t>(out.tv_nsec));
    TimePoint pa = TimePoint::FromTicks(a);
    TimePoint pb = TimePoint::FromEpochDelta(db);
    QPRINTF("tp %" PRId64 " %" PRId64 " %" PRId64 " %d\n",
                (pa - pb).ToNanoseconds(),
                (pa + db).ToEpochDelta().ToNanoseconds(),
                (pa - db).ToEpochDelta().ToNanoseconds(), Cmp(pa, pb));
    double s = BoundedF64(r, 9.0e9);
    double m = BoundedF64(r, 9.0e12);
    QPRINTF("fromf %" PRId64 " %" PRId64 "\n",
                TimeDelta::FromSecondsF(s).ToNanoseconds(),
                TimeDelta::FromMillisecondsF(m).ToNanoseconds());
    int64_t hz = static_cast<int64_t>(r.Below(240)) + 1;
    double hzf = BoundedF64(r, 240.0);
    QPRINTF("budget %016" PRIx64 " %016" PRIx64 "\n",
                Bits(fml::RefreshRateToFrameBudget(hz).count()),
                Bits(fml::RefreshRateToFrameBudget(hzf).count()));
  }
  QPRINTF("minmax %" PRId64 " %" PRId64 " %" PRId64 " %" PRId64 "\n",
              TimeDelta::Min().ToNanoseconds(),
              TimeDelta::Max().ToNanoseconds(),
              TimePoint::Min().ToEpochDelta().ToNanoseconds(),
              TimePoint::Max().ToEpochDelta().ToNanoseconds());
}

// ------------------------------------------------------------ strings ------

std::u16string GenUtf16(Rng& r) {
  std::u16string s;
  int n = static_cast<int>(r.Below(13));
  for (int i = 0; i < n; i++) {
    switch (r.Below(10)) {
      case 0: s.push_back(static_cast<char16_t>(1 + r.Below(127))); break;
      case 1: s.push_back(static_cast<char16_t>(0x80 + r.Below(0xD800 - 0x80))); break;
      case 2: s.push_back(static_cast<char16_t>(0xE000 + r.Below(0x2000))); break;
      case 3: {
        uint32_t cp = 0x10000 + static_cast<uint32_t>(r.Below(0x100000));
        cp -= 0x10000;
        s.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
        s.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
        break;
      }
      case 4: if (r.Chance(4)) s.push_back(static_cast<char16_t>(0xD800 + r.Below(0x400))); break;
      case 5: if (r.Chance(4)) s.push_back(static_cast<char16_t>(0xDC00 + r.Below(0x400))); break;
      case 6: if (r.Chance(6)) s.push_back(0); break;
      case 7: {
        static const char16_t kSpecial[] = {0xFFFE, 0xFFFF, 0xFEFF, 0x7FF, 0x800, 0xD7FF, 0xE000};
        s.push_back(kSpecial[r.Below(7)]);
        break;
      }
      default: s.push_back(static_cast<char16_t>('a' + r.Below(26))); break;
    }
  }
  return s;
}

void PushUtf8(std::string& s, uint32_t cp) {
  if (cp < 0x80) {
    s.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    s.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    s.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    s.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    s.push_back(static_cast<char>(0xF0 | (cp >> 18)));
    s.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
    s.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

std::string GenUtf8(Rng& r) {
  std::string s;
  int n = static_cast<int>(r.Below(10));
  for (int i = 0; i < n; i++) {
    switch (r.Below(14)) {
      case 0: PushUtf8(s, 1 + static_cast<uint32_t>(r.Below(127))); break;
      case 1: PushUtf8(s, 0x80 + static_cast<uint32_t>(r.Below(0x780))); break;
      case 2: PushUtf8(s, 0x800 + static_cast<uint32_t>(r.Below(0xD000))); break;
      case 3: PushUtf8(s, 0xE000 + static_cast<uint32_t>(r.Below(0x2000))); break;
      case 4: PushUtf8(s, 0x10000 + static_cast<uint32_t>(r.Below(0x100000))); break;
      case 5: if (r.Chance(3)) s.push_back(static_cast<char>(r.Below(256))); break;
      case 6: if (r.Chance(3)) {  // encoded surrogate
          uint32_t cp = 0xD800 + static_cast<uint32_t>(r.Below(0x800));
          PushUtf8(s, cp);
        }
        break;
      case 7: if (r.Chance(3)) {  // overlong
          static const char* kOverlong[] = {"\xC0\x80", "\xC1\xBF", "\xE0\x80\x80",
                                            "\xE0\x9F\xBF", "\xF0\x80\x80\x80",
                                            "\xF0\x8F\xBF\xBF"};
          s += kOverlong[r.Below(6)];
        }
        break;
      case 8: if (r.Chance(3)) {  // beyond U+10FFFF
          static const char* kBeyond[] = {"\xF4\x90\x80\x80", "\xF5\x80\x80\x80",
                                          "\xF7\xBF\xBF\xBF", "\xF8\x88\x80\x80\x80",
                                          "\xFF", "\xFE"};
          s += kBeyond[r.Below(6)];
        }
        break;
      case 9: if (r.Chance(3)) {  // truncated sequence
          std::string full;
          PushUtf8(full, 0x80 + static_cast<uint32_t>(r.Below(0x10FF80)));
          s += full.substr(0, 1 + r.Below(full.size() - 1));
        }
        break;
      case 10: if (r.Chance(6)) s.push_back('\0'); break;
      case 11: s += "\xEF\xBB\xBF"; break;
      default: s.push_back(static_cast<char>('a' + r.Below(26))); break;
    }
  }
  return s;
}

std::string GenBytes(Rng& r, int max_len) {
  std::string s;
  int n = static_cast<int>(r.Below(max_len + 1));
  for (int i = 0; i < n; i++) {
    s.push_back(static_cast<char>(r.Below(256)));
  }
  return s;
}

void SuiteStrings(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    std::u16string u16 = GenUtf16(r);
    QFPUTS("u16 ", stdout);
    PrintHex16(u16);
    QFPUTS(" -> ", stdout);
    try {
      PrintHex(fml::Utf16ToUtf8(u16));
    } catch (const std::range_error&) {
      QFPUTS("ERR", stdout);
    }
    QFPUTS("\n", stdout);

    std::string u8 = GenUtf8(r);
    QFPUTS("u8 ", stdout);
    PrintHex(u8);
    QFPUTS(" -> ", stdout);
    try {
      PrintHex16(fml::Utf8ToUtf16(u8));
    } catch (const std::range_error&) {
      QFPUTS("ERR", stdout);
    }
    QFPUTS("\n", stdout);

    std::vector<std::string> parts;
    int n = static_cast<int>(r.Below(5));
    for (int j = 0; j < n; j++) {
      std::string part;
      int len = static_cast<int>(r.Below(4));
      for (int k = 0; k < len; k++) {
        part.push_back(static_cast<char>('a' + r.Below(26)));
      }
      parts.push_back(part);
    }
    static const char* kDelims[] = {",", ", ", "", "--"};
    const char* delim = kDelims[r.Below(4)];
    QFPUTS("join ", stdout);
    PrintHex(fml::Join(parts, delim));
    QFPUTS("\n", stdout);

    std::string path_bytes = GenBytes(r, 8);
    QFPUTS("path ", stdout);
    PrintHex(fml::PathToUtf8(std::filesystem::path(path_bytes)));
    QFPUTS("\n", stdout);
  }
}

// -------------------------------------------------------------- codec ------

std::string GenBase32Text(Rng& r) {
  static const char kAlphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  static const char kInvalid[] = {'=', 'a', '1', '8', '0', '9', ':', '@',
                                  '[', ' ', '\x80', '\xff'};
  std::string s;
  int n = static_cast<int>(r.Below(17));
  for (int i = 0; i < n; i++) {
    if (r.Chance(25)) {
      s.push_back(kInvalid[r.Below(sizeof kInvalid)]);
    } else {
      s.push_back(kAlphabet[r.Below(32)]);
    }
  }
  return s;
}

void SuiteCodec(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    std::string bytes = GenBytes(r, 20);
    auto enc = fml::Base32Encode(bytes);
    QFPUTS("b32e ", stdout);
    PrintHex(bytes);
    QPRINTF(" -> %d ", enc.first ? 1 : 0);
    PrintHex(enc.second);
    auto round = fml::Base32Decode(enc.second);
    QPRINTF(" rt %d ", round.first ? 1 : 0);
    PrintHex(round.second);
    QFPUTS("\n", stdout);

    std::string text = GenBase32Text(r);
    auto dec = fml::Base32Decode(text);
    QFPUTS("b32d ", stdout);
    PrintHex(text);
    QPRINTF(" -> %d ", dec.first ? 1 : 0);
    PrintHex(dec.second);
    QFPUTS("\n", stdout);

    QFPUTS("hex ", stdout);
    PrintHex(fml::HexEncode(bytes));
    QFPUTS("\n", stdout);
  }
}

// --------------------------------------------------------------- hash ------

std::string GenHashString(Rng& r) {
  std::string s;
  int n;
  switch (r.Below(4)) {
    case 0: n = static_cast<int>(r.Below(17)); break;
    case 1: n = 17 + static_cast<int>(r.Below(16)); break;
    case 2: n = 33 + static_cast<int>(r.Below(32)); break;
    default: n = 65 + static_cast<int>(r.Below(200)); break;
  }
  for (int i = 0; i < n; i++) {
    if (r.Chance(8)) {
      PushUtf8(s, 0x80 + static_cast<uint32_t>(r.Below(0x700)));
    } else {
      s.push_back(static_cast<char>(' ' + r.Below(95)));
    }
  }
  return s;
}

float GenF32(Rng& r) {
  uint32_t bits;
  switch (r.Below(4)) {
    case 0: return 0.0f;
    case 1: return -0.0f;
    default: bits = static_cast<uint32_t>(r.Next()); break;
  }
  float f;
  std::memcpy(&f, &bits, sizeof f);
  return f;
}

double GenF64(Rng& r) {
  uint64_t bits;
  switch (r.Below(4)) {
    case 0: return 0.0;
    case 1: return -0.0;
    default: bits = r.Next(); break;
  }
  double d;
  std::memcpy(&d, &bits, sizeof d);
  return d;
}

void SuiteHash(Rng& r, int cases) {
  QPRINTF("empty %016zx\n", fml::HashCombine());
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    int a = static_cast<int>(r.Next());
    int64_t b = EdgeI64(r);
    uint32_t c = static_cast<uint32_t>(r.Next());
    bool d = r.Chance(2);
    std::string s = GenHashString(r);
    std::string t = GenBytes(r, 80);
    float f = GenF32(r);
    double g = GenF64(r);
    auto grade = static_cast<fml::TaskSourceGrade>(r.Below(3));
    uint8_t u8 = static_cast<uint8_t>(r.Next());
    int16_t i16 = static_cast<int16_t>(r.Next());
    char ch = static_cast<char>(r.Next());
    uint64_t u64 = r.Next();
    size_t seed = r.Next();
    QPRINTF("h1 %016zx\n", fml::HashCombine(a));
    QPRINTF("h2 %016zx\n", fml::HashCombine(b, c, d));
    QPRINTF("h3 %016zx\n", fml::HashCombine(s));
    QPRINTF("h4 %016zx\n", fml::HashCombine(t));
    QPRINTF("h5 %016zx\n", fml::HashCombine(s, a, f, g));
    QPRINTF("h6 %016zx\n", fml::HashCombine(grade, u8, i16, ch, u64));
    fml::HashCombineSeed(seed, a, s);
    QPRINTF("h7 %016zx\n", seed);
  }
}

// ------------------------------------------------------------- endian ------

void SuiteEndian(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    uint64_t x = r.Next();
    QPRINTF("x %016" PRIx64 " %02x %04x %08x %016" PRIx64 "\n", x,
                fml::ByteSwap(static_cast<uint8_t>(x)),
                fml::ByteSwap(static_cast<uint16_t>(x)),
                fml::ByteSwap(static_cast<uint32_t>(x)),
                fml::ByteSwap(static_cast<uint64_t>(x)));
    QPRINTF("s %d %d %" PRId64 "\n",
                fml::ByteSwap(static_cast<int16_t>(x)),
                fml::ByteSwap(static_cast<int32_t>(x)),
                fml::ByteSwap(static_cast<int64_t>(x)));
    QPRINTF("be %08x %016" PRIx64 " le %08x %016" PRIx64 "\n",
                fml::BigEndianToArch(static_cast<uint32_t>(x)),
                fml::BigEndianToArch(x),
                fml::LittleEndianToArch(static_cast<uint32_t>(x)),
                fml::LittleEndianToArch(x));
  }
}

// --------------------------------------------------------------- trie ------

std::string GenTrieWord(Rng& r, const char* alphabet, int alphabet_len,
                        int max_len) {
  std::string s;
  int n = static_cast<int>(r.Below(max_len + 1));
  for (int i = 0; i < n; i++) {
    s.push_back(alphabet[r.Below(alphabet_len)]);
  }
  return s;
}

void SuiteTrie(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    fml::AsciiTrie trie;
    if (!r.Chance(8)) {
      std::vector<std::string> entries;
      int n = static_cast<int>(r.Below(6));
      for (int j = 0; j < n; j++) {
        entries.push_back(GenTrieWord(r, "abc", 3, 4));
      }
      QFPUTS("fill", stdout);
      for (const auto& e : entries) {
        QPRINTF(" '%s'", e.c_str());
      }
      QFPUTS("\n", stdout);
      trie.Fill(entries);
    }
    for (int j = 0; j < 8; j++) {
      std::string q = GenTrieWord(r, "abcd", 4, 5);
      QPRINTF("q '%s' %d\n", q.c_str(), trie.Query(q.c_str()) ? 1 : 0);
    }
  }
}

// ------------------------------------------------------------- queues ------

class Recorder : public fml::Wakeable {
 public:
  explicit Recorder(size_t queue) : queue_(queue) {}
  void WakeUp(fml::TimePoint time_point) override {
    QPRINTF("  wake %zu %" PRId64 "\n", queue_,
                time_point.ToEpochDelta().ToNanoseconds());
  }

 private:
  size_t queue_;
};

fml::TimePoint GenTarget(Rng& r) {
  switch (r.Below(16)) {
    case 0: return fml::TimePoint::Max();
    case 1: return fml::TimePoint::Min();
    default: return fml::TimePoint::FromTicks(static_cast<int64_t>(r.Below(100)));
  }
}

void SuiteQueues(Rng& r, int cases) {
  auto* queues = fml::MessageLoopTaskQueues::GetInstance();
  int task_counter = 0;
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    std::vector<std::unique_ptr<Recorder>> recorders;
    std::vector<fml::TaskQueueId> live;
    std::map<size_t, size_t> subsumed_by;  // queue -> owner
    std::map<size_t, int> pauses;
    auto is_unmerged = [&](fml::TaskQueueId q) {
      return subsumed_by.find(q) == subsumed_by.end();
    };
    auto pick = [&]() { return live[r.Below(live.size())]; };
    int ops = 10 + static_cast<int>(r.Below(60));
    for (int op = 0; op < ops; op++) {
      uint64_t kind = live.empty() ? 0 : r.Below(20);
      switch (kind) {
        case 0:
        case 1: {
          if (live.size() >= 6) {
            break;
          }
          fml::TaskQueueId q = queues->CreateTaskQueue();
          live.push_back(q);
          QPRINTF("create %zu\n", static_cast<size_t>(q));
          if (r.Chance(2)) {
            recorders.push_back(std::make_unique<Recorder>(q));
            QPRINTF("wakeable %zu\n", static_cast<size_t>(q));
            queues->SetWakeable(q, recorders.back().get());
          }
          break;
        }
        case 2:
        case 3:
        case 4:
        case 5:
        case 6: {
          fml::TaskQueueId q = pick();
          fml::TimePoint t = GenTarget(r);
          auto grade = static_cast<fml::TaskSourceGrade>(r.Below(3));
          int id = task_counter++;
          QPRINTF("reg %zu task%d %" PRId64 " %d\n", static_cast<size_t>(q),
                      id, t.ToEpochDelta().ToNanoseconds(),
                      static_cast<int>(grade));
          queues->RegisterTask(
              q, [id]() { QPRINTF("  run task%d\n", id); }, t, grade);
          break;
        }
        case 7:
        case 8:
        case 9: {
          fml::TaskQueueId q = pick();
          fml::TimePoint from =
              r.Chance(8) ? fml::TimePoint::Max()
                          : fml::TimePoint::FromTicks(
                                static_cast<int64_t>(r.Below(120)));
          QPRINTF("next %zu %" PRId64 "\n", static_cast<size_t>(q),
                      from.ToEpochDelta().ToNanoseconds());
          fml::closure task = queues->GetNextTaskToRun(q, from);
          if (task) {
            task();
            QPRINTF("  grade %d\n",
                        static_cast<int>(fml::MessageLoopTaskQueues::
                                             GetCurrentTaskSourceGrade()));
          } else {
            QPRINTF("  none\n");
          }
          break;
        }
        case 10: {
          fml::TaskQueueId q = pick();
          QPRINTF("pending %zu %d %zu\n", static_cast<size_t>(q),
                      queues->HasPendingTasks(q) ? 1 : 0,
                      queues->GetNumPendingTasks(q));
          break;
        }
        case 11: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          QPRINTF("merge %zu %zu\n", static_cast<size_t>(a),
                      static_cast<size_t>(b));
          bool ok = queues->Merge(a, b);
          QPRINTF("  -> %d\n", ok ? 1 : 0);
          if (ok && a != b) {
            subsumed_by[b] = a;
          }
          break;
        }
        case 12: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          QPRINTF("unmerge %zu %zu\n", static_cast<size_t>(a),
                      static_cast<size_t>(b));
          bool ok = queues->Unmerge(a, b);
          QPRINTF("  -> %d\n", ok ? 1 : 0);
          if (ok) {
            subsumed_by.erase(b);
          }
          break;
        }
        case 13: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          QPRINTF("owns %zu %zu %d [", static_cast<size_t>(a),
                      static_cast<size_t>(b), queues->Owns(a, b) ? 1 : 0);
          for (auto s : queues->GetSubsumedTaskQueueId(a)) {
            QPRINTF(" %zu", static_cast<size_t>(s));
          }
          QPRINTF(" ]\n");
          break;
        }
        case 14: {
          fml::TaskQueueId q = pick();
          bool pause = pauses[q] == 0 || r.Chance(2);
          QPRINTF("%s %zu\n", pause ? "pause" : "resume",
                      static_cast<size_t>(q));
          if (pause) {
            pauses[q]++;
            queues->PauseSecondarySource(q);
          } else {
            pauses[q]--;
            queues->ResumeSecondarySource(q);
          }
          break;
        }
        case 15: {
          fml::TaskQueueId q = pick();
          intptr_t key = static_cast<intptr_t>(r.Below(5)) - 1;
          size_t qv = q;
          QPRINTF("observe %zu %" PRIdPTR "\n", qv, key);
          queues->AddTaskObserver(q, key, [qv, key]() {
            QPRINTF("  obs %zu %" PRIdPTR "\n", qv, key);
          });
          break;
        }
        case 16: {
          fml::TaskQueueId q = pick();
          intptr_t key = static_cast<intptr_t>(r.Below(5)) - 1;
          QPRINTF("unobserve %zu %" PRIdPTR "\n", static_cast<size_t>(q),
                      key);
          queues->RemoveTaskObserver(q, key);
          break;
        }
        case 17: {
          fml::TaskQueueId q = pick();
          QPRINTF("notify %zu\n", static_cast<size_t>(q));
          for (const auto& observer : queues->GetObserversToNotify(q)) {
            observer();
          }
          break;
        }
        case 18: {
          fml::TaskQueueId q = pick();
          if (!is_unmerged(q)) {
            break;
          }
          QPRINTF("dispose_tasks %zu\n", static_cast<size_t>(q));
          queues->DisposeTasks(q);
          break;
        }
        default: {
          fml::TaskQueueId q = pick();
          if (!is_unmerged(q)) {
            break;
          }
          QPRINTF("dispose %zu\n", static_cast<size_t>(q));
          queues->Dispose(q);
          std::vector<fml::TaskQueueId> kept;
          for (auto l : live) {
            auto it = subsumed_by.find(l);
            bool gone = l == q || (it != subsumed_by.end() && it->second == q);
            if (gone) {
              subsumed_by.erase(l);
            } else {
              kept.push_back(l);
            }
          }
          live = kept;
          break;
        }
      }
    }
    for (auto q : live) {
      if (is_unmerged(q)) {
        queues->Dispose(q);
      }
    }
  }
}

// -------------------------------------------------------------- clock ------

// A controllable clock for TimePoint::SetClockSource: every Now() returns the
// current fake time and then advances it by a step, so a loop that waits for
// a task due later spins forward to it deterministically. The trace reads
// the clock with PeekNow(), which does not advance it.
std::atomic<int64_t> g_fake_now{0};
std::atomic<int64_t> g_fake_step{1};

fml::TimePoint FakeNow() {
  return fml::TimePoint::FromTicks(g_fake_now.fetch_add(g_fake_step.load()));
}

int64_t PeekNow() {
  return g_fake_now.load();
}

// The clock starts at 100 or later and no task is posted more than 15 ticks
// in its past, so no target time is negative: TimerRearm converts the target
// to an unsigned count of nanoseconds, so a negative one arms the timer for
// the far future and the loop never wakes (unreachable on the real clock).
void SetFakeClock(int64_t now, int64_t step) {
  g_fake_now = now;
  g_fake_step = step;
  fml::TimePoint::SetClockSource(&FakeNow);
}

// --------------------------------------------------------------- loop ------

// One message loop (the platform's, MessageLoopLinux on Linux) run on a fresh
// thread per case, under the fake clock. Tasks post more tasks through every
// TaskRunner entry point, add and remove observers, move the clock, flush
// the loop re-entrantly and terminate it.
struct LoopCtx {
  Rng* r;
  int next_id = 0;
  int budget = 0;
  int64_t end = 0;
};

fml::closure MakeLoopTask(LoopCtx* c, int id);

void PostLoopTask(LoopCtx* c, const char* indent) {
  if (c->budget <= 0) {
    return;
  }
  c->budget--;
  Rng& r = *c->r;
  int id = c->next_id++;
  auto runner = fml::MessageLoop::GetCurrent().GetTaskRunner();
  switch (r.Below(7)) {
    case 0:
    case 1:
      QPRINTF("%spost t%d\n", indent, id);
      runner->PostTask(MakeLoopTask(c, id));
      break;
    case 2: {
      int64_t d = static_cast<int64_t>(r.Below(40)) - 8;
      QPRINTF("%sdelay t%d %" PRId64 "\n", indent, id, d);
      runner->PostDelayedTask(MakeLoopTask(c, id),
                              fml::TimeDelta::FromNanoseconds(d));
      break;
    }
    case 3: {
      fml::TimePoint t =
          r.Chance(12) ? fml::TimePoint::Max()
                       : fml::TimePoint::FromTicks(
                             PeekNow() + static_cast<int64_t>(r.Below(60)) -
                             15);
      QPRINTF("%sat t%d %" PRId64 "\n", indent, id,
                  t.ToEpochDelta().ToNanoseconds());
      runner->PostTaskForTime(MakeLoopTask(c, id), t);
      break;
    }
    case 4:
      QPRINTF("%snow-or-post t%d\n", indent, id);
      fml::TaskRunner::RunNowOrPostTask(runner, MakeLoopTask(c, id));
      break;
    case 5:
      QPRINTF("%snow-and-flush t%d\n", indent, id);
      fml::TaskRunner::RunNowAndFlushMessages(runner, MakeLoopTask(c, id));
      break;
    default: {
      QPRINTF("%spost-queues t%d\n", indent, id);
      fml::MessageLoopTaskQueues::GetInstance()->RegisterTask(
          fml::MessageLoop::GetCurrentTaskQueueId(), MakeLoopTask(c, id),
          fml::TimePoint::FromTicks(PeekNow()),
          static_cast<fml::TaskSourceGrade>(r.Below(3)));
      break;
    }
  }
}

void AddLoopObserver(Rng& r, const char* indent) {
  intptr_t key = static_cast<intptr_t>(r.Below(4));
  if (r.Chance(3)) {
    QPRINTF("%sunobserve %" PRIdPTR "\n", indent, key);
    fml::MessageLoop::GetCurrent().RemoveTaskObserver(key);
  } else {
    QPRINTF("%sobserve %" PRIdPTR "\n", indent, key);
    fml::MessageLoop::GetCurrent().AddTaskObserver(
        key, [key]() { QPRINTF("    obs %" PRIdPTR "\n", key); });
  }
}

fml::closure MakeLoopTask(LoopCtx* c, int id) {
  return [c, id]() {
    Rng& r = *c->r;
    auto runner = fml::MessageLoop::GetCurrent().GetTaskRunner();
    QPRINTF("  run t%d @%" PRId64 " on %d\n", id, PeekNow(),
                runner->RunsTasksOnCurrentThread() ? 1 : 0);
    switch (r.Below(12)) {
      case 0:
      case 1:
      case 2:
        PostLoopTask(c, "   ");
        break;
      case 3:
        PostLoopTask(c, "   ");
        PostLoopTask(c, "   ");
        break;
      case 4:
        AddLoopObserver(r, "   ");
        break;
      case 5: {
        int64_t jump = static_cast<int64_t>(r.Below(25));
        QPRINTF("   jump %" PRId64 "\n", jump);
        g_fake_now += jump;
        break;
      }
      case 6:
        if (r.Chance(4)) {
          QPRINTF("   nested flush\n");
          fml::MessageLoop::GetCurrent().RunExpiredTasksNow();
          QPRINTF("   nested done\n");
        }
        break;
      case 7:
        if (r.Chance(6)) {
          QPRINTF("   terminate\n");
          fml::MessageLoop::GetCurrent().Terminate();
        }
        break;
      case 8:
        QPRINTF("   pending %zu\n",
                    fml::MessageLoopTaskQueues::GetInstance()
                        ->GetNumPendingTasks(runner->GetTaskQueueId()));
        break;
      default:
        break;
    }
  };
}

void LoopCase(Rng& r, int i) {
  SetFakeClock(100 + static_cast<int64_t>(r.Below(50)),
               1 + static_cast<int64_t>(r.Below(4)));
  LoopCtx c;
  c.r = &r;
  c.budget = 10 + static_cast<int>(r.Below(40));
  QPRINTF("case %d now %" PRId64 " step %" PRId64 " budget %d\n", i,
              PeekNow(), g_fake_step.load(), c.budget);
  fml::MessageLoop::EnsureInitializedForCurrentThread();
  auto& loop = fml::MessageLoop::GetCurrent();
  auto runner = loop.GetTaskRunner();
  QPRINTF("init %d %d\n",
              fml::MessageLoop::IsInitializedForCurrentThread() ? 1 : 0,
              runner->RunsTasksOnCurrentThread() ? 1 : 0);
  int setup = 1 + static_cast<int>(r.Below(8));
  for (int s = 0; s < setup; s++) {
    switch (r.Below(6)) {
      case 0:
        AddLoopObserver(r, "");
        break;
      case 1:
        QPRINTF("poll @%" PRId64 "\n", PeekNow());
        loop.RunExpiredTasksNow();
        break;
      default:
        PostLoopTask(&c, "");
        break;
    }
  }
  int64_t end = PeekNow() + 20 + static_cast<int64_t>(r.Below(150));
  QPRINTF("end at %" PRId64 "\n", end);
  runner->PostTaskForTime(
      [end]() {
        QPRINTF("  end @%" PRId64 "\n", PeekNow());
        fml::MessageLoop::GetCurrent().Terminate();
      },
      fml::TimePoint::FromTicks(end));
  loop.Run();
  QPRINTF("ran @%" PRId64 " pending %zu\n", PeekNow(),
              fml::MessageLoopTaskQueues::GetInstance()->GetNumPendingTasks(
                  runner->GetTaskQueueId()));
  runner->PostTask([]() { QPRINTF("  never\n"); });
  QPRINTF("after terminate pending %zu\n",
              fml::MessageLoopTaskQueues::GetInstance()->GetNumPendingTasks(
                  runner->GetTaskQueueId()));
  loop.RunExpiredTasksNow();
}

void SuiteLoop(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    std::thread thread([&r, i]() { LoopCase(r, i); });
    thread.join();
  }
  fml::TimePoint::SetClockSource(nullptr);
}

// ------------------------------------------------------------- merger ------

// A platform loop (on the case's thread) and two raster loops (each on a
// parked thread that never runs it), all flushed from the case's thread
// with MessageLoop::RunExpiredTasksNow, as an embedder that polls does. So
// every task runs on one thread in an order the trace fixes, while
// RasterThreadMerger moves the raster queues in and out of the platform
// queue. The driver models the mergers only to stay off the paths where
// upstream aborts (FML_CHECK); every printed value is the real one.
struct ParkedLoop {
  fml::MessageLoop* loop = nullptr;
  fml::AutoResetWaitableEvent ready;
  fml::AutoResetWaitableEvent term;
  std::thread thread;

  ParkedLoop()
      : thread([this]() {
          fml::MessageLoop::EnsureInitializedForCurrentThread();
          loop = &fml::MessageLoop::GetCurrent();
          ready.Signal();
          term.Wait();
        }) {
    ready.Wait();
  }

  ~ParkedLoop() {
    term.Signal();
    thread.join();
  }
};

struct SharedModel {
  int pair;
  bool enabled = true;
  std::map<int, size_t> leases;  // merger index -> lease term

  bool Merged() const {
    for (const auto& [m, lease] : leases) {
      if (lease != 0) {
        return true;
      }
    }
    return false;
  }
};

struct MergerEntry {
  int pair;  // 0: P with R1, 1: P with R2, 2: P with P
  int shared;
  fml::RefPtr<fml::RasterThreadMerger> merger;
};

struct MergerCtx {
  Rng* r;
  fml::MessageLoop* loops[3];
  fml::TaskQueueId ids[3] = {fml::TaskQueueId(0), fml::TaskQueueId(0),
                             fml::TaskQueueId(0)};
  int flushing = 3;
  int next_id = 0;
  int budget = 0;
  std::vector<MergerEntry> mergers;
  std::vector<SharedModel> shared;
  bool queue_merged[3] = {false, false, false};
};

// Index 3 is "no loop is being flushed".
const char* kLoopNames[4] = {"P", "R1", "R2", "-"};

int RasterOf(int pair) {
  return pair == 0 ? 1 : (pair == 1 ? 2 : 0);
}

void CreateMerger(MergerCtx& c, const char* indent) {
  Rng& r = *c.r;
  int pair = static_cast<int>(r.Below(5));
  pair = pair >= 3 ? static_cast<int>(r.Below(2)) : pair;
  int parent = c.mergers.empty() || r.Chance(3)
                   ? -1
                   : static_cast<int>(r.Below(c.mergers.size()));
  fml::RefPtr<fml::RasterThreadMerger> parent_merger;
  if (parent >= 0) {
    parent_merger = c.mergers[parent].merger;
  }
  int index = static_cast<int>(c.mergers.size());
  auto merger = fml::RasterThreadMerger::CreateOrShareThreadMerger(
      parent_merger, c.ids[0], c.ids[RasterOf(pair)]);
  int shared;
  if (parent >= 0 && c.mergers[parent].pair == pair) {
    shared = c.mergers[parent].shared;
  } else {
    shared = static_cast<int>(c.shared.size());
    c.shared.push_back(SharedModel{pair});
  }
  bool shares = parent >= 0 && merger->GetSharedRasterThreadMerger().get() ==
                                   parent_merger->GetSharedRasterThreadMerger()
                                       .get();
  QPRINTF("%screate m%d pair %d parent %d shares %d\n", indent, index,
              pair, parent, shares ? 1 : 0);
  if (r.Chance(2)) {
    merger->SetMergeUnmergeCallback(
        [index]() { QPRINTF("    callback m%d\n", index); });
  }
  c.mergers.push_back(MergerEntry{pair, shared, merger});
}

void MergerOp(MergerCtx& c, const char* indent) {
  Rng& r = *c.r;
  if (c.mergers.empty() || r.Chance(10)) {
    CreateMerger(c, indent);
    return;
  }
  int m = static_cast<int>(r.Below(c.mergers.size()));
  MergerEntry& e = c.mergers[m];
  SharedModel& s = c.shared[e.shared];
  bool same = e.pair == 2;
  int raster = RasterOf(e.pair);
  auto& merger = e.merger;
  switch (r.Below(9)) {
    case 0:
    case 1: {
      size_t lease = 1 + r.Below(4);
      QPRINTF("%smerge m%d %zu\n", indent, m, lease);
      merger->MergeWithLease(lease);
      if (!same && s.enabled && !s.Merged()) {
        c.queue_merged[raster] = true;
        s.leases[m] = lease;
      }
      break;
    }
    case 2:
    case 3: {
      if (!same && s.Merged() && s.enabled) {
        auto it = s.leases.find(m);
        if (it != s.leases.end()) {
          if (it->second == 0) {
            break;  // FML_CHECK(lease_term_ref > 0) would abort.
          }
          it->second--;
        }
        if (!s.Merged()) {
          if (!c.queue_merged[raster]) {
            if (it != s.leases.end()) {
              it->second++;
            }
            break;  // Unmerge would fail: FML_CHECK aborts.
          }
          c.queue_merged[raster] = false;
        }
      }
      QPRINTF("%sdecrement m%d\n", indent, m);
      auto status = merger->DecrementLease();
      QPRINTF("%s  -> %d\n", indent, static_cast<int>(status));
      break;
    }
    case 4: {
      size_t lease = 1 + r.Below(4);
      if (!same && s.enabled && !s.Merged()) {
        break;  // FML_DCHECK(IsMergedUnSafe()) in debug builds.
      }
      QPRINTF("%sextend m%d %zu\n", indent, m, lease);
      merger->ExtendLeaseTo(lease);
      if (!same && s.enabled) {
        s.leases[m] = lease;
      }
      break;
    }
    case 5: {
      if (!same && s.enabled) {
        auto old = s.leases;
        s.leases.erase(m);
        if (s.leases.empty() || !s.Merged()) {
          if (!c.queue_merged[raster]) {
            s.leases = old;
            break;  // Unmerge would fail: FML_CHECK aborts.
          }
          c.queue_merged[raster] = false;
        }
      }
      QPRINTF("%sunmerge m%d\n", indent, m);
      merger->UnMergeNowIfLastOne();
      break;
    }
    case 6: {
      bool enable = r.Chance(2);
      QPRINTF("%s%s m%d\n", indent, enable ? "enable" : "disable", m);
      if (enable) {
        merger->Enable();
      } else {
        merger->Disable();
      }
      s.enabled = enable;
      break;
    }
    case 7: {
      bool merged = merger->IsMerged();
      QPRINTF("%squery m%d merged %d enabled %d raster %d platform %d\n",
                  indent, m, merged ? 1 : 0, merger->IsEnabled() ? 1 : 0,
                  merger->IsOnRasterizingThread() ? 1 : 0,
                  merger->IsOnPlatformThread() ? 1 : 0);
      if (merged) {
        merger->WaitUntilMerged();
        QPRINTF("%s  waited\n", indent);
      }
      break;
    }
    default:
      CreateMerger(c, indent);
      break;
  }
}

fml::closure MakeMergerTask(MergerCtx* c, int id, int queue);

void PostMergerTask(MergerCtx& c, const char* indent) {
  if (c.budget <= 0) {
    return;
  }
  c.budget--;
  Rng& r = *c.r;
  int id = c.next_id++;
  int q = static_cast<int>(r.Below(3));
  auto runner = c.loops[q]->GetTaskRunner();
  switch (r.Below(5)) {
    case 0:
    case 1:
      QPRINTF("%spost t%d to %s\n", indent, id, kLoopNames[q]);
      runner->PostTask(MakeMergerTask(&c, id, q));
      break;
    case 2: {
      fml::TimePoint t =
          r.Chance(10) ? fml::TimePoint::Max()
                       : fml::TimePoint::FromTicks(
                             PeekNow() + static_cast<int64_t>(r.Below(30)) -
                             10);
      QPRINTF("%sat t%d to %s %" PRId64 "\n", indent, id, kLoopNames[q],
                  t.ToEpochDelta().ToNanoseconds());
      runner->PostTaskForTime(MakeMergerTask(&c, id, q), t);
      break;
    }
    case 3: {
      int64_t d = static_cast<int64_t>(r.Below(20)) - 5;
      QPRINTF("%sdelay t%d to %s %" PRId64 "\n", indent, id,
                  kLoopNames[q], d);
      runner->PostDelayedTask(MakeMergerTask(&c, id, q),
                              fml::TimeDelta::FromNanoseconds(d));
      break;
    }
    default:
      QPRINTF("%snow-or-post t%d to %s\n", indent, id, kLoopNames[q]);
      fml::TaskRunner::RunNowOrPostTask(runner, MakeMergerTask(&c, id, q));
      break;
  }
}

fml::closure MakeMergerTask(MergerCtx* c, int id, int queue) {
  return [c, id, queue]() {
    Rng& r = *c->r;
    QPRINTF("  run t%d of %s flushing %s @%" PRId64 "\n", id,
                kLoopNames[queue], kLoopNames[c->flushing], PeekNow());
    switch (r.Below(6)) {
      case 0:
      case 1:
        MergerOp(*c, "   ");
        break;
      case 2:
      case 3:
        PostMergerTask(*c, "   ");
        break;
      default:
        break;
    }
  };
}

void MergerCase(Rng& r, int i) {
  SetFakeClock(100 + static_cast<int64_t>(r.Below(50)),
               1 + static_cast<int64_t>(r.Below(3)));
  fml::MessageLoop::EnsureInitializedForCurrentThread();
  // The parked threads are the driver's: spawning them is not timed.
  SwPause();
  auto r1 = std::make_unique<ParkedLoop>();
  auto r2 = std::make_unique<ParkedLoop>();
  SwResume();
  MergerCtx c;
  c.r = &r;
  c.loops[0] = &fml::MessageLoop::GetCurrent();
  c.loops[1] = r1->loop;
  c.loops[2] = r2->loop;
  for (int q = 0; q < 3; q++) {
    c.ids[q] = c.loops[q]->GetTaskRunner()->GetTaskQueueId();
  }
  c.budget = 10 + static_cast<int>(r.Below(40));
  QPRINTF("case %d now %" PRId64 " budget %d\n", i, PeekNow(), c.budget);
  auto* queues = fml::MessageLoopTaskQueues::GetInstance();
  int ops = 10 + static_cast<int>(r.Below(50));
  for (int op = 0; op < ops; op++) {
    switch (r.Below(12)) {
      case 0:
      case 1:
      case 2:
        PostMergerTask(c, "");
        break;
      case 3:
      case 4:
      case 5: {
        int q = static_cast<int>(r.Below(3));
        c.flushing = q;
        QPRINTF("flush %s @%" PRId64 "\n", kLoopNames[q], PeekNow());
        c.loops[q]->RunExpiredTasksNow();
        c.flushing = 3;
        break;
      }
      case 6:
      case 7:
        MergerOp(c, "");
        break;
      case 8: {
        int q = static_cast<int>(r.Below(3));
        intptr_t key = static_cast<intptr_t>(r.Below(3));
        if (r.Chance(3)) {
          QPRINTF("unobserve %s %" PRIdPTR "\n", kLoopNames[q], key);
          queues->RemoveTaskObserver(c.ids[q], key);
        } else {
          QPRINTF("observe %s %" PRIdPTR "\n", kLoopNames[q], key);
          queues->AddTaskObserver(c.ids[q], key, [q, key]() {
            QPRINTF("    obs %s %" PRIdPTR "\n", kLoopNames[q], key);
          });
        }
        break;
      }
      case 9: {
        QPRINTF("state");
        for (int q = 0; q < 3; q++) {
          bool has = queues->HasPendingTasks(c.ids[q]);
          size_t num = queues->GetNumPendingTasks(c.ids[q]);
          bool runs = c.loops[q]->GetTaskRunner()->RunsTasksOnCurrentThread();
          QPRINTF(" %s:%d/%zu/%d", kLoopNames[q], has ? 1 : 0, num,
                  runs ? 1 : 0);
        }
        bool owns1 = queues->Owns(c.ids[0], c.ids[1]);
        bool owns2 = queues->Owns(c.ids[0], c.ids[2]);
        bool same1 =
            fml::TaskRunnerChecker::RunsOnTheSameThread(c.ids[1], c.ids[0]);
        bool same2 =
            fml::TaskRunnerChecker::RunsOnTheSameThread(c.ids[2], c.ids[1]);
        QPRINTF(" owns %d %d same %d %d\n", owns1 ? 1 : 0, owns2 ? 1 : 0,
                same1 ? 1 : 0, same2 ? 1 : 0);
        break;
      }
      case 10: {
        fml::TaskRunnerChecker checker;
        bool on = checker.RunsOnCreationTaskRunner();
        QPRINTF("checker %d\n", on ? 1 : 0);
        break;
      }
      default: {
        int64_t jump = static_cast<int64_t>(r.Below(15));
        QPRINTF("jump %" PRId64 "\n", jump);
        g_fake_now += jump;
        break;
      }
    }
  }
  for (int q = 1; q < 3; q++) {
    if (c.queue_merged[q]) {
      QPRINTF("final unmerge %s %d\n", kLoopNames[q],
                  queues->Unmerge(c.ids[0], c.ids[q]) ? 1 : 0);
    }
  }
  QPRINTF("final pending %zu %zu %zu\n",
              queues->GetNumPendingTasks(c.ids[0]),
              queues->GetNumPendingTasks(c.ids[1]),
              queues->GetNumPendingTasks(c.ids[2]));
  for (int q = 0; q < 3; q++) {
    queues->DisposeTasks(c.ids[q]);
  }
  c.mergers.clear();
  SwPause();
  r2.reset();
  r1.reset();
  SwResume();
}

void SuiteMerger(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    // The case runs on a fresh thread; only its body is timed.
    SwPause();
    std::thread thread([&r, i]() {
      SwResume();
      MergerCase(r, i);
      SwPause();
    });
    thread.join();
    SwResume();
  }
  fml::TimePoint::SetClockSource(nullptr);
}

// ------------------------------------------------------------- thread ------

// fml::Thread, the task runner utilities and ConcurrentMessageLoop on real
// threads and the real clock. Only what is deterministic is printed: each
// thread's tasks in the order it ran them (posts are FIFO per thread and the
// driver waits for every task before printing), never the interleaving
// across threads.
std::string CurrentThreadName() {
  char name[16] = {};
  pthread_getname_np(pthread_self(), name, sizeof name);
  return name;
}

struct Pending {
  std::mutex mutex;
  std::condition_variable cv;
  int count = 0;

  void Add() {
    std::scoped_lock lock(mutex);
    count++;
  }
  void Done() {
    std::scoped_lock lock(mutex);
    if (--count == 0) {
      cv.notify_all();
    }
  }
  void Wait() {
    std::unique_lock lock(mutex);
    cv.wait(lock, [this] { return count == 0; });
  }
};

struct ThreadCtx {
  Rng* r;
  std::vector<std::unique_ptr<fml::Thread>> threads;
  std::vector<fml::RefPtr<fml::TaskRunner>> runners;
  std::mutex trace_mutex;
  std::map<int, std::vector<std::string>> traces;  // thread index -> lines
  Pending pending;
  int next_id = 0;
};

int ThreadIndexOf(ThreadCtx* c) {
  for (size_t i = 0; i < c->runners.size(); i++) {
    if (c->runners[i]->RunsTasksOnCurrentThread()) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

fml::closure MakeThreadTask(ThreadCtx* c, int id, int child_action);

fml::closure MakeThreadTask(ThreadCtx* c, int id, int child_action) {
  return [c, id, child_action]() {
    int at = ThreadIndexOf(c);
    std::string line = "t" + std::to_string(id) + " runs";
    for (auto& runner : c->runners) {
      line += runner->RunsTasksOnCurrentThread() ? " 1" : " 0";
    }
    if (child_action != 0) {
      auto own = c->runners[at];
      int child = id * 10 + child_action;
      c->pending.Add();
      switch (child_action) {
        case 1:
          line += " post";
          own->PostTask(MakeThreadTask(c, child, 0));
          break;
        case 2:
          line += " now";
          fml::TaskRunner::RunNowOrPostTask(own, MakeThreadTask(c, child, 0));
          break;
        default:
          line += " flush";
          fml::TaskRunner::RunNowAndFlushMessages(own,
                                                  MakeThreadTask(c, child, 0));
          break;
      }
    }
    {
      std::scoped_lock lock(c->trace_mutex);
      c->traces[at].push_back(line);
    }
    c->pending.Done();
  };
}

void ThreadNameConfigSetter(const fml::Thread::ThreadConfig& config) {
  QPRINTF("  setter %s %d\n", config.name.c_str(),
              static_cast<int>(config.priority));
  fml::Thread::SetCurrentThreadName(config);
}

std::string RandomThreadName(Rng& r) {
  static const char* kNames[] = {"ui", "raster", "io", "platform",
                                 "VeryLongThreadNameTest", "a.b.c.d.e.f.g.h.i"};
  std::string name = kNames[r.Below(6)];
  name += std::to_string(r.Below(100));
  return name;
}

void ConcurrentCase(Rng& r) {
  size_t workers = r.Below(5);
  auto loop = fml::ConcurrentMessageLoop::Create(workers);
  size_t count = loop->GetWorkerCount();
  QPRINTF("concurrent %zu -> %zu\n", workers, count);
  auto runner = loop->GetTaskRunner();
  size_t tasks = r.Below(30);
  fml::CountDownLatch latch(tasks);
  std::mutex mutex;
  size_t inside = 0;
  bool names_ok = true;
  for (size_t t = 0; t < tasks; t++) {
    runner->PostTask([&]() {
      std::string name = CurrentThreadName();
      bool on = loop->RunsTasksOnCurrentThread();
      {
        std::scoped_lock lock(mutex);
        inside += on ? 1 : 0;
        names_ok = names_ok && name.rfind("io.worker.", 0) == 0 &&
                   std::stoul(name.substr(10)) >= 1 &&
                   std::stoul(name.substr(10)) <= count;
      }
      latch.CountDown();
    });
  }
  latch.Wait();
  QPRINTF("  ran %zu inside %zu names %d outside %d\n", tasks, inside,
              names_ok ? 1 : 0, loop->RunsTasksOnCurrentThread() ? 1 : 0);
  fml::CountDownLatch all(count);
  std::vector<std::string> names;
  loop->PostTaskToAllWorkers([&]() {
    {
      std::scoped_lock lock(mutex);
      names.push_back(CurrentThreadName());
    }
    all.CountDown();
  });
  all.Wait();
  std::sort(names.begin(), names.end());
  QPRINTF("  all");
  for (const auto& name : names) {
    QPRINTF(" %s", name.c_str());
  }
  QPRINTF("\n");
  if (r.Chance(2)) {
    loop->Terminate();
    std::string where;
    runner->PostTask([&]() { where = CurrentThreadName(); });
    QPRINTF("  after terminate caller %d\n",
                where == CurrentThreadName() ? 1 : 0);
  }
  loop.reset();
  bool ran = false;
  runner->PostTask([&]() { ran = true; });
  QPRINTF("  after death ran %d\n", ran ? 1 : 0);
}

void ThreadCase(Rng& r, int i) {
  ThreadCtx c;
  c.r = &r;
  int n = 1 + static_cast<int>(r.Below(3));
  QPRINTF("case %d threads %d\n", i, n);
  std::vector<int> kinds;
  for (int t = 0; t < n; t++) {
    kinds.push_back(static_cast<int>(r.Below(3)));
    switch (kinds.back()) {
      case 0:
        QPRINTF("thread %d default\n", t);
        c.threads.push_back(std::make_unique<fml::Thread>());
        break;
      case 1: {
        std::string name = RandomThreadName(r);
        QPRINTF("thread %d named %s\n", t, name.c_str());
        c.threads.push_back(std::make_unique<fml::Thread>(name));
        break;
      }
      default: {
        std::string name = RandomThreadName(r);
        auto priority = static_cast<fml::Thread::ThreadPriority>(r.Below(4));
        QPRINTF("thread %d config %s %d\n", t, name.c_str(),
                    static_cast<int>(priority));
        c.threads.push_back(std::make_unique<fml::Thread>(
            ThreadNameConfigSetter,
            fml::Thread::ThreadConfig(name, priority)));
        break;
      }
    }
    c.runners.push_back(c.threads.back()->GetTaskRunner());
  }
  for (int t = 0; t < n; t++) {
    if (kinds[t] == 0) {
      // Unnamed: inherits the creating thread's name, the executable's.
      continue;
    }
    fml::AutoResetWaitableEvent latch;
    std::string name;
    c.runners[t]->PostTask([&]() {
      name = CurrentThreadName();
      latch.Signal();
    });
    latch.Wait();
    QPRINTF("name %d %s\n", t, name.c_str());
  }
  int rounds = 1 + static_cast<int>(r.Below(4));
  for (int round = 0; round < rounds; round++) {
    // Hold every thread while the batch is posted, so that tasks a task posts
    // queue behind the whole batch whatever the timing.
    std::vector<std::unique_ptr<fml::AutoResetWaitableEvent>> gates;
    for (int t = 0; t < n; t++) {
      gates.push_back(std::make_unique<fml::AutoResetWaitableEvent>());
      auto* gate = gates.back().get();
      c.runners[t]->PostTask([gate]() { gate->Wait(); });
    }
    std::vector<std::unique_ptr<fml::ConditionalBasicTaskRunner>> conditionals;
    int k = static_cast<int>(r.Below(20));
    for (int j = 0; j < k; j++) {
      int t = static_cast<int>(r.Below(n));
      int id = c.next_id++;
      int child = r.Chance(3) ? 1 + static_cast<int>(r.Below(3)) : 0;
      auto task = MakeThreadTask(&c, id, child);
      switch (r.Below(6)) {
        case 0:
          QPRINTF("post t%d to %d\n", id, t);
          c.pending.Add();
          c.runners[t]->PostTask(task);
          break;
        case 1:
          QPRINTF("now-or-post t%d to %d\n", id, t);
          c.pending.Add();
          fml::TaskRunner::RunNowOrPostTask(c.runners[t], task);
          break;
        case 2: {
          QPRINTF("wrapper t%d to %d\n", id, t);
          c.pending.Add();
          fml::WrapperBasicTaskRunner wrapper(c.runners[t]);
          wrapper.PostTask(task);
          break;
        }
        case 3: {
          bool usable = r.Chance(2);
          QPRINTF("conditional t%d to %d %d\n", id, t, usable ? 1 : 0);
          // Kept alive until the round ends: the task checks the predicate
          // through a weak reference when it runs.
          conditionals.push_back(
              std::make_unique<fml::ConditionalBasicTaskRunner>(
                  c.runners[t], [usable]() { return usable; }));
          if (usable) {
            c.pending.Add();
          }
          conditionals.back()->PostTask(task);
          break;
        }
        case 4: {
          // The runner, and the predicate it owns, dies before the gated
          // thread gets to the task, which must then not run.
          QPRINTF("conditional-dead t%d to %d\n", id, t);
          fml::ConditionalBasicTaskRunner conditional(c.runners[t],
                                                      []() { return true; });
          conditional.PostTask(task);
          break;
        }
        default:
          QPRINTF("for-time t%d to %d\n", id, t);
          c.pending.Add();
          c.runners[t]->PostTaskForTime(task, fml::TimePoint::Now());
          break;
      }
    }
    for (auto& gate : gates) {
      gate->Signal();
    }
    c.pending.Wait();
    // Children posted with PostTask/RunNowAndFlushMessages may still be
    // queued behind an empty flush task; run one more synchronous round trip
    // per thread so every queued task has run.
    for (int t = 0; t < n; t++) {
      fml::AutoResetWaitableEvent latch;
      c.runners[t]->PostTask([&latch]() { latch.Signal(); });
      latch.Wait();
    }
    std::scoped_lock lock(c.trace_mutex);
    for (auto& [t, lines] : c.traces) {
      for (const auto& line : lines) {
        QPRINTF("  %d: %s\n", t, line.c_str());
      }
    }
    c.traces.clear();
    QPRINTF("main runs");
    for (auto& runner : c.runners) {
      QPRINTF(" %d", runner->RunsTasksOnCurrentThread() ? 1 : 0);
    }
    QPRINTF("\n");
  }
  for (int t = 0; t < n; t++) {
    if (r.Chance(2)) {
      QPRINTF("join %d\n", t);
      c.threads[t]->Join();
      if (r.Chance(2)) {
        c.threads[t]->Join();
      }
      c.runners[t]->PostTask([]() { QPRINTF("never\n"); });
      QPRINTF("  pending %zu\n",
                  fml::MessageLoopTaskQueues::GetInstance()->GetNumPendingTasks(
                      c.runners[t]->GetTaskQueueId()));
    }
  }
  c.threads.clear();
  if (r.Chance(3)) {
    ConcurrentCase(r);
  }
}

void SuiteThread(Rng& r, int cases) {
  QPRINTF("default stack %zu\n", fml::Thread::GetDefaultStackSize());
  for (int i = 0; i < cases; i++) {
    ThreadCase(r, i);
  }
}

// ------------------------------------------------------------ logging ------

const char* kLogFiles[] = {"flutter/fml/logging.cc", "../../flutter/shell/x.cc",
                           "../a.cc", "./b.cc", "..", "", "../../../"};

std::string RandomLogText(Rng& r) {
  static const char* kWords[] = {"Hello!", "frame", "raster", "42", "-",
                                 "a b", "\t", "ok."};
  std::string text;
  int words = static_cast<int>(r.Below(5));
  for (int w = 0; w < words; w++) {
    text += kWords[r.Below(8)];
    if (r.Chance(2)) {
      text += " ";
    }
  }
  return text;
}

void PrintEscaped(const std::string& s) {
  if (g_quiet) {
    return;
  }
  for (char ch : s) {
    if (ch == '\n') {
      QFPUTS("\\n", stdout);
    } else if (ch == '\t') {
      QFPUTS("\\t", stdout);
    } else {
      QFPUTC(ch, stdout);
    }
  }
}

// One LogMessage as the macros make it; a fatal one kills the process.
void EmitLog(Rng& r, fml::LogSeverity severity, bool capture) {
  const char* file = kLogFiles[r.Below(7)];
  int line = static_cast<int>(r.Below(500));
  bool condition = r.Chance(3);
  std::string text = RandomLogText(r);
  QPRINTF("  emit %d %s %d %d %d\n", severity, file, line,
              condition ? 1 : 0, capture ? 1 : 0);
  std::fflush(stdout);
  fml::testing::LogCapture log_capture_slot;
  if (!capture) {
    fml::LogMessage::CaptureNextLog(nullptr);
  }
  {
    fml::LogMessage message(severity, file, line,
                            condition ? "x != nullptr" : nullptr);
    message.stream() << text;
  }
  if (capture) {
    QPRINTF("  captured ");
    PrintEscaped(log_capture_slot.str());
    QPRINTF("\n");
  }
}

void FatalChild(uint64_t seed) {
  Rng r{seed};
  fml::LogSeverity severity = 4 + static_cast<int>(r.Below(3));
  EmitLog(r, severity, r.Chance(3));
  QPRINTF("survived\n");
}

void RunFatalChild(uint64_t seed) {
  int err[2];
  if (pipe(err) != 0) {
    std::abort();
  }
  std::fflush(stdout);
  pid_t pid = fork();
  if (pid == 0) {
    dup2(err[1], 2);
    int devnull = open("/dev/null", O_WRONLY);
    dup2(devnull, 1);
    close(err[0]);
    close(err[1]);
    std::string s = std::to_string(seed);
    execl("/proc/self/exe", "fml_dump", "fatal", s.c_str(), "0", nullptr);
    _exit(127);
  }
  close(err[1]);
  std::string out;
  char buf[256];
  ssize_t n;
  while ((n = read(err[0], buf, sizeof buf)) > 0) {
    out.append(buf, n);
  }
  close(err[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  QPRINTF("  child %s %d stderr ",
              WIFSIGNALED(status) ? "signal" : "exit",
              WIFSIGNALED(status) ? WTERMSIG(status) : WEXITSTATUS(status));
  PrintEscaped(out);
  QPRINTF("\n");
}

void SuiteLogging(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(8)) {
      case 0:
      case 1: {
        fml::LogSettings settings;
        settings.min_log_level = static_cast<int>(r.Below(10)) - 3;
        fml::SetLogSettings(settings);
        QPRINTF("  set %d -> %d min %d vlog %d\n", settings.min_log_level,
                    fml::GetLogSettings().min_log_level, fml::GetMinLogLevel(),
                    fml::GetVlogVerbosity());
        break;
      }
      case 2: {
        fml::LogSettings settings;
        settings.min_log_level = static_cast<int>(r.Below(10)) - 3;
        int before = fml::GetMinLogLevel();
        {
          fml::ScopedSetLogSettings scoped(settings);
          QPRINTF("  scoped %d -> min %d vlog %d\n",
                      settings.min_log_level, fml::GetMinLogLevel(),
                      fml::GetVlogVerbosity());
        }
        QPRINTF("  restored %d %d\n", before, fml::GetMinLogLevel());
        break;
      }
      case 3:
      case 4:
      case 5: {
        // FML_LOG / FML_VLOG gating, then the message.
        bool vlog = r.Chance(3);
        int level = static_cast<int>(r.Below(4));
        fml::LogSeverity severity = vlog ? -level : level;
        bool on = vlog ? level <= fml::GetVlogVerbosity()
                       : fml::ShouldCreateLogMessage(severity);
        QPRINTF("  %s %d on %d\n", vlog ? "vlog" : "log", level,
                    on ? 1 : 0);
        if (on) {
          EmitLog(r, severity, r.Chance(2));
        }
        break;
      }
      case 6: {
        // Severities past the named ones print UNKNOWN.
        fml::LogSeverity severity = r.Chance(2) ? 5 + static_cast<int>(r.Below(3))
                                               : -static_cast<int>(r.Below(12));
        if (severity >= fml::kLogFatal) {
          QPRINTF("  fatal\n");
          RunFatalChild(r.Next());
        } else {
          EmitLog(r, severity, r.Chance(2));
        }
        break;
      }
      default:
        if (r.Chance(4)) {
          QPRINTF("  fatal\n");
          RunFatalChild(r.Next());
        }
        break;
    }
  }
  fml::SetLogSettings(fml::LogSettings{});
}

// ------------------------------------------------------- file system ------
//
// The file, mapping, paths, affinity and native suites work in a directory
// made fresh per run by fml::ScopedTemporaryDirectory (so its constructor and
// destructor are exercised too) as /tmp/flutter_XXXXXXXX; the harness masks
// the name mkdtemp picks. Every input is drawn before the calls it feeds, in
// the order the Rust driver draws it.

// Bytes between quotes; anything outside printable ASCII, and the quote and
// the backslash, as \xNN.
void PrintQuoted(const std::string& s) {
  if (g_quiet) {
    return;
  }
  QFPUTC('"', stdout);
  for (unsigned char c : s) {
    if (c < 0x20 || c > 0x7e || c == '"' || c == '\\') {
      QPRINTF("\\x%02x", c);
    } else {
      QFPUTC(c, stdout);
    }
  }
  QFPUTC('"', stdout);
}

uint64_t Fnv1a(const uint8_t* data, size_t size) {
  uint64_t h = 0xcbf29ce484222325ULL;
  for (size_t i = 0; i < size; i++) {
    h ^= data[i];
    h *= 0x100000001b3ULL;
  }
  return h;
}

std::vector<uint8_t> GenData(Rng& r, uint64_t max_len) {
  SwPause();
  std::vector<uint8_t> data(r.Below(max_len + 1));
  for (auto& b : data) {
    b = static_cast<uint8_t>(r.Next());
  }
  SwResume();
  return data;
}

// No "..": every path stays inside the scratch directory, which the suite
// empties with RemoveFilesInDirectory and friends.
const char* const kFileNames[] = {"a",   "b",      "c.txt", "d",
                                  "\xc3\xa4\xe3\x83\x86", "sp ace", "x\xff",
                                  ".",   "..x",    "",      "nl\nx",
                                  "a.temp"};
constexpr uint64_t kFileNameCount = 12;

std::string GenRelPathUntimed(Rng& r);

std::string GenRelPath(Rng& r) {
  SwPause();
  std::string path = GenRelPathUntimed(r);
  SwResume();
  return path;
}

std::string GenRelPathUntimed(Rng& r) {
  switch (r.Below(12)) {
    case 0:
      return std::string(256, 'n');  // longer than NAME_MAX
    case 1:
    case 2: {
      std::string p;
      int n = 2 + static_cast<int>(r.Below(2));
      for (int i = 0; i < n; i++) {
        if (i != 0) {
          p += '/';
        }
        p += kFileNames[r.Below(4)];
      }
      return p;
    }
    case 3:
      return "a/./b";
    default:
      return kFileNames[r.Below(kFileNameCount)];
  }
}

fml::FilePermission Perm(uint64_t p) {
  return p == 0 ? fml::FilePermission::kRead
                : p == 1 ? fml::FilePermission::kWrite
                         : fml::FilePermission::kReadWrite;
}

struct FileCtx {
  fml::ScopedTemporaryDirectory dir;
  fml::UniqueFD slots[4];
  fml::UniqueFD invalid;
};

const char* const kBaseNames[] = {"root", "s0", "s1", "s2", "s3", "bad"};

int GenBase(Rng& r) {
  return r.Chance(2) ? 0 : static_cast<int>(r.Below(6));
}

const fml::UniqueFD& Base(FileCtx& c, int b) {
  if (b == 0) {
    return c.dir.fd();
  }
  if (b == 5) {
    return c.invalid;
  }
  return c.slots[b - 1];
}

std::string Abs(FileCtx& c, const std::string& rel) {
  return c.dir.path() + "/" + rel;
}

// Visits, printing each name, stopping where the visitor says.
bool PrintingVisit(const fml::UniqueFD& dir, bool recursive, bool stop,
                   const std::string& stop_at) {
  fml::FileVisitor visitor = [&](const fml::UniqueFD& directory,
                                 const std::string& filename) {
    QPRINTF(" ");
    PrintQuoted(filename);
    return !(stop && filename == stop_at);
  };
  return recursive ? fml::VisitFilesRecursively(dir, visitor)
                   : fml::VisitFiles(dir, visitor);
}

void FileOp(FileCtx& c, Rng& r, int depth) {
  switch (r.Below(16)) {
    case 0:
    case 1:
    case 2:
    case 3: {
      // 0, 1: OpenFile; 2: OpenDirectory; 3: the read-only helpers.
      bool directory = r.Below(4) == 0;
      bool abs = r.Chance(6);
      int b = GenBase(r);
      std::string path = GenRelPath(r);
      bool create = r.Chance(2);
      uint64_t perm = r.Below(3);
      int slot = static_cast<int>(r.Below(4));
      bool read_only = r.Chance(4);
      errno = 0;
      fml::UniqueFD fd;
      if (read_only) {
        fd = directory ? fml::OpenDirectoryReadOnly(Base(c, b), path.c_str())
                       : fml::OpenFileReadOnly(Base(c, b), path.c_str());
      } else if (abs) {
        fd = directory ? fml::OpenDirectory(Abs(c, path).c_str(), create,
                                            Perm(perm))
                       : fml::OpenFile(Abs(c, path).c_str(), create,
                                       Perm(perm));
      } else {
        fd = directory ? fml::OpenDirectory(Base(c, b), path.c_str(), create,
                                            Perm(perm))
                       : fml::OpenFile(Base(c, b), path.c_str(), create,
                                       Perm(perm));
      }
      int e = errno;
      QPRINTF("  %s %s ", directory ? "opendir" : "open",
                  read_only ? "ro" : abs ? "abs" : kBaseNames[b]);
      PrintQuoted(path);
      QPRINTF(" c%d p%d -> s%d %d errno %d\n", create ? 1 : 0,
                  static_cast<int>(perm), slot, fd.is_valid() ? 1 : 0, e);
      c.slots[slot] = std::move(fd);
      break;
    }
    case 4: {
      int b = GenBase(r);
      std::vector<std::string> components;
      int n = static_cast<int>(r.Below(4));
      for (int i = 0; i < n; i++) {
        // Not ".": CreateDirectory's components are names.
        components.push_back(kFileNames[r.Below(7)]);
      }
      uint64_t perm = r.Below(3);
      int slot = static_cast<int>(r.Below(4));
      errno = 0;
      auto fd = fml::CreateDirectory(Base(c, b), components, Perm(perm));
      int e = errno;
      QPRINTF("  mkdirs %s", kBaseNames[b]);
      for (const auto& component : components) {
        QPRINTF(" ");
        PrintQuoted(component);
      }
      QPRINTF(" p%d -> s%d %d errno %d\n", static_cast<int>(perm), slot,
                  fd.is_valid() ? 1 : 0, e);
      c.slots[slot] = std::move(fd);
      break;
    }
    case 5: {
      int b = GenBase(r);
      std::string path = GenRelPath(r);
      int slot = static_cast<int>(r.Below(4));
      bool is_dir_fd = fml::IsDirectory(c.slots[slot]);
      bool is_dir = fml::IsDirectory(Base(c, b), path.c_str());
      bool exists = fml::FileExists(Base(c, b), path.c_str());
      bool exists_abs = fml::FileExists(c.dir.fd(), Abs(c, path).c_str());
      bool is_file = fml::IsFile(Abs(c, path));
      QPRINTF("  query %s ", kBaseNames[b]);
      PrintQuoted(path);
      QPRINTF(" s%d dir %d %d exists %d %d file %d\n", slot, is_dir_fd,
                  is_dir, exists, exists_abs, is_file);
      break;
    }
    case 6: {
      int slot = static_cast<int>(r.Below(4));
      size_t size = r.Below(5000);
      errno = 0;
      bool ok = fml::TruncateFile(c.slots[slot], size);
      int e = errno;
      QPRINTF("  truncate s%d %zu -> %d errno %d\n", slot, size, ok, e);
      break;
    }
    case 7:
    case 8: {
      bool directory = r.Chance(2);
      bool abs = r.Chance(6);
      int b = GenBase(r);
      std::string path = GenRelPath(r);
      errno = 0;
      bool ok = directory
                    ? (abs ? fml::UnlinkDirectory(Abs(c, path).c_str())
                           : fml::UnlinkDirectory(Base(c, b), path.c_str()))
                    : (abs ? fml::UnlinkFile(Abs(c, path).c_str())
                           : fml::UnlinkFile(Base(c, b), path.c_str()));
      int e = errno;
      QPRINTF("  %s %s ", directory ? "rmdir" : "unlink",
                  abs ? "abs" : kBaseNames[b]);
      PrintQuoted(path);
      QPRINTF(" -> %d errno %d\n", ok, e);
      break;
    }
    case 9: {
      bool abs = r.Chance(6);
      int b = GenBase(r);
      std::string path = GenRelPath(r);
      auto data = GenData(r, 300);
      fml::DataMapping mapping(data);
      errno = 0;
      bool ok = fml::WriteAtomically(
          abs ? c.dir.fd() : Base(c, b),
          abs ? Abs(c, path).c_str() : path.c_str(), mapping);
      int e = errno;
      QPRINTF("  write %s ", abs ? "abs" : kBaseNames[b]);
      PrintQuoted(path);
      QPRINTF(" %zu %016" PRIx64 " -> %d errno %d\n", data.size(),
                  Fnv1a(data.data(), data.size()), ok, e);
      break;
    }
    case 10:
    case 11: {
      bool recursive = r.Chance(2);
      int b = GenBase(r);
      bool stop = r.Chance(3);
      std::string stop_at = kFileNames[r.Below(kFileNameCount)];
      QPRINTF("  visit%s %s", recursive ? "-r" : "", kBaseNames[b]);
      bool ok = PrintingVisit(Base(c, b), recursive, stop, stop_at);
      QPRINTF(" -> %d\n", ok);
      break;
    }
    case 12: {
      bool whole = r.Chance(2);
      int b = GenBase(r);
      std::string path = GenRelPath(r);
      errno = 0;
      bool ok = whole ? fml::RemoveDirectoryRecursively(Base(c, b),
                                                         path.c_str())
                      : fml::RemoveFilesInDirectory(Base(c, b));
      int e = errno;
      QPRINTF("  %s %s ", whole ? "rmtree" : "empty", kBaseNames[b]);
      PrintQuoted(whole ? path : std::string());
      QPRINTF(" -> %d errno %d\n", ok, e);
      break;
    }
    case 13: {
      int from = static_cast<int>(r.Below(4));
      int to = static_cast<int>(r.Below(4));
      errno = 0;
      auto fd = fml::Duplicate(c.slots[from].get());
      int e = errno;
      QPRINTF("  dup s%d -> s%d %d errno %d dir %d\n", from, to,
                  fd.is_valid(), e, fml::IsDirectory(fd));
      c.slots[to] = std::move(fd);
      break;
    }
    case 14: {
      int slot = static_cast<int>(r.Below(4));
      errno = 0;
      fml::FileMapping mapping(c.slots[slot]);
      int e = errno;
      QPRINTF("  map s%d valid %d size %zu null %d errno %d fnv %016" PRIx64
                  "\n",
                  slot, mapping.IsValid(), mapping.GetSize(),
                  mapping.GetMapping() == nullptr, e,
                  Fnv1a(mapping.GetMapping(), mapping.GetSize()));
      break;
    }
    default: {
      static const unsigned kModes[] = {0, 0400, 0200, 0600, 0700, 0500, 0300,
                                        0644};
      std::string path = GenRelPath(r);
      unsigned mode = kModes[r.Below(8)];
      std::string abs = Abs(c, path);
      errno = 0;
      int rc = ::chmod(abs.c_str(), mode);
      int e = errno;
      struct stat st = {};
      bool dir = rc == 0 && ::stat(abs.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
      QPRINTF("  chmod ");
      PrintQuoted(path);
      QPRINTF(" %o -> %d errno %d dir %d\n", mode, rc, e, dir);
      if (dir) {
        // One operation under the changed mode, then back to rwx so that the
        // directory can be cleaned.
        if (depth == 0) {
          FileOp(c, r, 1);
        }
        ::chmod(abs.c_str(), 0700);
      }
      break;
    }
  }
}

// Makes every directory under `dir` rwx for its owner, so that the scratch
// directory can be removed when the suite runs as a user without
// CAP_DAC_OVERRIDE.
void MakeTreeWritable(const fml::UniqueFD& dir) {
  fml::FileVisitor visitor = [](const fml::UniqueFD& directory,
                                const std::string& filename) {
    if (fml::IsDirectory(directory, filename.c_str())) {
      std::string proc = "/proc/self/fd/" + std::to_string(directory.get()) +
                         "/" + filename;
      ::chmod(proc.c_str(), 0700);
    }
    return true;
  };
  fml::VisitFilesRecursively(dir, visitor);
}

void SuiteFile(Rng& r, int cases) {
  auto c = std::make_unique<FileCtx>();
  const std::string& root = c->dir.path();
  QPRINTF("root %s %d %zu valid %d\n", root.c_str(),
              root.rfind("/tmp/flutter_", 0) == 0, root.size(),
              c->dir.fd().is_valid());
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    FileOp(*c, r, 0);
  }
  QPRINTF("tree");
  PrintingVisit(c->dir.fd(), true, false, "");
  QPRINTF("\n");
  MakeTreeWritable(c->dir.fd());
  c.reset();
  QPRINTF("removed %d\n", ::access(root.c_str(), F_OK) != 0);
}

// ----------------------------------------------------------- mapping ------

const uint8_t* StaticBytes() {
  static uint8_t bytes[64];
  for (int i = 0; i < 64; i++) {
    bytes[i] = static_cast<uint8_t>(i * 7 + 3);
  }
  return bytes;
}

void PrintMapping(const fml::Mapping& m) {
  QPRINTF(" size %zu null %d dontneed %d fnv %016" PRIx64, m.GetSize(),
              m.GetMapping() == nullptr, m.IsDontNeedSafe(),
              Fnv1a(m.GetMapping(), m.GetSize()));
}

using Protection = fml::FileMapping::Protection;

// The driver's copy of mapping_posix.cc's ToPosixProtectionFlags, to know
// whether a mapping may be read or written.
int ProtectionFlags(const std::vector<Protection>& protection) {
  int flags = 0;
  for (auto p : protection) {
    switch (p) {
      case Protection::kRead:
        flags |= PROT_READ;
        break;
      case Protection::kWrite:
        flags |= PROT_WRITE;
        break;
      case Protection::kExecute:
        return PROT_READ | PROT_EXEC;
    }
  }
  return flags;
}

std::unique_ptr<fml::FileMapping> MakeFileMapping(
    const fml::UniqueFD& fd,
    const std::vector<Protection>& p) {
  switch (p.size()) {
    case 0:
      return std::make_unique<fml::FileMapping>(
          fd, std::initializer_list<Protection>{});
    case 1:
      return std::make_unique<fml::FileMapping>(
          fd, std::initializer_list<Protection>{p[0]});
    case 2:
      return std::make_unique<fml::FileMapping>(
          fd, std::initializer_list<Protection>{p[0], p[1]});
    default:
      return std::make_unique<fml::FileMapping>(
          fd, std::initializer_list<Protection>{p[0], p[1], p[2]});
  }
}

void SuiteMapping(Rng& r, int cases) {
  fml::ScopedTemporaryDirectory dir;
  QPRINTF("root %s\n", dir.path().c_str());
  const uint8_t* bytes = StaticBytes();
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(10)) {
      case 0: {
        auto data = GenData(r, 64);
        bool from_string = r.Chance(2);
        std::unique_ptr<fml::DataMapping> m =
            from_string ? std::make_unique<fml::DataMapping>(
                              std::string(data.begin(), data.end()))
                        : std::make_unique<fml::DataMapping>(std::move(data));
        QPRINTF("  data %d", from_string);
        PrintMapping(*m);
        QPRINTF("\n");
        break;
      }
      case 1: {
        uint64_t offset = r.Below(64);
        uint64_t size = r.Below(65 - offset);
        bool null = r.Chance(8);
        bool release = r.Chance(2);
        bool dontneed = r.Chance(2);
        const uint8_t* data = null ? nullptr : bytes + offset;
        {
          fml::NonOwnedMapping m(
              data, size,
              release ? fml::NonOwnedMapping::ReleaseProc(
                            [bytes](const uint8_t* d, size_t s) {
                              QPRINTF("  release %ld %zu\n",
                                          d ? static_cast<long>(d - bytes) : -1L,
                                          s);
                            })
                      : nullptr,
              dontneed);
          QPRINTF("  nonowned %d %" PRIu64 " same %d", null, offset,
                      m.GetMapping() == data);
          if (null) {
            QPRINTF(" size %zu dontneed %d\n", m.GetSize(),
                        m.IsDontNeedSafe());
          } else {
            PrintMapping(m);
            QPRINTF("\n");
          }
        }
        break;
      }
      case 2: {
        uint64_t kind = r.Below(4);
        auto data = GenData(r, 64);
        if (kind == 0) {
          fml::MallocMapping m;
          QPRINTF("  malloc empty");
          PrintMapping(m);
          QPRINTF("\n");
          break;
        }
        fml::MallocMapping m =
            fml::MallocMapping::Copy(data.data(), data.data() + data.size());
        QPRINTF("  malloc copy");
        PrintMapping(m);
        QPRINTF("\n");
        if (kind == 2) {
          size_t size = m.GetSize();
          uint8_t* released = m.Release();
          QPRINTF("  released %d fnv %016" PRIx64 " now",
                      released == nullptr, Fnv1a(released, size));
          std::free(released);
          PrintMapping(m);
          QPRINTF("\n");
        } else if (kind == 3) {
          fml::MallocMapping moved(std::move(m));
          QPRINTF("  moved");
          PrintMapping(moved);
          QPRINTF(" from");
          PrintMapping(m);
          QPRINTF("\n");
        }
        break;
      }
      case 3:
      case 4:
      case 5:
      case 6:
      case 7: {
        std::string name = "f" + std::to_string(r.Below(4));
        bool rewrite = !r.Chance(3);
        auto data = GenData(r, 9000);
        uint64_t perm = r.Below(3);
        std::vector<Protection> protection(r.Below(4));
        for (auto& p : protection) {
          p = static_cast<Protection>(r.Below(3));
        }
        if (rewrite) {
          if (data.empty()) {
            auto fd = fml::OpenFile(dir.fd(), name.c_str(), true,
                                    fml::FilePermission::kReadWrite);
            fml::TruncateFile(fd, 0);
          } else {
            fml::DataMapping contents(data);
            fml::WriteAtomically(dir.fd(), name.c_str(), contents);
          }
        }
        auto fd = fml::OpenFile(dir.fd(), name.c_str(), false, Perm(perm));
        errno = 0;
        auto m = MakeFileMapping(fd, protection);
        int e = errno;
        int flags = ProtectionFlags(protection);
        QPRINTF("  file %s %d %zu p%d prot", name.c_str(), rewrite,
                    data.size(), static_cast<int>(perm));
        for (auto p : protection) {
          QPRINTF("%d", static_cast<int>(p));
        }
        QPRINTF(" valid %d size %zu null %d mutable-null %d dontneed %d "
                    "errno %d",
                    m->IsValid(), m->GetSize(), m->GetMapping() == nullptr,
                    m->GetMutableMapping() == nullptr, m->IsDontNeedSafe(), e);
        if (m->GetMapping() != nullptr && (flags & PROT_READ)) {
          QPRINTF(" fnv %016" PRIx64, Fnv1a(m->GetMapping(), m->GetSize()));
        }
        QPRINTF("\n");
        uint64_t offset = r.Below(m->GetSize() + 1);
        uint64_t length = std::min<uint64_t>(r.Below(16) + 1,
                                             m->GetSize() - offset);
        uint8_t fill = static_cast<uint8_t>(r.Next());
        if (m->GetMutableMapping() != nullptr && (flags & PROT_WRITE) &&
            length > 0) {
          std::memset(m->GetMutableMapping() + offset, fill, length);
          m.reset();
          auto check = fml::FileMapping::CreateReadOnly(dir.fd(), name);
          QPRINTF("  wrote %" PRIu64 " %" PRIu64 " reread %d fnv %016" PRIx64
                      "\n",
                      offset, length, check != nullptr,
                      check ? Fnv1a(check->GetMapping(), check->GetSize()) : 0);
        }
        break;
      }
      case 8: {
        uint64_t kind = r.Below(6);
        static const char* const kNames[] = {"f0", "f1", "f2", "f3",
                                             "missing", ""};
        std::string name = kNames[r.Below(6)];
        std::unique_ptr<fml::FileMapping> m;
        errno = 0;
        switch (kind) {
          case 0:
            m = fml::FileMapping::CreateReadOnly(dir.path() + "/" + name);
            break;
          case 1:
            m = fml::FileMapping::CreateReadOnly(dir.fd(), name);
            break;
          case 2:
            m = fml::FileMapping::CreateReadOnly(
                fml::OpenFile(dir.fd(), name.c_str(), false,
                              fml::FilePermission::kRead));
            break;
          case 3:
            m = fml::FileMapping::CreateReadExecute(dir.path() + "/" + name);
            break;
          case 4:
            m = fml::FileMapping::CreateReadExecute(dir.fd(), name);
            break;
          default:
            m = fml::FileMapping::CreateReadExecute(
                fml::OpenFile(dir.fd(), name.c_str(), false,
                              fml::FilePermission::kRead));
            break;
        }
        int e = errno;
        QPRINTF("  factory %d ", static_cast<int>(kind));
        PrintQuoted(name);
        QPRINTF(" -> %d errno %d", m != nullptr, e);
        if (m) {
          QPRINTF(" valid %d", m->IsValid());
          PrintMapping(*m);
        }
        QPRINTF("\n");
        break;
      }
      default: {
        bool directory = r.Chance(2);
        fml::UniqueFD invalid;
        errno = 0;
        fml::FileMapping m(directory ? dir.fd() : invalid);
        int e = errno;
        QPRINTF("  file %s valid %d size %zu null %d errno %d\n",
                    directory ? "dir" : "invalid", m.IsValid(), m.GetSize(),
                    m.GetMapping() == nullptr, e);
        break;
      }
    }
  }
}

// ------------------------------------------------------------- paths ------

std::string GenPathText(Rng& r) {
  static const char kChars[] = {'a', 'b', '/',    '%',    '.', ':', 'f',
                                'F', '0', '9',    ' ',    '\xff', '\x80',
                                '\0'};
  std::string s;
  uint64_t n = r.Below(12);
  for (uint64_t i = 0; i < n; i++) {
    s += kChars[r.Below(14)];
  }
  return s;
}

std::string GenUriText(Rng& r) {
  static const char kHex[] = "0123456789abcdefABCDEF";
  std::string s;
  uint64_t n = r.Below(16);
  for (uint64_t i = 0; i < n; i++) {
    uint64_t k = r.Below(11);
    if (k == 10) {
      s += "%00";
    } else if (k < 3) {
      s += '%';
    } else if (k < 7) {
      s += kHex[r.Below(22)];
    } else if (k == 7) {
      s += 'g';
    } else if (k == 8) {
      s += '/';
    } else {
      s += GenPathText(r);
    }
  }
  return s;
}

void SuitePaths(Rng& r, int cases) {
  fml::ScopedTemporaryDirectory dir;
  std::string original = std::filesystem::current_path().string();
  // AbsolutePath prefixes the working directory, so work in the scratch
  // directory, whose name the harness masks.
  if (::chdir(dir.path().c_str()) != 0) {
    std::abort();
  }
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(6)) {
      case 0: {
        std::vector<std::string> c(r.Below(5));
        for (auto& s : c) {
          s = GenPathText(r);
        }
        std::string joined;
        switch (c.size()) {
          case 0:
            joined = fml::paths::JoinPaths({});
            break;
          case 1:
            joined = fml::paths::JoinPaths({c[0]});
            break;
          case 2:
            joined = fml::paths::JoinPaths({c[0], c[1]});
            break;
          case 3:
            joined = fml::paths::JoinPaths({c[0], c[1], c[2]});
            break;
          default:
            joined = fml::paths::JoinPaths({c[0], c[1], c[2], c[3]});
            break;
        }
        QPRINTF("  join");
        for (const auto& s : c) {
          QPRINTF(" ");
          PrintQuoted(s);
        }
        QPRINTF(" -> ");
        PrintQuoted(joined);
        QPRINTF("\n");
        break;
      }
      case 1: {
        std::string path = GenPathText(r);
        QPRINTF("  dirname ");
        PrintQuoted(path);
        QPRINTF(" -> ");
        PrintQuoted(fml::paths::GetDirectoryName(path));
        QPRINTF("\n");
        break;
      }
      case 2: {
        std::string text = GenUriText(r);
        QPRINTF("  sanitize ");
        PrintQuoted(text);
        QPRINTF(" -> ");
        PrintQuoted(fml::paths::SanitizeURIEscapedCharacters(text));
        QPRINTF("\n");
        break;
      }
      case 3: {
        static const char* const kPrefixes[] = {"file://", "file:/", "FILE://",
                                                ""};
        std::string uri = kPrefixes[r.Below(4)];
        uri += GenUriText(r);
        QPRINTF("  from-uri ");
        PrintQuoted(uri);
        QPRINTF(" -> ");
        PrintQuoted(fml::paths::FromURI(uri));
        QPRINTF("\n");
        break;
      }
      case 4: {
        uint64_t kind = r.Below(3);
        std::string path = kind == 0   ? std::string()
                           : kind == 1 ? "/" + GenPathText(r)
                                       : GenPathText(r);
        QPRINTF("  absolute ");
        PrintQuoted(path);
        QPRINTF(" -> ");
        PrintQuoted(fml::paths::AbsolutePath(path));
        QPRINTF("\n");
        break;
      }
      default: {
        auto exe = fml::paths::GetExecutablePath();
        auto exe_dir = fml::paths::GetExecutableDirectoryPath();
        QPRINTF("  exe %d %d dir %d %d caches %d\n", exe.first,
                    !exe.second.empty() && exe.second[0] == '/',
                    exe_dir.first,
                    exe_dir.second == fml::paths::GetDirectoryName(exe.second),
                    fml::paths::GetCachesDirectory().is_valid());
        break;
      }
    }
  }
  if (::chdir(original.c_str()) != 0) {
    std::abort();
  }
}

// ------------------------------------------------------- command line ------

const std::string kArgTokens[] = {
    "prog",  "",      "-",       "-x",      "--",   "--a",    "--b",
    "--a=1", "--a=",  "--=",     "--=v",    "--==", "--===",  "--==x",
    "--a=b=c", "--\xc3\xa9=\xc3\xbc", std::string("--a\0b=z", 7), "pos",
    "--b=2", "arg",   "\xc3\xa9"};
constexpr uint64_t kArgTokenCount = 21;

const std::string kOptionNames[] = {"a", "b", "", "=", std::string("a\0b", 3),
                                    "x", "\xc3\xa9", "a=1"};

void PrintCommandLine(const fml::CommandLine& cl) {
  QPRINTF(" argv0 %d ", cl.has_argv0());
  PrintQuoted(cl.argv0());
  QPRINTF(" opts");
  for (const auto& option : cl.options()) {
    QPRINTF(" ");
    PrintQuoted(option.name);
    QPRINTF("=");
    PrintQuoted(option.value);
  }
  QPRINTF(" pos");
  for (const auto& arg : cl.positional_args()) {
    QPRINTF(" ");
    PrintQuoted(arg);
  }
  QPRINTF("\n");
}

void SuiteCmdline(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    std::vector<std::string> argv(r.Below(7));
    for (auto& arg : argv) {
      arg = kArgTokens[r.Below(kArgTokenCount)];
    }
    std::vector<std::string>::const_iterator first;
    auto cl = fml::CommandLineFromIteratorsFindFirstPositionalArg(
        argv.cbegin(), argv.cend(), &first);
    QPRINTF("  parse first %ld", static_cast<long>(first - argv.cbegin()));
    PrintCommandLine(cl);
    for (int q = 0; q < 3; q++) {
      const std::string& name = kOptionNames[r.Below(8)];
      size_t index = 12345;
      bool has = cl.HasOption(name, &index);
      std::string value = "untouched";
      bool got = cl.GetOptionValue(name, &value);
      auto values = cl.GetOptionValues(name);
      std::string with_default = cl.GetOptionValueWithDefault(name, "dflt");
      QPRINTF("  query ");
      PrintQuoted(name);
      QPRINTF(" has %d %zu got %d ", has, index, got);
      PrintQuoted(value);
      QPRINTF(" values");
      for (auto v : values) {
        QPRINTF(" ");
        PrintQuoted(std::string(v));
      }
      QPRINTF(" default ");
      PrintQuoted(with_default);
      QPRINTF("\n");
    }
    auto args = fml::CommandLineToArgv(cl);
    QPRINTF("  argv");
    for (const auto& arg : args) {
      QPRINTF(" ");
      PrintQuoted(arg);
    }
    auto again = fml::CommandLineFromIterators(args.begin(), args.end());
    QPRINTF(" roundtrip %d\n", again == cl);
    size_t k = r.Below(argv.size() + 1);
    auto with0 = fml::CommandLineFromIteratorsWithArgv0("p0", argv.cbegin() + k,
                                                        argv.cend());
    QPRINTF("  with-argv0 %zu", k);
    PrintCommandLine(with0);
    fml::CommandLine built(cl.argv0(), cl.options(), cl.positional_args());
    fml::CommandLine copy = cl;
    fml::CommandLine moved = std::move(copy);
    fml::CommandLine assigned;
    bool empty_equal = assigned == cl;
    assigned = moved;
    QPRINTF("  components %d %d copy %d empty %d assigned %d\n",
                built == cl, built.HasOption("a"), moved == cl, empty_equal,
                assigned == cl);
  }
}

// -------------------------------------------------------------- misc ------

uint64_t GenU64(Rng& r) {
  switch (r.Below(6)) {
    case 0:
      return 0;
    case 1:
      return r.Below(1000);
    case 2:
      return 0xffffffffULL - r.Below(3);
    case 3:
      return (1ULL << 32) + r.Below(3);
    case 4:
      return ~0ULL >> r.Below(64);
    default:
      return r.Next();
  }
}

void SuiteMisc(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(5)) {
      case 0:
      case 1: {
        bool ordered = r.Chance(2);
        uint64_t n = r.Below(8);
        std::vector<std::pair<int, int>> entries;
        for (uint64_t k = 0; k < n; k++) {
          int key = static_cast<int>(r.Below(16));
          int value = static_cast<int>(r.Below(16));
          entries.emplace_back(key, value);
        }
        int mod = 1 + static_cast<int>(r.Below(4));
        int rem = static_cast<int>(r.Below(mod));
        std::map<int, int> result;
        if (ordered) {
          std::map<int, int> m;
          for (auto [k, v] : entries) {
            m[k] = v;
          }
          QPRINTF("  map visits");
          fml::erase_if(m, [&](std::map<int, int>::iterator it) {
            QPRINTF(" %d", it->first);
            return (it->first + it->second) % mod == rem;
          });
          result = m;
        } else {
          std::unordered_map<int, int> m;
          for (auto [k, v] : entries) {
            m[k] = v;
          }
          QPRINTF("  unordered");
          fml::erase_if(m, [&](std::unordered_map<int, int>::iterator it) {
            return (it->first + it->second) % mod == rem;
          });
          result = std::map<int, int>(m.begin(), m.end());
        }
        QPRINTF(" keep");
        for (auto [k, v] : result) {
          QPRINTF(" %d:%d", k, v);
        }
        QPRINTF("\n");
        break;
      }
      case 2: {
        fml::SafeMath safe;
        int steps = 1 + static_cast<int>(r.Below(4));
        for (int s = 0; s < steps; s++) {
          uint64_t x = GenU64(r);
          uint64_t y = GenU64(r);
          size_t product = safe.mul(x, y);
          QPRINTF("  mul %" PRIu64 " %" PRIu64 " = %zu overflow %d\n", x, y,
                      product, safe.overflow_detected());
        }
        break;
      }
      case 3: {
        std::string text = GenPathText(r);
        char* copy = fml::strdup(text.c_str());
        QPRINTF("  strdup ");
        PrintQuoted(text);
        QPRINTF(" -> ");
        PrintQuoted(copy);
        QPRINTF(" %d\n", copy != text.c_str());
        std::free(copy);
        break;
      }
      default:
        QPRINTF("  pid %d\n", fml::GetCurrentProcId() == ::getpid());
        break;
    }
  }
}

// ---------------------------------------------------------- affinity ------

const char* const kAffinityNames[] = {"performance", "efficiency",
                                      "not-performance", "not-efficiency"};

std::string GenNumberText(Rng& r) {
  switch (r.Below(12)) {
    case 0:
      return "0x1A";
    case 1:
      return "whoa this isnt a number";
    default:
      break;
  }
  static const char kSpace[] = {' ', '\t', '\n', '\v', '\f', '\r'};
  static const char* const kSuffixes[] = {"", "abc", " 77", "\n", ".5", "x1",
                                          "e3"};
  std::string s;
  uint64_t spaces = r.Below(3);
  for (uint64_t i = 0; i < spaces; i++) {
    s += kSpace[r.Below(6)];
  }
  uint64_t sign = r.Below(4);
  if (sign == 0) {
    s += '+';
  } else if (sign == 1) {
    s += '-';
  }
  if (!r.Chance(4)) {
    uint64_t digits = 1 + r.Below(24);
    for (uint64_t i = 0; i < digits; i++) {
      s += static_cast<char>('0' + r.Below(10));
    }
  }
  s += kSuffixes[r.Below(7)];
  return s;
}

void SuiteAffinity(Rng& r, int cases) {
  fml::ScopedTemporaryDirectory dir;
  QPRINTF("efficiency-count %d request",
              fml::EfficiencyCoreCount().has_value());
  for (int a = 0; a < 4; a++) {
    QPRINTF(" %d",
                fml::RequestAffinity(static_cast<fml::CpuAffinity>(a)));
  }
  QPRINTF("\n");
  static const int64_t kSpeeds[] = {1,  2,       3,       1800000, 2400000,
                                    -1, 0, kI64Max, kI64Min};
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    if (r.Chance(2)) {
      std::vector<fml::CpuIndexAndSpeed> speeds(r.Below(7));
      QPRINTF("  tracker");
      for (auto& s : speeds) {
        s.index = r.Below(8);
        s.speed = kSpeeds[r.Below(9)];
        QPRINTF(" %zu:%" PRId64, s.index, s.speed);
      }
      fml::CPUSpeedTracker tracker(speeds);
      QPRINTF(" valid %d\n", tracker.IsValid());
      for (int a = 0; a < 4; a++) {
        QPRINTF("    %s", kAffinityNames[a]);
        for (size_t index :
             tracker.GetIndices(static_cast<fml::CpuAffinity>(a))) {
          QPRINTF(" %zu", index);
        }
        QPRINTF("\n");
      }
    } else {
      uint64_t kind = r.Below(8);
      std::string path = dir.path() + "/speed";
      std::string text;
      if (kind == 0) {
        path = dir.path() + "/missing";
      } else if (kind == 1) {
        path = dir.path();
      } else {
        text = GenNumberText(r);
        auto fd = fml::OpenFile(dir.fd(), "speed", true,
                                fml::FilePermission::kReadWrite);
        fml::TruncateFile(fd, 0);
        if (!text.empty()) {
          fml::DataMapping data(text);
          fml::WriteAtomically(dir.fd(), "speed", data);
        }
      }
      auto value = fml::ReadIntFromFile(path);
      QPRINTF("  read %d ", static_cast<int>(kind));
      PrintQuoted(text);
      QPRINTF(" -> %d %" PRId64 "\n", value.has_value(),
                  value.value_or(0));
    }
  }
}

// ------------------------------------------------------------ native ------

const char* const kSymbols[] = {"strlen", "malloc", "IO_putc", "_IO_putc",
                                "no_such_symbol", ""};

void ResolveSome(Rng& r, const fml::RefPtr<fml::NativeLibrary>& lib) {
  for (int s = 0; s < 2; s++) {
    const char* symbol = kSymbols[r.Below(6)];
    QPRINTF("    resolve ");
    PrintQuoted(symbol);
    QPRINTF(" -> %d\n", lib->ResolveSymbol(symbol) != nullptr);
  }
}

void SuiteNative(Rng& r, int cases) {
  fml::ScopedTemporaryDirectory dir;
  fml::DataMapping not_a_library(std::string("hello"));
  fml::WriteAtomically(dir.fd(), "notalib", not_a_library);
  const std::string libraries[] = {"libc.so.6",
                                   "libm.so.6",
                                   "/nonexistent/libnope.so",
                                   "",
                                   dir.path() + "/notalib",
                                   dir.path(),
                                   "libpthread.so.0"};
  auto libc = fml::NativeLibrary::Create("libc.so.6");
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(5)) {
      case 0: {
        const std::string& path = libraries[r.Below(7)];
        auto lib = fml::NativeLibrary::Create(path.c_str());
        QPRINTF("  create ");
        PrintQuoted(path);
        QPRINTF(" -> %d\n", static_cast<bool>(lib));
        if (lib) {
          ResolveSome(r, lib);
        }
        break;
      }
      case 1: {
        auto lib = fml::NativeLibrary::CreateForCurrentProcess();
        QPRINTF("  process %d\n", static_cast<bool>(lib));
        ResolveSome(r, lib);
        QPRINTF("    same-strlen %d\n",
                    lib->ResolveSymbol("strlen") ==
                        libc->ResolveSymbol("strlen"));
        break;
      }
      case 2: {
        bool null = r.Chance(3);
        bool close = r.Chance(2);
        void* handle = null ? nullptr : ::dlopen("libm.so.6", RTLD_NOW);
        {
          auto lib = fml::NativeLibrary::CreateWithHandle(handle, close);
          QPRINTF("  handle %d close %d -> %d", null, close,
                      static_cast<bool>(lib));
          if (lib) {
            QPRINTF(" cos %d", lib->ResolveSymbol("cos") != nullptr);
          }
          QPRINTF("\n");
        }
        if (handle != nullptr && !close) {
          ::dlclose(handle);
        }
        break;
      }
      case 3: {
        uint64_t which = r.Below(3);
        bool null_name = r.Chance(5);
        const char* symbol = kSymbols[r.Below(6)];
        fml::RefPtr<fml::NativeLibrary> lib =
            which == 0   ? nullptr
            : which == 1 ? fml::NativeLibrary::CreateForCurrentProcess()
                         : libc;
        fml::SymbolMapping m(lib, null_name ? nullptr : symbol);
        QPRINTF("  symbol %d ", static_cast<int>(which));
        PrintQuoted(null_name ? std::string("<null>") : std::string(symbol));
        QPRINTF(" size %zu null %d dontneed %d\n", m.GetSize(),
                    m.GetMapping() == nullptr, m.IsDontNeedSafe());
        break;
      }
      default: {
        std::string text = GenPathText(r);
        auto strlen_fn =
            libc->ResolveFunction<size_t (*)(const char*)>("strlen");
        auto missing =
            libc->ResolveFunction<size_t (*)(const char*)>("no_such_symbol");
        QPRINTF("  call %d %d ", strlen_fn.has_value(),
                    missing.has_value());
        PrintQuoted(text);
        QPRINTF(" -> %zu\n", strlen_fn.value()(text.c_str()));
        break;
      }
    }
  }
}

// ------------------------------------------------------------- trace ------

void PrintTraceEvent(const char* label,
                     int64_t timestamp0,
                     int64_t timestamp1_or_async_id,
                     intptr_t flow_id_count,
                     const int64_t* flow_ids,
                     Dart_Timeline_Event_Type type,
                     intptr_t argument_count,
                     const char** argument_names,
                     const char** argument_values) {
  QPRINTF("    event %d ", static_cast<int>(type));
  PrintQuoted(label);
  QPRINTF(" %" PRId64 " %" PRId64 " flows", timestamp0,
              timestamp1_or_async_id);
  for (intptr_t i = 0; i < flow_id_count; i++) {
    QPRINTF(" %" PRId64, flow_ids[i]);
  }
  QPRINTF(" args");
  for (intptr_t i = 0; i < argument_count; i++) {
    QPRINTF(" ");
    PrintQuoted(argument_names[i]);
    QPRINTF("=");
    PrintQuoted(argument_values[i]);
  }
  QPRINTF("\n");
}

int64_t g_trace_clock = 0;

int64_t CountingMicros() {
  return g_trace_clock += 3;
}

int64_t ConstantMicros() {
  return 7;
}

const char* const kTraceLabels[] = {"frame", "raster", "fml::OpenFile", "ui",
                                    "Frame Build", "a", ""};
const char* const kTraceWords[] = {"fr", "frame", "ra", "fml", "", "u"};

const char* TraceLabel(Rng& r) {
  return kTraceLabels[r.Below(7)];
}

double GenTraceDouble(Rng& r) {
  static const double kValues[] = {0.0,     -0.0, 1.5,
                                   -2.25,   1e20, 3.14159265358979,
                                   1e-7,    std::numeric_limits<double>::infinity(),
                                   -std::numeric_limits<double>::infinity(),
                                   std::numeric_limits<double>::quiet_NaN()};
  return kValues[r.Below(10)];
}

fml::TimePoint GenTracePoint(Rng& r) {
  return fml::TimePoint::FromEpochDelta(fml::TimeDelta::FromMicroseconds(
      static_cast<int64_t>(r.Below(2000000000001ULL)) - 1000000000000LL));
}

void SuiteTrace(Rng& r, int cases) {
  fml::tracing::TraceSetTimelineMicrosSource(CountingMicros);
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    switch (r.Below(16)) {
      case 0: {
        std::vector<std::string> allowlist(r.Below(4));
        QPRINTF("  allow");
        for (auto& word : allowlist) {
          word = kTraceWords[r.Below(6)];
          QPRINTF(" ");
          PrintQuoted(word);
        }
        QPRINTF("\n");
        fml::tracing::TraceSetAllowlist(allowlist);
        break;
      }
      case 1: {
        bool set = !r.Chance(3);
        fml::tracing::TraceSetTimelineEventHandler(set ? PrintTraceEvent
                                                       : nullptr);
        bool has = fml::tracing::TraceHasTimelineEventHandler();
        QPRINTF("  handler %d %d\n", set, has);
        break;
      }
      case 2: {
        bool counting = !r.Chance(4);
        fml::tracing::TraceSetTimelineMicrosSource(
            counting ? CountingMicros : ConstantMicros);
        int64_t micros = fml::tracing::TraceGetTimelineMicros();
        QPRINTF("  micros %d %" PRId64 "\n", counting, micros);
        break;
      }
      case 3: {
        const char* label = TraceLabel(r);
        QPRINTF("  event0\n");
        {
          TRACE_EVENT0("flutter", label);
          QPRINTF("  inside\n");
        }
        break;
      }
      case 4: {
        const char* label = TraceLabel(r);
        const char* value = TraceLabel(r);
        QPRINTF("  event1\n");
        {
          TRACE_EVENT1("flutter", label, "k", value);
          QPRINTF("  inside\n");
        }
        break;
      }
      case 5: {
        const char* label = TraceLabel(r);
        const char* v1 = TraceLabel(r);
        const char* v2 = TraceLabel(r);
        QPRINTF("  event2\n");
        {
          TRACE_EVENT2("flutter", label, "k1", v1, "k2", v2);
          QPRINTF("  inside\n");
        }
        break;
      }
      case 6: {
        const char* label = TraceLabel(r);
        uint64_t form = r.Below(4);
        int64_t n = EdgeI64(r);
        double d = GenTraceDouble(r);
        fml::TimePoint t = GenTracePoint(r);
        QPRINTF("  fml-event %d\n", static_cast<int>(form));
        switch (form) {
          case 0: {
            FML_TRACE_EVENT("flutter", label, "i", static_cast<int>(n));
            QPRINTF("  inside\n");
            break;
          }
          case 1: {
            FML_TRACE_EVENT("flutter", label, "s", std::string(TraceLabel(r)),
                            "d", d);
            QPRINTF("  inside\n");
            break;
          }
          case 2: {
            FML_TRACE_EVENT("flutter", label, "b", n % 2 == 0, "c", "chars",
                            "t", t);
            QPRINTF("  inside\n");
            break;
          }
          default: {
            FML_TRACE_EVENT("flutter", label, "u", static_cast<uint64_t>(n),
                            "f", static_cast<float>(d), "n", n);
            QPRINTF("  inside\n");
            break;
          }
        }
        break;
      }
      case 7: {
        const char* label = TraceLabel(r);
        int64_t id = EdgeI64(r);
        bool two = r.Chance(2);
        int64_t n = EdgeI64(r);
        double d = GenTraceDouble(r);
        QPRINTF("  counter %d\n", two);
        if (two) {
          FML_TRACE_COUNTER("flutter", label, id, "x", d, "y", "str");
        } else {
          FML_TRACE_COUNTER("flutter", label, id, "x", n);
        }
        break;
      }
      case 8: {
        const char* label = TraceLabel(r);
        int64_t id = EdgeI64(r);
        const char* value = TraceLabel(r);
        uint64_t which = r.Below(4);
        QPRINTF("  async %d\n", static_cast<int>(which));
        switch (which) {
          case 0:
            TRACE_EVENT_ASYNC_BEGIN0("flutter", label, id);
            break;
          case 1:
            TRACE_EVENT_ASYNC_END0("flutter", label, id);
            break;
          case 2:
            TRACE_EVENT_ASYNC_BEGIN1("flutter", label, id, "k", value);
            break;
          default:
            // Not TRACE_EVENT_ASYNC_END1: upstream's macro passes a flow id
            // count and flow ids that TraceEventAsyncEnd1 does not take, so
            // it does not compile.
            fml::tracing::TraceEventAsyncEnd1("flutter", label, id, "k", value);
            break;
        }
        break;
      }
      case 9: {
        const char* label = TraceLabel(r);
        const char* v1 = TraceLabel(r);
        const char* v2 = TraceLabel(r);
        uint64_t which = r.Below(3);
        QPRINTF("  instant %d\n", static_cast<int>(which));
        switch (which) {
          case 0:
            TRACE_EVENT_INSTANT0("flutter", label);
            break;
          case 1:
            TRACE_EVENT_INSTANT1("flutter", label, "k", v1);
            break;
          default:
            TRACE_EVENT_INSTANT2("flutter", label, "k1", v1, "k2", v2);
            break;
        }
        break;
      }
      case 10: {
        const char* label = TraceLabel(r);
        int64_t id = EdgeI64(r);
        uint64_t which = r.Below(3);
        QPRINTF("  flow %d\n", static_cast<int>(which));
        switch (which) {
          case 0:
            TRACE_FLOW_BEGIN("flutter", label, id);
            break;
          case 1:
            TRACE_FLOW_STEP("flutter", label, id);
            break;
          default:
            TRACE_FLOW_END("flutter", label, id);
            break;
        }
        break;
      }
      case 11: {
        const char* label = TraceLabel(r);
        fml::TimePoint begin = GenTracePoint(r);
        fml::TimePoint end = GenTracePoint(r);
        bool args = r.Chance(2);
        QPRINTF("  complete %d\n", args);
        if (args) {
          fml::tracing::TraceEventAsyncComplete("flutter", label, begin, end,
                                                "k", "v");
        } else {
          fml::tracing::TraceEventAsyncComplete("flutter", label, begin, end);
        }
        break;
      }
      case 12: {
        const char* label = TraceLabel(r);
        const char* other = TraceLabel(r);
        uint64_t steps = r.Below(3);
        bool named_step = r.Chance(2);
        bool end = r.Chance(2);
        bool move = r.Chance(3);
        QPRINTF("  traceflow %d %d %d %d\n", static_cast<int>(steps),
                    named_step, end, move);
        fml::tracing::TraceFlow flow(label);
        for (uint64_t s = 0; s < steps; s++) {
          flow.Step(named_step ? other : nullptr);
        }
        if (move) {
          fml::tracing::TraceFlow moved(std::move(flow));
          moved.Step();
        }
        if (end) {
          flow.End(other);
        }
        break;
      }
      case 13: {
        const char* label = TraceLabel(r);
        uint64_t ids[3];
        size_t count = r.Below(4);
        for (size_t k = 0; k < count; k++) {
          ids[k] = static_cast<uint64_t>(EdgeI64(r));
        }
        bool one = r.Chance(2);
        const char* value = TraceLabel(r);
        QPRINTF("  with-flows %zu %d\n", count, one);
        if (one) {
          TRACE_EVENT1_WITH_FLOW_IDS("flutter", label, count, ids, "k", value);
          QPRINTF("  inside\n");
        } else {
          TRACE_EVENT0_WITH_FLOW_IDS("flutter", label, count, ids);
          QPRINTF("  inside\n");
        }
        break;
      }
      case 14: {
        const char* label = TraceLabel(r);
        int a = static_cast<int>(EdgeI64(r));
        int64_t b = EdgeI64(r);
        QPRINTF("  event2-int\n");
        {
          TRACE_EVENT2_INT("flutter", label, "a", a, "b", b);
          QPRINTF("  inside\n");
        }
        break;
      }
      default: {
        size_t nonce = fml::tracing::TraceNonce();
        QPRINTF("  openfile nonce %zu\n", nonce);
        fml::OpenFile("/nonexistent-fml-oracle", false,
                      fml::FilePermission::kRead);
        break;
      }
    }
  }
  fml::tracing::TraceSetTimelineEventHandler(nullptr);
}

// --------------------------------------------------------- backtrace ------

// Checks a backtrace's shape: lines "Frame <i>: 0x<hex> <name>" numbered
// from 0. Which frames and names a binary has differs between the C++ and
// the Rust one, so only the shape is printed.
std::string BacktraceShape(const std::string& trace) {
  if (trace.empty()) {
    return "empty";
  }
  size_t pos = 0;
  int expected = 0;
  while (pos < trace.size()) {
    size_t eol = trace.find('\n', pos);
    if (eol == std::string::npos) {
      return "unterminated";
    }
    std::string line = trace.substr(pos, eol - pos);
    std::string prefix = "Frame " + std::to_string(expected) + ": 0x";
    if (line.rfind(prefix, 0) != 0) {
      return "bad-number";
    }
    size_t i = prefix.size();
    size_t hex_start = i;
    while (i < line.size() && std::isxdigit(static_cast<unsigned char>(line[i]))) {
      i++;
    }
    if (i == hex_start || i + 1 >= line.size() || line[i] != ' ') {
      return "bad-frame";
    }
    expected++;
    pos = eol + 1;
  }
  return "ok";
}

// BacktraceHere under eight more frames of the driver's own, so that the
// C++ and the Rust binary (whose stacks below main differ in depth) both
// have frames past every offset the suite skips.
__attribute__((noinline)) std::string DeepBacktrace(int depth, size_t offset) {
  if (depth == 0) {
    return fml::BacktraceHere(offset);
  }
  std::string trace = DeepBacktrace(depth - 1, offset);
  asm volatile("" : : "r"(trace.data()) : "memory");
  return trace;
}

const int kCrashSignals[] = {SIGABRT, SIGFPE,  SIGTERM, SIGSEGV,
                             SIGBUS,  SIGSYS, SIGPIPE, SIGALRM};

void CrashChild(int signal) {
  fml::InstallCrashHandler();
  ::raise(signal);
  QPRINTF("survived\n");
}

void RunCrashChild(int signal) {
  int err[2];
  if (pipe(err) != 0) {
    std::abort();
  }
  std::fflush(stdout);
  pid_t pid = fork();
  if (pid == 0) {
    dup2(err[1], 2);
    int devnull = open("/dev/null", O_WRONLY);
    dup2(devnull, 1);
    close(err[0]);
    close(err[1]);
    std::string s = std::to_string(signal);
    execl("/proc/self/exe", "fml_dump", "crash", s.c_str(), "0", nullptr);
    _exit(127);
  }
  close(err[1]);
  std::string out;
  char buf[256];
  ssize_t n;
  while ((n = read(err[0], buf, sizeof buf)) > 0) {
    out.append(buf, n);
  }
  close(err[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  // "[ERROR:...] Caught signal ... execution.\n" + frames + "\n".
  size_t eol = out.find('\n');
  std::string header = out.substr(0, eol);
  std::string frames =
      eol == std::string::npos ? "" : out.substr(eol + 1);
  bool tail = frames.size() >= 2 && frames.compare(frames.size() - 2, 2, "\n\n") == 0;
  if (tail) {
    frames.resize(frames.size() - 1);
  }
  QPRINTF("  child %s %d ", WIFSIGNALED(status) ? "signal" : "exit",
              WIFSIGNALED(status) ? WTERMSIG(status) : WEXITSTATUS(status));
  PrintEscaped(header);
  QPRINTF(" frames %s tail %d\n", BacktraceShape(frames).c_str(), tail);
}

void SuiteBacktrace(Rng& r, int cases) {
  QPRINTF("supported %d\n", fml::IsCrashHandlingSupported());
  for (int i = 0; i < cases; i++) {
    QPRINTF("case %d\n", i);
    if (r.Chance(4)) {
      int signal = kCrashSignals[r.Below(8)];
      QPRINTF("  crash %d\n", signal);
      RunCrashChild(signal);
    } else {
      static const size_t kOffsets[] = {0, 1, 2, 3, 300};
      size_t offset = kOffsets[r.Below(5)];
      QPRINTF("  here %zu %s\n", offset,
                  BacktraceShape(DeepBacktrace(8, offset)).c_str());
    }
  }
}

// -------------------------------------------------------------- bench ------

// flutter/fml/message_loop_unittests.cc's NonDelayedTasksAreRunInOrder at
// 10000 tasks: post them, then run the loop until the last one terminates it.
void BenchLoop() {
  // Only the loop's thread is timed, not spawning and joining it.
  std::thread thread([]() {
    SwResume();
    fml::MessageLoop::EnsureInitializedForCurrentThread();
    auto& loop = fml::MessageLoop::GetCurrent();
    const size_t count = 10000;
    size_t current = 0;
    for (size_t i = 0; i < count; i++) {
      loop.GetTaskRunner()->PostTask([i, &current]() {
        current++;
        if (i + 1 == count) {
          fml::MessageLoop::GetCurrent().Terminate();
        }
      });
    }
    loop.Run();
    SwPause();
    if (current != count) {
      std::abort();
    }
  });
  thread.join();
}

// An fml::Thread that 10000 tasks are posted to from another thread, then
// joined.
void BenchThread() {
  fml::Thread thread("bench");
  std::atomic<size_t> ran{0};
  for (size_t i = 0; i < 10000; i++) {
    thread.GetTaskRunner()->PostTask([&ran]() { ran++; });
  }
  thread.Join();
  if (ran != 10000) {
    std::abort();
  }
}

// A four-worker ConcurrentMessageLoop running 10000 tasks.
void BenchConcurrent() {
  auto loop = fml::ConcurrentMessageLoop::Create(4);
  auto runner = loop->GetTaskRunner();
  fml::CountDownLatch latch(10000);
  for (size_t i = 0; i < 10000; i++) {
    runner->PostTask([&latch]() { latch.CountDown(); });
  }
  latch.Wait();
}

// flutter/fml/message_loop_task_queues_benchmark.cc, BM_RegisterAndGetTasks,
// one iteration of its loop body.
void BenchRegisterAndGetTasks() {
  auto task_queue = fml::MessageLoopTaskQueues::GetInstance();
  const int num_task_queues = 10;
  const int num_tasks_per_queue = 100;
  const fml::TimePoint past = fml::TimePoint::Now();
  for (int i = 0; i < num_task_queues; i++) {
    task_queue->CreateTaskQueue();
  }
  std::vector<std::thread> threads;
  fml::CountDownLatch tasks_registered(num_task_queues);
  fml::CountDownLatch tasks_done(num_task_queues);
  threads.reserve(num_task_queues);
  for (int i = 0; i < num_task_queues; i++) {
    threads.emplace_back([task_runner_id = i, &task_queue, past, &tasks_done,
                          &tasks_registered]() {
      for (int j = 0; j < num_tasks_per_queue; j++) {
        task_queue->RegisterTask(fml::TaskQueueId(task_runner_id), [] {}, past);
      }
      tasks_registered.CountDown();
      tasks_registered.Wait();
      const auto now = fml::TimePoint::Now();
      int num_invocations = 0;
      for (;;) {
        fml::closure invocation =
            task_queue->GetNextTaskToRun(fml::TaskQueueId(task_runner_id), now);
        if (!invocation) {
          break;
        }
        num_invocations++;
      }
      if (num_invocations != num_tasks_per_queue) {
        std::abort();
      }
      tasks_done.CountDown();
    });
  }
  tasks_done.Wait();
  for (auto& thread : threads) {
    thread.join();
  }
}

long PeakRssKiB() {
  FILE* f = std::fopen("/proc/self/status", "r");
  if (!f) {
    return -1;
  }
  char line[256];
  long kib = -1;
  while (std::fgets(line, sizeof line, f)) {
    if (std::strncmp(line, "VmHWM:", 6) == 0) {
      kib = std::strtol(line + 6, nullptr, 10);
    }
  }
  std::fclose(f);
  return kib;
}

// The suites that call cheap functions (time, strings, hash, paths,
// cmdline) are benchmarked as kernels: a chunk of inputs is drawn with the
// clock stopped, then only the ported calls run while it runs, each result
// folded into a checksum that both drivers must agree on (so neither can
// drop the work). The same inputs, calls and folds as src/bin/fml_dump.rs.

constexpr size_t kChunk = 1000;

inline void Fold(uint64_t& h, uint64_t v) {
  h = ((h << 5) | (h >> 59)) ^ v;
}

struct TimeIn {
  int64_t a, b;
  double s, m;
  int64_t hz;
  double hzf;
};

uint64_t KernelTime(Rng& r, size_t cases) {
  using fml::TimeDelta;
  using fml::TimePoint;
  uint64_t h = 0;
  std::vector<TimeIn> input;
  input.reserve(kChunk);
  for (size_t done = 0; done < cases;) {
    size_t n = std::min(kChunk, cases - done);
    input.clear();
    for (size_t i = 0; i < n; i++) {
      TimeIn c;
      c.a = EdgeI64(r);
      c.b = EdgeI64(r);
      c.s = BoundedF64(r, 9.0e9);
      c.m = BoundedF64(r, 9.0e12);
      c.hz = static_cast<int64_t>(r.Below(240)) + 1;
      c.hzf = BoundedF64(r, 240.0);
      input.push_back(c);
    }
    SwResume();
    for (const TimeIn& c : input) {
      int64_t a = c.a, b = c.b;
      Fold(h, TimeDelta::FromNanoseconds(a).ToNanoseconds());
      Fold(h, TimeDelta::FromMicroseconds(a).ToNanoseconds());
      Fold(h, TimeDelta::FromMilliseconds(a).ToNanoseconds());
      Fold(h, TimeDelta::FromSeconds(a).ToNanoseconds());
      TimeDelta da = TimeDelta::FromNanoseconds(a);
      TimeDelta db = TimeDelta::FromNanoseconds(b);
      Fold(h, da.ToMicroseconds());
      Fold(h, da.ToMilliseconds());
      Fold(h, da.ToSeconds());
      Fold(h, Bits(da.ToNanosecondsF()));
      Fold(h, Bits(da.ToMicrosecondsF()));
      Fold(h, Bits(da.ToMillisecondsF()));
      Fold(h, Bits(da.ToSecondsF()));
      Fold(h, (da + db).ToNanoseconds());
      Fold(h, (da - db).ToNanoseconds());
      Fold(h, (da * b).ToNanoseconds());
      if (b != 0 && !(a == kI64Min && b == -1)) {
        Fold(h, (da / b).ToNanoseconds());
        Fold(h, da / db);
        Fold(h, (da % db).ToNanoseconds());
      }
      Fold(h, static_cast<uint64_t>(static_cast<int64_t>(Cmp(da, db))));
      Fold(h, da == db);
      Fold(h, da < db);
      Fold(h, da >= db);
      struct timespec ts{};
      ts.tv_sec = static_cast<time_t>(a);
      ts.tv_nsec = static_cast<long>(b % 1000000000);
      Fold(h, TimeDelta::FromTimespec(ts).ToNanoseconds());
      struct timespec out = da.ToTimespec();
      Fold(h, static_cast<int64_t>(out.tv_sec));
      Fold(h, static_cast<int64_t>(out.tv_nsec));
      TimePoint pa = TimePoint::FromTicks(a);
      TimePoint pb = TimePoint::FromEpochDelta(db);
      Fold(h, (pa - pb).ToNanoseconds());
      Fold(h, (pa + db).ToEpochDelta().ToNanoseconds());
      Fold(h, (pa - db).ToEpochDelta().ToNanoseconds());
      Fold(h, static_cast<uint64_t>(static_cast<int64_t>(Cmp(pa, pb))));
      Fold(h, TimeDelta::FromSecondsF(c.s).ToNanoseconds());
      Fold(h, TimeDelta::FromMillisecondsF(c.m).ToNanoseconds());
      Fold(h, Bits(fml::RefreshRateToFrameBudget(c.hz).count()));
      Fold(h, Bits(fml::RefreshRateToFrameBudget(c.hzf).count()));
    }
    SwPause();
    done += n;
  }
  return h;
}

struct StringsIn {
  std::u16string u16;
  std::string u8;
  std::vector<std::string> parts;
  const char* delim;
  std::filesystem::path path;
};

uint64_t KernelStrings(Rng& r, size_t cases) {
  uint64_t h = 0;
  std::vector<StringsIn> input;
  input.reserve(kChunk);
  for (size_t done = 0; done < cases;) {
    size_t n = std::min(kChunk, cases - done);
    input.clear();
    for (size_t i = 0; i < n; i++) {
      StringsIn c;
      c.u16 = GenUtf16(r);
      c.u8 = GenUtf8(r);
      int count = static_cast<int>(r.Below(5));
      for (int j = 0; j < count; j++) {
        std::string part;
        int len = static_cast<int>(r.Below(4));
        for (int k = 0; k < len; k++) {
          part.push_back(static_cast<char>('a' + r.Below(26)));
        }
        c.parts.push_back(part);
      }
      static const char* kDelims[] = {",", ", ", "", "--"};
      c.delim = kDelims[r.Below(4)];
      c.path = std::filesystem::path(GenBytes(r, 8));
      input.push_back(std::move(c));
    }
    SwResume();
    for (const StringsIn& c : input) {
      try {
        Fold(h, fml::Utf16ToUtf8(c.u16).size());
      } catch (const std::range_error&) {
        Fold(h, ~uint64_t{0});
      }
      try {
        Fold(h, fml::Utf8ToUtf16(c.u8).size());
      } catch (const std::range_error&) {
        Fold(h, ~uint64_t{0});
      }
      Fold(h, fml::Join(c.parts, c.delim).size());
      Fold(h, fml::PathToUtf8(c.path).size());
    }
    SwPause();
    done += n;
  }
  return h;
}

struct HashIn {
  int a;
  int64_t b;
  uint32_t c;
  bool d;
  std::string s, t;
  float f;
  double g;
  fml::TaskSourceGrade grade;
  uint8_t u8;
  int16_t i16;
  char ch;
  uint64_t u64;
  size_t seed;
};

uint64_t KernelHash(Rng& r, size_t cases) {
  uint64_t h = fml::HashCombine();
  std::vector<HashIn> input;
  input.reserve(kChunk);
  for (size_t done = 0; done < cases;) {
    size_t n = std::min(kChunk, cases - done);
    input.clear();
    for (size_t i = 0; i < n; i++) {
      HashIn c;
      c.a = static_cast<int>(r.Next());
      c.b = EdgeI64(r);
      c.c = static_cast<uint32_t>(r.Next());
      c.d = r.Chance(2);
      c.s = GenHashString(r);
      c.t = GenBytes(r, 80);
      c.f = GenF32(r);
      c.g = GenF64(r);
      c.grade = static_cast<fml::TaskSourceGrade>(r.Below(3));
      c.u8 = static_cast<uint8_t>(r.Next());
      c.i16 = static_cast<int16_t>(r.Next());
      c.ch = static_cast<char>(r.Next());
      c.u64 = r.Next();
      c.seed = r.Next();
      input.push_back(std::move(c));
    }
    SwResume();
    for (const HashIn& c : input) {
      Fold(h, fml::HashCombine(c.a));
      Fold(h, fml::HashCombine(c.b, c.c, c.d));
      Fold(h, fml::HashCombine(c.s));
      Fold(h, fml::HashCombine(c.t));
      Fold(h, fml::HashCombine(c.s, c.a, c.f, c.g));
      Fold(h, fml::HashCombine(c.grade, c.u8, c.i16, c.ch, c.u64));
      size_t seed = c.seed;
      fml::HashCombineSeed(seed, c.a, c.s);
      Fold(h, seed);
    }
    SwPause();
    done += n;
  }
  return h;
}

struct PathsIn {
  uint64_t kind;
  std::vector<std::string> c;
};

uint64_t KernelPaths(Rng& r, size_t cases) {
  fml::ScopedTemporaryDirectory dir;
  std::string original = std::filesystem::current_path().string();
  if (::chdir(dir.path().c_str()) != 0) {
    std::abort();
  }
  uint64_t h = 0;
  std::vector<PathsIn> input;
  input.reserve(kChunk);
  for (size_t done = 0; done < cases;) {
    size_t n = std::min(kChunk, cases - done);
    input.clear();
    for (size_t i = 0; i < n; i++) {
      PathsIn in;
      in.kind = r.Below(6);
      switch (in.kind) {
        case 0: {
          uint64_t count = r.Below(5);
          for (uint64_t k = 0; k < count; k++) {
            in.c.push_back(GenPathText(r));
          }
          break;
        }
        case 1:
          in.c.push_back(GenPathText(r));
          break;
        case 2:
          in.c.push_back(GenUriText(r));
          break;
        case 3: {
          static const char* const kPrefixes[] = {"file://", "file:/",
                                                  "FILE://", ""};
          std::string uri = kPrefixes[r.Below(4)];
          uri += GenUriText(r);
          in.c.push_back(uri);
          break;
        }
        case 4: {
          uint64_t kind = r.Below(3);
          in.c.push_back(kind == 0   ? std::string()
                         : kind == 1 ? "/" + GenPathText(r)
                                     : GenPathText(r));
          break;
        }
        default:
          break;
      }
      input.push_back(std::move(in));
    }
    SwResume();
    for (const PathsIn& in : input) {
      const auto& c = in.c;
      switch (in.kind) {
        case 0:
          switch (c.size()) {
            case 0:
              Fold(h, fml::paths::JoinPaths({}).size());
              break;
            case 1:
              Fold(h, fml::paths::JoinPaths({c[0]}).size());
              break;
            case 2:
              Fold(h, fml::paths::JoinPaths({c[0], c[1]}).size());
              break;
            case 3:
              Fold(h, fml::paths::JoinPaths({c[0], c[1], c[2]}).size());
              break;
            default:
              Fold(h, fml::paths::JoinPaths({c[0], c[1], c[2], c[3]}).size());
              break;
          }
          break;
        case 1:
          Fold(h, fml::paths::GetDirectoryName(c[0]).size());
          break;
        case 2:
          Fold(h, fml::paths::SanitizeURIEscapedCharacters(c[0]).size());
          break;
        case 3:
          Fold(h, fml::paths::FromURI(c[0]).size());
          break;
        case 4:
          Fold(h, fml::paths::AbsolutePath(c[0]).size());
          break;
        default: {
          auto exe = fml::paths::GetExecutablePath();
          auto exe_dir = fml::paths::GetExecutableDirectoryPath();
          Fold(h, exe.first);
          Fold(h, !exe.second.empty() && exe.second[0] == '/');
          Fold(h, exe_dir.first);
          Fold(h, exe_dir.second == fml::paths::GetDirectoryName(exe.second));
          Fold(h, fml::paths::GetCachesDirectory().is_valid());
          break;
        }
      }
    }
    SwPause();
    done += n;
  }
  if (::chdir(original.c_str()) != 0) {
    std::abort();
  }
  return h;
}

struct CmdlineIn {
  std::vector<std::string> argv;
  const std::string* names[3];
  std::string values[3];
  size_t k;
};

uint64_t KernelCmdline(Rng& r, size_t cases) {
  uint64_t h = 0;
  std::vector<CmdlineIn> input;
  input.reserve(kChunk);
  for (size_t done = 0; done < cases;) {
    size_t n = std::min(kChunk, cases - done);
    input.clear();
    for (size_t i = 0; i < n; i++) {
      CmdlineIn c;
      c.argv.resize(r.Below(7));
      for (auto& arg : c.argv) {
        arg = kArgTokens[r.Below(kArgTokenCount)];
      }
      for (auto& name : c.names) {
        name = &kOptionNames[r.Below(8)];
      }
      c.k = r.Below(c.argv.size() + 1);
      for (auto& value : c.values) {
        value = "untouched";
      }
      input.push_back(std::move(c));
    }
    SwResume();
    for (CmdlineIn& c : input) {
      std::vector<std::string>::const_iterator first;
      auto cl = fml::CommandLineFromIteratorsFindFirstPositionalArg(
          c.argv.cbegin(), c.argv.cend(), &first);
      Fold(h, first - c.argv.cbegin());
      for (int q = 0; q < 3; q++) {
        const std::string& name = *c.names[q];
        size_t index = 12345;
        cl.HasOption(name, &index);
        Fold(h, index);
        Fold(h, cl.GetOptionValue(name, &c.values[q]));
        Fold(h, c.values[q].size());
        Fold(h, cl.GetOptionValues(name).size());
        Fold(h, cl.GetOptionValueWithDefault(name, "dflt").size());
      }
      auto args = fml::CommandLineToArgv(cl);
      Fold(h, args.size());
      auto again = fml::CommandLineFromIterators(args.begin(), args.end());
      Fold(h, again == cl);
      auto with0 = fml::CommandLineFromIteratorsWithArgv0(
          "p0", c.argv.cbegin() + c.k, c.argv.cend());
      Fold(h, with0.options().size());
      Fold(h, with0.positional_args().size());
      fml::CommandLine built(cl.argv0(), cl.options(), cl.positional_args());
      fml::CommandLine copy = cl;
      fml::CommandLine moved = std::move(copy);
      fml::CommandLine assigned;
      bool empty_equal = assigned == cl;
      assigned = moved;
      Fold(h, built == cl);
      Fold(h, built.HasOption("a"));
      Fold(h, moved == cl);
      Fold(h, empty_equal);
      Fold(h, assigned == cl);
    }
    SwPause();
    done += n;
  }
  return h;
}

// Runs `name` `iterations` times and reports the fastest, median and slowest
// round of the stopwatch (only the ported code runs under it; see the bench
// clock above), the process's peak RSS, and a check value both drivers must
// agree on: a kernel's checksum, or for a suite the number of random draws it
// took.
void Bench(const std::string& name, int iterations) {
  g_quiet = true;
  std::vector<double> rounds;
  uint64_t check = 0;
  for (int i = 0; i < iterations; i++) {
    SwReset();
    Rng r{static_cast<uint64_t>(i)};
    auto timed = [](void (*f)()) {
      SwResume();
      f();
      SwPause();
    };
    auto suite = [&](auto run) {
      TapeStart(static_cast<uint64_t>(i));
      Rng tape{0};
      SwResume();
      run(tape);
      SwPause();
      check = TapeUsed();
      g_tape_on = false;
    };
    if (name == "queues") {
      timed(BenchRegisterAndGetTasks);
    } else if (name == "loop") {
      BenchLoop();
    } else if (name == "thread") {
      timed(BenchThread);
    } else if (name == "concurrent") {
      timed(BenchConcurrent);
    } else if (name == "time") {
      check = KernelTime(r, 20000);
    } else if (name == "strings") {
      check = KernelStrings(r, 20000);
    } else if (name == "hash") {
      check = KernelHash(r, 20000);
    } else if (name == "paths") {
      check = KernelPaths(r, 20000);
    } else if (name == "cmdline") {
      check = KernelCmdline(r, 20000);
    } else if (name == "dispatch") {
      suite([](Rng& t) { SuiteQueues(t, 2000); });
    } else if (name == "merger") {
      suite([](Rng& t) { SuiteMerger(t, 200); });
    } else if (name == "file") {
      suite([](Rng& t) { SuiteFile(t, 250); });
    } else if (name == "mapping") {
      suite([](Rng& t) { SuiteMapping(t, 2000); });
    } else if (name == "trace") {
      suite([](Rng& t) { SuiteTrace(t, 20000); });
    } else {
      std::fprintf(stderr, "unknown bench %s\n", name.c_str());
      std::exit(2);
    }
    rounds.push_back(g_sw_total_ns.load(std::memory_order_relaxed) / 1e3);
  }
  std::sort(rounds.begin(), rounds.end());
  std::fprintf(stderr,
               "bench %s fastest %.1f us median %.1f us slowest %.1f us "
               "peak_rss %ld KiB check %016" PRIx64 "\n",
               name.c_str(), rounds.front(), rounds[rounds.size() / 2],
               rounds.back(), PeakRssKiB(), check);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 4) {
    std::fprintf(stderr,
                 "usage: fml_dump <suite> <seed> <cases> | bench <name> <n>\n");
    return 2;
  }
  std::string suite = argv[1];
  if (suite == "bench") {
    std::freopen("/dev/null", "w", stdout);
    Bench(argv[2], std::atoi(argv[3]));
    return 0;
  }
  if (suite == "fatal") {
    FatalChild(std::strtoull(argv[2], nullptr, 10));
    return 0;
  }
  if (suite == "crash") {
    CrashChild(std::atoi(argv[2]));
    return 0;
  }
  Rng r{std::strtoull(argv[2], nullptr, 10)};
  int cases = std::atoi(argv[3]);
  bool all = suite == "all";
  bool known = false;
  if (all || suite == "time") { known = true; SuiteTime(r, cases); }
  if (all || suite == "strings") { known = true; SuiteStrings(r, cases); }
  if (all || suite == "codec") { known = true; SuiteCodec(r, cases); }
  if (all || suite == "hash") { known = true; SuiteHash(r, cases); }
  if (all || suite == "endian") { known = true; SuiteEndian(r, cases); }
  if (all || suite == "trie") { known = true; SuiteTrie(r, cases); }
  if (all || suite == "queues") { known = true; SuiteQueues(r, cases); }
  if (all || suite == "loop") { known = true; SuiteLoop(r, cases); }
  if (all || suite == "merger") { known = true; SuiteMerger(r, cases); }
  if (all || suite == "thread") { known = true; SuiteThread(r, cases); }
  if (all || suite == "logging") { known = true; SuiteLogging(r, cases); }
  if (all || suite == "file") { known = true; SuiteFile(r, cases); }
  if (all || suite == "mapping") { known = true; SuiteMapping(r, cases); }
  if (all || suite == "paths") { known = true; SuitePaths(r, cases); }
  if (all || suite == "cmdline") { known = true; SuiteCmdline(r, cases); }
  if (all || suite == "misc") { known = true; SuiteMisc(r, cases); }
  if (all || suite == "affinity") { known = true; SuiteAffinity(r, cases); }
  if (all || suite == "native") { known = true; SuiteNative(r, cases); }
  if (all || suite == "trace") { known = true; SuiteTrace(r, cases); }
  if (all || suite == "backtrace") { known = true; SuiteBacktrace(r, cases); }
  if (!known) {
    std::fprintf(stderr, "unknown suite %s\n", suite.c_str());
    return 2;
  }
  return 0;
}

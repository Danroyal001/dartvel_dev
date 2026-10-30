// Not an upstream file: the oracle driver for the Rust port of flutter/fml.
//
// Links the upstream C++ (the files named in ../README.md) and prints what it
// does on seeded random inputs. src/bin/fml_dump.rs is the same program over
// the port; the two outputs must be byte-identical.
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues loop merger thread
//                                              logging all
//   fml_dump bench <name> <iterations>  name: queues time strings hash
//                                              dispatch loop thread concurrent
//                                              merger
//   fml_dump fatal <seed> 0             (internal) the logging suite's child,
//                                       which logs at FATAL and dies
//
// Both drivers draw every input from the same splitmix64 stream, so a suite's
// output is a function of (suite, seed, cases) alone.

#include <algorithm>
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
#include <vector>

#include <fcntl.h>
#include <pthread.h>
#include <sys/wait.h>
#include <unistd.h>

#include "flutter/fml/ascii_trie.h"
#include "flutter/fml/base32.h"
#include "flutter/fml/concurrent_message_loop.h"
#include "flutter/fml/endianness.h"
#include "flutter/fml/hash_combine.h"
#include "flutter/fml/hex_codec.h"
#include "flutter/fml/log_settings.h"
#include "flutter/fml/logging.h"
#include "flutter/fml/memory/task_runner_checker.h"
#include "flutter/fml/message_loop.h"
#include "flutter/fml/message_loop_task_queues.h"
#include "flutter/fml/raster_thread_merger.h"
#include "flutter/fml/string_conversion.h"
#include "flutter/fml/synchronization/count_down_latch.h"
#include "flutter/fml/synchronization/waitable_event.h"
#include "flutter/fml/task_runner.h"
#include "flutter/fml/task_runner_util.h"
#include "flutter/fml/thread.h"
#include "flutter/fml/time/time_delta.h"
#include "flutter/fml/time/time_point.h"

namespace {

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
  if (s.empty()) {
    std::fputs("-", stdout);
    return;
  }
  for (unsigned char c : s) {
    std::printf("%02x", c);
  }
}

void PrintHex16(const std::u16string& s) {
  if (s.empty()) {
    std::fputs("-", stdout);
    return;
  }
  for (char16_t c : s) {
    std::printf("%04x", static_cast<unsigned>(c));
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
  std::printf("frame_budget %016" PRIx64 "\n",
              Bits(fml::kDefaultFrameBudget.count()));
  for (int i = 0; i < cases; i++) {
    int64_t a = EdgeI64(r);
    int64_t b = EdgeI64(r);
    std::printf("case %d a=%" PRId64 " b=%" PRId64 "\n", i, a, b);
    std::printf("from %" PRId64 " %" PRId64 " %" PRId64 " %" PRId64 "\n",
                TimeDelta::FromNanoseconds(a).ToNanoseconds(),
                TimeDelta::FromMicroseconds(a).ToNanoseconds(),
                TimeDelta::FromMilliseconds(a).ToNanoseconds(),
                TimeDelta::FromSeconds(a).ToNanoseconds());
    TimeDelta da = TimeDelta::FromNanoseconds(a);
    TimeDelta db = TimeDelta::FromNanoseconds(b);
    std::printf("to %" PRId64 " %" PRId64 " %" PRId64 "\n",
                da.ToMicroseconds(), da.ToMilliseconds(), da.ToSeconds());
    std::printf("tof %016" PRIx64 " %016" PRIx64 " %016" PRIx64
                " %016" PRIx64 "\n",
                Bits(da.ToNanosecondsF()), Bits(da.ToMicrosecondsF()),
                Bits(da.ToMillisecondsF()), Bits(da.ToSecondsF()));
    std::printf("add %" PRId64 " sub %" PRId64 " mul %" PRId64 "\n",
                (da + db).ToNanoseconds(), (da - db).ToNanoseconds(),
                (da * b).ToNanoseconds());
    if (b != 0 && !(a == kI64Min && b == -1)) {
      std::printf("div %" PRId64 " divd %" PRId64 " mod %" PRId64 "\n",
                  (da / b).ToNanoseconds(), da / db, (da % db).ToNanoseconds());
    } else {
      std::printf("div skip\n");
    }
    std::printf("cmp %d %d %d %d\n", Cmp(da, db), da == db ? 1 : 0,
                da < db ? 1 : 0, da >= db ? 1 : 0);
    struct timespec ts{};
    ts.tv_sec = static_cast<time_t>(a);
    ts.tv_nsec = static_cast<long>(b % 1000000000);
    std::printf("fromts %" PRId64 "\n",
                TimeDelta::FromTimespec(ts).ToNanoseconds());
    struct timespec out = da.ToTimespec();
    std::printf("tots %" PRId64 " %" PRId64 "\n",
                static_cast<int64_t>(out.tv_sec),
                static_cast<int64_t>(out.tv_nsec));
    TimePoint pa = TimePoint::FromTicks(a);
    TimePoint pb = TimePoint::FromEpochDelta(db);
    std::printf("tp %" PRId64 " %" PRId64 " %" PRId64 " %d\n",
                (pa - pb).ToNanoseconds(),
                (pa + db).ToEpochDelta().ToNanoseconds(),
                (pa - db).ToEpochDelta().ToNanoseconds(), Cmp(pa, pb));
    double s = BoundedF64(r, 9.0e9);
    double m = BoundedF64(r, 9.0e12);
    std::printf("fromf %" PRId64 " %" PRId64 "\n",
                TimeDelta::FromSecondsF(s).ToNanoseconds(),
                TimeDelta::FromMillisecondsF(m).ToNanoseconds());
    int64_t hz = static_cast<int64_t>(r.Below(240)) + 1;
    double hzf = BoundedF64(r, 240.0);
    std::printf("budget %016" PRIx64 " %016" PRIx64 "\n",
                Bits(fml::RefreshRateToFrameBudget(hz).count()),
                Bits(fml::RefreshRateToFrameBudget(hzf).count()));
  }
  std::printf("minmax %" PRId64 " %" PRId64 " %" PRId64 " %" PRId64 "\n",
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
    std::printf("case %d\n", i);
    std::u16string u16 = GenUtf16(r);
    std::fputs("u16 ", stdout);
    PrintHex16(u16);
    std::fputs(" -> ", stdout);
    try {
      PrintHex(fml::Utf16ToUtf8(u16));
    } catch (const std::range_error&) {
      std::fputs("ERR", stdout);
    }
    std::fputs("\n", stdout);

    std::string u8 = GenUtf8(r);
    std::fputs("u8 ", stdout);
    PrintHex(u8);
    std::fputs(" -> ", stdout);
    try {
      PrintHex16(fml::Utf8ToUtf16(u8));
    } catch (const std::range_error&) {
      std::fputs("ERR", stdout);
    }
    std::fputs("\n", stdout);

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
    std::fputs("join ", stdout);
    PrintHex(fml::Join(parts, delim));
    std::fputs("\n", stdout);

    std::string path_bytes = GenBytes(r, 8);
    std::fputs("path ", stdout);
    PrintHex(fml::PathToUtf8(std::filesystem::path(path_bytes)));
    std::fputs("\n", stdout);
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
    std::printf("case %d\n", i);
    std::string bytes = GenBytes(r, 20);
    auto enc = fml::Base32Encode(bytes);
    std::fputs("b32e ", stdout);
    PrintHex(bytes);
    std::printf(" -> %d ", enc.first ? 1 : 0);
    PrintHex(enc.second);
    auto round = fml::Base32Decode(enc.second);
    std::printf(" rt %d ", round.first ? 1 : 0);
    PrintHex(round.second);
    std::fputs("\n", stdout);

    std::string text = GenBase32Text(r);
    auto dec = fml::Base32Decode(text);
    std::fputs("b32d ", stdout);
    PrintHex(text);
    std::printf(" -> %d ", dec.first ? 1 : 0);
    PrintHex(dec.second);
    std::fputs("\n", stdout);

    std::fputs("hex ", stdout);
    PrintHex(fml::HexEncode(bytes));
    std::fputs("\n", stdout);
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
  std::printf("empty %016zx\n", fml::HashCombine());
  for (int i = 0; i < cases; i++) {
    std::printf("case %d\n", i);
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
    std::printf("h1 %016zx\n", fml::HashCombine(a));
    std::printf("h2 %016zx\n", fml::HashCombine(b, c, d));
    std::printf("h3 %016zx\n", fml::HashCombine(s));
    std::printf("h4 %016zx\n", fml::HashCombine(t));
    std::printf("h5 %016zx\n", fml::HashCombine(s, a, f, g));
    std::printf("h6 %016zx\n", fml::HashCombine(grade, u8, i16, ch, u64));
    fml::HashCombineSeed(seed, a, s);
    std::printf("h7 %016zx\n", seed);
  }
}

// ------------------------------------------------------------- endian ------

void SuiteEndian(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    uint64_t x = r.Next();
    std::printf("x %016" PRIx64 " %02x %04x %08x %016" PRIx64 "\n", x,
                fml::ByteSwap(static_cast<uint8_t>(x)),
                fml::ByteSwap(static_cast<uint16_t>(x)),
                fml::ByteSwap(static_cast<uint32_t>(x)),
                fml::ByteSwap(static_cast<uint64_t>(x)));
    std::printf("s %d %d %" PRId64 "\n",
                fml::ByteSwap(static_cast<int16_t>(x)),
                fml::ByteSwap(static_cast<int32_t>(x)),
                fml::ByteSwap(static_cast<int64_t>(x)));
    std::printf("be %08x %016" PRIx64 " le %08x %016" PRIx64 "\n",
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
    std::printf("case %d\n", i);
    fml::AsciiTrie trie;
    if (!r.Chance(8)) {
      std::vector<std::string> entries;
      int n = static_cast<int>(r.Below(6));
      for (int j = 0; j < n; j++) {
        entries.push_back(GenTrieWord(r, "abc", 3, 4));
      }
      std::fputs("fill", stdout);
      for (const auto& e : entries) {
        std::printf(" '%s'", e.c_str());
      }
      std::fputs("\n", stdout);
      trie.Fill(entries);
    }
    for (int j = 0; j < 8; j++) {
      std::string q = GenTrieWord(r, "abcd", 4, 5);
      std::printf("q '%s' %d\n", q.c_str(), trie.Query(q.c_str()) ? 1 : 0);
    }
  }
}

// ------------------------------------------------------------- queues ------

class Recorder : public fml::Wakeable {
 public:
  explicit Recorder(size_t queue) : queue_(queue) {}
  void WakeUp(fml::TimePoint time_point) override {
    std::printf("  wake %zu %" PRId64 "\n", queue_,
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
    std::printf("case %d\n", i);
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
          std::printf("create %zu\n", static_cast<size_t>(q));
          if (r.Chance(2)) {
            recorders.push_back(std::make_unique<Recorder>(q));
            std::printf("wakeable %zu\n", static_cast<size_t>(q));
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
          std::printf("reg %zu task%d %" PRId64 " %d\n", static_cast<size_t>(q),
                      id, t.ToEpochDelta().ToNanoseconds(),
                      static_cast<int>(grade));
          queues->RegisterTask(
              q, [id]() { std::printf("  run task%d\n", id); }, t, grade);
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
          std::printf("next %zu %" PRId64 "\n", static_cast<size_t>(q),
                      from.ToEpochDelta().ToNanoseconds());
          fml::closure task = queues->GetNextTaskToRun(q, from);
          if (task) {
            task();
            std::printf("  grade %d\n",
                        static_cast<int>(fml::MessageLoopTaskQueues::
                                             GetCurrentTaskSourceGrade()));
          } else {
            std::printf("  none\n");
          }
          break;
        }
        case 10: {
          fml::TaskQueueId q = pick();
          std::printf("pending %zu %d %zu\n", static_cast<size_t>(q),
                      queues->HasPendingTasks(q) ? 1 : 0,
                      queues->GetNumPendingTasks(q));
          break;
        }
        case 11: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          std::printf("merge %zu %zu\n", static_cast<size_t>(a),
                      static_cast<size_t>(b));
          bool ok = queues->Merge(a, b);
          std::printf("  -> %d\n", ok ? 1 : 0);
          if (ok && a != b) {
            subsumed_by[b] = a;
          }
          break;
        }
        case 12: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          std::printf("unmerge %zu %zu\n", static_cast<size_t>(a),
                      static_cast<size_t>(b));
          bool ok = queues->Unmerge(a, b);
          std::printf("  -> %d\n", ok ? 1 : 0);
          if (ok) {
            subsumed_by.erase(b);
          }
          break;
        }
        case 13: {
          fml::TaskQueueId a = pick();
          fml::TaskQueueId b = pick();
          std::printf("owns %zu %zu %d [", static_cast<size_t>(a),
                      static_cast<size_t>(b), queues->Owns(a, b) ? 1 : 0);
          for (auto s : queues->GetSubsumedTaskQueueId(a)) {
            std::printf(" %zu", static_cast<size_t>(s));
          }
          std::printf(" ]\n");
          break;
        }
        case 14: {
          fml::TaskQueueId q = pick();
          bool pause = pauses[q] == 0 || r.Chance(2);
          std::printf("%s %zu\n", pause ? "pause" : "resume",
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
          std::printf("observe %zu %" PRIdPTR "\n", qv, key);
          queues->AddTaskObserver(q, key, [qv, key]() {
            std::printf("  obs %zu %" PRIdPTR "\n", qv, key);
          });
          break;
        }
        case 16: {
          fml::TaskQueueId q = pick();
          intptr_t key = static_cast<intptr_t>(r.Below(5)) - 1;
          std::printf("unobserve %zu %" PRIdPTR "\n", static_cast<size_t>(q),
                      key);
          queues->RemoveTaskObserver(q, key);
          break;
        }
        case 17: {
          fml::TaskQueueId q = pick();
          std::printf("notify %zu\n", static_cast<size_t>(q));
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
          std::printf("dispose_tasks %zu\n", static_cast<size_t>(q));
          queues->DisposeTasks(q);
          break;
        }
        default: {
          fml::TaskQueueId q = pick();
          if (!is_unmerged(q)) {
            break;
          }
          std::printf("dispose %zu\n", static_cast<size_t>(q));
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
      std::printf("%spost t%d\n", indent, id);
      runner->PostTask(MakeLoopTask(c, id));
      break;
    case 2: {
      int64_t d = static_cast<int64_t>(r.Below(40)) - 8;
      std::printf("%sdelay t%d %" PRId64 "\n", indent, id, d);
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
      std::printf("%sat t%d %" PRId64 "\n", indent, id,
                  t.ToEpochDelta().ToNanoseconds());
      runner->PostTaskForTime(MakeLoopTask(c, id), t);
      break;
    }
    case 4:
      std::printf("%snow-or-post t%d\n", indent, id);
      fml::TaskRunner::RunNowOrPostTask(runner, MakeLoopTask(c, id));
      break;
    case 5:
      std::printf("%snow-and-flush t%d\n", indent, id);
      fml::TaskRunner::RunNowAndFlushMessages(runner, MakeLoopTask(c, id));
      break;
    default: {
      std::printf("%spost-queues t%d\n", indent, id);
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
    std::printf("%sunobserve %" PRIdPTR "\n", indent, key);
    fml::MessageLoop::GetCurrent().RemoveTaskObserver(key);
  } else {
    std::printf("%sobserve %" PRIdPTR "\n", indent, key);
    fml::MessageLoop::GetCurrent().AddTaskObserver(
        key, [key]() { std::printf("    obs %" PRIdPTR "\n", key); });
  }
}

fml::closure MakeLoopTask(LoopCtx* c, int id) {
  return [c, id]() {
    Rng& r = *c->r;
    auto runner = fml::MessageLoop::GetCurrent().GetTaskRunner();
    std::printf("  run t%d @%" PRId64 " on %d\n", id, PeekNow(),
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
        std::printf("   jump %" PRId64 "\n", jump);
        g_fake_now += jump;
        break;
      }
      case 6:
        if (r.Chance(4)) {
          std::printf("   nested flush\n");
          fml::MessageLoop::GetCurrent().RunExpiredTasksNow();
          std::printf("   nested done\n");
        }
        break;
      case 7:
        if (r.Chance(6)) {
          std::printf("   terminate\n");
          fml::MessageLoop::GetCurrent().Terminate();
        }
        break;
      case 8:
        std::printf("   pending %zu\n",
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
  std::printf("case %d now %" PRId64 " step %" PRId64 " budget %d\n", i,
              PeekNow(), g_fake_step.load(), c.budget);
  fml::MessageLoop::EnsureInitializedForCurrentThread();
  auto& loop = fml::MessageLoop::GetCurrent();
  auto runner = loop.GetTaskRunner();
  std::printf("init %d %d\n",
              fml::MessageLoop::IsInitializedForCurrentThread() ? 1 : 0,
              runner->RunsTasksOnCurrentThread() ? 1 : 0);
  int setup = 1 + static_cast<int>(r.Below(8));
  for (int s = 0; s < setup; s++) {
    switch (r.Below(6)) {
      case 0:
        AddLoopObserver(r, "");
        break;
      case 1:
        std::printf("poll @%" PRId64 "\n", PeekNow());
        loop.RunExpiredTasksNow();
        break;
      default:
        PostLoopTask(&c, "");
        break;
    }
  }
  int64_t end = PeekNow() + 20 + static_cast<int64_t>(r.Below(150));
  std::printf("end at %" PRId64 "\n", end);
  runner->PostTaskForTime(
      [end]() {
        std::printf("  end @%" PRId64 "\n", PeekNow());
        fml::MessageLoop::GetCurrent().Terminate();
      },
      fml::TimePoint::FromTicks(end));
  loop.Run();
  std::printf("ran @%" PRId64 " pending %zu\n", PeekNow(),
              fml::MessageLoopTaskQueues::GetInstance()->GetNumPendingTasks(
                  runner->GetTaskQueueId()));
  runner->PostTask([]() { std::printf("  never\n"); });
  std::printf("after terminate pending %zu\n",
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
  std::printf("%screate m%d pair %d parent %d shares %d\n", indent, index,
              pair, parent, shares ? 1 : 0);
  if (r.Chance(2)) {
    merger->SetMergeUnmergeCallback(
        [index]() { std::printf("    callback m%d\n", index); });
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
      std::printf("%smerge m%d %zu\n", indent, m, lease);
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
      std::printf("%sdecrement m%d\n", indent, m);
      auto status = merger->DecrementLease();
      std::printf("%s  -> %d\n", indent, static_cast<int>(status));
      break;
    }
    case 4: {
      size_t lease = 1 + r.Below(4);
      std::printf("%sextend m%d %zu\n", indent, m, lease);
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
      std::printf("%sunmerge m%d\n", indent, m);
      merger->UnMergeNowIfLastOne();
      break;
    }
    case 6: {
      bool enable = r.Chance(2);
      std::printf("%s%s m%d\n", indent, enable ? "enable" : "disable", m);
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
      std::printf("%squery m%d merged %d enabled %d raster %d platform %d\n",
                  indent, m, merged ? 1 : 0, merger->IsEnabled() ? 1 : 0,
                  merger->IsOnRasterizingThread() ? 1 : 0,
                  merger->IsOnPlatformThread() ? 1 : 0);
      if (merged) {
        merger->WaitUntilMerged();
        std::printf("%s  waited\n", indent);
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
      std::printf("%spost t%d to %s\n", indent, id, kLoopNames[q]);
      runner->PostTask(MakeMergerTask(&c, id, q));
      break;
    case 2: {
      fml::TimePoint t =
          r.Chance(10) ? fml::TimePoint::Max()
                       : fml::TimePoint::FromTicks(
                             PeekNow() + static_cast<int64_t>(r.Below(30)) -
                             10);
      std::printf("%sat t%d to %s %" PRId64 "\n", indent, id, kLoopNames[q],
                  t.ToEpochDelta().ToNanoseconds());
      runner->PostTaskForTime(MakeMergerTask(&c, id, q), t);
      break;
    }
    case 3: {
      int64_t d = static_cast<int64_t>(r.Below(20)) - 5;
      std::printf("%sdelay t%d to %s %" PRId64 "\n", indent, id,
                  kLoopNames[q], d);
      runner->PostDelayedTask(MakeMergerTask(&c, id, q),
                              fml::TimeDelta::FromNanoseconds(d));
      break;
    }
    default:
      std::printf("%snow-or-post t%d to %s\n", indent, id, kLoopNames[q]);
      fml::TaskRunner::RunNowOrPostTask(runner, MakeMergerTask(&c, id, q));
      break;
  }
}

fml::closure MakeMergerTask(MergerCtx* c, int id, int queue) {
  return [c, id, queue]() {
    Rng& r = *c->r;
    std::printf("  run t%d of %s flushing %s @%" PRId64 "\n", id,
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
  ParkedLoop r1;
  ParkedLoop r2;
  MergerCtx c;
  c.r = &r;
  c.loops[0] = &fml::MessageLoop::GetCurrent();
  c.loops[1] = r1.loop;
  c.loops[2] = r2.loop;
  for (int q = 0; q < 3; q++) {
    c.ids[q] = c.loops[q]->GetTaskRunner()->GetTaskQueueId();
  }
  c.budget = 10 + static_cast<int>(r.Below(40));
  std::printf("case %d now %" PRId64 " budget %d\n", i, PeekNow(), c.budget);
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
        std::printf("flush %s @%" PRId64 "\n", kLoopNames[q], PeekNow());
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
          std::printf("unobserve %s %" PRIdPTR "\n", kLoopNames[q], key);
          queues->RemoveTaskObserver(c.ids[q], key);
        } else {
          std::printf("observe %s %" PRIdPTR "\n", kLoopNames[q], key);
          queues->AddTaskObserver(c.ids[q], key, [q, key]() {
            std::printf("    obs %s %" PRIdPTR "\n", kLoopNames[q], key);
          });
        }
        break;
      }
      case 9: {
        std::printf("state");
        for (int q = 0; q < 3; q++) {
          std::printf(" %s:%d/%zu/%d", kLoopNames[q],
                      queues->HasPendingTasks(c.ids[q]) ? 1 : 0,
                      queues->GetNumPendingTasks(c.ids[q]),
                      c.loops[q]->GetTaskRunner()->RunsTasksOnCurrentThread()
                          ? 1
                          : 0);
        }
        std::printf(" owns %d %d same %d %d\n",
                    queues->Owns(c.ids[0], c.ids[1]) ? 1 : 0,
                    queues->Owns(c.ids[0], c.ids[2]) ? 1 : 0,
                    fml::TaskRunnerChecker::RunsOnTheSameThread(c.ids[1],
                                                                c.ids[0])
                        ? 1
                        : 0,
                    fml::TaskRunnerChecker::RunsOnTheSameThread(c.ids[2],
                                                                c.ids[1])
                        ? 1
                        : 0);
        break;
      }
      case 10: {
        fml::TaskRunnerChecker checker;
        std::printf("checker %d\n", checker.RunsOnCreationTaskRunner() ? 1 : 0);
        break;
      }
      default: {
        int64_t jump = static_cast<int64_t>(r.Below(15));
        std::printf("jump %" PRId64 "\n", jump);
        g_fake_now += jump;
        break;
      }
    }
  }
  for (int q = 1; q < 3; q++) {
    if (c.queue_merged[q]) {
      std::printf("final unmerge %s %d\n", kLoopNames[q],
                  queues->Unmerge(c.ids[0], c.ids[q]) ? 1 : 0);
    }
  }
  std::printf("final pending %zu %zu %zu\n",
              queues->GetNumPendingTasks(c.ids[0]),
              queues->GetNumPendingTasks(c.ids[1]),
              queues->GetNumPendingTasks(c.ids[2]));
  for (int q = 0; q < 3; q++) {
    queues->DisposeTasks(c.ids[q]);
  }
  c.mergers.clear();
}

void SuiteMerger(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    std::thread thread([&r, i]() { MergerCase(r, i); });
    thread.join();
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
  std::printf("  setter %s %d\n", config.name.c_str(),
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
  std::printf("concurrent %zu -> %zu\n", workers, count);
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
  std::printf("  ran %zu inside %zu names %d outside %d\n", tasks, inside,
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
  std::printf("  all");
  for (const auto& name : names) {
    std::printf(" %s", name.c_str());
  }
  std::printf("\n");
  if (r.Chance(2)) {
    loop->Terminate();
    std::string where;
    runner->PostTask([&]() { where = CurrentThreadName(); });
    std::printf("  after terminate caller %d\n",
                where == CurrentThreadName() ? 1 : 0);
  }
  loop.reset();
  bool ran = false;
  runner->PostTask([&]() { ran = true; });
  std::printf("  after death ran %d\n", ran ? 1 : 0);
}

void ThreadCase(Rng& r, int i) {
  ThreadCtx c;
  c.r = &r;
  int n = 1 + static_cast<int>(r.Below(3));
  std::printf("case %d threads %d\n", i, n);
  std::vector<int> kinds;
  for (int t = 0; t < n; t++) {
    kinds.push_back(static_cast<int>(r.Below(3)));
    switch (kinds.back()) {
      case 0:
        std::printf("thread %d default\n", t);
        c.threads.push_back(std::make_unique<fml::Thread>());
        break;
      case 1: {
        std::string name = RandomThreadName(r);
        std::printf("thread %d named %s\n", t, name.c_str());
        c.threads.push_back(std::make_unique<fml::Thread>(name));
        break;
      }
      default: {
        std::string name = RandomThreadName(r);
        auto priority = static_cast<fml::Thread::ThreadPriority>(r.Below(4));
        std::printf("thread %d config %s %d\n", t, name.c_str(),
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
    std::printf("name %d %s\n", t, name.c_str());
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
          std::printf("post t%d to %d\n", id, t);
          c.pending.Add();
          c.runners[t]->PostTask(task);
          break;
        case 1:
          std::printf("now-or-post t%d to %d\n", id, t);
          c.pending.Add();
          fml::TaskRunner::RunNowOrPostTask(c.runners[t], task);
          break;
        case 2: {
          std::printf("wrapper t%d to %d\n", id, t);
          c.pending.Add();
          fml::WrapperBasicTaskRunner wrapper(c.runners[t]);
          wrapper.PostTask(task);
          break;
        }
        case 3: {
          bool usable = r.Chance(2);
          std::printf("conditional t%d to %d %d\n", id, t, usable ? 1 : 0);
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
          std::printf("conditional-dead t%d to %d\n", id, t);
          fml::ConditionalBasicTaskRunner conditional(c.runners[t],
                                                      []() { return true; });
          conditional.PostTask(task);
          break;
        }
        default:
          std::printf("for-time t%d to %d\n", id, t);
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
        std::printf("  %d: %s\n", t, line.c_str());
      }
    }
    c.traces.clear();
    std::printf("main runs");
    for (auto& runner : c.runners) {
      std::printf(" %d", runner->RunsTasksOnCurrentThread() ? 1 : 0);
    }
    std::printf("\n");
  }
  for (int t = 0; t < n; t++) {
    if (r.Chance(2)) {
      std::printf("join %d\n", t);
      c.threads[t]->Join();
      if (r.Chance(2)) {
        c.threads[t]->Join();
      }
      c.runners[t]->PostTask([]() { std::printf("never\n"); });
      std::printf("  pending %zu\n",
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
  std::printf("default stack %zu\n", fml::Thread::GetDefaultStackSize());
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
  for (char ch : s) {
    if (ch == '\n') {
      std::fputs("\\n", stdout);
    } else if (ch == '\t') {
      std::fputs("\\t", stdout);
    } else {
      std::fputc(ch, stdout);
    }
  }
}

// One LogMessage as the macros make it; a fatal one kills the process.
void EmitLog(Rng& r, fml::LogSeverity severity, bool capture) {
  const char* file = kLogFiles[r.Below(7)];
  int line = static_cast<int>(r.Below(500));
  bool condition = r.Chance(3);
  std::string text = RandomLogText(r);
  std::printf("  emit %d %s %d %d %d\n", severity, file, line,
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
    std::printf("  captured ");
    PrintEscaped(log_capture_slot.str());
    std::printf("\n");
  }
}

void FatalChild(uint64_t seed) {
  Rng r{seed};
  fml::LogSeverity severity = 4 + static_cast<int>(r.Below(3));
  EmitLog(r, severity, r.Chance(3));
  std::printf("survived\n");
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
  std::printf("  child %s %d stderr ",
              WIFSIGNALED(status) ? "signal" : "exit",
              WIFSIGNALED(status) ? WTERMSIG(status) : WEXITSTATUS(status));
  PrintEscaped(out);
  std::printf("\n");
}

void SuiteLogging(Rng& r, int cases) {
  for (int i = 0; i < cases; i++) {
    std::printf("case %d\n", i);
    switch (r.Below(8)) {
      case 0:
      case 1: {
        fml::LogSettings settings;
        settings.min_log_level = static_cast<int>(r.Below(10)) - 3;
        fml::SetLogSettings(settings);
        std::printf("  set %d -> %d min %d vlog %d\n", settings.min_log_level,
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
          std::printf("  scoped %d -> min %d vlog %d\n",
                      settings.min_log_level, fml::GetMinLogLevel(),
                      fml::GetVlogVerbosity());
        }
        std::printf("  restored %d %d\n", before, fml::GetMinLogLevel());
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
        std::printf("  %s %d on %d\n", vlog ? "vlog" : "log", level,
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
          std::printf("  fatal\n");
          RunFatalChild(r.Next());
        } else {
          EmitLog(r, severity, r.Chance(2));
        }
        break;
      }
      default:
        if (r.Chance(4)) {
          std::printf("  fatal\n");
          RunFatalChild(r.Next());
        }
        break;
    }
  }
  fml::SetLogSettings(fml::LogSettings{});
}

// -------------------------------------------------------------- bench ------

// flutter/fml/message_loop_unittests.cc's NonDelayedTasksAreRunInOrder at
// 10000 tasks: post them, then run the loop until the last one terminates it.
void BenchLoop() {
  std::thread thread([]() {
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

// Silences a suite's stdout for benchmarking by pointing it at /dev/null.
void Bench(const std::string& name, int iterations) {
  std::vector<double> rounds;
  for (int i = 0; i < iterations; i++) {
    auto start = std::chrono::steady_clock::now();
    if (name == "queues") {
      BenchRegisterAndGetTasks();
    } else if (name == "loop") {
      BenchLoop();
    } else if (name == "thread") {
      BenchThread();
    } else if (name == "concurrent") {
      BenchConcurrent();
    } else {
      Rng r{static_cast<uint64_t>(i)};
      if (name == "time") {
        SuiteTime(r, 20000);
      } else if (name == "strings") {
        SuiteStrings(r, 20000);
      } else if (name == "hash") {
        SuiteHash(r, 20000);
      } else if (name == "dispatch") {
        SuiteQueues(r, 2000);
      } else if (name == "merger") {
        SuiteMerger(r, 200);
      } else {
        std::fprintf(stderr, "unknown bench %s\n", name.c_str());
        std::exit(2);
      }
    }
    auto end = std::chrono::steady_clock::now();
    rounds.push_back(std::chrono::duration<double, std::micro>(end - start).count());
  }
  std::sort(rounds.begin(), rounds.end());
  std::fprintf(stderr, "bench %s fastest %.1f us median %.1f us peak_rss %ld KiB\n",
               name.c_str(), rounds.front(), rounds[rounds.size() / 2],
               PeakRssKiB());
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
  if (!known) {
    std::fprintf(stderr, "unknown suite %s\n", suite.c_str());
    return 2;
  }
  return 0;
}

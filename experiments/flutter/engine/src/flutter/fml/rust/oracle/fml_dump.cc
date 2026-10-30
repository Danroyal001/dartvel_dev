// Not an upstream file: the oracle driver for the Rust port of flutter/fml.
//
// Links the upstream C++ (the files named in ../README.md) and prints what it
// does on seeded random inputs. src/bin/fml_dump.rs is the same program over
// the port; the two outputs must be byte-identical.
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues all
//   fml_dump bench <name> <iterations>  name: queues time strings hash
//
// Both drivers draw every input from the same splitmix64 stream, so a suite's
// output is a function of (suite, seed, cases) alone.

#include <algorithm>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "flutter/fml/ascii_trie.h"
#include "flutter/fml/base32.h"
#include "flutter/fml/endianness.h"
#include "flutter/fml/hash_combine.h"
#include "flutter/fml/hex_codec.h"
#include "flutter/fml/message_loop_task_queues.h"
#include "flutter/fml/string_conversion.h"
#include "flutter/fml/synchronization/count_down_latch.h"
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

// -------------------------------------------------------------- bench ------

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
  if (!known) {
    std::fprintf(stderr, "unknown suite %s\n", suite.c_str());
    return 2;
  }
  return 0;
}

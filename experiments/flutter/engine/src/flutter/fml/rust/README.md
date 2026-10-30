# `fml` in Rust

A file-by-file Rust port of the Flutter engine's foundation library,
`engine/src/flutter/fml`, started with the portable parts the rest of the
engine leans on: time, the codecs, hashing, memory ownership,
synchronization and the task queues behind every message loop. Each file
under `src/` ports the C++ file at the same path under `..`, keeps its
structure and names, and names that file in its first line. Files that are
not ports (`lib.rs`, `mod.rs`, the driver, the harness) say so in their first
line. `*_unittest(s).rs` modules port the gtest file of the same name.

The crate is a member of the Cargo workspace at `experiments/flutter`.

## What is ported

| Upstream | Port | Upstream tests | Rust tests |
|---|---|---|---|
| `time/time_delta.h` | `src/time/time_delta.rs` | 1 | 1 |
| `time/time_point.h`, `.cc` | `src/time/time_point.rs` | 2 | 1 (the Dart-clock test needs `flutter/runtime`) |
| `time/timestamp_provider.h`, `time/chrono_timestamp_provider.h`, `.cc` | `src/time/…` | — | — |
| `time/time_unittest.cc` | `src/time/time_unittest.rs` | 4 | 4 |
| `string_conversion.h`, `.cc` | `src/string_conversion.rs` | 7 | 7 |
| `base32.h`, `.cc` | `src/base32.rs` | 4 | 4 |
| `hex_codec.h`, `.cc` | `src/hex_codec.rs` | 1 | 1 |
| `hash_combine.h` | `src/hash_combine.rs` | 1 | 1 |
| `endianness.h`, `.cc` | `src/endianness.rs` | 3 | 3 |
| `math.h` | `src/math.rs` | 1 | 1 |
| `ascii_trie.h`, `.cc` | `src/ascii_trie.rs` | 4 | 4 |
| `memory/ref_counted.h`, `ref_counted_internal.h`, `ref_ptr.h`, `ref_ptr_internal.h` | `src/memory/ref_counted.rs`, `ref_ptr.rs` | 12 | 11 + 1 |
| `memory/weak_ptr.h`, `weak_ptr_internal.h`, `.cc`, `thread_checker.h` | `src/memory/weak_ptr.rs`, `weak_ptr_internal.rs`, `thread_checker.rs` | 15 | 14 + 2 |
| `synchronization/waitable_event.h`, `.cc` | `src/synchronization/waitable_event.rs` | 4 | 4 |
| `synchronization/count_down_latch.h`, `.cc` | `src/synchronization/count_down_latch.rs` | 2 | 2 |
| `synchronization/semaphore.h`, `.cc` | `src/synchronization/semaphore.rs` | 4 | 4 + 1 |
| `synchronization/sync_switch.h`, `.cc` | `src/synchronization/sync_switch.rs` | 3 | 3 |
| `synchronization/atomic_object.h` | `src/synchronization/atomic_object.rs` | — | — |
| `closure.h` (the alias), `wakeable.h`, `task_queue_id.h`, `task_source_grade.h` | `src/…` | — | — |
| `delayed_task.h`, `.cc` | `src/delayed_task.rs` | — | — |
| `task_source.h`, `.cc` | `src/task_source.rs` | 5 | 5 + 1 |
| `message_loop_task_queues.h`, `.cc` | `src/message_loop_task_queues.rs` | 16 + 12 (merge/unmerge) | 16 + 12 |
| `logging.h`, `.cc` (message format only) | `src/logging.rs` | — | — |

"+ n" are tests that are not upstream's, each marked as such: the
counting of `RefCountedThreadSafeBase`, a factory stored inside its object,
the debug thread check, `SEM_VALUE_MAX`, and tasks due at the same time
running in registration order (see *Deliberate failures*). Upstream tests
not ported: `RefCountedTest.DebugChecks` (C++ debug deaths on raw `delete`),
`TimePoint.DartClockIsMonotonic` and `TaskRunnerAffineWeakPtrTest` (they need
`flutter/runtime`, `MessageLoop` and `RasterThreadMerger`). Two tests post to
an `fml::Thread`, which is not ported; a plain thread runs the same tasks.

## The oracle

The upstream C++ stays in this checkout and is the oracle.
`oracle/fml_dump.cc` links the upstream sources listed in
`tests/oracle.rs` and prints what they do; `src/bin/fml_dump.rs` is the same
program over the port. Both draw every input from the same splitmix64 stream,
so the output is a function of the suite, the seed and the case count.

| Suite | What it drives |
|---|---|
| `time` | every TimeDelta/TimePoint constructor, conversion and operator on edge values (0, ±1, `i64::MIN`/`MAX`, values that overflow on ×1000), including wrapping overflow, `timespec` round trips, float conversions (as bit patterns) and frame budgets |
| `strings` | `Utf16ToUtf8` on random UTF-16 with lone and paired surrogates, NULs and specials; `Utf8ToUtf16` on random UTF-8 with overlong forms, encoded surrogates, code points past U+10FFFF, truncated sequences, stray bytes, BOMs and NULs; `Join`; `PathToUtf8` on random bytes |
| `codec` | Base32 encode, decode, round trip and decode of near-alphabet text; hex |
| `hash` | `HashCombine` over ints of every width, bools, chars, floats (incl. ±0 and NaN bits), enums, and strings of 0–264 bytes (every CityHash64 length class) |
| `endian` | `ByteSwap`, `BigEndianToArch`, `LittleEndianToArch` |
| `trie` | `AsciiTrie::Fill` and `Query`, including the empty trie and empty entries |
| `queues` | `MessageLoopTaskQueues` under random schedules: create, set wakeable, register (all three grades, many equal target times, `Min`/`Max`), get next task (runs it and reports the thread's grade), pending counts, merge, unmerge, owns, pause/resume secondary, add/remove/notify observers, dispose tasks, dispose; every `WakeUp` is printed, and the `FML_LOG` warnings on stderr are compared too |

The oracle is built with `clang++ -stdlib=libc++ -O2 -DNDEBUG -fwrapv` from
`engine/src` with relative paths, as the engine is: the engine ships libc++,
whose `codecvt` and `std::hash` the port reproduces, and `-fwrapv` defines
the signed overflow that upstream leaves undefined (see *Differences*).
`FML_ORACLE_STDLIB=libstdc++` builds it against libstdc++ instead, whose
string hash differs.

## Running it

From `experiments/flutter`, with clang and libc++ (`libc++-dev`) installed:

```sh
cargo test --release
```

runs the unit tests and the oracle (7 suites × 16 seeds × 250 cases).
`FML_ORACLE_SEED_BASE`, `FML_ORACLE_SEEDS`, `FML_ORACLE_CASES` and
`FML_ORACLE_SUITES` pick another corpus; `FML_ORACLE_WORK` moves the scratch
directory. The test fails on the first differing line of any run and prints
it.

Benchmarks: `fml_dump bench <name> <rounds>` with either binary; `queues` is
upstream's `message_loop_task_queues_benchmark.cc` (`BM_RegisterAndGetTasks`),
the others run a suite with its output discarded.

## Porting conventions

- Types keep their C++ names; methods and free functions become snake case;
  constants and enum values keep their spelling (`kDefaultFrameBudget`,
  `TaskSourceGrade::kUserInteraction`).
- Variadic templates become macros (`hash_combine!`, `hash_combine_seed!`).
- Ownership follows Track E: a `RefCountedThreadSafe<T>` object lives in an
  `Arc<T>`, `RefPtr<T>` is a nullable `Arc`, `WeakPtr<T>` is a `Weak` plus
  upstream's invalidation flag and debug thread check, virtual interfaces
  are traits, and a non-owning pointer that the pointee unregisters
  (`Wakeable*`) is a `Weak`.
- Where upstream throws, the port panics with the C++ library's message, and
  offers a `try_` variant returning the error where callers need it
  (`try_utf8_to_utf16`). A failed `FML_CHECK` panics.
- Behaviour that looks like an upstream slip is ported as is and marked in a
  comment, never fixed, since the oracle would report the fix.
- `unsafe` appears once: `TimePoint::now()` reads `CLOCK_MONOTONIC`
  (`CLOCK_UPTIME_RAW` on Apple) through the C library, because the engine
  compares that clock with platform timestamps and Rust's `std` cannot read
  its epoch. Each block has a SAFETY comment.

## Differences

None on the oracle's corpus. Where the port knowingly differs from the C++:

- Signed overflow in `TimeDelta`/`TimePoint` is undefined behaviour upstream;
  the port wraps (as every engine target does in practice, and as the oracle
  pins with `-fwrapv`). Out-of-range `double`→`int64` in `FromSecondsF` is
  undefined upstream and saturates here; the oracle does not feed it.
- `Utf8ToUtf16`/`Utf16ToUtf8` stop at the first NUL as upstream does, but a
  slice that is not NUL-terminated ends at its end rather than reading past
  it.
- `AsciiTrie` with a byte ≥ 0x80 indexes out of bounds upstream (undefined);
  it panics here.
- `RefPtr` cannot be made from a raw pointer; `WeakPtr::get` returns an
  `Arc<T>` rather than a `T*`.
- `SyncSwitch::SetSwitch` notifies a copy of the observer list taken under
  the lock; upstream reads the list after unlocking (a race).
- `MessageLoopTaskQueues` keeps the wakeable as a `Weak`, skipping a dead one
  where upstream would call through a dangling pointer.
- `Semaphore` ports the POSIX branch (`sem_t`) with a mutex and a condition
  variable, keeping `SEM_VALUE_MAX`.
- `hash_combine`'s string hash is libc++'s default-ABI CityHash64, whose
  4–8-byte branch shifts a 32-bit value (a libc++ slip, kept).

## Deliberate failures

Each rule below was broken on purpose, the tests named were run, and the
change was restored.

| Broken | Caught by |
|---|---|
| `from_microseconds` saturates instead of wrapping | oracle `time` (4 of 4 seeds differ) |
| `DelayedTask` tie-break reversed | oracle `queues` (4 of 4); **no ported upstream test** — `equal_target_times_run_in_registration_order` was added and fails under it |
| `Utf16ToUtf8` no longer stops at NUL | oracle `strings` |
| CityHash64's 32-bit shift widened | oracle `hash` |
| `AsciiTrie::Query` drops the `trie_position != trie` check | oracle `trie` |
| Base32 padding check removed | `decode_returns_false_for_invalide_input` |
| `WeakPtrFactory` no longer invalidates on drop | `multiple`, `factory_inside_its_object`, … |
| `AutoResetWaitableEvent::wait` no longer resets | `waitable_event_unittest` hangs (timed out) |
| Paused secondary heap still counted | `ordering_multi_task_heaps_secondary_paused` |
| Subsumed queue reports its own pending count | `after_merge_secondary_tasks_also_serviced_on_primary`, `merge_unmerge_tasks_preserved` |
| `Semaphore::try_wait` does not decrement | `wait_on_zero_signal_then_wait` |
| `big_endian_to_arch` does not swap | `big_endian_to_arch_test` |

## Baseline

Measured 2026-10-30 on a 4-core Intel Xeon at 2.10 GHz (shared, so medians
are noisy), clang 18.1.3 with libc++ 18 at `-O2 -DNDEBUG`, rustc 1.97.0
release. Peak RSS is the whole process (`VmHWM`). `queues` is 500 rounds of
upstream's benchmark; the others are 30 rounds of a suite, which includes
the driver's input generation and formatting, not only the ported code.

| Benchmark | C++ fastest | C++ median | Rust fastest | Rust median | C++ RSS | Rust RSS |
|---|---|---|---|---|---|---|
| `queues` (BM_RegisterAndGetTasks) | 1.38 ms | 1.82 ms | 0.72 ms | 1.13 ms | 5.0 MiB | 3.9 MiB |
| `dispatch` (queues suite, 2000 cases) | 39.4 ms | 68.0 ms | 42.3 ms | 50.6 ms | 3.3 MiB | 2.4 MiB |
| `time` (20000 cases) | 27.6 ms | 31.9 ms | 20.7 ms | 28.3 ms | 3.2 MiB | 2.3 MiB |
| `strings` (20000 cases) | 126.6 ms | 146.4 ms | 27.9 ms | 31.4 ms | 3.2 MiB | 2.3 MiB |
| `hash` (20000 cases) | 20.2 ms | 23.7 ms | 22.8 ms | 25.5 ms | 3.2 MiB | 2.4 MiB |

The `strings` gap is libc++'s `wstring_convert`, which allocates a converter
per call and throws on bad input; `hash` and `dispatch` are slower in Rust
at the fastest round, within noise at the median.

## Not ported yet

From `fml`: `MessageLoop`, `MessageLoopImpl` and the platform loops
(`platform/linux`, `android`, `darwin`, `win`, `fuchsia`), `TaskRunner`,
`task_runner_util`, `Thread`, `ConcurrentMessageLoop`, `RasterThreadMerger`,
`SharedThreadMerger`, `TaskRunnerChecker` and `TaskRunnerAffineWeakPtr`
(all wait for the message loop), `closure.h`'s `ScopedCleanupClosure`,
`make_copyable`, the rest of `logging` (settings, capture, `FATAL`, platform
sinks), `file`, `mapping`, `paths`, `unique_fd`, `unique_object`,
`native_library`, `command_line`, `backtrace`, `cpu_affinity`, `icu_util`,
`trace_event`, `log_settings`, `process`, `container`, `safe_math`, `posix_wrappers`
and `eintr_wrapper`.

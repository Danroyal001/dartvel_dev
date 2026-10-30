# `fml` in Rust

A file-by-file Rust port of the Flutter engine's foundation library,
`engine/src/flutter/fml`, started with the portable parts the rest of the
engine leans on: time, the codecs, hashing, memory ownership,
synchronization, the task queues, and the message loops, task runners,
threads and thread mergers built on them. Each file
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
| `logging.h`, `.cc`, `log_level.h`, `log_settings.h`, `.cc`, `log_settings_state.cc` | `src/logging.rs`, `log_level.rs`, `log_settings.rs` | 3 | 3 |
| `closure.h` (`ScopedCleanupClosure`) | `src/closure.rs` | 6 | 6 + 1 |
| `make_copyable.h`, `eintr_wrapper.h`, `unique_object.h`, `unique_fd.h`, `.cc` (POSIX) | `src/…` | — | — |
| `message_loop.h`, `.cc`, `message_loop_impl.h`, `.cc` | `src/message_loop.rs`, `message_loop_impl.rs` | 10 | 10 + 3 |
| `platform/linux/message_loop_linux.h`, `.cc`, `timerfd.h`, `.cc` | `src/platform/linux/…` | — | — |
| `task_runner.h`, `.cc` | `src/task_runner.rs` | — | — |
| `task_runner_util.h`, `.cc` | `src/task_runner_util.rs` | 2 | 2 + 1 |
| `thread.h`, `.cc` | `src/thread.rs` | 7 | 7 |
| `concurrent_message_loop.h`, `.cc`, `concurrent_message_loop_factory.cc` | `src/concurrent_message_loop.rs` | (in message_loop's) | |
| `raster_thread_merger.h`, `.cc`, `shared_thread_merger.h`, `.cc` | `src/raster_thread_merger.rs`, `shared_thread_merger.rs` | 17 | 17 |
| `memory/task_runner_checker.h`, `.cc` | `src/memory/task_runner_checker.rs` | 7 | 7 |
| `memory/weak_ptr.h` (`TaskRunnerAffineWeakPtr`) | `src/memory/weak_ptr.rs` | 1 | 1 |

"+ n" are tests that are not upstream's, each marked as such: the
counting of `RefCountedThreadSafeBase`, a factory stored inside its object,
the debug thread check, `SEM_VALUE_MAX`, tasks due at the same time running
in registration order, and five that cover breaks no upstream test caught
(see *Deliberate failures*): a terminated loop drops new tasks,
DoRun's last flush runs tasks that fell due, `RunsTasksOnCurrentThread`
follows merges, a destroyed `ConditionalBasicTaskRunner` drops its tasks, and
move-assigning a `ScopedCleanupClosure` does not invoke the closure it
replaces. Upstream tests not ported: `RefCountedTest.DebugChecks` (C++ debug
deaths on raw `delete`) and `TimePoint.DartClockIsMonotonic` (it needs
`flutter/runtime`); logging's static-initialization segfault check has no
counterpart. gtest's `ASSERT_DEATH` becomes `expect_death`, which runs the
test binary again filtered to the one test and checks for SIGABRT and the
message; assertions made on loop threads are recorded and checked on the
test's thread.

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
| `loop` | `MessageLoopLinux` (epoll and timerfd) run on a fresh thread per case under a controllable clock (`TimePoint::SetClockSource`): every `Now()` returns the clock and advances it a step, so the loop spins forward to the next delayed task deterministically, and the trace is the order tasks and observers run in, with the clock each saw. Tasks post through `PostTask`, `PostDelayedTask` (also negative delays), `PostTaskForTime` (also `Max`), `RunNowOrPostTask`, `RunNowAndFlushMessages` and the queues with a grade; add and remove observers; jump the clock; flush re-entrantly; terminate; embedder polling before `Run`; posting after termination |
| `merger` | A platform loop on the case's thread and two raster loops on parked threads, all flushed with `RunExpiredTasksNow` from one thread (as a polling embedder does), so tasks run in an order the trace fixes while `RasterThreadMerger`s (shared, independent, same-queue, with callbacks) merge, extend, decrement, unmerge, enable and disable; queries of `IsMerged`, `IsOnRasterizingThread`, `WaitUntilMerged`, pending counts, `Owns`, `RunsTasksOnCurrentThread`, `TaskRunnerChecker`; observers across merged queues. The driver models the leases only to stay off paths where upstream aborts (`FML_CHECK`) or DCHECKs |
| `thread` | `fml::Thread` (default, named, a config setter with priority), thread names (truncated to 15 bytes), tasks posted through `PostTask`, `RunNowOrPostTask`, `PostTaskForTime`, `WrapperBasicTaskRunner` and `ConditionalBasicTaskRunner` (usable, unusable, destroyed) while each thread is held, children posted, run now or flushed; `Join` (twice) and posting after it; `ConcurrentMessageLoop` worker counts, `RunsTasksOnCurrentThread`, `PostTaskToAllWorkers`, posting after `Terminate` and after the loop dies. Only what is deterministic is printed: each thread's own order, never the interleaving |
| `logging` | `SetLogSettings`/`ScopedSetLogSettings` with clamping, `GetVlogVerbosity`, the `FML_LOG`/`FML_VLOG` gates, `LogMessage` for every severity (`VERBOSEn`, `UNKNOWN`), `../` stripping and check conditions, to stderr or `LogCapture`; FATAL and higher in a child process (the driver re-executes itself), reporting the signal and stderr |

Threads and timing are kept out of every trace: the loop and merger suites
run on one thread at a time under the fake clock, and the thread suite holds
each thread while a batch is posted and prints per-thread order only after
every task has run. The one address upstream logs (SharedThreadMerger's
`caller=0x…`) is masked on both sides. A driver run that does not finish in
`FML_ORACLE_TIMEOUT` seconds (300) fails the test, since a port that loses a
task leaves those suites waiting forever.

The oracle is built with `clang++ -stdlib=libc++ -O2 -DNDEBUG -fwrapv` from
`engine/src` with relative paths, as the engine is (without `-DNDEBUG` when
the port is a debug build, so that `FML_DLOG`/`FML_DCHECK` match): the
engine ships libc++,
whose `codecvt` and `std::hash` the port reproduces, and `-fwrapv` defines
the signed overflow that upstream leaves undefined (see *Differences*).
`FML_ORACLE_STDLIB=libstdc++` builds it against libstdc++ instead, whose
string hash differs.

## Running it

From `experiments/flutter`, with clang and libc++ (`libc++-dev`) installed:

```sh
cargo test --release
```

runs the unit tests and the oracle (11 suites × 16 seeds × 250 cases,
about two minutes; the thread suite dominates). `oracle/shim/` holds a no-op
`trace_event.h`, because the real one includes the Dart VM's
`dart_tools_api.h`, which this checkout lacks.
`FML_ORACLE_SEED_BASE`, `FML_ORACLE_SEEDS`, `FML_ORACLE_CASES` and
`FML_ORACLE_SUITES` pick another corpus; `FML_ORACLE_WORK` moves the scratch
directory. The test fails on the first differing line of any run and prints
it.

Benchmarks: `fml_dump bench <name> <rounds>` with either binary; `loop`,
`thread` and `concurrent` post 10000 tasks to a Linux loop, an `fml::Thread`
and a four-worker `ConcurrentMessageLoop`; `queues` is
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
- `FML_CHECK` and `FATAL` behave as upstream: the line is written to stderr
  (or a `LogCapture`) and the process aborts (`fml_check_at!`,
  `fml_log_at!(kLogFatal, ...)`). Ported files pass the upstream file and
  line to the `_at` macros so that their logs read as upstream's.
  `FML_DCHECK`/`FML_DLOG` follow `debug_assertions`.
- A `MessageLoopImpl` is a trait over the platform loop plus a
  `MessageLoopImplBase` holding the base class's state; `MessageLoop` is a
  cheap handle (two reference-counted pointers) that `get_current()` clones
  out of the thread-local, so it can be kept as upstream's tests keep a
  `MessageLoop*`.
- `unsafe` is confined to C library calls Rust's `std` has no safe form of:
  `clock_gettime` for `TimePoint::now()` (the engine compares that clock with
  platform timestamps), `epoll_create`/`epoll_ctl`/`epoll_wait`,
  `timerfd_create`/`timerfd_settime` and `read` in the Linux loop, `close` in
  `UniqueFD`, and `pthread_setname_np` on Apple. Each block has a SAFETY
  comment. Thread names on Linux are written to `/proc/thread-self/comm`,
  safely, with the effect of `pthread_setname_np`. The tests add a few pthread
  calls (stack size, scheduling) as upstream's do.

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
- Data races upstream are atomics or locks here: `MessageLoopLinux::running_`
  (written by `Terminate` from any thread), the log settings, and
  `SharedThreadMerger`'s lease map and enabled flag (read under the calling
  `RasterThreadMerger`'s mutex, not the shared one); the merge callback has
  its own lock.
- `TimerRearm` converts a negative target to an unsigned count, arming the
  timer for the far future (the loop never wakes); kept. Unreachable on the
  real clock; the oracle's fake clock stays positive.
- `TaskRunner` is a struct: upstream's virtual methods (for embedder task
  runners) wait for the shell's port. `ConcurrentMessageLoop::ExecuteTask`
  is not virtual, and its trace event is not emitted (`trace_event` is not
  ported). A `closure` cannot be empty, so the null-task checks and the
  "Tried to add a null TaskObserver." path do not exist.
- Only the Linux message loop is ported; `MessageLoopImpl::create()` returns
  null elsewhere, as upstream does on an unknown platform. Android's loop
  (ALooper), Darwin's (CFRunLoop), Fuchsia's (async::Loop) and Windows'
  (a message window) need their platforms' bindings. Only the stderr log
  sink is ported (not Android's, iOS's or Fuchsia's).

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
| Observers not notified after a task | `task_observer_fire`; oracle `loop` (4 of 4) |
| `RunsTasksOnCurrentThread` ignores merges | oracle `merger` (8 of 4: stdout and stderr); **no ported upstream test** — `runs_tasks_on_current_thread_follows_merges` was added and fails |
| Terminated loop still accepts tasks | oracle `loop` (4 of 4); **no upstream test** — `tasks_posted_after_termination_are_dropped` added |
| DoRun skips its last flush | oracle `loop` (4 of 4); **no upstream test** — `tasks_due_when_the_loop_terminates_still_run` added |
| `UnMergeNowIfLastOne` keeps the caller | `disable`, `the_last_caller_…`, `the_last_merged_caller_…`, `two_independent_mergers_…`; oracle `merger` (the port aborts on an FML_CHECK) |
| `DecrementLease` skips the callback on unmerge | `set_merge_unmerge_callback`; oracle `merger` (4 of 4) |
| `ConditionalBasicTaskRunner` holds its predicate strongly | oracle `thread` (the driver hangs; killed after the timeout); **no upstream test** — `conditional_basic_task_runner_drops_tasks_once_destroyed` added |
| `PostTaskToAllWorkers` reaches one worker | oracle `thread` (hangs) |
| FATAL does not abort | `sanity_tests` (death test); oracle `logging` |
| `../` not stripped from log file names | oracle `logging` |
| `SetLogSettings` does not clamp to FATAL | oracle `logging` |
| Move assignment invokes the replaced closure | **no upstream test** — `closure_replaced_by_move_assignment_is_not_invoked` added |
| The Linux loop does not drain the timer | **not caught**: epoll is level-triggered, so the loop wakes once per flush either way; the cost is CPU, not behaviour |

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
| `loop` (10000 tasks, Linux loop) | 444 ms | 509 ms | 445 ms | 496 ms | 4.0 MiB | 3.6 MiB |
| `thread` (10000 tasks, `fml::Thread`) | 514 ms | 651 ms | 559 ms | 630 ms | 3.9 MiB | 3.3 MiB |
| `concurrent` (10000 tasks, 4 workers, 200 rounds) | 1.5 ms | 106–118 ms | 4.0 ms | 33–77 ms | 3.6 MiB | 3.0 MiB |
| `merger` (200 cases, 10 rounds) | 157 ms | 181 ms | 136 ms | 180 ms | 3.5 MiB | 2.9 MiB |

The loop benchmarks are dominated by system calls (each post rearms the
timerfd; each flush reads the clock and rearms it), which are slow in this
sandbox and identical on both sides. `concurrent` is contention-bound and
very noisy: C++ has the faster best rounds, Rust the faster medians (its
`Mutex`/`Condvar` are futexes; libc++'s are pthread's).

The `strings` gap is libc++'s `wstring_convert`, which allocates a converter
per call and throws on bad input; `hash` and `dispatch` are slower in Rust
at the fastest round, within noise at the median.

## Not ported yet

From `fml`: the platform loops other than Linux (`platform/android`,
`darwin`, `win`, `fuchsia`, including `task_observers` and
`concurrent_message_loop_factory.mm`), the logging sinks other than stderr,
`file`, `mapping`, `paths` (and `paths_linux.cc`), `UniqueDir`,
`native_library`, `command_line`, `backtrace`, `cpu_affinity`, `icu_util`,
`trace_event`, `process`, `container`, `safe_math`, `posix_wrappers`,
`build_config.h`/`macros.h` (nothing to port), the platform helpers
(`platform/android` JNI, `platform/darwin` CF/NS utilities,
`platform/win` errors and wide strings) and the `TaskRunner` subclassing the
embedder uses.

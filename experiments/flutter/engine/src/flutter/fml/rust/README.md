# `fml` in Rust

A file-by-file Rust port of the Flutter engine's foundation library,
`engine/src/flutter/fml`, started with the portable parts the rest of the
engine leans on: time, the codecs, hashing, memory ownership,
synchronization, the task queues, and the message loops, task runners,
threads and thread mergers built on them; and the portable POSIX/Linux
rest: files, mappings, paths, native libraries, the command line, tracing,
backtraces and the small helpers. Each file
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
| `file.h`, `.cc`, `platform/posix/file_posix.cc`, `unique_fd.h` (`UniqueDir`) | `src/file.rs`, `src/platform/posix/file_posix.rs`, `src/unique_fd.rs` | 14 | 14 + 1 |
| `mapping.h`, `.cc`, `platform/posix/mapping_posix.cc` | `src/mapping.rs`, `src/platform/posix/mapping_posix.rs` | 7 | 7 + 1 |
| `paths.h`, `.cc`, `platform/posix/paths_posix.cc`, `platform/linux/paths_linux.cc` | `src/paths.rs`, `src/platform/posix/paths_posix.rs`, `src/platform/linux/paths_linux.rs` | 1 | 1 |
| `native_library.h`, `platform/posix/native_library_posix.cc` | `src/native_library.rs`, `src/platform/posix/native_library_posix.rs` | — | — |
| `command_line.h`, `.cc`, `platform/posix/command_line_posix.cc` | `src/command_line.rs`, `src/platform/posix/command_line_posix.rs` | 12 (+ 1 Windows) | 12 + 1 |
| `container.h` | `src/container.rs` | 1 | 1 |
| `safe_math.h`, `.cc` | `src/safe_math.rs` | 1 | 1 |
| `posix_wrappers.h`, `platform/posix/posix_wrappers_posix.cc`, `process.h`, `platform/posix/process_posix.cc` | `src/posix_wrappers.rs`, `src/process.rs`, `src/platform/posix/…` | — | — |
| `cpu_affinity.h`, `.cc` (not Android) | `src/cpu_affinity.rs` | 8 | 8 |
| `backtrace.h`, `.cc` (POSIX) | `src/backtrace.rs` | 1 | 1 + 1 |
| `trace_event.h`, `.cc` | `src/trace_event.rs` | — | — |

"+ n" are tests that are not upstream's, each marked as such: the
counting of `RefCountedThreadSafeBase`, a factory stored inside its object,
a `ScopedTemporaryDirectory` removing its whole tree, an empty `DataMapping`
being null, command line lookups stopping at a NUL, frames being symbolized,
the debug thread check, `SEM_VALUE_MAX`, tasks due at the same time running
in registration order, and five that cover breaks no upstream test caught
(see *Deliberate failures*): a terminated loop drops new tasks,
DoRun's last flush runs tasks that fell due, `RunsTasksOnCurrentThread`
follows merges, a destroyed `ConditionalBasicTaskRunner` drops its tasks, and
move-assigning a `ScopedCleanupClosure` does not invoke the closure it
replaces. Upstream tests not ported: `RefCountedTest.DebugChecks` (C++ debug
deaths on raw `delete`), `TimePoint.DartClockIsMonotonic` (it needs
`flutter/runtime`) and `CommandLineFromWideArgvUnicode` (Windows only); logging's static-initialization segfault check has no
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
| `file` | Random operations on a scratch tree, names drawn from ASCII, UTF-8, a 0xFF byte, a newline, `.`, a 256-byte name (ENAMETOOLONG) and nested paths, against the scratch directory, four descriptor slots, an invalid descriptor, or absolute paths (the `AT_FDCWD` overloads): `OpenFile`/`OpenDirectory` (create or not, all three permissions) and the read-only helpers, `CreateDirectory`, `IsDirectory` (both), `FileExists`, `IsFile`, `TruncateFile`, `UnlinkFile`/`UnlinkDirectory` (both), `WriteAtomically` (also of an empty, null mapping), `VisitFiles`/`VisitFilesRecursively` in readdir order with a stop, `RemoveFilesInDirectory`, `RemoveDirectoryRecursively`, `Duplicate`, a `FileMapping` of a slot, and `chmod` of files and directories (one operation runs under the directory's new mode). Every call is preceded by `errno = 0` and followed by printing `errno`; the final tree and the directory's removal are printed |
| `mapping` | `DataMapping` (vector and string, empty included), `NonOwnedMapping` (null, release callbacks, dontneed), `MallocMapping` (empty, `Copy` incl. zero length, `Release`, move), `FileMapping` of files of 0–9000 bytes opened read, write or read-write under every protection list of up to three entries (empty, duplicates, `{kWrite, kExecute}`), with errno, contents read where readable, a write through the mutable mapping read back after unmapping; the `CreateReadOnly`/`CreateReadExecute` factories (path, base and sub-path, descriptor) on files, a missing file and the directory; mappings of a directory and of an invalid descriptor |
| `paths` | `JoinPaths` of 0–4 components, `GetDirectoryName`, `SanitizeURIEscapedCharacters` and `FromURI` (four prefixes) on random bytes with `%`, hex digits, `%00`, 0x80/0xFF and NULs; `AbsolutePath` (empty, absolute, relative, run in the scratch directory); `GetExecutablePath`, `GetExecutableDirectoryPath`, `GetCachesDirectory` (their shape only: the executables differ) |
| `cmdline` | `CommandLineFromIteratorsFindFirstPositionalArg` on 0–6 arguments from malformed tokens (`--`, `-`, `--=`, `--==x`, `--a=b=c`, UTF-8, an embedded NUL, empty), `HasOption` (with index), `GetOptionValue`, `GetOptionValues`, `GetOptionValueWithDefault` for names including one with a NUL, `CommandLineToArgv` and the round trip, `CommandLineFromIteratorsWithArgv0`, the component constructor, copy, move, assignment and `==` |
| `misc` | `erase_if` on `std::map` (the visit order) and `std::unordered_map`; `SafeMath::mul` on edge sizes, its sticky overflow flag; `fml::strdup` of text with NULs; `GetCurrentProcId` |
| `affinity` | `CPUSpeedTracker` on 0–6 CPUs with repeated indices and edge speeds (negative, zero, `INT64_MIN`/`MAX`); `ReadIntFromFile` on synthetic files (white space, signs, 1–24 digits that overflow, suffixes, hex, words, empty), a missing file and a directory; `EfficiencyCoreCount`, `RequestAffinity`. Upstream reads `/sys` only on Android, through a path the code builds itself, so the files are injected through `ReadIntFromFile` |
| `native` | `NativeLibrary::Create` on libc, libm, libpthread, a missing path, `""` (the main program), a file that is not ELF and a directory (the debug builds log `dlerror`); `CreateForCurrentProcess`, `CreateWithHandle` (null, owned, not owned); `ResolveSymbol` and `ResolveFunction` (calling `strlen`); `SymbolMapping` with null libraries and names and its `_` fallback (`IO_putc` → `_IO_putc`) |
| `trace` | With a printing handler and a counting micros source: allowlists, installing and removing the handler, the micros source; every macro (`TRACE_EVENT0/1/2`, `FML_TRACE_EVENT` with string, integer, unsigned, bool, double, float and TimePoint arguments, `FML_TRACE_COUNTER`, the async, instant and flow macros, the `_WITH_FLOW_IDS` forms, `TRACE_EVENT2_INT`), `TraceEventAsyncComplete` (swapping begin and end), `TraceFlow` (steps, named steps, end, move, destruction), `TraceNonce`, and `OpenFile`'s own event. The events' order, labels, timestamps, ids, flow ids and arguments are printed |
| `backtrace` | `BacktraceHere` at offsets 0–3 and 300, checked for shape ("Frame <i>: 0x<hex> <name>" numbered from 0), and `InstallCrashHandler` in a child process that raises each handled signal: the signal it dies of, the log line naming the signal, and the shape of the backtrace after it. Which frames and names a binary has is not compared |

Threads and timing are kept out of every trace: the loop and merger suites
run on one thread at a time under the fake clock, and the thread suite holds
each thread while a batch is posted and prints per-thread order only after
every task has run. The one address upstream logs (SharedThreadMerger's
`caller=0x…`) is masked on both sides, and so is the name mkdtemp gives the
file-system suites' scratch directory (`/tmp/flutter_<tmp>`), which each run
makes fresh through `ScopedTemporaryDirectory` and leaves removed. Run as
root, the permission cases succeed where a user's would fail with EACCES;
both sides run as the same user, so they agree either way.
A driver run that does not finish in
`FML_ORACLE_TIMEOUT` seconds (300) fails the test, since a port that loses a
task leaves those suites waiting forever.

The oracle is built with `clang++ -stdlib=libc++ -O2 -DNDEBUG -fwrapv` from
`engine/src` with relative paths, as the engine is (without `-DNDEBUG` when
the port is a debug build, so that `FML_DLOG`/`FML_DCHECK` match): the
engine ships libc++,
whose `codecvt` and `std::hash` the port reproduces, and `-fwrapv` defines
the signed overflow that upstream leaves undefined (see *Differences*).
`FML_ORACLE_STDLIB=libstdc++` builds it against libstdc++ instead, whose
string hash differs (and whose `ifstream >> int64_t` differs from the
libc++ reading `ReadIntFromFile` reproduces). `-fmacro-prefix-map=./=`
makes `__FILE__` in headers read `flutter/fml/…` as in the engine's build,
where `../../` is stripped by `FML_LOG`.

## Running it

From `experiments/flutter`, with clang and libc++ (`libc++-dev`) installed:

```sh
cargo test --release
```

runs the unit tests and the oracle (20 suites × 16 seeds × 250 cases,
about three minutes; the thread suite dominates). `oracle/shim/` stands in
for what this checkout lacks: the Dart VM's `dart_tools_api.h` (only the
timeline event enum `trace_event.h` needs, so the real `trace_event.cc` is
built), abseil's `uint128` (the compiler's `unsigned __int128`, for
`safe_math.cc`) and abseil's `Symbolize` (dladdr, for `backtrace.cc`, whose
names the oracle does not compare).
`FML_ORACLE_SEED_BASE`, `FML_ORACLE_SEEDS`, `FML_ORACLE_CASES` and
`FML_ORACLE_SUITES` pick another corpus; `FML_ORACLE_WORK` moves the scratch
directory. The test fails on the first differing line of any run and prints
it.

Benchmarks: `fml_dump bench <name> <rounds>` with either binary prints the
fastest, median and slowest round, the peak RSS and a check value the two
drivers must agree on. Only the ported code runs while a round's stopwatch
runs, on both sides alike:

- `loop`, `thread` and `concurrent` post 10000 tasks to a Linux loop, an
  `fml::Thread` and a four-worker `ConcurrentMessageLoop` (the tasks share
  no reference count: the C++ captures by reference, the Rust a static or a
  leaked latch); `queues` is upstream's
  `message_loop_task_queues_benchmark.cc` (`BM_RegisterAndGetTasks`). Only
  the loop's own thread is timed in `loop`, not spawning it.
- `time`, `strings`, `hash`, `paths` and `cmdline` are kernels: a chunk of
  1000 inputs is drawn with the clock stopped, then the suite's calls run on
  them with each result folded into a checksum (the check value), so
  neither compiler can drop the work and neither side formats anything.
- `dispatch` (the queues suite), `merger`, `file`, `mapping` and `trace` run
  the suite with output off (the print macros do not evaluate their
  arguments: `QPRINTF` in C++, `p!`/`w!` in Rust), the random stream read
  from a tape refilled with the clock stopped, and the input generators and
  the driver's own threads (the merger's parked loops and case thread)
  outside the clock; the check value is the number of random draws taken,
  which pins the path both sides took.

Before these changes each round timed a whole suite, which included the
input generation and the formatting of every value (`format!` per escaped
byte in the Rust driver), so the drivers rather than the ports were
compared.

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
- Paths, file names and URIs are byte strings (`impl AsRef<[u8]>` in,
  `Vec<u8>` out), handed to the C library up to the first NUL as a
  `const char*` is. C++ overloads that take a base directory get an `_at`
  suffix after the POSIX calls they wrap (`OpenFile(base, path, …)` is
  `open_file_at`); `CommandLine` arguments are `SmallString`s (see below).
- Where libc++'s short-string optimisation decides upstream's cost (a
  command line's options and arguments, trace argument values), the port
  holds `SmallString`s (`small_string.rs`, not an upstream file): up to 22
  bytes inline as libc++ keeps them, read as a `str`, compared equal to
  `str` and `String`.
- `Mapping` is an `unsafe trait`: its pointer is null or covers `GetSize()`
  bytes while the mapping is borrowed. Reading through it is the caller's
  `unsafe`, as upstream leaves it to the caller; `NonOwnedMapping::new` is
  `unsafe` for the same reason (`from_static` is not).
- The POSIX files' C library declarations (with Linux's `struct stat` and
  `struct dirent` for x86-64 and AArch64) are in
  `src/platform/posix/libc.rs`; each call stays in the ported file.
- `unsafe` is confined to C library calls Rust's `std` has no safe form of:
  `clock_gettime` for `TimePoint::now()` (the engine compares that clock with
  platform timestamps), `epoll_create`/`epoll_ctl`/`epoll_wait`,
  `timerfd_create`/`timerfd_settime` and `read` in the Linux loop, `close` in
  `UniqueFD` and `closedir` in `UniqueDir`, the file calls (`openat`,
  `mkdirat`, `fstat`, `stat`, `ftruncate`, `unlinkat`, `faccessat`, `dup`,
  `write`, `fsync`, `renameat`, `fdopendir`/`readdir`/`rewinddir`,
  `mkdtemp`, `strerror`), `mmap`/`munmap`, `dlopen`/`dlsym`/`dlclose`/
  `dlerror`, `backtrace`, `signal`/`raise`, `getcwd` and `readlink` (into
  PATH_MAX buffers, as upstream), and `pthread_setname_np` on Apple; besides
  those, loading the trace handler and micros source from their atomics (a
  function pointer kept as a data pointer, as upstream's
  `std::atomic<fn*>`) and reading `SmallString`'s inline bytes as `str`.
  Each block has a SAFETY comment, and `tests/unsafe_audit.rs` fails when
  one does not (see *Safety*). Thread names on Linux are written to `/proc/thread-self/comm`,
  safely, with the effect of `pthread_setname_np`. The tests add a few pthread
  calls (stack size, scheduling) as upstream's do.

## Differences

None on the oracle's corpus. Where the port knowingly differs from the C++:

- Signed overflow in `TimeDelta`/`TimePoint` is undefined behaviour upstream;
  the port wraps (as every engine target does in practice, and as the oracle
  pins with `-fwrapv`). Out-of-range `double`→`int64` in `FromSecondsF` is
  undefined upstream; the port converts as the compiled C++ does
  (`cvttsd2si` on x86-64, giving `INT64_MIN`; Rust's saturating `as`, as
  AArch64's `fcvtzs`, elsewhere), pinned by
  `out_of_range_doubles_convert_as_upstreams_code_does`; the oracle does not
  feed it.
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
  is not virtual (its "ConcurrentWorkerWake" trace event is emitted after
  each wake in WorkerMain, as upstream's). The loop counts the workers
  blocked in its wait and skips `notify_one` when there are none, where
  `pthread_cond_signal` returns without a system call and std's `Condvar`
  would make one. A `closure` cannot be empty, so the null-task checks and the
  "Tried to add a null TaskObserver." path do not exist.
- `fml::UniqueFD{AT_FDCWD}`, which the overloads without a base directory
  build, holds -100, which is not the invalid value (-1): destroying it calls
  `close(-100)`, which fails with EBADF, so those calls leave `errno` at
  EBADF. Kept (the oracle prints it).
- Upstream's `TRACE_EVENT_ASYNC_END1` macro passes a flow id count and flow
  ids that `TraceEventAsyncEnd1` does not take, and does not compile;
  `trace_event_async_end1!` calls the function with what it takes. The
  oracle calls the function. The handler and micros source are atomics as
  upstream's; the allowlist is behind a lock (upstream's is unsynchronized);
  flow ids and arguments reach the handler as slices (up to eight on the
  stack, where upstream fills vectors); `FLUTTER_TIMELINE_ENABLED` is the `flutter_release` feature
  (off: every tracing function does nothing, as upstream's release build).
- `backtrace` names frames from `.symtab`/`.dynsym` of the object mapped at
  each address, as absl::Symbolize does, but does not demangle (Rust frames
  read `_ZN…E`); absl is async-signal-safe and this is not (it reads files
  and allocates, as upstream's handler's `FML_LOG` does). Windows' branch is
  not ported.
- `MallocMapping` owns a `Box<[u8]>` (upstream: malloc'd memory) and
  `Release` returns it; `posix_wrappers`' `strdup` returns a `CString`;
  `ReadIntFromFile` reads the whole file and parses it as libc++'s
  `ifstream >> int64_t` does (white space, sign, digits, saturation);
  `GetExecutablePath` and `AbsolutePath` call readlink and getcwd into
  PATH_MAX buffers as upstream does (so a working directory longer than
  PATH_MAX fails the check, as upstream's does). A null `const char*`
  (path, symbol, file name) cannot be passed. `CommandLine` takes UTF-8;
  `CommandLineFromWideArgv` (Windows) is not ported.
- `CommandLine` keeps no `option_index_`: upstream's unordered_map from each
  name to its last index is never iterated, so `HasOption` searches the
  options from the back instead, with the same answers. `TaskSource::PopTask`
  returns the popped task, so that `GetNextTaskToRun` moves the closure out
  where upstream copies it.
- `erase_if` takes the entry rather than an iterator (the same visit order
  for ordered maps).
- Logged non-UTF-8 file names ("Can't open sub-directory") are written
  lossily; the log stream is a `String`.
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
| `VisitFiles` drops its `rewinddir` | `visit_files_can_be_called_twice` |
| `CreateDirectory` stops at the first component | `create_directory_structure`, `can_list_files_recursively`, `can_stop_visit_early` |
| A `FileMapping` is never writable | `can_truncate_and_write`, `mapping_dont_need_safe_test`, `create_directory_structure` |
| `MallocMapping`'s move leaves the source holding its buffer | `move_constructor` |
| Lower-case hex escapes decode wrongly | `sanitize_uri` |
| `SanitizeURIEscapedCharacters` accepts `%00` | oracle `paths` (4 of 4); **not caught at first**: four seeds drew no `%00`, so the generator now draws it on purpose |
| `GetDirectoryName("/x")` is empty instead of "/" | oracle `paths` (3 of 4) |
| `CommandLineBuilder` looks for `=` from position 2 | `odd_arguments` |
| `HasOption` does not stop at a NUL | oracle `cmdline` (4 of 4); **no upstream test** — `lookup_stops_at_nul` added |
| `erase_if` keeps what the predicate holds for | `map_erase_if` |
| `SafeMath` misses overflow by one bit | `multiply_size_t` |
| `CPUSpeedTracker` takes the slowest as performance | `normal_slow_med_fast_cores` |
| `ReadIntFromFile` overflow reads 0 instead of `INT64_MAX`; white space other than ' ' not skipped | oracle `affinity` (4 of 4 each); **no upstream test** |
| The `AT_FDCWD` UniqueFD is released instead of closed (no EBADF) | oracle `file` (4 of 4) |
| `OpenFile` creates without `O_TRUNC` | oracle `file` (1 of 4) |
| An empty `DataMapping` is not null | oracle `file`, `mapping` (2 of 8); `empty_data_mapping_is_null` added |
| `kExecute` no longer overrides the other protections | oracle `mapping` (4 of 4) |
| `SymbolMapping` drops its `_` fallback | oracle `native` (4 of 4); **no upstream test** |
| The trace allowlist is ignored; `ScopedInstantEnd` ends nothing; `TraceEventAsyncComplete` does not swap; doubles not printed as "%f" | oracle `trace` (4 of 4 each); **upstream has no trace_event tests** |
| Frames print "frame" | `can_gather_backtrace`, `frames_are_symbolized` |
| Frames are not symbolized | `frames_are_symbolized` (added); **not caught by the upstream test or the oracle**, which check only the shape |
| The crash handler does not reset the handlers before re-raising | oracle `backtrace` (the child re-enters the handler forever; killed after the timeout) |
| ConcurrentWorkerWake traced when posting to a terminated loop instead of after each worker wake (the port shipped this way until the benchmark work found it) | `tests/concurrent_worker_wake.rs` (added; one event, from the posting thread); **not caught by the oracle**, whose thread suite runs without a trace handler |
| `BacktraceHere` keeps its caller's frame (its helper out of line) | `frames_are_symbolized` (rewritten to look past two out-of-line frames); before, the frames left out depended on whether LLVM inlined the helper |
| The Linux loop does not drain the timer | **not caught**: epoll is level-triggered, so the loop wakes once per flush either way; the cost is CPU, not behaviour |

## Benchmarks

Measured 2026-10-30 on a shared 4-core Intel Xeon at 2.10 GHz whose load
average stood at 7–9 from other builds throughout, clang 18.1.3 with libc++
18 at `-O2 -DNDEBUG`, rustc 1.97.0 with the workspace's release profile.
Each benchmark ran 4–8 times, alternating the C++ and the Rust binary, each
run a number of rounds (below); *fastest* is the fastest round of all runs,
*median* the median of the runs' medians. Peak RSS is the whole process
(`VmHWM`), the largest of the runs. Every run's check value agreed between
the two sides. On a machine this loaded the system-call-bound benchmarks
(`loop`, `thread`, `concurrent`, `merger`, `file`, `mapping`) move by tens
of percent from run to run, so for those the deterministic measures follow
the table.

| Benchmark (rounds per run) | C++ fastest | C++ median | Rust fastest | Rust median | C++ RSS | Rust RSS |
|---|---|---|---|---|---|---|
| `queues` (300) | 502 µs | 3935 µs | **355 µs** | **3881 µs** | 4.8 MiB | **4.0 MiB** |
| `dispatch` (20) | 18.3 ms | 23.8 ms | **16.4 ms** | **23.5 ms** | 3.7 MiB | **2.9 MiB** |
| `time` (300) | 388 µs | 435 µs | 394 µs | **434 µs** | 3.3 MiB | **2.9 MiB** |
| `strings` (20) | 98.4 ms | 111.0 ms | **4.0 ms** | **4.3 ms** | 3.6 MiB | **3.2 MiB** |
| `hash` (100) | 1037 µs | 1169 µs | **963 µs** | 1176 µs | 3.6 MiB | **3.3 MiB** |
| `loop` (10) | 459 ms | 544 ms | **448 ms** | 566 ms | 4.3 MiB | **4.0 MiB** |
| `thread` (10) | 438 ms | 573 ms | 450 ms | **499 ms** | 4.1 MiB | **3.4 MiB** |
| `concurrent` (200) | 0.78 ms | 4.10 ms | 1.11 ms | 5.02 ms | 4.2 MiB | **3.7 MiB** |
| `merger` (3) | 89.7 ms | 102.3 ms | **88.0 ms** | **99.8 ms** | 3.8 MiB | **3.1 MiB** |
| `file` (20) | 1.96 ms | 6.73 ms | 2.65 ms | 7.31 ms | 3.7 MiB | **2.9 MiB** |
| `mapping` (5) | 230 ms | 434 ms | 239 ms | **390 ms** | 3.7 MiB | **3.0 MiB** |
| `paths` (50) | 8.72 ms | 9.70 ms | **7.92 ms** | **9.36 ms** | 3.7 MiB | **3.2 MiB** |
| `cmdline` (50) | 22.0 ms | 24.4 ms | **13.3 ms** | **15.0 ms** | 3.7 MiB | **3.2 MiB** |
| `trace` (50) | 2.80 ms | 3.50 ms | **2.42 ms** | **3.02 ms** | 3.7 MiB | **2.8 MiB** |

Bold where Rust is ahead. Before this work (the old harness, which timed the
drivers' formatting with the ports, at 30 or 10 rounds) Rust trailed on
`cmdline` (94.5/102.0 ms against 52.5/60.3), `paths`, `trace`, `mapping`
and on the fastest rounds of `hash`, `dispatch`, `thread` and
`concurrent`. What changed:

- **Fair benchmarks** (see *Running it*): the drivers no longer time their
  own input generation and formatting.
- `cmdline`: libc++ keeps strings of up to 22 bytes inline and a Rust
  `String` always allocates, which made copies of a command line twice as
  slow; command lines now hold `SmallString`s, drop upstream's never
  iterated index map (lookups search the options from the back), and move
  rather than copy what the builder made.
- `hash`: CityHash's words are read at constant offsets from fixed-size
  arrays, without bounds checks.
- `dispatch`/`queues`/`thread`: the popped task's closure is moved out
  instead of cloned (an atomic increment and decrement per task).
- `paths`: `getcwd`/`readlink` into PATH_MAX stack buffers, one copy out.
- `trace`: the handler and micros source are atomics (they were behind
  read-write locks), argument and flow-id lists live on the stack, values are
  `SmallString`s formatted through a stack buffer.
- `concurrent`: std's `Condvar` makes a futex call on every `notify_one`,
  where `pthread_cond_signal` makes none without a waiter. The loop now
  notifies only when a worker waits that no earlier notification will wake:
  futex calls in 20 rounds fell from about 550 000 to 60 000–100 000, which
  is upstream's range (74 000–101 000).
- `time`: `FromSecondsF` converts with `cvttsd2si`, as upstream's compiled
  code does, instead of Rust's saturating cast; the per-case instruction
  count is now upstream's to 0.4% (3.42 M against 3.41 M for 20000 cases).

Where Rust is not ahead in the table:

- `time` fastest (+1.5%) and `hash` median (+0.6%): within the run-to-run
  spread on this machine; Callgrind counts the same work as upstream's
  (`time`) or less (`hash`). With the recommended profile below `hash` is
  ahead on both (902/1070 µs against 1038/1195) and `time` stays level
  within the spread (369/430 µs against 326/428: that fastest C++ round is
  25% under its median, an outlier of the load rather than of the code,
  whose instruction counts match).
- `loop` median, `thread` fastest, `file`, `mapping` fastest: these make the
  same system calls as upstream (`strace -c`: 20 001 `timerfd_settime` in
  both for `loop`; 20 004 against 20 031 and 3 344 against 35 900 futex
  calls for `thread`; the same `openat`/`fsync`/`mmap` counts for `file`
  and `mapping`) and fewer user-space instructions (`thread`: 19.0 M against
  37.6 M), and they are ahead in other runs (`file` 3.8/9.0 ms against
  3.4/12.1, `mapping` 263/373 ms against 369/406 earlier the same day). The
  difference is the scheduler and the disk.
- `concurrent` (fixed since; see *Unsafe code*): every posted task was an
  `Arc` closure, allocated on the posting thread and freed on a worker
  (malloc, free and `malloc_consolidate` were 40% of the benchmark's
  instructions). `closure` now keeps up to three words of captures in
  place, as libc++'s `std::function` does: the benchmark's instructions
  fell from 128.4 M to 49.6 M (upstream: 124.2 M, Callgrind, 20 rounds).

### Binary size

The driver binary (`fml_dump`, the oracle and benchmarks over each side) and
the ported code alone, in bytes:

| | C++ as the oracle builds it (libc++ shared) | C++, libc++ linked in | Rust, workspace profile | Rust, recommended profile |
|---|---|---|---|---|
| `fml_dump` unstripped | 634 056 | 1 749 072 | 1 432 816 | **1 034 600** |
| `fml_dump` stripped | 454 400 | 1 262 264 | 1 103 848 | **876 328** |
| ported code: text + data + bss | 168 824 (42 objects) | | 202 911 | **162 511** |
| ported code: object file(s) | 604 560 (667 082 as `.a`) | | 571 248 | **424 456** |

The C++ driver as the oracle builds it is smaller only because libc++
(`libc++.so.1`, `libc++abi.so.1`, `libunwind.so.1`) stays outside it; Rust
links its standard library in. Linked the same way, with libc++ inside, the
C++ binary is larger than either Rust one, unstripped and stripped. The
ported code is measured as the 42 upstream sources compiled to objects at
`-O2` against the crate compiled to one object (`cargo rustc --lib --
--emit=obj`). The workspace profile (`opt-level = 3`, 16 codegen units,
unwinding) makes more code than `-O2`. The **recommended profile**, which
matches `-O2`, is

```toml
[profile.release]
opt-level = 2
lto = "fat"
codegen-units = 1
panic = "abort"
```

in the workspace's `Cargo.toml` (`experiments/flutter/Cargo.toml`, shared
with the other crates there); the oracle passes under it (nothing in the
port catches a panic; FATAL and failed checks abort either way), and its
run of the table above is no slower: ahead on `queues`, `dispatch`,
`strings`, `hash`, `thread` fastest, `merger` median, `file` fastest,
`paths`, `cmdline` and `trace`; behind on `time` (above), `loop`,
`concurrent` and the fastest `mapping` round, for the reasons above. The
driver also writes all output through one function (`emit`) instead of
expanding the lock and the write at each of its several hundred call sites,
which took 190 KB off it.

## Safety

Every `.rs` file names the upstream file it ports in its first line, or says
that it is not a port (`lib.rs`, the `mod.rs` files, `small_string.rs`, the
driver and the tests).

### Unsafe code

`unsafe` appears only where the C library has to be called, a raw pointer
crosses the API, or `closure` keeps a callable in place as `std::function`
does (one type-erased buffer, below), never to skip a check in the ported
logic. Every site has a
`SAFETY:` comment (or a `# Safety` section) saying which invariant makes it
sound; `tests/unsafe_audit.rs` fails the build of the test suite when one
does not, and tests its own checker on a failing sample. The library's sites
(line numbers as of this table; the unit tests add pthread calls, reads of
mapped bytes and a counting allocator, the driver `errno`, `dlopen` and
`raise`):

| File | Lines | What | Why it is needed | Verified by |
|---|---|---|---|---|
| `platform/posix/libc.rs` | 73, 135, 189, 232, 250 | a zeroed `struct stat`; the C library declarations; `strerror`; `with_c_str`'s C string on its stack buffer (`from_bytes_with_nul_unchecked`, the parts cut at their first NUL and the buffer still zero after them) and the `memchr` that finds that NUL | the POSIX calls upstream makes, which `std` has no form of (`openat` relative to a descriptor, `mkdirat`, `fdopendir`, …); a path handed to them as upstream hands `c_str()`, with no heap `CString` per call and glibc's vectorized scan rather than core's word loop | oracle `file`, `mapping`, `native`, `paths`; `c_strings_are_cut_at_the_first_nul_on_every_path` (both buffer sizes and the heap, NULs before and after each boundary, the `.temp` suffix) under Miri; ASan |
| `platform/posix/file_posix.rs` | 28 … 358 (18 calls) | `mkdtemp`, `openat`, `mkdirat`, `dup`, `fstat`, `stat`, `ftruncate`, `unlinkat`, `faccessat`, `write`, `fsync`, `renameat`, `fdopendir`/`rewinddir`/`readdir` | upstream's file calls, in upstream's order, so that `errno` and the results match | oracle `file` (errno printed after every call); `file_unittest`; ASan |
| `platform/posix/mapping_posix.rs` | 46, 60, 95 | `fstat`, `mmap`, `munmap` | `FileMapping` | oracle `mapping` (contents read back, writes through the mapping re-read); `mapping_unittests` under Miri (in-memory mappings); ASan |
| `mapping.rs` | 25 … 345 | the `unsafe trait Mapping` (pointer covers `get_size()` bytes), its impls, `Send`/`Sync` for mappings that own their bytes, `NonOwnedMapping::new` | upstream hands out raw pointers; the trait states the contract a reader relies on | `mapping_unittests` under Miri; oracle `mapping`; ASan |
| `platform/posix/native_library_posix.rs`, `native_library.rs` | 18 … 93; 28 … 51 | `dlopen`, `dlsym`, `dlclose`, `dlerror`; `resolve_function` transmuting a symbol to the caller's function type | `NativeLibrary`; the caller names the type, as upstream's template does | oracle `native` (calls `strlen` through it); ASan |
| `platform/linux/message_loop_linux.rs`, `platform/linux/timerfd.rs` | 46 … 138; 37 … 90 | `epoll_create`/`epoll_ctl`/`epoll_wait`, `timerfd_create`/`timerfd_settime`, `read` | the Linux message loop | oracle `loop`, `merger`, `thread`; TSan and ASan |
| `unique_fd.rs` | 15, 38, 62 | `close`, `closedir` | `UniqueFD`/`UniqueDir` ownership | oracle `file` (the AT_FDCWD close's EBADF is printed); ASan |
| `platform/posix/paths_posix.rs`, `platform/linux/paths_linux.rs` | 19; 14 | `getcwd`, `readlink` into PATH_MAX buffers | upstream's calls and limits | `paths_unittests` under Miri; oracle `paths` |
| `time/time_point.rs` | 125 … 150 | `clock_gettime(CLOCK_MONOTONIC)` (`clock_gettime_nsec_np` on Apple) | the clock libc++'s `steady_clock` reads, which the engine compares with platform timestamps | `time` tests under Miri |
| `time/time_delta.rs` | 29 | `_mm_cvttsd_si64` (x86-64 only) | `FromSecondsF`/`FromMillisecondsF` convert as upstream's compiled code (`cvttsd2si`) does; the intrinsic needs only SSE2, which the cfg requires | `out_of_range_doubles_convert_as_upstreams_code_does`; `time` tests under Miri |
| `thread.rs` | 112, 118 | `pthread_setname_np` (Apple only) | thread names; Linux writes `/proc/thread-self/comm` safely | `thread_unittests` |
| `backtrace.rs` | 34 … 279 | `backtrace`, `signal` | `BacktraceHere` and `InstallCrashHandler` | `backtrace_unittests`; oracle `backtrace` (children killed by each signal) |
| `trace_event.rs` | 92, 103 | a function pointer loaded back from an `AtomicPtr<()>` | upstream's `std::atomic<TimelineEventHandler>`; a function pointer cannot sit in an atomic otherwise (sizes asserted at compile time; only function pointers are ever stored) | `tests/concurrent_worker_wake.rs` under Miri; oracle `trace` |
| `small_string.rs` | 68 | `from_utf8_unchecked` on the inline bytes | the inline bytes are always whole copies of `str`s (checked again under `debug_assertions`) | `small_string` tests and `command_line_unittest` under Miri; oracle `cmdline`, `trace` |
| `closure.rs` | 22 … 126 (the vtable's `unsafe fn` entries 22–24 and their bodies 46–48; writing the callable 96; calling, cloning and dropping through the vtable 105, 116, 126; `Send`/`Sync` 70, 72) | `closure` keeps a callable of up to three words in a buffer beside a pointer to a per-type vtable (call, clone, drop), as libc++'s `std::function` keeps `__buf_` beside its `__base` vtable; a larger or over-aligned callable is boxed and the `Box` kept in the buffer, so one vtable per type is the only erasure | posting a task allocated an `Arc` per closure on the posting thread and freed it on another, which was 40% of the `concurrent` benchmark's instructions; `std::function` allocates nothing for small captures. Moves need no entry (a Rust move copies the bytes); `Send`/`Sync` hold because every constructor requires them of the callable | `closure_unittests` (in place, boxed, zero-sized, over-aligned, shared, cloned, moved through a growing `Vec`, called from threads, a panic during a call and during a clone, every capture counted live; a counting allocator proves three words allocate nothing and a larger capture once per copy) under Miri; TSan over the unit tests, `concurrent_worker_wake` and the threaded oracle suites; the full oracle |

### Checks

Run 2026-10-30 with rustc 1.101.0-nightly (2026-10-29) for Miri, the
sanitizers and coverage:

- **Miri** (`cargo +nightly miri test -p fml --lib -- <module>`,
  `MIRIFLAGS=-Zmiri-disable-isolation`): 144 unit tests in 22 modules pass
  with no undefined behaviour reported — `ascii_trie`, `base32`, `closure`,
  `command_line`, `container`, `cpu_affinity` (all but `file_parsing`),
  `endianness`, `hash_combine`, `hex_codec`, `math`, the task queues and
  their merge/unmerge tests, `memory::ref_counted`, `memory::weak_ptr` (all
  but the task-runner-affine test), `safe_math`, `small_string`,
  `string_conversion`, the `synchronization` tests (threads, condition
  variables, semaphores), `task_source`, the `time` tests, `paths`
  (`getcwd`, `readlink`) and `mapping` — and `tests/concurrent_worker_wake.rs`
  (the worker threads and the trace handler loaded from its atomic). Miri
  cannot run the rest: they call `epoll_create` (every message loop, so the
  loop, thread, merger, task-runner and checker tests), `mkdtemp` (the file
  tests), `backtrace`, or spawn a process (the logging death tests). Those
  run under the sanitizers instead.
- **AddressSanitizer** (`RUSTFLAGS=-Zsanitizer=address cargo +nightly test
  -Zbuild-std`, debug): all 211 unit tests pass, and the oracle's suites
  (16 seeds for every suite) match except `native`, where ASan's own
  `strlen` interceptor makes the driver's `strlen` and the one `dlsym`
  returns differ ("same-strlen 0"): an artefact of the instrumentation, not
  of the port. No ASan report.
- **ThreadSanitizer** (`-Zsanitizer=thread`, std rebuilt, `halt_on_error=1`):
  all 211 unit tests, `tests/concurrent_worker_wake.rs`, and the oracle's
  threaded suites (`queues`, `loop`, `merger`, `thread`, `trace`, `logging`;
  2 seeds × 100 cases, whose stderr would carry any report) pass with no
  data race reported.
- **Coverage** (`-C instrument-coverage -Zcoverage-options=branch`, the unit
  tests, the two test binaries and the full oracle, merged; the ported files
  only, not the tests or the driver): **87.6% of lines** (3816 of 4355),
  **86.4% of branches** (603 of 698), 85.0% of functions, 85.7% of regions.
  Fully covered: `ascii_trie`, `container`, `cpu_affinity` (lines),
  `hex_codec`, `log_settings`, `paths_posix`, `task_runner_util`,
  `task_source`, `time_delta`, `unique_fd`, `count_down_latch`. The least
  covered are code the engine reaches and the oracle does not drive:
  `make_copyable` (0 of 17), `atomic_object` (0 of 11), `thread_checker`
  (8 of 26), `task_queue_id` (9 of 18), `eintr_wrapper` (10 of 19),
  `unique_object` (33 of 55), `sync_switch` (33 of 54), `safe_math` (22 of
  32), `weak_ptr` (82 of 113), `ref_ptr` (47 of 63), `backtrace` (129 of
  168). (That run found `frames_are_symbolized` failing: whether the port's
  `Backtrace` helper was inlined, and so which frames `BacktraceHere` left
  out, depended on the build. It is now always inlined, as upstream's is at
  `-O2`.)

## Not ported yet

The rest of `fml` is platform code or needs a library this checkout lacks:

- `icu_util.h`, `.cc`: its mapping half (open the data file directly or
  beside the executable, map it, refuse an empty one) is `file`, `paths` and
  `FileMapping`, all ported; the other half hands the bytes to ICU's
  `udata_setCommonData`, which needs ICU, so there is nothing to compare it
  against here.
- `backtrace.cc` on Windows (`CaptureStackBackTrace`, the CRT report mode)
  and `backtrace_stub.cc` (the build without backtraces); absl's C++
  demangler.
- `cpu_affinity` on Android (`platform/android/cpu_affinity.cc`: the
  cpufreq files under `/sys` and `sched_setaffinity`).
- `trace_event.h`'s Fuchsia branch (`lib/trace/event.h`).
- The message loops other than Linux (`platform/android`, `darwin`, `win`,
  `fuchsia`, including `task_observers` and
  `concurrent_message_loop_factory.mm`) and the logging sinks other than
  stderr.
- The Windows files: `platform/win` (file, mapping, paths, native library,
  command line with `CommandLineFromWideArgv`, process, posix_wrappers,
  errors and wide strings) and `UniqueFD`'s HANDLE branch and directory
  cache.
- The Darwin paths and helpers (`platform/darwin`: `paths_darwin.mm`,
  CF/NS utilities, `scoped_nsobject`, string ranges), Android's JNI
  helpers and `paths_android.cc`, and Fuchsia's `paths_fuchsia.cc`.
- `build_config.h` and `macros.h` (nothing to port) and the `TaskRunner`
  subclassing the embedder uses.

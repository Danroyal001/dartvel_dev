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

Benchmarks: `fml_dump bench <name> <rounds>` with either binary; `loop`,
`thread` and `concurrent` post 10000 tasks to a Linux loop, an `fml::Thread`
and a four-worker `ConcurrentMessageLoop`; `queues` is
upstream's `message_loop_task_queues_benchmark.cc` (`BM_RegisterAndGetTasks`),
the others run a suite with its output discarded (`file`, `mapping`,
`paths`, `cmdline` and `trace` included).

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
  `open_file_at`); `CommandLine` arguments are `String`s.
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
  `dlerror`, `backtrace`, `signal`/`raise`, and `pthread_setname_np` on
  Apple. Each block has a SAFETY
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
  is not virtual (its "ConcurrentWorkerWake" trace event is emitted, as
  upstream's). A `closure` cannot be empty, so the null-task checks and the
  "Tried to add a null TaskObserver." path do not exist.
- `fml::UniqueFD{AT_FDCWD}`, which the overloads without a base directory
  build, holds -100, which is not the invalid value (-1): destroying it calls
  `close(-100)`, which fails with EBADF, so those calls leave `errno` at
  EBADF. Kept (the oracle prints it).
- Upstream's `TRACE_EVENT_ASYNC_END1` macro passes a flow id count and flow
  ids that `TraceEventAsyncEnd1` does not take, and does not compile;
  `trace_event_async_end1!` calls the function with what it takes. The
  oracle calls the function. The trace globals are behind locks (upstream's
  allowlist is unsynchronized); flow ids and arguments reach the handler as
  slices; `FLUTTER_TIMELINE_ENABLED` is the `flutter_release` feature
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
  `GetExecutablePath` and `AbsolutePath` call std's `read_link` and
  `current_dir`, which call readlink and getcwd. A null `const char*`
  (path, symbol, file name) cannot be passed. `CommandLine` takes UTF-8;
  `CommandLineFromWideArgv` (Windows) is not ported.
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
| `file` (250 operations, 10 rounds) | 5.7 ms | 10.0 ms | 3.1 ms | 5.6 ms | 3.5 MiB | 2.9 MiB |
| `mapping` (2000 cases, 10 rounds) | 375 ms | 427 ms | 395 ms | 471 ms | 3.6 MiB | 2.9 MiB |
| `paths` (20000 cases, 10 rounds) | 18.4 ms | 19.4 ms | 21.8 ms | 26.0 ms | 3.5 MiB | 3.2 MiB |
| `cmdline` (20000 cases, 10 rounds) | 52.5 ms | 60.3 ms | 94.5 ms | 102.0 ms | 3.5 MiB | 2.8 MiB |
| `trace` (20000 cases, 10 rounds) | 8.4 ms | 8.6 ms | 10.0 ms | 11.9 ms | 3.6 MiB | 2.8 MiB |

The loop benchmarks are dominated by system calls (each post rearms the
timerfd; each flush reads the clock and rearms it), which are slow in this
sandbox and identical on both sides. `concurrent` is contention-bound and
very noisy: C++ has the faster best rounds, Rust the faster medians (its
`Mutex`/`Condvar` are futexes; libc++'s are pthread's).

The `strings` gap is libc++'s `wstring_convert`, which allocates a converter
per call and throws on bad input; `hash` and `dispatch` are slower in Rust
at the fastest round, within noise at the median.

The file-system benchmarks are system calls (each `WriteAtomically` is an
fsync, `mapping` writes up to 9000 bytes and maps them); the port makes the
same calls, and is faster at `file` where upstream builds strings through
`std::stringstream`. `paths`, `cmdline` and `trace` are dominated by the
drivers' formatting of every byte as it is printed, which is slower in
the Rust driver (`format!` per escaped byte); `cmdline` also hashes option
names with SipHash where libc++ uses CityHash.

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

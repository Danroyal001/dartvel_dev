# dartvel_aot: whole-program Dart compilation with tree shaking

Ours, not a port. A Dart compiler that sees the whole program at once
(the user's code and the core library it uses), works out at compile time
what can run, and emits only that. Its front end is the Rust port of the
Dart analyzer's `parseString` in `../analyzer`; its back end writes C for
the system C compiler.

It exists because of a problem a compiler author described in November
2026: `dartc` compiling hello world went from 16 KiB to 5.12 MiB, and the
cause was the Dart SDK pushing compile-time work to run time, with no
whole-program inference of user-code semantics, keeping alive many objects
that are unreachable at run time. The measurements below show where the
stock SDK's bytes go, and this crate is the first increment of not paying
for them.

## Where the stock SDK's bytes go

Measured 2026-11-15, Dart 3.13.4 (stable), linux x64, on the programs in
`tests/programs/` (`hello`, `json_roundtrip`, `http_handler`).

| Program | `dart compile exe` | of which AOT snapshot | `dart compile js -O2` | `-O4` | `dart compile wasm` (+ `.mjs`) |
|---|---|---|---|---|---|
| hello | 6,501,864 | 800,216 | 5,168 | 5,168 | 1,828 (+ 6,206) |
| json_roundtrip | 6,561,872 | 860,232 | 51,671 | 49,034 | 51,549 (+ 6,773) |
| http_handler | 6,562,520 | 860,880 | 53,637 | 50,785 | 55,910 (+ 6,994) |

Bytes. Where they come from:

1. **The VM runtime.** A `dart compile exe` binary is `dartaotruntime`
   (5,667,040 bytes in this SDK) with the AOT snapshot appended: the
   garbage collector, the snapshot reader, isolates and ports, the
   service protocol hooks, FFI, the symbolizer. Every program carries all
   of it, whether it allocates one object or a million. That is 87% of
   hello world.
2. **Core library retention.** Hello world's snapshot keeps 1,463
   compiled functions, 290,508 bytes of machine code, of which `main` is
   40 bytes (`--print-instructions-sizes-to`). The rest is `dart:core`
   (120,656), `dart:async` (40,688), stubs (33,132), `dart:typed_data`
   (31,376), `dart:_compact_hash` (13,584), `dart:convert` (12,968),
   `dart:isolate` (12,316), `dart:io` (7,316) and more. They are kept
   because the VM's own entry points are roots the tree shaker must
   assume reachable (`@pragma('vm:entry-point')`: isolate start-up, the
   zone and microtask loop that run `main`, `print`'s path through
   `dart:_builtin`, error and stack-trace formatting), not because hello
   world calls them.
3. **Run-time type information and metadata.** The other 510 KB of
   hello's snapshot is data, not code: object pools, class tables, type
   arguments and type-testing stubs, names kept for `toString` and
   `runtimeType`, PC descriptors and stack maps. On the web the same cost
   is visible by name: in `json_roundtrip -O4` (49,018 bytes),
   `dart2js --dump-info` charges 16,611 bytes to `rti` (the run-time type
   library), 11,302 to `_js_helper` and 2,756 to `_interceptors`, against
   4,592 for `dart:convert` itself and 824 for the program.
4. **Escaping objects.** To keep the public API's surface, generic code
   builds objects whose only purpose is that a caller *might* use them:
   a `jsonDecode` reaches the whole `JsonCodec`/`Converter`/sink machinery,
   and `print` reaches zones. A closed-world compiler can see that nobody
   does.

`dart2js` and `dart2wasm` already shake well (hello is 5 KiB and 2 KiB);
what they cannot drop is the run-time type system, which is why one JSON
round trip costs 50 KiB on both.

## Design: what is computed at compile time

The program is **closed**: there is no `dart:mirrors`, no loading of code
at run time, and nothing is looked up by name. Under that assumption:

1. **Closed-world call graph.** From `main`, follow every call. A static
   call (top-level function, static method, constructor, super call)
   reaches one function. A dynamic call (`x.foo(...)`) reaches the
   implementations of `foo` in the classes `x` can be.
2. **Type flow (rapid type analysis, this increment).** A class's
   methods matter only if some reachable code instantiates the class. The
   set of instantiated classes and the set of invoked selectors grow
   together until neither changes; a method is reachable when its class
   is instantiated and its selector is invoked. The next step is a full
   type-flow analysis (the VM's TFA, done here at compile time over the
   resolved program): per-call-site receiver sets from the ported
   resolver's static types, so a call whose receiver can be one class
   becomes a plain call.
3. **Devirtualisation.** Each invoked selector becomes one dispatch
   function with a case per instantiated class that implements it; with
   one target that is a guarded direct call the C compiler inlines. Once
   static types are in (next increments), the guard goes too.
4. **Dropping what cannot run.** Unreachable classes, members, globals
   and core-library code are not emitted at all, and neither is run-time
   type metadata nobody can observe: class names are emitted only when
   the default `Object.toString` (`Instance of 'X'`) is reachable, and
   only for instantiated classes. `is` and `as` compile to class-id
   tests over the instantiated subclasses, not to a type object.
5. **No runtime system you did not ask for.** No VM, no snapshot, no
   isolates, no zones: the runtime is a few C helpers, each `static`, so
   the C compiler drops any no reachable code calls.

### What is safe to remove, and what must stay

- **Removed:** functions no reachable call can land on; classes never
  instantiated (their `is` checks become `false`); selectors never
  invoked; class names, unless default `toString` is reachable;
  core-library code (JSON, map/list printing, `int.parse`, iterators)
  unless used.
- **Kept, for correctness:** every override of an invoked selector in an
  instantiated class, including `toString` overrides, which string
  interpolation and `print` invoke implicitly; `noSuchMethod` behaviour
  (a dynamic call on a class without the member throws, as in Dart);
  the order of evaluation (arguments are evaluated left to right even
  though C does not promise it); lazy initialisation of top-level
  variables; 64-bit wrapping integer arithmetic and Dart's `%`, `~/`
  and shift semantics.
- **Assumed absent:** `dart:mirrors`, deferred loading, isolates, and any
  lookup of members by string. A program that needs them cannot be
  closed-world compiled; it keeps the stock SDK.

## The supported subset (this increment)

Single-file programs that import at most `dart:core` and `dart:convert`:
classes with single inheritance, fields, constructors (with `this.x`
parameters, initializer lists and `super(...)`), methods, getters,
setters, `operator []`/`[]=`, static methods, top-level functions and
lazily initialised top-level variables; `int`, `bool`, `String`
(ASCII), `null`, `List`, `Map` (insertion-ordered), `StringBuffer`;
interpolation, `is`/`is!`/`as`, `??`, `?:`, compound and index
assignment, `++`/`--`, `if`, `while`, `for`, `for-in`, `break`,
`continue`; `print`, `jsonEncode`, `jsonDecode`, `int.parse`.

Everything else is a compile error that names the construct, never a
silent miscompile: doubles, closures and tear-offs, named parameters,
generics as run-time types (type arguments are erased; `is List<int>` is
refused), mixins and interfaces, exceptions (`throw`/`try`), async,
`dart:io`, non-ASCII strings. Memory is never freed (no GC yet), so it
is for short-lived programs. The C compiler is the system's (`$CC` or
`cc`).

## Results

`dartvel_aot build <file.dart> -o <exe> --tree-shake=none|calls|types`;
`--report` lists what was kept. Sizes in bytes, linux x64, gcc `-Os`,
stripped, position-independent, dynamically linked against libc (as the stock executable is), gcc 15.2:

| Program | stock `exe` | stock `js -O4` | stock `wasm` (+ `.mjs`) | ours, `none` | ours, `calls` | ours, `types` |
|---|---|---|---|---|---|---|
| hello | 6,501,864 | 5,168 | 1,828 (+ 6,206) | 14,720 | 6,216 | **6,216** |
| json_roundtrip | 6,561,872 | 49,034 | 51,549 (+ 6,773) | 28,224 | 24,128 | **24,096** |
| http_handler | 6,562,520 | 50,785 | 55,910 (+ 6,994) | 28,736 | 28,736 | **28,704** |
| shapes | | | | 18,992 | 14,896 | **14,800** |
| loops | | | | 19,216 | 19,224 | **19,144** |

An empty C program (`int main(void) { return 0; }`) built the same way
is 5,968 bytes, so hello world's own code and data are 248 bytes; without
shaking they are 8,752. Hello world keeps 8 of the 110 functions the
program and its core library declare, 4 of 11 classes and 1 of 49
selectors. The JavaScript and WebAssembly columns need a JavaScript
engine to run and are there to show where the stock SDK's shaking
already works; the native column is the like-for-like one, 230 to 1,050
times larger.

`calls` matches `types` on hello because hello invokes one selector;
`types` wins where classes are declared but never made (`shapes`) or a
core-library class goes unused. `http_handler` uses nearly everything it
declares, so all three modes are within a few bytes.

Every row prints exactly what `dart run` prints, byte for byte
(`tests/differential.rs`, five programs, all three modes).

## Tests

```sh
cargo test -p dartvel_aot
```

- `tests/differential.rs`: each program in `tests/programs/` is compiled
  in each mode and run; its stdout must equal `<name>.expected` byte for
  byte, which is the stock SDK's output. When `dart` is on PATH the test
  re-runs it and fails if a recording is stale.
- `tests/size.rs`: the tree shaker's contract. Hello world is at most
  24 KiB and at most 2 KiB over an empty C program built the same way;
  shaking by types is never larger than the other modes and smaller
  overall; hello world keeps no JSON code, no class names, no `List` and
  no `Map`; a class that is declared but never instantiated keeps none of
  its members or its name.

## Next increments, in order

1. Static types from the ported resolver (branch `agent/rust-body`): per
   call site receiver sets, unguarded direct calls, unboxed `int`/`bool`
   locals.
2. A garbage collector (precise, using the class layouts this compiler
   already knows), so long-running programs can be compiled.
3. Closures and tear-offs, named parameters, exceptions.
4. `double` with Dart's exact `toString`; UTF-16 strings.
5. More of `dart:core` and `dart:convert` written in the prelude, then
   `dart:io` (files, sockets) over the C library, so a real HTTP server
   compiles.
6. Our own object-file writer, to drop the dependency on a C compiler.

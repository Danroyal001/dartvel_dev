# `vm` in Rust

A file-by-file Rust port of the AOT global type-flow analysis of this
package (`lib/transformations/type_flow/`, about 16,000 lines of Dart), to
become a drop-in stage of `gen_kernel --aot`: the Dart passes before it, the
Rust type flow (kernel in, kernel out), the Dart passes after it, stock
`gen_snapshot`. Same input, same output, byte for byte; the proof is
upstream's own tests and expectation files, unchanged.

It builds on the kernel crate (`../../kernel/rust`), whose binary reader and
writer are byte-identical to upstream's. Each file under `src/` ports the
Dart library at the same path under `../lib` and names it in its first line.

## The oracle

Upstream's `test/transformations/type_flow/summary_collector_test.dart`
compiles each program in `testcases/transformations/type_flow/summary_collector`,
prints the summary of every member of the main library (and of each local
function) and compares the text with the program's `.expect` file.

- `oracle/build_inputs.dart` (run on the installed Dart VM, this checkout's
  `pkg/front_end`, `pkg/kernel` and `pkg/vm` from source) builds this
  checkout's VM platform, compiles each testcase as the test does (VmTarget,
  the platform as SDK summary, the main library renamed `#lib`) and writes
  its `.dill`. It then runs the test's own `PrintSummaries`, copied from the
  test file at build time (everything above `class TestOptions`, minus the
  `package:test` and `common_test_utils.dart` imports, which it does not
  use), on the component in memory and on the `.dill` read back. Both must
  equal the `.expect` file: **12 of 12 do**, so the `.dill` carries
  everything the test's output depends on.
- `tests/summary_collector_test.rs` ports the test: its fakes
  (`FakeTypesBuilder`, `FakeEntryPointsListener`, `FakeSharedVariableBuilder`)
  and `PrintSummaries`, run on the Rust port over each `.dill`, compared byte
  for byte with the unchanged `.expect` file.

```sh
DART=/path/to/dart cargo test -p vm --test summary_collector_test -- --nocapture
```

Inputs go to `target/tfa_oracle` (or `TFA_ORACLE`); the test builds them
when they are missing. Each run writes the port's text to
`<name>.rust.txt` beside the `.dill`.

## Pass count

| Test | Testcases | Identical to `.expect` |
|---|---|---|
| `summary_collector_test` | 12 | **12** |

The directory holds 13 `.expect` files: `class_generics.dart.expect` has no
`.dart` beside it, so upstream's test never runs it (it prints statements,
`_Instantiate`, that this checkout's summary.dart no longer has).

On a stub (first commit) the oracle passed 0 of 12.

## What is ported

| Dart (`../lib/...`) | Rust (`src/...`) | Extent |
|---|---|---|
| `transformations/type_flow/types.dart` | same path `.rs` | types, equality, text, `fromStaticType`, constant/closure/record types; not `union`, `intersection`, `specialize` |
| `transformations/type_flow/calls.dart` | same | selectors, `Args` |
| `transformations/type_flow/summary.dart` | same | statements (in an arena, by index), text, `Summary`; `simplify` is beside the normalizer; not `apply` |
| `transformations/type_flow/summary_collector.dart` | same | `SummaryCollector`, `_SummaryNormalizer`, `_VariablesInfoCollector`, `RuntimeTypeTranslatorImpl`, `ConstantAllocationCollector`; not native procedures, protobuf handler, field guards, `UsedFieldsCollector`, the side tables the transformer reads |
| `transformations/type_flow/analysis.dart` | same | `GenericInterfacesInfoImpl`, the `EntryPointsListener` interface |
| `modular/target/vm.dart` | same | `VmTarget`'s concrete classes |

In the kernel crate (new modules; the binary reader and writer are not
touched): `reference_index.rs` (what `Reference.node` and parents give
upstream), `visitor.rs` (`visitChildren` order), `core_types.rs`,
`type_algebra.rs` (`Substitution`), `class_hierarchy.rs` (closed-world
generic supertypes, dispatch targets, interface members, subtypes),
`type_environment.rs` (subtyping, `getStaticType`, `getterType`),
`src/printer.rs` (`AstPrinter` with `astTextStrategyForTesting`). Each is
ported as far as the summaries need; the parts not yet exercised by an
oracle (subtyping of function and record types, `nnbdTopMergeSupertype` for
differing instantiations, printing of expressions the summaries do not
print) are approximations or panics, and say so.

## What is next

1. `types_test.dart`: union, intersection and specialization of types,
   against upstream's own test.
2. `transformer_test.dart` is the real gate: the whole analysis
   (`analysis.dart`, `transformer.dart`, `signature_shaking.dart`,
   `table_selector_assigner.dart`, `unboxing_info.dart`, `rta.dart`,
   `native_code.dart`), kernel in and kernel out, compared with upstream's
   `.expect` files for the 120 programs in
   `testcases/transformations/type_flow/transformer`. That needs the VM's
   metadata repositories in the kernel writer (the analysis writes inferred
   types, call-site attributes, table selectors and unboxing info as
   metadata) and kernel's text printer (`ast_to_text.dart`), which the
   transformer test compares.
3. Then the stage in `gen_kernel --aot` itself, checked by byte-identical
   `.dill` output over the kernel corpus.

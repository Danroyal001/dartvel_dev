# Static Error Cross-File Contexts

This document describes the current static error expectation format used by the test runner, and a possible extension for context messages whose locations are in files other than the primary diagnostic location.

The short version is:

```text
// main_test.dart
import 'helper.dart';

void f(C c) {
  c.value.isEven;
  //      ^^^^^^
  // [analyzer 1 see helper.dart] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
}
```

```text
// helper.dart
class C {
  int? get value => 0;
  //       ^^^^^
  // [context 1 for main_test.dart] 'value' refers to a getter so it couldn't be promoted.
}
```

The relationship is bidirectional. The primary error names helper files with a `see` list, and each cross-file context marker names its owning root test with a `for` clause. A shared helper does not affect a root test unless both sides agree.

See also:

- `doc/refactorings/plans/source_identity.md`
- `doc/refactorings/plans/diagnostic_source_ownership.md`
- `pkg/test_runner/lib/src/static_error.dart`
- `pkg/test_runner/lib/src/command_output.dart`
- `pkg/test_runner/lib/src/update_errors.dart`

## Table of Contents

- [Current Model](#current-model)
  - [Static Error Markers](#static-error-markers)
  - [Context Messages](#context-messages)
  - [Parsing Imports](#parsing-imports)
  - [Analyzer And CFE Output](#analyzer-and-cfe-output)
  - [Updater](#updater)
- [Problems](#problems)
  - [Cross-File Contexts Cannot Be Expressed](#cross-file-contexts-cannot-be-expressed)
  - [Shared Helpers Make Inline Ownership Ambiguous](#shared-helpers-make-inline-ownership-ambiguous)
  - [The Updater Writes One Root At A Time](#the-updater-writes-one-root-at-a-time)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Format](#proposed-format)
  - [Same-File Contexts](#same-file-contexts)
  - [Cross-File Contexts](#cross-file-contexts)
  - [Grammar](#grammar)
  - [Path Resolution](#path-resolution)
  - [Numbering](#numbering)
- [Proposed Semantics](#proposed-semantics)
  - [Context Anchors](#context-anchors)
  - [Attaching Contexts](#attaching-contexts)
  - [Unconsumed Contexts](#unconsumed-contexts)
  - [Validation](#validation)
- [Updater Direction](#updater-direction)
  - [Rewrite Strategy](#rewrite-strategy)
  - [Ownership Of Existing Helper Markers](#ownership-of-existing-helper-markers)
  - [Dropping Contexts](#dropping-contexts)
  - [Number Allocation](#number-allocation)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

<a name="static-error-markers"></a>
### Static Error Markers

Static error tests encode expected frontend diagnostics in line comments.

An error location is written either with carets:

```text
badExpression;
// ^^^^^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.SOME_CODE
// [cfe] CFE message.
```

or with an explicit location:

```text
// [error line 12, column 34, length 5]
// [analyzer] COMPILE_TIME_ERROR.SOME_CODE
```

The frontend marker is one of:

- `[analyzer]`
- `[cfe]`
- `[web]`

Analyzer expectations use error codes. CFE and web expectations use diagnostic text.

<a name="context-messages"></a>
### Context Messages

Context messages are represented by a pseudo frontend marker:

```text
int? get value => 0;
//       ^^^^^
// [context 1] 'value' refers to a getter so it couldn't be promoted.

void f(C c) {
  c.value.isEven;
  //      ^^^^^^
  // [analyzer 1] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
}
```

The number links a context marker to a numbered primary diagnostic marker. Numbers are arbitrary join keys. The current parser enforces only local consistency:

- a context marker must have a number,
- a numbered primary error must have at least one context with the same number,
- two primary errors in the same parsed file cannot use the same number,
- a context marker whose number does not match any primary error in the same parsed file is a format error,
- the numbers do not have to start at `1`,
- the numbers do not have to be contiguous,
- the numbers do not have to appear in source order.

The updater assigns fresh simple numbers, starting from `1`, to errors that have context messages.

<a name="parsing-imports"></a>
### Parsing Imports

`TestFile._parseExpectations()` parses the root test file and recursively parses local imports. Each file is passed separately to `StaticError.parseExpectations()`.

This means imported libraries can contain their own expected errors. It also means context attachment is currently file-local: `_attachContext()` only sees the numbered primary errors and context markers parsed from one file.

<a name="analyzer-and-cfe-output"></a>
### Analyzer And CFE Output

Analyzer JSON diagnostics already include `contextMessages`, and each context message carries its own file location. The test runner currently drops analyzer context messages whose file is different from the primary diagnostic file.

CFE output parsing also recognizes `Context` messages and attaches them to the preceding CFE error or warning. If CFE prints a location for the context message, the parsed `StaticError` can carry that path.

The in-memory model is therefore close to what is needed. The missing support is in the expectation format, parser, validator, and updater.

<a name="updater"></a>
### Updater

`update_static_error_tests.dart` runs analyzer, CFE, or dart2js for each selected root test. It converts actual diagnostics to `StaticError` objects and calls `updateErrorExpectations()` to rewrite expectation comments.

Today this is effectively a per-root rewrite:

1. collect diagnostics for one root test,
2. find files mentioned by the primary errors,
3. rewrite those files,
4. move to the next root test.

When `--context` is not passed, context messages are omitted from output. When `--context` is passed, context messages are flattened into the file being rewritten and numbered by `_numberErrors()`.

<a name="problems"></a>
## Problems

<a name="cross-file-contexts-cannot-be-expressed"></a>
### Cross-File Contexts Cannot Be Expressed

The current format cannot say that an error marker in `main_test.dart` owns a context marker in `helper.dart`.

A marker such as `[context 1]` in `helper.dart` can only be attached to a numbered primary error in that same `StaticError.parseExpectations()` call. If the primary error is in `main_test.dart`, the relationship is lost.

<a name="shared-helpers-make-inline-ownership-ambiguous"></a>
### Shared Helpers Make Inline Ownership Ambiguous

Many helper libraries are imported by more than one test. If helper files are allowed to contain cross-file context markers without explicit ownership, those markers leak into every test that imports the helper.

The root test must own the relationship. The helper should provide context anchors, but each cross-file context anchor should also say which root test owns it. This gives the test runner and updater a narrow ownership rule instead of asking them to infer ownership from imports.

<a name="the-updater-writes-one-root-at-a-time"></a>
### The Updater Writes One Root At A Time

The current updater can safely rewrite one root test at a time because each expectation is effectively owned by the file being rewritten.

Cross-file contexts break that assumption. If both `a_test.dart` and `b_test.dart` use `helper.dart`, processing `a_test.dart` must not remove or renumber context markers that still belong to `b_test.dart`.

<a name="design-goals"></a>
## Design Goals

- Keep the existing same-file format valid.
- Let expected analyzer and CFE context messages point to other files.
- Keep context markers close to the source ranges they describe.
- Make root tests explicitly opt into context files, and make helper context markers explicitly point back to their owning root tests.
- Preserve the existing simple mental model for same-file context messages.
- Keep numbering arbitrary, but make updater-assigned numbers collision-safe for shared helper files.
- Let the updater remove stale context expectations for selected root tests without damaging expectations that belong to unselected root tests.
- Keep validation deterministic and easy to explain in failure output.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign static error expectations unrelated to context messages.
- Do not require frontend diagnostics to produce stable IDs.
- Do not require helper libraries to know all tests that import them. A helper only names a root test when that root test has an actual cross-file context expectation in the helper.
- Do not make context messages affect primary diagnostic ownership. A primary diagnostic still belongs to the file containing its primary location.
- Do not make updater cleanup of orphaned shared-helper context markers a default destructive operation.

<a name="proposed-format"></a>
## Proposed Format

<a name="same-file-contexts"></a>
### Same-File Contexts

Same-file context expectations keep the current spelling:

```text
int? get value => 0;
//       ^^^^^
// [context 1] 'value' refers to a getter so it couldn't be promoted.

void f(C c) {
  c.value.isEven;
  //      ^^^^^^
  // [analyzer 1] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
}
```

No `see` or `for` clause is needed when the context marker is in the same file as the primary diagnostic marker.

<a name="cross-file-contexts"></a>
### Cross-File Contexts

A numbered primary diagnostic can list additional files to search for context markers:

```text
// main_test.dart
import 'helper.dart';
import 'another.dart';

void f(C c) {
  c.value.isEven;
  //      ^^^^^^
  // [analyzer 1 see helper.dart, another.dart] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
}
```

```text
// helper.dart
class C {
  int? get value => 0;
  //       ^^^^^
  // [context 1 for main_test.dart] 'value' refers to a getter so it couldn't be promoted.
}
```

```text
// another.dart
class D {
  int? get value => 0;
  //       ^^^^^
  // [context 1 for main_test.dart] 'value' refers to a getter so it couldn't be promoted.
}
```

The `see` clause says that the primary diagnostic should include context markers from the listed files. The `for` clause on each helper context marker says which root test owns that marker. The relationship is valid only when both sides match: the primary marker lists the helper file, and the helper marker points back to the primary file.

The same spelling works for CFE:

```text
// [cfe 2 see helper.dart] Property 'isEven' cannot be accessed on 'int?' because it is potentially null.
```

<a name="grammar"></a>
### Grammar

The marker grammar should be extended for numbered primary diagnostic markers and context markers:

```text
primary-marker:
  "[" source "]"
  "[" source number "]"
  "[" source number "see" path-list "]"

context-marker:
  "[context" number "]"
  "[context" number "for" path "]"

source:
  "analyzer" | "cfe" | "web"

path-list:
  path
  path "," path-list
```

`see` is invalid on unnumbered primary markers because there would be no number to match in the context files. `see` is also invalid on context markers. `for` is valid only on context markers, and is required when a context marker is in a different file from the primary diagnostic that owns it.

The initial implementation can require simple paths with no spaces. That matches current test file paths and avoids needing escaping rules inside marker comments.

<a name="path-resolution"></a>
### Path Resolution

Paths in a `see` clause are resolved relative to the file containing the primary diagnostic marker. Paths in a `for` clause are resolved relative to the file containing the context marker.

For example, in `tests/language/foo/main_test.dart`:

```text
// [analyzer 1 see helpers/types.dart] COMPILE_TIME_ERROR.X
```

refers to:

```text
tests/language/foo/helpers/types.dart
```

The parsed and stored path should be canonicalized the same way `StaticError` canonicalizes paths today, so validation compares relative paths consistently.

For example, in `tests/language/foo/helpers/types.dart`:

```text
// [context 1 for ../main_test.dart] Context message.
```

refers back to:

```text
tests/language/foo/main_test.dart
```

<a name="numbering"></a>
### Numbering

Numbers remain arbitrary join keys, not semantic identifiers. They are not stable across updater runs.

For same-file contexts, existing rules continue to apply. For cross-file contexts, the effective join key is `(owner root path, number)`, where the owner root path comes from the helper-side `for` clause.

This matters for shared helpers. If `a_test.dart` and `b_test.dart` both use `helper.dart`, they may both use number `1` because the helper context markers have different owners:

```text
// a_test.dart
// [analyzer 1 see helper.dart] COMPILE_TIME_ERROR.A
```

```text
// b_test.dart
// [analyzer 1 see helper.dart] COMPILE_TIME_ERROR.B
```

```text
// helper.dart
// [context 1 for a_test.dart] Context for a_test.dart.
// [context 1 for b_test.dart] Context for b_test.dart.
```

The updater should choose numbers from scratch for selected root tests whenever it regenerates expectations. It does not need to preserve old numbers or avoid gaps. It only needs to avoid collisions among numbered primary errors in the same selected root file. In helper files, the `for` owner disambiguates otherwise identical numbers.

<a name="proposed-semantics"></a>
## Proposed Semantics

<a name="context-anchors"></a>
### Context Anchors

Parsing should separate context markers from the act of attaching them to primary diagnostics.

Instead of making `StaticError.parseExpectations()` immediately attach all contexts in one file, parsing should produce:

- primary errors,
- numbered primary error metadata,
- context anchors.

A context anchor is a `StaticError` with source `ErrorSource.context`, plus its number, containing file path, and optional owner path from a `for` clause. If the owner path is omitted, the owner is the context marker's own file. It can later be attached to a primary diagnostic only when the primary marker agrees with that ownership.

<a name="attaching-contexts"></a>
### Attaching Contexts

After the root file and relevant local files have been parsed, context attachment should happen across the whole expectation graph for that root test.

For a numbered primary error in file `P` with number `N`:

1. attach unqualified context anchors numbered `N` from `P`,
2. attach context anchors numbered `N` from every file in the primary error's `see` list when the context anchor's `for` path resolves to `P`,
3. preserve source order within each file, and preserve `see` list order across files for deterministic output.

If a primary error has context anchors in another file, the resulting expected `StaticError.contextMessages` contains context messages whose `path` is the other file.

Both directions should be validated. A helper context with `for main_test.dart` is not enough unless `main_test.dart` has a matching numbered primary marker whose `see` list contains the helper. A primary marker with `see helper.dart` is not enough unless `helper.dart` has matching context anchors whose `for` path points back to the primary file.

<a name="unconsumed-contexts"></a>
### Unconsumed Contexts

Shared helper files need to be able to contain context anchors for other root tests. Therefore, a context anchor whose `for` path points to a different root test should be inert for the current root test.

The stricter current behavior should remain for the current root test. An unconsumed unqualified `[context N]` in the root test file is likely a typo. An unconsumed `[context N for current_root.dart]` in a helper is also likely stale and should be removed by the updater or reported by validation.

For helper files, context anchors owned by other roots should be inert expectations. They are available to those roots when they explicitly name the helper with `see`, but they do not affect the current root test.

<a name="validation"></a>
### Validation

The current same-file format already validates that numbered markers line up. A `[context N]` marker must have a matching numbered primary error in the same parsed file. A numbered primary error such as `[analyzer N]` or `[cfe N]` must have at least one `[context N]`. Two primary errors in the same parsed file cannot claim the same number.

Cross-file contexts should keep that strictness for the current root, but use the bidirectional relationship:

- a primary marker `[analyzer N see helper.dart]` must find at least one `[context N for root_test.dart]` marker in `helper.dart`,
- a helper marker `[context N for root_test.dart]` must be matched by a numbered primary marker `N` in `root_test.dart` whose `see` list includes the helper file,
- a helper marker whose `for` path points to a different root is inert while validating the current root,
- a helper marker whose `for` path points to the current root but has no matching primary marker is a validation error for the current root,
- a primary marker whose `see` list names a helper but no matching context is found in that helper is a validation error.

This catches path typos, number mismatches, and stale helper markers without making shared-helper annotations leak into unrelated tests.

Validation should compare expected and actual context messages by:

- source `context`,
- message,
- path,
- line,
- column,
- length when present.

`StaticError.compareTo()`, equality, and `hashCode` should include `path`. Cross-file contexts make path part of the observable identity. Ignoring path can make two context messages in different files compare equal when they should not.

Once expected cross-file context messages can be represented, the analyzer adapter in `command_output.dart` can stop dropping analyzer context messages whose file differs from the primary diagnostic file.

<a name="updater-direction"></a>
## Updater Direction

<a name="rewrite-strategy"></a>
### Rewrite Strategy

The `for` back pointer gives the updater a safe per-root ownership rule. When updating `a_test.dart`, the updater may remove all existing helper context markers whose `for` path resolves to `a_test.dart`, regenerate expectations from actual diagnostics, and write fresh markers with fresh numbers. It must preserve helper context markers whose `for` path resolves to any other root.

This works with the current updater shape, which rewrites expectations one root test at a time:

1. collect actual diagnostics for the current root test,
2. remove primary markers in the root file for the selected sources,
3. remove helper context markers whose `for` owner is the current root,
4. preserve helper context markers whose `for` owner is any other root,
5. allocate fresh numbers for the current root,
6. write the root file and any touched helper files.

The updater can still collect frontend results for several roots before writing, as it does today for analyzer and CFE. The helper-side `for` owner is enough to make root-by-root rewrites safe.

<a name="ownership-of-existing-helper-markers"></a>
### Ownership Of Existing Helper Markers

An existing helper context marker is owned by the root named in its `for` clause.

For example:

```text
// a_test.dart
// [analyzer 7 see helper.dart] COMPILE_TIME_ERROR.X
```

owns:

```text
// helper.dart
// [context 7 for a_test.dart] Context message.
```

When updating only `a_test.dart`, the updater should remove and regenerate context anchors whose `for` path resolves to `a_test.dart`. It must preserve context anchors owned by unselected roots, even when those anchors use the same number.

If the updater finds a cross-file helper marker without a `for` clause, the safe behavior is to preserve it and report that the helper contains an unowned context marker. Same-file context markers do not need `for`, but helper markers that participate in cross-file expectations do.

<a name="dropping-contexts"></a>
### Dropping Contexts

When a frontend no longer reports a context message for a selected root test, the updater should drop that context because selected-root expectations are regenerated from actual diagnostics.

For same-file contexts, this is the current behavior.

For cross-file contexts, dropping a context means:

- remove the helper file from the primary marker's `see` list if no remaining expected context for that diagnostic comes from that helper,
- remove the helper's `[context N for root_test.dart]` marker when `root_test.dart` is selected for update,
- preserve the marker and warn if ownership is ambiguous.

This keeps the updater useful without making it destructive in shared helpers.

<a name="number-allocation"></a>
### Number Allocation

The updater should allocate fresh numbers for selected roots after it knows the actual diagnostics for those roots. It should not try to preserve existing numbers.

For each primary diagnostic that has context messages:

1. compute the set of files containing its context messages,
2. assign the next number for that selected root, starting from `1`,
3. write that number on the primary marker,
4. write the same number on all context anchors for that diagnostic.

This lets independent root tests share a helper without accidentally consuming each other's context anchors.

If several roots own context anchors in the same helper, each root may still start at `1` because the helper-side `for` owner disambiguates them. Preserved markers for other roots do not constrain the numbering for the root currently being updated.

<a name="migration-plan"></a>
## Migration Plan

1. Extend the marker parser to recognize `see` on numbered primary markers and `for` on context markers.
2. Split expectation parsing into primary errors and context anchors.
3. Add an attachment phase that resolves same-file context anchors and bidirectional `see`/`for` cross-file context anchors for one root test.
4. Keep current same-file behavior and tests passing.
5. Include `path` in `StaticError.compareTo()`, equality, and `hashCode`.
6. Change analyzer command output conversion to keep cross-file context messages instead of dropping them.
7. Add parser and validation tests for:
   - same-file contexts,
   - one cross-file context file,
   - multiple `see` files,
   - shared helper files with the same number and different `for` owners,
   - unconsumed helper contexts,
   - stale root-file contexts.
8. Change `updateErrorExpectations()` to understand context anchors, `see` lists, and helper-side `for` owners.
9. Change `update_static_error_tests.dart` to remove and rewrite helper context anchors by selected root owner, and allocate fresh numbers from actual diagnostics.
10. Add updater tests for shared helper preservation and context dropping.
11. Enable generated cross-file analyzer contexts under `--context`.
12. Consider enabling cross-file CFE contexts once the same updater path handles both analyzer and CFE diagnostics.

<a name="open-questions"></a>
## Open Questions

- Should same-file context markers be allowed to spell a redundant `for current_file.dart`, or should `for` be reserved for cross-file helper markers?
- Should unconsumed context anchors owned by the current root always be errors, given that the updater regenerates selected-root expectations from scratch?
- Should a context anchor in a helper be allowed to attach both to a local primary error in that helper and to remote primary errors that `see` the helper?
- Should `see` and `for` paths be limited to local file URIs, or should package URIs be allowed?
- How should dry-run output display multi-file rewrites so that it is clear which root test caused each helper edit?
- Should the updater ever delete orphaned helper context anchors automatically, or should that require a dedicated cleanup mode?

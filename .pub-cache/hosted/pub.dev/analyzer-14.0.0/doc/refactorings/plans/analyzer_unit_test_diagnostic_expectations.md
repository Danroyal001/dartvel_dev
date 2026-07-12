# Analyzer Unit Test Diagnostic Expectations

This document proposes an inline diagnostic expectation format for analyzer unit tests. The goal is to make parser and analyzer test expectations reviewable when diagnostic locations move, without losing the idiomatic `diag.foo` spelling used by analyzer tests today.

The short version is:

```text
var parseResult = parseStringWithExpectedDiagnostics(r'''
void f(int a, int b ;
//                  ^
// [diag.expectedToken] Expected to find ')'.
''');
```

For locations that are hard to draw with carets, the diagnostic line can specify the column and length explicitly:

```text
var parseResult = parseStringWithExpectedDiagnostics(r'''
void f(int a, int b ;
// [diag.expectedToken][column 20][length 1] Expected to find ')'.
''');
```

The same bracketed syntax can represent context messages:

```text
var x = 0;
//  ^
// [context previousX] Previous declaration.

var x = 1;
//  ^
// [diag.duplicateDefinition][context previousX] The name 'x' is already defined.
```

See also:

- `pkg/analyzer_testing/lib/src/analysis_rule/pub_package_resolution.dart`
- `pkg/_fe_analyzer_shared/lib/src/base/errors.dart`
- `pkg/_fe_analyzer_shared/lib/src/base/diagnostic_message.dart`
- `pkg/test_runner/lib/src/static_error.dart`
- `doc/refactorings/plans/static_error_cross_file_contexts.md`

## Table of Contents

- [Current Model](#current-model)
  - [Offset Expectations](#offset-expectations)
  - [Diagnostic And Context Types](#diagnostic-and-context-types)
  - [Static Error Test Markers](#static-error-test-markers)
- [Problems](#problems)
  - [Offsets Are Hard To Review](#offsets-are-hard-to-review)
  - [Capitalized Codes Are Not Analyzer-Test Idiom](#capitalized-codes-are-not-analyzer-test-idiom)
  - [Context Messages Need Ownership](#context-messages-need-ownership)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Format](#proposed-format)
  - [Primary Diagnostics](#primary-diagnostics)
  - [Caret Locations](#caret-locations)
  - [Column And Length Overrides](#column-and-length-overrides)
  - [Diagnostic Message Text](#diagnostic-message-text)
  - [Context Messages](#context-messages)
  - [Corrections](#corrections)
  - [Grammar](#grammar)
- [Proposed Semantics](#proposed-semantics)
  - [Keeping Expectation Lines](#keeping-expectation-lines)
  - [Location Resolution](#location-resolution)
  - [Context Attachment](#context-attachment)
  - [Files](#files)
  - [Context Checking Policy](#context-checking-policy)
  - [Validation](#validation)
- [Implementation Direction](#implementation-direction)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

<a name="offset-expectations"></a>
### Offset Expectations

Many analyzer tests currently express diagnostics as explicit offsets and lengths:

```text
parseResult.assertErrors([
  error(diag.expectedToken, 20, 1),
]);
```

This is compact, and the `diag.expectedToken` code name reads well in analyzer tests. But the source location is disconnected from the source text. When a large parser recovery change moves diagnostics from one token to another, a diff of raw offsets is difficult to review.

<a name="diagnostic-and-context-types"></a>
### Diagnostic And Context Types

The shared diagnostic model separates the primary diagnostic from its context messages:

```text
Diagnostic
  diagnosticCode
  problemMessage
    filePath
    offset
    length
    messageText
  correctionMessage
  contextMessages
    DiagnosticMessage*
      filePath
      offset
      length
      messageText
```

Analyzer test expectations mirror this shape with `ExpectedDiagnostic` and `ExpectedContextMessage`.

Context messages are not diagnostics on their own. They are related locations owned by a primary diagnostic. An expectation format should keep that relationship visible.

<a name="static-error-test-markers"></a>
### Static Error Test Markers

Language tests and the test runner already use inline static error markers:

```text
badExpression;
// ^^^^^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.SOME_CODE
// [cfe] CFE message.
```

The test runner also supports explicit locations:

```text
// [error column 17, length 3]
// [analyzer] COMPILE_TIME_ERROR.SOME_CODE
```

Analyzer unit tests can reuse the useful parts of this idea, but they do not need the `[analyzer]` frontend tag because the tests run only one analyzer expectation language.

<a name="problems"></a>
## Problems

<a name="offsets-are-hard-to-review"></a>
### Offsets Are Hard To Review

Offset-only expectations answer "what byte offset changed?" They do not answer "which source construct now owns the diagnostic?"

For parser recovery tests, the latter is what a reviewer needs. A caret marker beside the source makes a benign location shift visible as source context instead of arithmetic.

<a name="capitalized-codes-are-not-analyzer-test-idiom"></a>
### Capitalized Codes Are Not Analyzer-Test Idiom

Static error tests use capitalized frontend code names such as `SYNTACTIC_ERROR.EXPECTED_TOKEN`. Analyzer unit tests generally use imported diagnostic constants such as `diag.expectedToken`.

The inline format should preserve `diag.foo` because it matches existing test helpers and generated failure output.

<a name="context-messages-need-ownership"></a>
### Context Messages Need Ownership

A context message has its own location and text, but it is meaningful only as part of a primary diagnostic. Treating it as another top-level expected diagnostic would lose ordering and ownership information.

The expectation format should define context anchors near their source ranges and then let primary diagnostics reference those anchors explicitly.

<a name="design-goals"></a>
## Design Goals

- Make diagnostic locations reviewable in source diffs.
- Preserve the existing `diag.foo` analyzer-test spelling.
- Keep the common case short: one caret line and one diagnostic line.
- Allow `column` and `length` to be overridden independently.
- Represent context messages without making ordinary diagnostics noisy.
- Keep context messages attached to primary diagnostics in an explicit order.
- Keep expectation marker comments in the parsed source so diagnostic offsets, parsed AST text, and generated expectations all describe the same source text.
- Support an incremental migration; existing offset expectations remain valid.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign language-test static error expectations.
- Do not require analyzer tests to use `[analyzer]`, `[cfe]`, or capitalized frontend diagnostic names.
- Do not require every analyzer test to move to inline expectations at once.
- Do not solve cross-file static error test contexts; that is covered by `static_error_cross_file_contexts.md`.
- Do not require a string-to-`DiagnosticCode` registry. The inline parser can compare textual expectation codes with `DiagnosticCode.constantName`.

<a name="proposed-format"></a>
## Proposed Format

<a name="primary-diagnostics"></a>
### Primary Diagnostics

A primary diagnostic expectation is a line comment whose first bracket group is the analyzer diagnostic constant name:

```text
// [diag.expectedToken] Expected to find ')'.
```

Multiple diagnostics can share a location marker:

```text
var x;
//  ^
// [diag.missingIdentifier] Expected an identifier.
// [diag.expectedToken] Expected to find ';'.
```

The code inside the first bracket group is compared textually with `actual.diagnosticCode.constantName`.

<a name="caret-locations"></a>
### Caret Locations

A caret line gives the default location for the following diagnostic or context lines:

```text
void f(int a, int b ;
//                  ^
// [diag.expectedToken] Expected to find ')'.
```

The column is the one-based column of the first caret. The default length is the number of carets.

Caret lines are intentionally familiar from language static error tests, but the following diagnostic line uses analyzer unit-test spelling.

<a name="column-and-length-overrides"></a>
### Column And Length Overrides

`column` and `length` are independent bracket groups:

```text
// [diag.expectedToken][column 20][length 1] Expected to find ')'.
```

They can be used together or separately:

```text
//     ^^^
// [diag.someCode][length 1] Message.
```

```text
// [diag.someCode][column 12] Message.
```

Rules:

- If `column` is omitted, there must be a preceding caret location.
- If `column` is present, the line is the previous non-expectation source line. A future `[line N]` bracket could make the line explicit.
- If `length` is omitted and there is a caret location, the length is the number of carets.
- If `length` is omitted and there is no caret location, the length defaults to `1`.
- If a zero-width range is needed, write `[length 0]`.

<a name="diagnostic-message-text"></a>
### Diagnostic Message Text

Text after the bracket groups is the expected diagnostic message:

```text
// [diag.invalidAssignment] A value of type 'String' can't be assigned to a variable of type 'int'.
```

The message text is required and is checked exactly against `diagnostic.problemMessage.messageText(includeUrl: false)`. Requiring the message keeps inline expectations strict by default and catches changes in diagnostic arguments or wording, not just code and location changes.

If migration finds a case where exact message checking is genuinely too brittle, add an explicit escape hatch such as `[message unchecked]` or keep that test on the existing offset-based helper. Omitted message text should be a format error, not an implicit weak assertion.

<a name="context-messages"></a>
### Context Messages

A context message is declared with a named context anchor:

```text
var x = 0;
//  ^
// [context previousX] Previous declaration.
```

The primary diagnostic references one or more context anchors:

```text
var x = 1;
//  ^
// [diag.duplicateDefinition][context previousX] The name 'x' is already defined.
```

The order of `[context ...]` groups on the primary diagnostic line is the expected order of `Diagnostic.contextMessages`.

The context anchor has the same location syntax as a primary diagnostic:

```text
// [context previousX][column 5][length 1] Previous declaration.
```

Context message text is required and is checked exactly against `DiagnosticMessage.messageText(includeUrl: false)`. A context definition without trailing message text is a format error.

Context anchors are definitions. Context groups on primary diagnostic lines are references. This distinction is syntactic:

- a line whose first bracket group is `[context name]` defines a context,
- a `[context name]` group after `[diag.foo]` references a context.

<a name="corrections"></a>
### Corrections

Correction messages are not part of the common parser recovery case. The initial format can omit them.

If inline expectations are later used in tests that need corrections, add an explicit bracket:

```text
// [diag.someCode][correction Use 'final'.] Message.
```

This should map to `correctionContains`.

<a name="grammar"></a>
### Grammar

The proposed grammar is deliberately line-oriented.

```text
caret-line:
  line-comment spaces "^"+

primary-diagnostic-line:
  line-comment diagnostic-code location-group* context-ref* message-text

context-definition-line:
  line-comment context-definition location-group* message-text

diagnostic-code:
  "[" "diag." identifier "]"

context-definition:
  "[" "context" spaces context-id "]"

context-ref:
  "[" "context" spaces context-id "]"

location-group:
  "[" "column" spaces integer "]"
  "[" "length" spaces integer "]"

context-id:
  identifier

message-text:
  spaces text
```

Whitespace between bracket groups is optional:

```text
// [diag.expectedToken][column 20][length 1] Expected to find ')'.
// [diag.expectedToken] [column 20] [length 1] Expected to find ')'.
```

The parser should accept both forms.

<a name="proposed-semantics"></a>
## Proposed Semantics

<a name="keeping-expectation-lines"></a>
### Keeping Expectation Lines

Expectation marker comments should remain in the source that is scanned and parsed.

Keeping one source string avoids a second offset space. The inline expectation parser, the scanner, the parser, diagnostic assertions, and generated AST text all operate on the same content.

The marker comments can affect the parsed result slightly, primarily through offsets and comment tokens. That is acceptable for analyzer unit tests because the expected diagnostics and expected AST text are generated from the same marked source.

This also keeps the helper simple: it parses expectation comments as metadata, but passes the original marked source to `parseString`.

<a name="location-resolution"></a>
### Location Resolution

The inline expectation parser should process the marked source line by line and track the previous non-expectation source line.

A caret line records a pending location on the previous non-expectation source line. The pending location is available to following contiguous diagnostic and context definition lines.

If a diagnostic or context definition specifies `[column N]`, it uses column `N` on the previous non-expectation source line unless a future extension adds explicit `[line N]` support.

Offsets are computed against the marked source using its `LineInfo`.

<a name="context-attachment"></a>
### Context Attachment

Parsing should collect context definitions separately from primary diagnostic expectations. After all lines are parsed:

1. validate that each context id is unique in the source scope,
2. validate that every referenced context id exists,
3. attach referenced contexts to the primary diagnostic in reference order,
4. validate that no context definition is unreferenced.

This produces the same conceptual `ExpectedDiagnostic` as:

```text
error(
  diag.duplicateDefinition,
  offset,
  length,
  contextMessages: [
    message(testFile, contextOffset, contextLength),
  ],
)
```

but the source locations are visible in the test input.

<a name="files"></a>
### Files

For the first parser-test-oriented helper, all expectations are in one source string. Context messages therefore point into that same parsed source.

The inline parser should still avoid directly constructing `ExpectedContextMessage` too early. A small neutral model keeps the format usable from different test bases:

```text
InlineExpectedDiagnostic
  codeName
  offset
  length
  message
  correctionContains
  contextRefs

InlineExpectedContext
  id
  offset
  length
  message
```

The test base can lower this neutral model into `ExpectedDiagnostic` and `ExpectedContextMessage` using the file identity available in that test environment.

If a future multi-file analyzer test helper adopts this syntax, context ids should be scoped by the marked file that defines them, or explicitly qualified by a file alias. That is a separate extension from the single-source parser case.

<a name="context-checking-policy"></a>
### Context Checking Policy

For this inline helper, primary diagnostics should check context messages strictly:

- no `[context ...]` references means the expected context list is empty,
- one or more `[context ...]` references means the actual context list must have exactly those messages in that order.

This matches parser-style unit tests, where unexpected context messages should be visible. A more general resolution-test helper can add an option to preserve the existing nullable `contextMessages` behavior if broad migration requires it.

<a name="validation"></a>
### Validation

The format should fail fast for test-author mistakes:

- a diagnostic line without a caret and without `[column N]`,
- a context definition without a caret and without `[column N]`,
- duplicate context ids,
- a referenced context id that is not defined,
- an unreferenced context definition,
- a malformed bracket group,
- an unknown bracket group,
- a `[length N]` with a negative value,
- a `[column N]` with a value less than `1`,
- a primary diagnostic line without message text,
- a context definition line without message text,
- trailing text on a line that is neither a primary diagnostic nor a context definition.

Failure messages should include the line number in the marked source.

<a name="implementation-direction"></a>
## Implementation Direction

Add a small parser for annotated diagnostic source in analyzer test support. It should be independent from scanner/parser production code and from `pkg/test_runner`.

One possible API shape:

```text
final class ExpectedDiagnosticSource {
  final String markedSource;
  final List<InlineExpectedDiagnostic> diagnostics;
}

ExpectedDiagnosticSource parseExpectedDiagnosticSource(String markedSource);
```

Parser diagnostics tests can then use:

```text
ParseStringResult parseTestCodeWithDiagnostics(String content) {
  var expectedSource = parseExpectedDiagnosticSource(content);
  var result = parseString(
    content: expectedSource.markedSource,
    throwIfDiagnostics: false,
  );
  result.assertErrors(expectedSource.toExpectedDiagnostics());
  return result;
}
```

The helper should print accepted inline expectations when the actual diagnostics do not match. That keeps the new format self-updating in the same spirit as the existing `To accept the current state, expect:` output.

<a name="migration-plan"></a>
## Migration Plan

1. Add the inline diagnostic source parser and focused unit tests for its grammar.
2. Add a parser-test helper that parses marked source, runs `parseString`, and asserts diagnostics.
3. Convert a small number of parser recovery tests touched by scanner/parser diagnostic location churn.
4. Improve mismatch output to print inline caret expectations.
5. Convert larger generated partial-code recovery tests only after the helper is stable.
6. Leave existing offset-based expectations in place where they remain clearer or where migration would not improve reviewability.

<a name="open-questions"></a>
## Open Questions

- Should the first version support `[line N]`, or is "previous non-expectation source line" enough?
- Should context ids be required to be identifiers, or should quoted strings be allowed for generated tests?
- Should a primary diagnostic without `[context ...]` always assert no contexts, or should that be configurable per test base?
- Is an explicit `[message unchecked]` escape hatch worth adding, or should tests that do not want exact messages stay on offset-based expectations?
- Should the eventual updater preserve hand-written context ids or regenerate simple names?

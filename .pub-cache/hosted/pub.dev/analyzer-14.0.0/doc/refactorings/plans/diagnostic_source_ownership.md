# Diagnostic Source Ownership

This document describes a possible refactoring of analyzer diagnostics so that diagnostic production does not require a `Source` until a real source identity is available.

The short version is:

```text
LocatableDiagnostic = diagnostic code + arguments + context
LocatedDiagnostic   = LocatableDiagnostic + offset + length
Diagnostic          = LocatedDiagnostic + Source/display location
```

Scanner, parser, and string-based parsing utilities should produce `LocatedDiagnostic`s. They know where a problem is in the content being parsed, but they do not necessarily know the address by which that content can be imported, included, or displayed to clients.

`Diagnostic` should be created at the boundary where the client has a real `Source`, or where a result object already carries an analyzed file identity. This matches the direction in `source_identity.md`: a `Source` is source identity, not a generic bag of content, display names, and fake file paths.

See also:

- `doc/refactorings/plans/source_identity.md`
- https://github.com/dart-lang/sdk/issues/63277
- https://dart-review.googlesource.com/c/sdk/+/499780

## Table of Contents

- [Current Model](#current-model)
  - [Source](#current-source)
  - [Diagnostic Types](#current-diagnostic-types)
  - [DiagnosticReporter](#current-diagnostic-reporter)
  - [Scanner](#current-scanner)
  - [Parser](#current-parser)
  - [StringSource](#current-string-source)
  - [ParseStringResult](#current-parse-string-result)
  - [Per-File Results](#current-per-file-results)
- [Current Data Flow](#current-data-flow)
  - [parseString](#flow-parse-string)
  - [parseFile](#flow-parse-file)
  - [Analysis Driver Parsing](#flow-analysis-driver-parsing)
- [Problems](#problems)
  - [StringSource Is Not A Source](#string-source-is-not-a-source)
  - [String Parsing Cannot Own Source Identity](#string-parsing-cannot-own-source-identity)
  - [Scanner And Parser Should Not Need Source](#scanner-and-parser-should-not-need-source)
  - [Per-File Results Should Not Contain Other Primary Sources](#per-file-results-should-not-contain-other-primary-sources)
  - [DiagnosticReporter Mixes Two Jobs](#diagnostic-reporter-mixes-two-jobs)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Direction](#proposed-direction)
  - [Diagnostic Layers](#proposed-diagnostic-layers)
  - [Located Diagnostic Collection](#proposed-located-collection)
  - [Source Attachment](#proposed-source-attachment)
  - [Scanner](#proposed-scanner)
  - [Parser](#proposed-parser)
  - [ParseStringResult](#proposed-parse-string-result)
  - [parseFile](#proposed-parse-file)
  - [Per-File Results](#proposed-per-file-results)
  - [DiagnosticReporter](#proposed-diagnostic-reporter)
  - [Context Messages](#proposed-context-messages)
- [Compatibility](#compatibility)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

<a name="current-source"></a>
### Source

`Source` currently exposes:

- `uri`
- `fullName`
- `shortName`
- `contents`
- `exists()`
- `==` and `hashCode`

The source identity plan proposes shrinking this to:

```text
abstract interface class Source {
  Uri get uri;
}
```

Concrete sources would carry their own backing identity. For example, `FileSource` would carry a resource provider `File`, and `SummarySource` would carry summary identity. A source should be the identity of addressable source code, not the authority for reading the content snapshot that produced an analysis result.

<a name="current-diagnostic-types"></a>
### Diagnostic Types

The shared diagnostic model already has three useful layers.

`LocatableDiagnostic` is a diagnostic code whose template arguments have been supplied. It has no source location yet:

```text
code
arguments
contextMessages
```

It has `at`, `atOffset`, `atSourceRange`, and `atSourceSpan` methods that produce a `LocatedDiagnostic`.

`LocatedDiagnostic` is a locatable diagnostic with a primary location:

```text
locatableDiagnostic
offset
length
```

It still has no `Source`.

`Diagnostic` is the public source-attached diagnostic:

```text
diagnosticCode
source
problemMessage
contextMessages
correctionMessage
```

`Diagnostic.tmp` requires a `Source`. `Diagnostic.forValues` builds the primary `DiagnosticMessage` using `source.fullName` as its file path.

The `Diagnostic.source` documentation currently says that the source can be `null` if unknown, but the field is non-nullable and every constructor requires a `Source`. In practice, this means callers that do not have a real source create a fake one.

<a name="current-diagnostic-reporter"></a>
### DiagnosticReporter

`DiagnosticReporter` currently combines two responsibilities:

- location helpers such as `atNode`, `atToken`, `atOffset`, and `atSourceRange`,
- source attachment and listener delivery.

It owns a `Source`, creates a `Diagnostic.tmp`, and sends it to a `DiagnosticListener`.

There is also an extension method:

```text
DiagnosticReporter.report(LocatedDiagnostic)
```

This method converts a `LocatedDiagnostic` into a `Diagnostic` by attaching the reporter's source.

<a name="current-scanner"></a>
### Scanner

CL 499780 changed `Scanner` so that it no longer takes a `DiagnosticReporter`. It now takes:

```text
void Function(LocatedDiagnostic) reportError
```

This lets scanner clients ignore scanner diagnostics or collect them without constructing a `Source`. Existing source-owning callers can still pass `diagnosticReporter.report`.

This is the right direction: the scanner knows offsets and lengths in the scanned content, but it does not need a `Source`.

<a name="current-parser"></a>
### Parser

`Parser` still takes a `DiagnosticReporter`.

The parser wrapper passes `diagnosticReporter.source.uri` to `AstBuilder`, and the builder reports parser diagnostics through `FastaErrorReporter`, which can attach the reporter's source.

This means parser clients still need a `Source` even when they only have a string of Dart code.

<a name="current-string-source"></a>
### StringSource

`StringSource` extends `Source` and stores in-memory contents. If no URI is provided, it invents a URI for `/test.dart` or `C:\test.dart`. Its default `fullName` is also `/test.dart`.

`StringSource` equality compares contents and `fullName`, not URI or backing identity.

This is useful as a compatibility shim, but it is not a real source identity. An arbitrary string has no importable address, no stable file identity, and no authoritative current file contents outside itself.

<a name="current-parse-string-result"></a>
### ParseStringResult

`ParseStringResult` currently exposes:

```text
String get content;
List<Diagnostic> get errors;
LineInfo get lineInfo;
CompilationUnit get unit;
```

`parseString` creates a `StringSource`, creates a `DiagnosticReporter`, scans and parses with that reporter, and returns the collected `Diagnostic`s.

This makes a string parse result look as if its diagnostics are attached to a real source. They are actually attached to a fake `StringSource`.

<a name="current-per-file-results"></a>
### Per-File Results

`AnalysisResultWithDiagnostics` exposes:

```text
List<Diagnostic> get diagnostics;
```

`ParsedUnitResult` and `ResolvedUnitResult` implement this interface through file-based result objects. These result objects also expose file identity:

- `file`
- `path`
- `uri`
- `content`
- `lineInfo`

A per-file result therefore already has the source/file identity needed to attach primary diagnostics. Returning `Diagnostic` makes that attachment eager and lets callers observe `diagnostic.source`, but it also suggests that a single-file result might validly contain primary diagnostics for another source.

<a name="current-data-flow"></a>
## Current Data Flow

<a name="flow-parse-string"></a>
### parseString

Current flow:

```text
parseString(content, path?)
  source = StringSource(content, path ?? '')
  listener = RecordingDiagnosticListener()
  reporter = DiagnosticReporter(listener, source)

  scanner = Scanner(content, reporter.report)
  token = scanner.tokenize()

  parser = Parser(reporter, ...)
  unit = parser.parseCompilationUnit(token)

  return ParseStringResultImpl(
    content,
    unit,
    listener.diagnostics,
  )
```

The scanner side is already source-free. The parser side still forces a `DiagnosticReporter`, and the result still returns source-attached `Diagnostic`s.

<a name="flow-parse-file"></a>
### parseFile

`parseFile` reads file contents through the provided `ResourceProvider`, then calls `parseString` with the file path.

The function has a real file path and resource provider, but the current return type is still `ParseStringResult`. It does not expose a `FileResult` shape, and it inherits `parseString`'s `StringSource` behavior.

<a name="flow-analysis-driver-parsing"></a>
### Analysis Driver Parsing

Driver parsing starts from a `FileState`. That file state has:

- current content,
- line info,
- a resource provider file,
- a URI,
- analysis options,
- library/part classification.

This path has enough information to attach a real source identity at the driver boundary. Scanner and parser do not need to know that identity while producing offsets.

<a name="problems"></a>
## Problems

<a name="string-source-is-not-a-source"></a>
### StringSource Is Not A Source

In the source identity model, a `Source` is the identity by which source code can be referenced through URI resolution. A string literal passed to a parsing utility is not source code in that sense. It has no stable URI, no file-system location, and no package-graph identity.

The current fake `/test.dart` source gives callers a path-like value, but the value is not semantically true. It can leak into diagnostics, equality, display logic, tests, and client code.

<a name="string-parsing-cannot-own-source-identity"></a>
### String Parsing Cannot Own Source Identity

String parsing utilities know only:

- the content,
- offsets and lengths,
- line starts,
- the chosen feature set and language version.

They do not know whether the content came from a physical file, an overlay, an editor buffer, a generated string, a snippet, or a test fixture. They should therefore return diagnostics that are located within the content, not diagnostics attached to a made-up source.

If a caller has a real source identity, the caller can attach it.

<a name="scanner-and-parser-should-not-need-source"></a>
### Scanner And Parser Should Not Need Source

Scanner and parser diagnostics are naturally location-local. They are produced while processing one token stream and point into that token stream.

Requiring `Source` at this layer creates fake sources for content-only clients and makes the scanner/parser interface wider than necessary. CL 499780 already removed this requirement from `Scanner`; `Parser` should follow the same direction.

<a name="per-file-results-should-not-contain-other-primary-sources"></a>
### Per-File Results Should Not Contain Other Primary Sources

For a result that represents one analyzed file, every primary diagnostic location should be in that file's content. If a diagnostic's primary location is in another file, it belongs to that other file's result.

The current `List<Diagnostic>` type does not express that invariant. A `Diagnostic` carries its own `Source`, so the result type appears to permit a diagnostic against a different source.

Context messages are different. A primary diagnostic in one file can have context messages that point to declarations or related locations in other files. That does not make the primary diagnostic owned by those files.

<a name="diagnostic-reporter-mixes-two-jobs"></a>
### DiagnosticReporter Mixes Two Jobs

`LocatableDiagnostic` already has the important `atX` methods for producing `LocatedDiagnostic`s. That removes much of the need for `DiagnosticReporter` as a location helper API.

The remaining valuable job is source attachment and listener delivery:

```text
LocatedDiagnostic + Source -> Diagnostic -> DiagnosticListener
```

Keeping both jobs in one type encourages lower layers to accept a `DiagnosticReporter` when they only need a `LocatedDiagnostic` sink.

<a name="design-goals"></a>
## Design Goals

- Make `Diagnostic` mean "a located diagnostic attached to a real source identity."
- Let content-only utilities return `LocatedDiagnostic`s.
- Remove the need for `StringSource` from production parsing paths.
- Keep scanner and parser independent from `Source`.
- Make per-file result ownership explicit: primary diagnostics are located in the result content.
- Keep context messages available for cross-file explanatory locations.
- Keep migration incremental enough for public API compatibility.
- Reuse `LocatableDiagnostic.atX` instead of growing more reporter location helpers.
- Keep source attachment at narrow boundaries where the source identity is already known.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign diagnostic codes or message templates.
- Do not remove `Diagnostic` from public analyzer APIs in one step.
- Do not remove context messages that point to other files.
- Do not make parser clients invent a URI just to receive diagnostics.
- Do not make `Source` nullable inside `Diagnostic` as a substitute for fixing ownership. A source-free diagnostic is `LocatedDiagnostic`, not `Diagnostic(source: null)`.
- Do not change scanner/parser recovery behavior.

<a name="proposed-direction"></a>
## Proposed Direction

<a name="proposed-diagnostic-layers"></a>
### Diagnostic Layers

Use the three diagnostic layers according to what the producer actually knows.

Diagnostic code declarations produce `LocatableDiagnostic`s:

```text
diag.expectedToken.withArguments(token: ...)
```

Syntax and analysis code that knows the source range produces `LocatedDiagnostic`s:

```text
diag.expectedToken
  .withArguments(token: ...)
  .atOffset(offset: offset, length: length)
```

Only source-owning code produces `Diagnostic`s:

```text
sourceAttacher.attach(locatedDiagnostic)
```

The source-attaching boundary should be explicit and narrow.

<a name="proposed-located-collection"></a>
### Located Diagnostic Collection

Introduce or expose a small located-diagnostic listener/collector shape:

```text
abstract interface class LocatedDiagnosticListener {
  void onDiagnostic(LocatedDiagnostic diagnostic);
}

class RecordingLocatedDiagnosticListener
    implements LocatedDiagnosticListener {
  List<LocatedDiagnostic> get diagnostics;
}
```

A callback is enough for scanner/parser internals, but a named listener type is useful for utilities and tests.

If `LocatedDiagnostic` becomes part of public API, export it from `package:analyzer/diagnostic/diagnostic.dart` together with `LocatableDiagnostic`. Today that library exports only `Diagnostic` from the shared diagnostic model.

<a name="proposed-source-attachment"></a>
### Source Attachment

Source attachment should be a small adapter:

```text
Diagnostic attachDiagnostic({
  required Source source,
  required LocatedDiagnostic diagnostic,
})
```

The adapter formats arguments, creates context messages, builds `Diagnostic.tmp`, and sends the result to a `DiagnosticListener` if needed.

This can initially be implemented by `DiagnosticReporter.report`, but the interface seen by scanner/parser/string utilities should be only:

```text
void Function(LocatedDiagnostic)
```

or a `LocatedDiagnosticListener`.

<a name="proposed-scanner"></a>
### Scanner

Keep the CL 499780 scanner shape:

```text
Scanner(
  String contents,
  void Function(LocatedDiagnostic) reportError,
)
```

Source-owning callers pass an attaching adapter:

```text
Scanner(contents, diagnosticReporter.report)
```

Content-only callers pass a collector:

```text
var diagnostics = <LocatedDiagnostic>[];
Scanner(contents, diagnostics.add)
```

<a name="proposed-parser"></a>
### Parser

Change `Parser` so it accepts a located-diagnostic sink instead of a `DiagnosticReporter`.

The parser and `AstBuilder` may still need non-diagnostic origin information for parser state, debug checks, native-clause behavior, or `dart:`-library behavior. That information should be passed explicitly, for example:

```text
Parser(
  reportDiagnostic,
  featureSet: ...,
  languageVersion: ...,
  lineInfo: ...,
  fileUri: optionalUri,
)
```

The important point is that this URI is parser context, not a `Source`, and it does not imply that a public `Diagnostic` can be created.

If some parser logic only needs to know whether the current unit is a `dart:` library, pass that fact directly rather than requiring a full source object.

<a name="proposed-parse-string-result"></a>
### ParseStringResult

Change the content-only result shape to:

```text
abstract class ParseStringResult {
  String get content;
  List<LocatedDiagnostic> get diagnostics;
  LineInfo get lineInfo;
  CompilationUnit get unit;
}
```

This result says exactly what the utility knows: the diagnostics are located in the parsed content.

`throwIfDiagnostics` can still format messages using `lineInfo`:

```text
for diagnostic in result.diagnostics:
  location = lineInfo.getLocation(diagnostic.offset)
```

It does not need a `Source` to report line and column numbers for the parsed content.

<a name="proposed-parse-file"></a>
### parseFile

`parseFile` has two possible steady-state shapes.

One option is to keep returning `ParseStringResult`. In that case it should also return `LocatedDiagnostic`s, because its return type is the content-only shape and the caller can attach the file identity if desired.

Another option is to introduce a file-owning parse result:

```text
abstract class ParseFileResult implements FileResult {
  List<LocatedDiagnostic> get diagnostics;
  CompilationUnit get unit;
}
```

The first option is a smaller migration. The second option better communicates that `parseFile` has real file identity and should not be confused with `parseString`.

In either case, `parseFile` should not need `StringSource`.

<a name="proposed-per-file-results"></a>
### Per-File Results

Internally, per-file results should store primary diagnostics as `LocatedDiagnostic`s plus the result's file identity.

The public API can then choose the compatibility surface:

```text
List<LocatedDiagnostic> get diagnostics;
List<Diagnostic> get sourceDiagnostics; // compatibility or adapter view
```

or:

```text
List<Diagnostic> get diagnostics; // temporary public API
List<LocatedDiagnostic> get locatedDiagnostics; // new internal/public API
```

The final model should make the invariant clear:

```text
Every primary diagnostic in a FileResult is located in FileResult.content.
```

The file result itself owns the file/path/URI/source identity. The individual located diagnostics do not need to repeat it.

<a name="proposed-diagnostic-reporter"></a>
### DiagnosticReporter

Shrink `DiagnosticReporter` toward a source-attaching adapter.

In the long term, most call sites should create diagnostics in the literate style:

```text
diagnosticSink.report(
  diag.expectedNamedTypeExtends.at(superclass),
);
```

instead of:

```text
diagnosticReporter.atNode(
  superclass,
  diag.expectedNamedTypeExtends,
);
```

This keeps location selection at the call site and removes many convenience methods from the source-attaching object.

`DiagnosticReporter` can remain as a compatibility type while call sites move to a narrower sink interface. Its durable value is:

```text
Source + LocatedDiagnostic + DiagnosticListener
```

not:

```text
all possible ways to compute a diagnostic range
```

<a name="proposed-context-messages"></a>
### Context Messages

Primary diagnostic ownership and context message ownership should remain separate.

A `LocatedDiagnostic` has one primary offset and length in the current content. It can also carry context messages. Some context messages can refer to other files when the analyzer has that information, such as "where this other type is defined" or "previous declaration is here."

This does not violate the per-file primary diagnostic invariant. The per-file result owns the primary diagnostic. Context messages are explanatory related locations.

Longer term, context messages should also avoid depending on `Source.fullName` where possible. They should be produced from explicit display locations or file identity helpers, consistent with the source identity plan.

<a name="compatibility"></a>
## Compatibility

The largest compatibility issue is public API type changes.

`ParseStringResult.errors` currently has type `List<Diagnostic>`. Replacing it with `List<LocatedDiagnostic>` is a breaking change. A staged migration could be:

1. Add `ParseStringResult.diagnostics` as `List<LocatedDiagnostic>`.
2. Keep `errors` temporarily, attach a compatibility source only for this deprecated getter, and mark it deprecated.
3. Remove `errors` in a breaking release.

This still lets the implementation stop using `StringSource` on the primary path. The compatibility getter can be isolated and documented as legacy.

For file results, changing `AnalysisResultWithDiagnostics.diagnostics` from `List<Diagnostic>` to `List<LocatedDiagnostic>` is a much larger public break. It should happen only after internal code stores located diagnostics and after clients have an adapter path for source-attached diagnostics.

Possible compatibility APIs:

```text
List<LocatedDiagnostic> get locatedDiagnostics;
List<Diagnostic> get diagnostics; // deprecated source-attached view
```

or the reverse, depending on release constraints.

<a name="migration-plan"></a>
## Migration Plan

1. Export `LocatableDiagnostic` and `LocatedDiagnostic` from the public diagnostic library if they will appear in public result APIs.
2. Add a recording located-diagnostic collector for tests and parsing utilities.
3. Change `Parser`, `AstBuilder`, and `FastaErrorReporter` to report `LocatedDiagnostic`s without requiring `DiagnosticReporter`. Pass any needed parser origin information separately from source identity.
4. Change `parseString` to collect `LocatedDiagnostic`s directly. Remove `StringSource` from the normal `parseString` path.
5. Add `ParseStringResult.diagnostics` as `List<LocatedDiagnostic>`. Update `throwIfDiagnostics` to use this list and `LineInfo`.
6. Keep `ParseStringResult.errors` only as a deprecated compatibility getter, if public compatibility requires it. Isolate any fake-source attachment there rather than in scanner/parser.
7. Decide whether `parseFile` remains a content-only `ParseStringResult` or gets a file-owning result type. In both cases, avoid `StringSource`.
8. Convert analysis-driver parsing so scanner and parser produce located diagnostics, then attach the file source at the driver/result boundary.
9. Add internal per-file result storage for `LocatedDiagnostic`s. Keep the public `Diagnostic` view as an adapter while clients migrate.
10. Move analyzer diagnostics call sites toward `LocatableDiagnostic.atX` plus a narrow sink. Shrink `DiagnosticReporter` to source attachment and listener delivery.
11. Remove production uses of `StringSource`. If tests still benefit from an in-memory source helper, move it to test utilities and keep it out of the production source identity model.
12. After public API migration, remove `ParseStringResult.errors` and any compatibility fake-source attachment path.

<a name="open-questions"></a>
## Open Questions

- Should `parseFile` continue to return `ParseStringResult`, or should it have a file-owning result type?
- Should public per-file result APIs eventually expose only `LocatedDiagnostic`, or should they keep `Diagnostic` as a convenience view forever?
- What is the smallest parser context object that replaces `diagnosticReporter.source.uri` in `Parser` and `AstBuilder`?
- Should source attachment live in a renamed type, such as `DiagnosticSourceAttacher`, to avoid preserving the old `DiagnosticReporter` mental model?
- How should context messages represent cross-file locations after `Source.fullName` is removed?

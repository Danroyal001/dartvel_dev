# Source Identity Refactoring

This document explores a possible refactoring of analyzer `Source` objects. The goal is to make `Source` a small identity object instead of a mixed abstraction for URI resolution, files, display names, existence checks, and content reads.

The proposed direction is radical but intentionally narrow:

```text
abstract interface class Source {
  Uri get uri;
}
```

Concrete source implementations carry any additional data they need. For example, `FileSource` carries a `File`, and `SummarySource` carries summary metadata. Callers that need a file path or contents must first know that they have a file-backed source.

## Table of Contents

- [Current Model](#current-model)
- [Problems](#problems)
  - [Source Has Too Many Responsibilities](#source-has-too-many-responsibilities)
  - [Equality Is Not A Reliable Equivalence Relation](#equality-is-not-a-reliable-equivalence-relation)
  - [URI Identity Needs A Backing Identity](#uri-identity-needs-a-backing-identity)
  - [Content Reads Are Misleading](#content-reads-are-misleading)
  - [Full Name Is Not Always A File Path](#full-name-is-not-always-a-file-path)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Model](#proposed-model)
  - [Source](#source)
  - [Resolved Backing Identity](#resolved-backing-identity)
  - [FileSource](#filesource)
  - [SummarySource](#summarysource)
  - [Removed Source Types](#removed-source-types)
- [Source Resolution](#source-resolution)
- [Content And Existence](#content-and-existence)
- [Display Names And File Paths](#display-names-and-file-paths)
- [Equality](#equality)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

`Source` currently exposes:

- `uri`
- `fullName`
- `shortName`
- `contents`
- `exists()`
- `==` and `hashCode`

Analyzer has several production and test implementations:

- `FileSource`
- `BasicSource`
- `InSummarySource`
- `NonExistingSource`
- `StringSource`

The implementations do not model the same concept. Some are file-backed, some are summary placeholders, some are in-memory strings, and some are sentinels for missing data.

<a name="problems"></a>
## Problems

<a name="source-has-too-many-responsibilities"></a>
### Source Has Too Many Responsibilities

The current interface combines several different concepts:

- URI identity.
- File-system location.
- Human-readable display name.
- File existence.
- Content access.
- Timestamped content access.

These are not uniformly meaningful for all source kinds. A summary source has a URI but no physical file path. A string source has contents but is not part of the file system. A file source can read contents, but those contents might not be the contents used by the analysis result that holds the source.

<a name="equality-is-not-a-reliable-equivalence-relation"></a>
### Equality Is Not A Reliable Equivalence Relation

Current `Source` equality is implemented differently by each subtype. `FileSource` compares to another `FileSource` by a URI/path identifier, but compares to other `Source` implementations by URI. `BasicSource` compares by URI. `StringSource` compares by contents and `fullName`.

This makes `Source` unsafe as a semantic key. In particular, equality can be asymmetric or non-transitive when different source implementations share a URI but not the same backing data.

<a name="uri-identity-needs-a-backing-identity"></a>
### URI Identity Needs A Backing Identity

A URI alone is not enough to identify analyzer source code.

For example, `package:foo/foo.dart` depends on:

- the package config,
- workspace-specific URI rules,
- generated-file redirection rules,
- the selected SDK,
- summary data,
- resolver ordering.

The same URI can validly resolve to different code in different analysis contexts. Therefore `runtimeType + uri` is too weak as a general identity model.

The missing information is not the whole package configuration or resolver stack. For file-backed sources, the missing information is the resolved file. For summary-backed sources, it is the summary store or bundle that supplies the source.

<a name="content-reads-are-misleading"></a>
### Content Reads Are Misleading

`Source.contents` and `Source.exists()` read from the backing object, usually the file system. Analysis results, however, are produced from `FileState`, overlays, caches, and analysis-session state.

This means `result.unit.declaredFragment.source.contents` can return different text from the text that produced `result.unit`. The API looks convenient, but it exposes the wrong authority for analysis data.

<a name="full-name-is-not-always-a-file-path"></a>
### Full Name Is Not Always A File Path

Many call sites use `source.fullName` as a file path. This is valid for `FileSource`, but not for summary sources, where `fullName` is currently the URI string. This forces scattered special cases and makes path-sensitive code harder to audit.

<a name="design-goals"></a>
## Design Goals

- Make `Source` represent only analyzer source identity.
- Make file-specific operations explicit through `FileSource`.
- Make summary-specific operations explicit through `SummarySource`.
- Remove content and existence reads from `Source`.
- Remove display-name and file-path APIs from `Source`.
- Make equality stable and defensible for package-config-sensitive URIs.
- Base equality on concrete resolved backing identity, not on resolver machinery.
- Keep migration incremental enough to land in reviewable steps.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign `FileState` persistence or make analysis results fully persistent.
- Do not make public APIs expose analyzer-internal URI resolver objects.
- Do not preserve `Source.contents` as a compatibility shim indefinitely.
- Do not make fake missing sources part of the steady-state model.
- Do not require all URI resolution to eagerly produce a source.

<a name="proposed-model"></a>
## Proposed Model

<a name="source"></a>
### Source

`Source` becomes a small interface:

```text
abstract interface class Source {
  Uri get uri;
}
```

The interface intentionally does not expose:

- path,
- short name,
- display name,
- contents,
- timestamp,
- existence.

The public contract is that a `Source` has a URI and can be used in diagnostics and element metadata as the identity of the source reference.

<a name="resolved-backing-identity"></a>
### Resolved Backing Identity

Each concrete source subtype defines equality in terms of the backing identity that makes sense for that subtype.

For `FileSource`, the backing identity is the resolved file. This lets two analysis contexts agree that a shared pub-cache file is the same source when they resolve the same URI to the same file. It also prevents accidental equality when two package configurations resolve the same `package:` URI to different files.

For `SummarySource`, the backing identity is the summary store or bundle that supplies the source. Summary-backed code does not have a `File`, so it needs an explicit summary identity.

The important distinction is:

```text
Source equality uses resolved backing identity, not package configuration identity.
```

This avoids retaining resolver machinery in every source while still making package-config-sensitive URI equality safe.

<a name="filesource"></a>
### FileSource

`FileSource` represents a file-backed source:

```text
final class FileSource implements Source {
  @override
  final Uri uri;

  final File file;

  FileSource({
    required this.uri,
    required this.file,
  });
}
```

Callers that need a path use `source.file.path`. Callers that need to read the current file contents use `source.file.readAsStringSync()`, but only when they really want the current backing-file contents rather than the contents used by an analysis result.

<a name="summarysource"></a>
### SummarySource

`InSummarySource` should become `SummarySource`.

The motivation for the rename is symmetry with `FileSource`. `FileSource` is a source backed by a file; `SummarySource` is a source backed by summary data. The old name, `InSummarySource`, describes where the URI was found, but the new model is about the backing representation of each source subtype.

`SummarySource` also avoids implying that source text is literally stored "inside" the summary in a file-system-like way. The summary is the authority for analysis information, not a replacement source file. If this name turns out to be too broad during review, `SummaryBackedSource` is the more explicit fallback, but it is longer and less parallel with `FileSource`.

```text
final class SummarySource implements Source {
  @override
  final Uri uri;

  final Object summaryIdentity;

  final String? summaryPath;

  final SummarySourceKind kind;
}

enum SummarySourceKind {
  library,
  part,
}
```

`SummarySource` has no file path and no contents. It represents code whose analysis information is supplied by summaries.

`summaryIdentity` is intentionally a placeholder in this design. It might be a summary data store identity, a bundle identity, or another small stable object owned by the summary-loading layer. The requirement is that two summary sources with the same URI compare equal only when their source information comes from the same summary identity.

<a name="removed-source-types"></a>
### Removed Source Types

`BasicSource` should be removed. It encodes the problematic idea that a URI string can stand in for a full name or path.

`NonExistingSource` should be removed. Failure to resolve should be represented as `null` or as an explicit URI resolution failure, not as a fake source.

`StringSource` should be removed from production APIs. Parsing utilities and tests can pass content directly, or use test-only helpers that are not part of the production source model.

<a name="source-resolution"></a>
## Source Resolution

URI resolution does not need a wrapper hierarchy around `Source`.

If the meaningful success cases are `FileSource` and `SummarySource`, then the resolved object can be returned directly:

```text
Source? resolveAbsolute(Uri uri);
```

Callers that need to distinguish success kinds can switch on the source subtype:

```text
switch (sourceFactory.forUri2(uri)) {
  case FileSource(:var file):
    // File-backed source.
  case SummarySource():
    // Summary-backed source.
  case null:
    // Unresolved URI.
}
```

The distinction between "resolved to a file" and "resolved to a summary" belongs in the `Source` subtype itself, not in another result hierarchy.

Detailed failure reasons are not part of the core source identity model. Most callers only need to know that a URI did not resolve through the current source factory. If a diagnostic path needs to explain why resolution failed, that can be a separate diagnostic-oriented API rather than the default resolution result.

<a name="content-and-existence"></a>
## Content And Existence

Remove these APIs from `Source`:

```text
TimestampedData<String> get contents;
bool exists();
```

Preferred replacements:

- For analysis result contents, ask the analysis result/session API that owns the result.
- For current file-system contents, narrow to `FileSource` and read `file`.
- For existence during URI resolution, return `null` for unresolved URIs or check `FileSource.file.exists` explicitly.

This avoids implying that `Source` knows which content snapshot was analyzed.

<a name="display-names-and-file-paths"></a>
## Display Names And File Paths

Remove these APIs from `Source`:

```text
String get fullName;
String get shortName;
```

Preferred replacements:

```text
String? sourceFilePath(Source source) {
  return switch (source) {
    FileSource(:var file) => file.path,
    SummarySource() => null,
  };
}

String sourceDisplayName(Source source) {
  return switch (source) {
    FileSource(:var file) => file.path,
    SummarySource(:var uri) => uri.toString(),
  };
}
```

Path-sensitive code should use nullable file-path helpers or switch on `FileSource`. Diagnostic code should use display-name helpers.

<a name="equality"></a>
## Equality

Concrete sources should compare by:

```text
runtimeType
uri
resolved backing identity
```

For `FileSource`, the resolved backing identity is the file:

```text
@override
bool operator ==(Object other) {
  return other is FileSource &&
      other.uri == uri &&
      sameFileIdentity(other.file, file);
}

@override
int get hashCode => Object.hash(uri, fileIdentity(file));
```

The exact `fileIdentity` helper needs to match analyzer's file system model. A reasonable starting point is resource provider identity plus normalized path, unless `File` itself gets a reliable identity API.

For `SummarySource`, the resolved backing identity is the summary identity:

```text
@override
bool operator ==(Object other) {
  return other is SummarySource &&
      other.uri == uri &&
      identical(other.summaryIdentity, summaryIdentity);
}

@override
int get hashCode => Object.hash(uri, identityHashCode(summaryIdentity));
```

Including `uri` as well as the backing identity is intentional. The same file can be referenced by different URIs, and the source still records the URI from which it was derived. Including the backing identity prevents accidental equality between two package configurations that use the same URI text for different files.

If a source is used as a key in a context where object identity is desired, callers should use identity maps or a separate key type. `Source.==` should mean "same URI resolved to the same backing source", not "same Dart object".

<a name="migration-plan"></a>
## Migration Plan

1. Add internal helpers for file paths and display names.

   Start replacing `source.fullName` call sites with either file-path access or display-name access. This makes the intended operation explicit before changing the interface.

2. Stop using `Source.contents` internally.

   Replace content reads with analysis-session, `FileState`, or explicit `FileSource.file` access depending on the authority needed.

3. Stop using `Source.exists()` internally.

   Move existence checks into URI resolution or explicit `FileSource.file` checks.

4. Implement subtype-specific source equality.

   For `FileSource`, compare by URI and file identity. For `SummarySource`, compare by URI and summary identity. Add tests for same URI / same file, same URI / different file, same URI / same summary identity, and same URI / different summary identity.

5. Rename `InSummarySource` to `SummarySource`.

   Remove its dependency on `BasicSource`; implement `Source` directly.

6. Remove or quarantine fake source types.

   Delete `BasicSource` and `NonExistingSource` once call sites no longer need them. Move `StringSource` to test utilities or replace it with parse APIs that accept content directly.

7. Shrink the public `Source` interface.

   After internal and package-private usage is migrated, remove `fullName`, `shortName`, `contents`, and `exists()` from `Source`.

8. Audit source resolution call sites.

   Keep nullable resolution for ordinary lookup. Where a caller needs to distinguish file-backed and summary-backed sources, switch on the returned `Source` subtype. Add a richer diagnostic-only failure API only if a caller needs failure reasons.

<a name="open-questions"></a>
## Open Questions

- Should `Source.==` be part of the public semantic contract, or should public API recommend a separate key for maps and sets?
- What is the right `File` identity helper: resource provider identity plus normalized path, `File` equality, or a new file-system API?
- How should summary sources distinguish two summary stores that both contain the same URI?
- How much compatibility surface is needed for external analyzer clients that currently read `Source.fullName` from diagnostics?
- Should `Source` live in `_fe_analyzer_shared` if most of its concrete model is analyzer-specific?

# Search File Ownership And Search Partitioning

This document describes the current file ownership structures used by analyzer search, and a possible direction for using `OwnedFiles` as the long-lived source of search file partitioning.

The goal is to reduce repeated multi-driver bookkeeping in hierarchy and reference search without changing search semantics.

The proposed ownership identity is the resource provider `File`, not the library URI. A library URI is a name in a package graph; the same URI string can denote different files, and therefore different elements, in different package graphs. Search ownership should partition the actual resource files that produced the `FileState`s.

## Table of Contents

- [Current Model](#current-model)
  - [OwnedFiles](#current-owned-files)
  - [SearchedFiles](#current-searched-files)
  - [SearchEngineCache](#current-search-engine-cache)
  - [AnalysisDriverUnitIndex](#current-analysis-driver-unit-index)
  - [filesToCheck](#current-files-to-check)
  - [referencedNames](#current-referenced-names)
- [Current Data Flow](#current-data-flow)
  - [Reference Search](#flow-reference-search)
  - [Subtype Search](#flow-subtype-search)
  - [Workspace Declarations](#flow-workspace-declarations)
- [Problems](#problems)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Direction](#proposed-direction)
  - [OwnedFiles As The Authority](#proposed-owned-files-authority)
  - [Ownership Key](#proposed-ownership-key)
  - [Driver-Owned Files](#proposed-driver-owned-files)
  - [Typed Index Targets](#proposed-typed-index-targets)
  - [Subtype Identity](#proposed-subtype-identity)
  - [Library And Fragment References](#proposed-library-and-fragment-references)
  - [Subtype Search](#proposed-subtype-search)
  - [Reference Search](#proposed-reference-search)
  - [SearchedFiles](#proposed-searched-files)
- [Invalidation](#invalidation)
- [Migration Plan](#migration-plan)

<a name="current-model"></a>
## Current Model

Analyzer search has several related ownership and identity structures.

<a name="current-owned-files"></a>
### OwnedFiles

`OwnedFiles` is a long-lived object owned by `AnalysisContextCollectionImpl`. It is passed to each `AnalysisDriver` built by the collection.

Each driver reports newly known files through `_onNewFile`. The file is recorded as:

- added, if it is in the driver's added files,
- known, if it is available through dependencies.

The maps are keyed by file URI. Added files take precedence over known files. This already gives the collection a shared, persistent answer to "which driver owns this file for workspace-style operations?"

Today `OwnedFiles` is used by workspace declaration search. It is not used by reference search or subtype search.

The URI key is part of the current design, not a requirement. It is questionable for search partitioning because a `package:` URI is resolved relative to a package graph. Two drivers can have the same URI string for different package versions, and those files contain different elements. In that case URI ownership collapses two distinct resources.

<a name="current-searched-files"></a>
### SearchedFiles

`SearchedFiles` is a short-lived per-search object. It records path and URI owners while a search is running.

It has two roles:

- assign a file to at most one `Search` object across multiple drivers,
- prevent duplicate index reads and duplicate results inside one search.

For reference search, `SearchEngineImpl.searchReferences` creates one `SearchedFiles` object, pre-owns analyzed files, and then asks each driver to search. Each driver still computes its own candidate files, but final index work is guarded by `SearchedFiles.add`.

The path side is close to the desired resource identity, but it is just a string. The URI side is not a behavior we should preserve: if the index and ownership model are resource based, URI spelling should not participate in search result de-duplication.

<a name="current-search-engine-cache"></a>
### SearchEngineCache

`SearchEngineCache` is a per-hierarchy cache. It is supplied by callers that expect to make repeated subtype queries while building one hierarchy.

It stores:

- the list of drivers used by this hierarchy operation,
- a `SearchedFiles` object,
- `assignedFiles`, a map from driver to files assigned to that driver.

The cache is not global. It is typically created for one hierarchy computation or one all-subtypes traversal.

<a name="current-analysis-driver-unit-index"></a>
### AnalysisDriverUnitIndex

`AnalysisDriverUnitIndex` is the serialized search index for one resolved unit. It records references to elements by decomposing each target element into:

- the URI of the target element's library,
- the URI of the target element's declaring unit or part,
- the top-level name,
- the class member name,
- the named parameter name,
- the synthetic getter/setter kind.

Subtype entries use a similar URI-based string identity:

```text
libraryUri;declaringUnitUri;interfaceName
```

This is compact and works inside one package graph. It is not a complete cross-driver identity because the same `package:` URI string can resolve to different resource files in different package graphs.

The declaring unit URI is part of the current encoding, but it is not necessarily part of element identity. In the summary reference model, top-level declarations are identified by their enclosing library reference, kind, and internal key. How a declaration is distributed across library fragments is usually not visible to clients outside the library.

The index also records import, export, and part directive URI references in dedicated library-fragment-reference arrays. Import and export directives are semantically references to a library. Part directives are references to a source fragment/file inside the containing library.

<a name="current-files-to-check"></a>
### filesToCheck

`filesToCheck` is the analyzer-side parameter that receives `SearchEngineCache.assignedFiles[driver]`.

It is used only by `Search.subTypes`. It means "these are the files assigned to this driver for the current cached subtype search; filter only these files by `referencedNames`."

It does not mean that the files are already known to reference the type. It is only an ownership partition.

<a name="current-referenced-names"></a>
### referencedNames

`FileState.referencedNames` is computed from the parsed, unlinked unit. It is a cheap syntactic prefilter. Search uses it to find files that might reference one of a set of names, and then uses the index to check exact element relations.

This is independent from file ownership. Ownership chooses which driver checks a file. `referencedNames` chooses whether the file is a candidate for a specific element name.

<a name="current-data-flow"></a>
## Current Data Flow

<a name="flow-reference-search"></a>
### Reference Search

```text
SearchEngineImpl.searchReferences(element)
  drivers = _drivers.toList()
  searchedFiles = _createSearchedFiles(drivers)
    searchedFiles.ownAnalyzed(driver.search)

  for driver in drivers:
    driver.search.references(element, searchedFiles)
      _addResults(...)
        driver.getFilesReferencingNames(referenceNames)
          scan driver.knownFiles
          filter with FileState.referencedNames

        for candidate file:
          if searchedFiles.add(file.path, search):
            read index
            collect exact element relations
```

`SearchedFiles` prevents duplicate final work, but each driver may still scan an overlapping `knownFiles` set to build candidates.

<a name="flow-subtype-search"></a>
### Subtype Search

```text
SearchEngineImpl.searchSubtypes(type, SearchEngineCache)
  _searchDirectSubtypes(type, cache)
    drivers = cache.drivers ??= _drivers.toList()
    searchedFiles = cache.searchedFiles ??= _createSearchedFiles(drivers)

    if cache.assignedFiles == null:
      for driver in drivers:
        driver.discoverAvailableFiles()
        for file in driver.fsState.knownFiles:
          if searchedFiles.add(file.path, driver.search):
            cache.assignedFiles[driver].add(file)

    for driver in drivers:
      driver.search.subTypes(
        type,
        searchedFiles,
        filesToCheck: cache.assignedFiles[driver],
      )
```

Inside `Search.subTypes`, `_addResults` filters `filesToCheck` using `referencedNames`, then reads indexes only for the matching files.

This avoids each direct-subtype query scanning every driver's full `knownFiles` again. The benefit is limited to the lifetime of one `SearchEngineCache`.

<a name="flow-workspace-declarations"></a>
### Workspace Declarations

Workspace declaration search already uses `OwnedFiles`.

```text
AnalysisContextCollectionImpl.ownedFiles
  drivers update it as files become known

FindDeclarations
  consumes ownedFiles.addedFiles
  consumes ownedFiles.knownFiles
```

This is the existing example of a long-lived collection-level partition.

<a name="problems"></a>
## Problems

The same concept is represented multiple times:

- `OwnedFiles` is long-lived but used only by declaration search.
- `SearchedFiles` is short-lived and mixes ownership assignment with duplicate result prevention.
- `SearchEngineCache.assignedFiles` is a per-hierarchy partition.
- `filesToCheck` exposes the per-hierarchy partition through the analyzer search API.

This has a few costs:

- Hierarchy searches rebuild the same assigned file lists for each request.
- Reference searches can still scan overlapping `knownFiles` sets across drivers before `SearchedFiles` removes duplicate final work.
- The ownership policy is split between analyzer and analysis_server.
- Names like `filesToCheck` do not communicate that the list is an ownership partition, not a semantic candidate set.
- URI-based ownership is not precise enough for workspaces that contain different versions of the same package. The same named class with the same URI is not the same element if it was resolved from a different resource file. This is the failure mode in https://github.com/dart-lang/sdk/issues/62425.
- The unit index has the same URI identity issue. Even if candidate files are partitioned by resource file, searching an index by URI/name components can still match an element from a different package version.
- Subtype ids are URI-only strings, so hierarchy traversal can also merge different package versions that expose the same library and interface names.
- `FileState` is not a suitable ownership key today because its equality is URI-based.

<a name="design-goals"></a>
## Design Goals

- Have one authoritative long-lived ownership model for files known to a context collection.
- Use the resource provider `File` as the ownership identity. URI should be metadata, not the partition key.
- Make index matching use resource identity at the target's library/file boundary.
- Keep index target encoding typed by semantic identity shape instead of forcing libraries, fragments, declarations, members, and parameters through one nullable tuple.
- Preserve exact search semantics: `referencedNames` remains only a prefilter, and the index remains authoritative.
- Avoid duplicate candidate scans across drivers where practical.
- Keep search APIs clear about whether a file set is an ownership partition or a semantic candidate set.
- Remove per-search ownership bookkeeping when `OwnedFiles` can provide the same ownership answer.

<a name="non-goals"></a>
## Non-Goals

- Do not change language-level element identity or index relation semantics.
- Do not make `referencedNames` exact.
- Do not add another global cache or partition object.
- Do not make the search index a portable package summary format. It is driver-local analysis output and can use resource paths for identity.
- Do not split index targets by every Dart element class unless their identity or lookup behavior actually differs.

<a name="proposed-direction"></a>
## Proposed Direction

<a name="proposed-owned-files-authority"></a>
### OwnedFiles As The Authority

Make `OwnedFiles` the collection-level authority for search ownership.

Conceptually, `OwnedFiles` should answer:

```text
which driver owns this resource file?
which files are added vs only known?
which current files are assigned to this driver?
```

The existing maps contain an ownership partition, but the key should change from URI to resource file before search depends on it for correctness. `OwnedFiles` should remain in analyzer, owned by `AnalysisContextCollectionImpl`, and `Search` should reach it through the current `AnalysisDriver`. Added files should keep precedence over known files.

<a name="proposed-ownership-key"></a>
### Ownership Key

`OwnedFiles` should key ownership by `File` from the collection's `ResourceProvider`.

This is effectively path identity, but it is a better interface than passing raw paths around: it says that search is partitioning resource files, not library names. `OwnedFiles` should expose resource ownership, not URI metadata. Callers that need URI data can get it from `FileState`, sources, or URI resolution.

This distinction matters for multi-package-graph workspaces. A file from `analyzer` v9 and a file from `analyzer` v10 can both be named by the same `package:analyzer/...` URI string in their respective graphs. They are not the same library for element identity, and search must not assign one owner for both.

Today the physical, memory, and overlay resource implementations compare files by resource runtime type and path. That is acceptable if all keys in one `OwnedFiles` instance come from the same collection resource provider. The `OwnedFiles` API should document that invariant. If a future caller needs to mix providers in one ownership structure, the implementation should use an explicit `(ResourceProvider, path)` key instead of relying on `File` equality alone.

<a name="proposed-driver-owned-files"></a>
### Driver-Owned Files

`OwnedFiles` can provide helper APIs that iterate its owner maps and return current `FileState`s for one driver:

```text
Iterable<FileState> filesFor(AnalysisDriver driver)
```

The helper can filter `addedFiles` and `knownFiles` by owner driver, then ask that owner driver for the current `FileState` for each file. If a stale file entry does not currently resolve to a `FileState`, it can be skipped.

This keeps the ownership logic in `OwnedFiles` and avoids exposing its mutable maps as an API contract.

<a name="proposed-typed-index-targets"></a>
### Typed Index Targets

The search index does not have to squeeze every searchable target into one structure. The current `elementUnits + unitName + className + parameterName + syntheticKind` shape mixes several different identity domains and leaves the reader to interpret nullable fields.

A clearer model is to split targets by semantic identity shape:

```text
LibraryTarget
  library resource key

FragmentTarget
  fragment/file resource key

TopLevelTarget
  library target id
  top-level reference kind
  top-level reference key

MemberTarget
  container top-level target id
  member reference kind
  member reference key

ParameterTarget
  enclosing executable target id
  parameter reference key, or parameter name until parameters have reference keys
```

This split follows the summary `Reference` tree: typed parent plus key. It does not require a separate table for every Dart element class. Classes, enums, mixins, extensions, extension types, type aliases, top-level variables, functions, getters, and setters are all top-level targets. Constructors, fields, methods, getters, and setters declared inside a container are member targets. Parameters are separate because their identity is nested under an executable and their search behavior is different from ordinary members.

Relations can either share one relation table with a target kind and target id, or use separate relation arrays per target domain. The choice should be driven by lookup simplicity and encoded size. The important design point is that target identity remains typed instead of encoded as one broad nullable tuple.

This replaces the current `_ElementInfo.unitId` model, which points to a pair of URI strings: the target library URI and the declaring unit URI. The resource key should be the normalized path from the collection's `ResourceProvider`, or an explicit provider/path key if the implementation needs to mix providers. Target identity fields should store resource keys. URI strings are not target identity; keep them only as non-identity payload for a concrete index feature.

The reference key is an internal declaration identity component, not always the source name. Generated keys are used for unnamed declarations and duplicate source names. This makes index matching consistent with `OwnedFiles`: a reference resolved to `analyzer` v10 will not match a target element from `analyzer` v9 just because both target elements have the same `package:analyzer/...` URI and lookup name.

<a name="proposed-subtype-identity"></a>
### Subtype Identity

Subtype records should also stop using URI-only ids.

Current subtype ids have this shape:

```text
libraryUri;declaringUnitUri;interfaceName
```

The resource-based equivalent is:

```text
library file path;top-level kind;top-level reference key
```

`SubtypeResult` should carry the resource-based id used by hierarchy traversal and visited-subtype keys. Private-member filtering should also compare the defining library resource, not the library URI string.

<a name="proposed-library-and-fragment-references"></a>
### Library And Fragment References

Import and export directive URI references fit the same reference-shaped model as declarations. Their target is the imported or exported library, so the target identity should be the library resource key. The directive URI offset and length remain source-location data.

Part directives are different. A `part` directive targets a source fragment/file inside the containing library, not a library declaration. These references should use a fragment/file resource key rather than a declaration reference key.

This means the current `libFragmentRefTargets` table should conceptually split into:

- import/export references to a library resource,
- part references to a fragment/file resource.

`part of` references can also be represented as references to the containing library resource, although today that search path is handled by resolving and walking the AST.

<a name="proposed-subtype-search"></a>
### Subtype Search

Subtype search can use the shared `OwnedFiles` object from the current `AnalysisDriver` instead of `SearchEngineCache.assignedFiles`.

Current:

```text
SearchEngineCache.assignedFiles[driver] -> Search.subTypes(filesToCheck: ...)
```

Possible:

```text
Search.subTypes(type)
  files = driver.ownedFiles.filesFor(driver)
  filter files by referencedNames
  read indexes for matching files
```

`Search` already knows its `AnalysisDriver`, and the driver knows the shared `OwnedFiles` object. There is no need to pass an assigned file list through the search API. At that point `SearchEngineCache.assignedFiles` and the `filesToCheck` data flow can be removed.

<a name="proposed-reference-search"></a>
### Reference Search

Reference search can use the same driver-local ownership lookup as subtype search.

One possible shape:

```text
for driver in drivers:
  driver.search.references(element)
    files = driver.ownedFiles.filesFor(driver)
```

Then `_addResults` can filter assigned files by `referencedNames` instead of calling `driver.getFilesReferencingNames(referenceNames)`, which scans the driver's whole `knownFiles` set.

This would reduce duplicate prefilter scans across drivers. Normal reference search has fewer repeated subtype-style queries, but the ownership model is the same and does not require a separate staged mechanism.

<a name="proposed-searched-files"></a>
### SearchedFiles

`SearchedFiles` should disappear from the final design. Its useful current responsibility is choosing one driver for a file during a multi-driver search. Once `OwnedFiles` owns that partitioning as a long-lived resource-file map, search should not need a per-search owner assignment object.

If `OwnedFiles` provides the owner query, `SearchedFiles` can be removed from the multi-driver search path. Search methods can ask the current driver for the files it owns, and element-local searches can be routed to the owning driver instead of asking every driver and relying on `SearchedFiles.add` to reject duplicates.

The final invariant should be simple: `OwnedFiles` assigns each resource file to one driver, and search only asks that owner to search the file. Different URI spellings for the same resource do not need a separate de-duplication rule, and the same URI spelling for different resources must not collapse those resources.

<a name="invalidation"></a>
## Invalidation

`OwnedFiles` has the same lifetime as `AnalysisContextCollectionImpl`. When the collection is disposed, all of its drivers and the shared `OwnedFiles` object are discarded together.

Content changes do not invalidate ownership. They change `referencedNames` and index data, but those are read from current `FileState` and driver caches when search runs.

`AnalysisDriver.removeFile()` removes the path from the driver's added files, clears the driver's `FileSystemState`, and later discovery creates new `FileState`s. Each newly created `FileState` is reported back through `_onNewFile`, so ownership is recorded again by a live driver.

The caveat is that the current `OwnedFiles` maps are append-only. They record new ownership, but do not remove stale entries or downgrade an added file to a known file. That is acceptable if the public helper treats the maps as ownership hints and resolves each file through the current owner driver before returning a `FileState`.

With this model, `OwnedFiles` is the long-lived owner of the partitioning service, but each result is derived from current driver state.

<a name="migration-plan"></a>
## Migration Plan

This does not need to be staged through a new cache. A direct migration is possible:

1. Add owner-query APIs to `OwnedFiles`. These should return current files for a driver and use resource `File` identity for ownership.

2. Introduce typed target tables in `AnalysisDriverUnitIndex`. Store library, fragment, top-level declaration, member, and parameter targets according to their own identity shapes. Top-level and member targets should use resource identity at the library boundary plus reference key paths. Keep URI data only where it is still useful as metadata.

3. Change subtype ids to resource-based ids. Use library resource key plus top-level reference key in stored supertype ids, produced subtype ids, and visited-subtype keys. Use library resource identity for private-library comparisons.

4. Split library and fragment references. Import and export directive URI references should target a library resource. Part directive URI references should target a fragment/file resource.

5. Expose `OwnedFiles` from `AnalysisDriver` to `Search`. Single-driver search engines can use a small `OwnedFiles` with one owner, or fall back to driver-local search if no shared owner is available.

6. Convert subtype search to `OwnedFiles`. Remove `SearchEngineCache.assignedFiles`, remove `filesToCheck`, and remove the subtype need for `SearchEngineCache.searchedFiles`.

7. Convert other multi-driver search entry points to `OwnedFiles`. This includes member declarations, unresolved member references, normal element references, subtype-member discovery, and import/prefix/local searches that currently use `SearchedFiles`.

8. Remove `SearchedFiles` once all multi-driver search routing uses `OwnedFiles`.

# Specification vocabulary

One page of the words `NEW_SPEC.md` uses precisely, kept beside it so a
proposal written in prose stops drifting from the conventions the code
already follows. Nothing here is new: each entry records a rule that exists,
and names where it is stated normatively.

This is a crib, not a source of truth. Where it disagrees with the
specification, the specification wins and this file is wrong.

## Generation inputs are private and expression-bodied

An annotated declaration is an **input** to the generator, never the API.
Inputs are private and begin with `_`; application code references the
generated public name.

```dart
@DVPage()
Widget _usersPage(BuildContext context) => DVBox.list([DVText('Users')]);
```

`_usersPage` generates `UsersPage`, and pages, widgets and functions are
referenced through the generated `dartvel_client/dartvel_client.dart` barrel.
Until full body lowering is implemented, private `@DVPage`,
`@DVFunctionalWidget` and `@DVBackendFunction` inputs use expression bodies;
a public annotated functional widget input is a hard error. See *Models*.

## Models use the primary-constructor form

```dart
@DVModel()
class _User(
  final String name,
  @DVModel.sensitiveField() final String nationalId,
);
```

## Field metadata lives under `@DVModel`

Field-scoped annotations are named constructors on the model annotation, not
standalone annotations. `@DVModel.sensitiveField()`,
`@DVModel.searchableField()`, `@DVModel.featuredImage()`,
`@DVModel.pageTitle()`, `@DVModel.mainContent()`, `@DVModel.pageOrder(n)`,
`@DVModel.hideFromPage()`, `@DVModel.model3dField()`.

There is no `@DVFeaturedImage`, no `@DVHideFromPage`, and no `@DVStaticPaths`:
a route is derived from the model, never written out as a string in an
annotation, because a repeated route drifts the moment the page file moves.

## Namespaces, and the ones that do not exist

Runtime surfaces hang off `DV`; device and screen surfaces off `DV.Platform`.
A proxy reads `DV.X` or `DV.Platform.X` and nothing else.

| Write | Not |
|---|---|
| `DV.Auth.authorization` | `DV.Authorization` |
| `DV.Notifications.mail.send(...)` | `DV.Mail` |
| `DV.FileStorage` (alias `DV.BlobStorage`) | `DV.Storage` |
| `DV.Cache.revalidateTag(...)` | `DV.CacheInvalidation` |
| generated model sync, signals, queues | `DV.Realtime`, `DVRealtime` |
| `context.signal(...)`, `DV.global<T>(...)` | `DV.Signals`, `context.computed(...)`, `DVService` |

`DV.Storage` is the one entry in that column that does exist: it is a third
name for the storage `DV.FileStorage` names, deprecated, working until the next
minor removes it. Write the canonical name; the column says what not to write,
not what the runtime refuses.

A derived signal is the result of operating on signals — `price * quantity`
is already a signal — so there is no separate constructor for one.

## Status labels: two axes, both required

Every h1 section prints `Stability: X · Status: Y` and carries the same pair
in `docs/spec-status.json`. An h2 inherits its parent's unless it declares
its own.

- **Stability** — `Draft` (the shape may still move) or `Contract` (frozen;
  a breaking change takes the migration path, not a spec edit).
- **Status** — `Designed` (nothing shipped), `Partial` (some shipped; the
  entry must say what is absent), `Shipped` (implemented and tested).

`Partial` and `Shipped` must cite evidence that exists — a test file, a
source path, a command. `dart run tool/spec_status_check.dart` enforces all
of it, including that the printed labels match the index. See *Specification
Status*.

## Compatibility labels: what a target does with a capability

Used in every platform matrix, and distinct from the status labels above:
status is about the specification, compatibility is about one target.

`Supported` · `Supported with limitations` (footnoted with the limitation) ·
`Experimental` · `Unsupported`.

An unsupported capability degrades and reports; it does not throw. Per-target
build evidence lives in `docs/build-targets.md`, where "verified" means the
command was run and the artifact inspected.

## Diagnostic codes

`DV-<AREA>-<NNN>`, with a level: `debug`, `info`, `warning`, `error`. Areas
in use include `DV-KIOSK`, `DV-WINDOW`, `DV-SECRETS`, `DV-ELINUX`,
`DV-MEMORY` and `DV-3D`. A degradation table lists the code, the reason and
the level, and every enumerated degradation has a member in the matching
enum — the level is calibrated to whether the developer can act on it.

A level may be qualified by where it is reported — `build `error``,
`gate `error``, `doctor `warning`` — and the qualifier is prose, not part of
the level: the code is registered at the bare level and the qualifier says
which stage raises it. Every code in a table is registered in
`DVDiagnostics.all`, and a test compares the two in both directions.

## Commands

`dartvel test` runs the fast suites; the named ones are `e2e`, `golden`,
`native`, `accessibility` and `release`. `dartvel build` and `dartvel dev`
generate before they run, so `dartvel routes` is only needed to generate
without building.

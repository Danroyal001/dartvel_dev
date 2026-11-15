# Proposal: `dartvel flutter migrate`, `dartvel expo migrate`, `dartvel qt migrate`

> **Status:** proposal for review, 15 November 2026. Design only: no command
> code is in this change. Nothing here is built. The `docs/spec-status.json`
> entry in Part 10 goes in with the first command (`Draft` / `Partial`).
> Until then the feature is `Designed` only.

## Contents

1. Goal and non-goals
2. How this fits the commands that exist
3. CLI shape
4. One pipeline for all three sources
5. Reading each source
6. Mapping tables
7. `MIGRATION-REPORT.md`
8. How success is tested
9. Free or paid (open question)
10. Phased plan
11. The first command, closely enough to write failing tests
12. Open questions for the owner
13. Sources

---

## 1. Goal and non-goals

The owner's requirement: turn an existing Flutter, Expo (React Native) or Qt
(QML + C++) app into a Dartvel project, "1:1 or closest with notes for the
gaps".

Goals:

- **The source is never changed.** Each command reads one folder and writes a
  new project in another. Nothing is written, generated or installed in the
  source folder. That includes `.dart_tool/`, `pubspec.lock` and
  `node_modules/`.
- **Every thing the reader finds gets one of three outcomes:**
  - **1:1:** converted, and it behaves the same.
  - **Closest:** converted to the nearest Dartvel form, with a note saying
    what differs.
  - **Gap:** not converted. The report gives the file, the line and a
    suggested fix.
- **The output is a real Dartvel project.** It analyzes with no errors, and
  `dartvel build web` finishes. Gaps are written as code that compiles and
  points at the report. They are never left as broken code.
- **The report is honest.** It gives a measured conversion percentage. It also
  counts the code the reader did not recognise, so a high number cannot hide
  code that was never looked at.

Non-goals:

- Converting arbitrary business logic perfectly. JavaScript, TypeScript and
  C++ logic is translated only where the translation is mechanical (Phase 5).
  The rest is a gap with the original code carried next to it.
- Keeping the source framework running inside the output. That is what
  `dartvel init` (adoption, in place) and the `--brownfield` path are for.
- Any network access at migrate time. The commands download nothing.

## 2. How this fits the commands that exist

| Command | What it does | How migrate relates |
|---|---|---|
| `dartvel init` (`AdoptCommand`) | Adds Dartvel to an existing Flutter project **in place**: the dependency and the `dartvel:` key, nothing else. It mounts Dartvel pages into the app's own router (`adoption/host_router.dart`). | The gentle path. `flutter migrate` is the full rewrite into a new folder. The report names `init` as the alternative whenever the app's router is one `init` can mount into. |
| `dartvel inspect adoption` | Counts what in a project is Dartvel-managed and what is not, and says how it counted. | Migrate uses the same honesty rule: "0 unmanaged" must never just mean "nothing recognised". After migrating, `inspect adoption` on the output should agree with the report. |
| `dartvel migrate-code` | Rewrites **deprecated Dartvel names** in a Dartvel project. Dry run unless `--apply`. | A different job: it migrates within Dartvel, not into it. The name stays. The new commands go under each source's name, so the two cannot be confused. |
| `dartvel import openapi\|postman` | Turns an external description into Dartvel source. Shares one base class (`DVImportSubcommand`) for reading, writing and the overwrite rule. | The model for the CLI shape: a parent command with one subcommand per kind, `--dry-run`, and one shared write rule. |
| `dartvel doctor` / build conventions check (`analysis/conventions_check.dart`) | Reports `DV-CONV-0xx` findings, for example DV-CONV-003 (a Flutter widget where `DVBox`/`DVText` exists), DV-CONV-004 (string routes), DV-CONV-009 (platform channels) and DV-CONV-012 (StatelessWidget/StatefulWidget/builders). | Migrate runs this check on its output and puts what is left in the report. The conventions check is the measure of how Dartvel-shaped the output is. |
| `dartvel i18n extract\|check` | Catalogues in `lib/l10n/app_<locale>.arb`, typed `DVTranslationKey`s. | Flutter's `gen-l10n` uses the same ARB files and folder, so Flutter catalogues copy across as they are. Expo and Qt catalogues are converted into the same files. |

## 3. CLI shape

Three parent commands, each with a `migrate` subcommand. This is the shape the
owner named. It also leaves room for later subcommands per source (for
example `dartvel flutter inspect`). `import` and `i18n` already use the
parent/subcommand pattern.

```text
dartvel flutter migrate <source> <destination> [options]
dartvel expo    migrate <source> <destination> [options]
dartvel qt      migrate <source> <destination> [options]
```

Options, the same for all three:

| Option | Meaning |
|---|---|
| `--dry-run` | Read the source and print the report to standard output. Write nothing. Same word as `import` and `init`. |
| `--name <package>` | The Dart package name of the new project. Default: the source's name, made a valid Dart identifier. |
| `--json` | Also write `migration-report.json` (the same items, for tools and CI). |
| `--no-verify` | Skip the analyze and build check at the end. The report then says "not verified". |
| `--fail-under <percent>` | Exit 1 when the measured conversion is below this number. For CI. |

Rules:

- `<destination>` must not exist, or must be an empty folder. Otherwise the
  command refuses and writes nothing. There is no `--overwrite`: a migration
  that writes over an earlier one would destroy hand fixes made since.
- `<destination>` must not be inside `<source>`, and `<source>` must not be
  inside `<destination>`.
- Exit codes: `0` when the project was written and verified, `1` when the
  command refused or the output failed verification (the project and report
  are still written, and the report says what failed), `64` for a usage error.
  This matches `migrate-code` (1 for a refusal) and `import` (64 for usage).
- Each source checks that it is that kind of project before anything else:
  - `flutter`: a `pubspec.yaml` that depends on the Flutter SDK.
  - `expo`: a `package.json` that depends on `expo` or `react-native`.
  - `qt`: a `CMakeLists.txt` that calls `find_package(Qt6 ...)` or
    `qt_add_qml_module`, or a `.pro` file.
  - A wrong kind is refused with a message naming the right command.

## 4. One pipeline for all three sources

```text
source folder ──read──▶ items (IR) ──plan──▶ files ──write──▶ new project
                                                              │
                                     verify (routes, analyze, build web)
                                                              │
                                                 MIGRATION-REPORT.md
```

1. **Read.** A source-specific reader turns the app into a list of
   **migration items**. Each item has: a source location (`path:line`), a
   category (route, state, widget, network, native, asset, i18n, test, build,
   logic), what it is, and the lines it covers. The reader also records which
   lines it covered. Everything else counts as unrecognised.
2. **Plan.** Mapping rules (Part 6) give each item an outcome (1:1, closest,
   gap), a note, a suggested fix and the output it produces. This step is pure:
   it does no I/O, so it can be tested on items alone.
3. **Write.** The new project starts from the same scaffold `dartvel create`
   writes. The planned files go on top of it. Native folders are not written:
   in Dartvel the build generates them. Native settings the source had
   (permissions, bundle ids) go into `pubspec.yaml` `dartvel:` keys where a
   key exists, and into the report where none does.
4. **Verify.** In the new project, run `dartvel routes`, then `dart analyze`,
   then `dartvel build web`. Each result goes into the report.
5. **Report.** Write `MIGRATION-REPORT.md` (Part 7) at the root of the new
   project.

The IR, the planner, the writer, the verifier and the report are shared.
Only the readers and the mapping rules differ per source. This is the same
split `DVImportSubcommand` uses: one copy of the write rule, so only one
place can get it wrong.

Proposed layout in `packages/dartvel_cli/lib/src/migrate/`:

```text
migrate/
  migration_item.dart      # the IR: DVMigrationItem, DVMigrationOutcome
  migration_plan.dart      # outcomes -> files
  project_writer.dart      # refuses a non-empty destination, writes the scaffold + files
  verify.dart              # routes, analyze, build web
  report.dart              # MIGRATION-REPORT.md and migration-report.json
  flutter/                 # reader + rules
  expo/
  qt/
```

## 5. Reading each source

### 5.1 Flutter: `package:analyzer`

- `package:analyzer` is already a dependency of `dartvel_cli` (`^14.7.0`), and
  the syntax check uses it. The reader walks the **AST**: no regexes. The
  earlier unmerged attempt was regex-based and missed nested and computed
  routes. That is the main reason it is not reused.
- **Resolution without touching the source.** Types are needed to tell a
  `Provider<CartModel>` from any other `Provider`, or a go_router `GoRoute`
  from a class of the same name. Resolving needs the packages, and running
  `flutter pub get` in the source would write `.dart_tool/` and
  `pubspec.lock` there. So the reader copies the source (without `build/`,
  `.dart_tool/` or native build output) into a temporary folder, resolves
  there with `AnalysisContextCollection`, and deletes the copy afterwards.
- **No network, no resolution.** If packages cannot be resolved (offline, or
  no pub cache), the reader falls back to the unresolved AST (`parseString`).
  It matches by import URI and name instead. The report then says, at the
  top, that types were not resolved, and every item matched that way is
  marked as such.
- **API stability.** The `analyzer` package page says its API has no clear
  line between public and internal and will break. So all analyzer use stays
  behind one visitor layer in `migrate/flutter/`, and the version stays
  pinned to the CLI's own range.

### 5.2 Expo / React Native: a Rust parser carried in the CLI

The One Language Rule says the repository is Dart. Rust is the one other
language, but `CLAUDE.md` limits it to two uses:

- a package's native library under `packages/<name>/rust/`;
- ports of the Dart SDK and Flutter under `rust/`, where the Dart still
  decides ("Rust may make an answer faster, never different").

No Python, no Node script.

**This choice needs the owner's decision (open question 3).** A TS/JS parser
is neither a port nor a package library, and it would have no Dart fallback.
So it is outside the rule as written. The proposal recommends it anyway, for
the reasons below. If the owner says no, `expo migrate` and the JS parts of
`qt migrate` need one of the alternatives in the table.

Recommended: **`oxc_parser`** (Rust) in a small helper program,
`rust/dartvel_jsparse`, in the existing Cargo workspace. It parses `.js`,
`.jsx`, `.ts` and `.tsx` and passes all Test262 parser tests and 99% of
Babel's and TypeScript's ([oxc parser docs](https://oxc.rs/docs/guide/usage/parser.html)).
Its AST is ESTree for JS and TS-ESTree for TypeScript, and "any deviation
would be considered a bug" ([oxc_parser_napi README](https://docs.rs/crate/oxc_parser_napi/0.96.0/source/README.md)).
Those formats are documented, so the Dart side can model only the node types
it needs.

How it ships: exactly as `dartvel_syntax` does today (see `rust/README.md`,
"How it ships"). It is built into the release executable, written to
`~/.dartvel/native/` on first use, and checked against a SHA-256 compiled
into the CLI before every run. Protocol: file paths on standard input; on
standard output, a greeting line with a protocol version, then one JSON AST
per file. A parser panic is caught per file, and that file becomes an
"unreadable" item in the report.

Without the helper (a `dart pub global activate` or pub.dev install, which
carries no Rust): there is no Dart fallback, unlike the syntax check. A
TypeScript parser in Dart is too large to write and keep correct. So
`expo migrate` refuses, and says to use the release binary or set
`DARTVEL_JSPARSE=<path>` to a helper built with `cargo build --release`.
This is open question 3.

Alternatives considered:

| Option | Why not |
|---|---|
| The TypeScript compiler API through Node, from the app's own `node_modules` | Needs a JavaScript file in this repository (breaks the One Language Rule) and an installed `node_modules`. |
| A TS/JSX parser written in Dart | A very large grammar to match exactly. No maintained Dart package does it. |
| tree-sitter | Gives a concrete syntax tree, not an AST. Its TS/TSX grammars would need their own conformance testing. A C library over FFI. |

What else the Expo reader reads:

- `package.json`, to know what the app depends on.
- `app.json`, or `app.config.js`/`.ts` when it exports a plain object
  literal. A config computed at run time becomes a note.
- `tsconfig.json` `paths` and Babel `module-resolver` aliases, so imports
  resolve to files.
- The `app/` folder tree for Expo Router.

### 5.3 Qt: QML, CMake, qmake, `.qrc`, `.ts`, C++ headers

- **QML documents:** a Dart parser for the QML document grammar:
  - pragmas, imports and object declarations;
  - `property`, `signal`, `function` and `enum` declarations;
  - bindings and inline components.

  Expressions and function bodies inside QML are JavaScript. They are passed
  to the same `dartvel_jsparse` helper as Expo code, so one JS→Dart
  expression translator serves both. This proposal does not rely on Qt's own
  tools being installed on the machine.
- **CMake:** the CMake language is a list of command calls. The reader parses
  it into calls and evaluates only literal arguments and simple `set()`
  variables. It reads:
  - `qt_add_executable`;
  - `qt_add_qml_module` (its `URI`, `QML_FILES`, `SOURCES` and resources,
    see [Qt docs](https://doc.qt.io/qt-6/qt-add-qml-module.html));
  - `qt_add_translations`.

  Conditions and generator expressions become notes.
- **qmake:** `.pro` files are `VAR = / += / -= values` with scopes. The reader
  takes `QT`, `SOURCES`, `HEADERS`, `RESOURCES` and `TRANSLATIONS`. qmake still
  has a manual in the Qt 6 docs ([qmake manual](https://doc.qt.io/qt-6/qmake-manual.html)).
- **`.qrc` and `.ts`** are XML. This needs a small XML reader. Proposal: add
  the pure-Dart `xml` package to `dartvel_cli`.
- **C++:** a narrow scanner over headers, on masked source (comments and
  strings removed, the way `conventions_check.dart`'s lexer does it). It finds
  `Q_OBJECT`, `QML_ELEMENT`/`QML_NAMED_ELEMENT`/`QML_SINGLETON`,
  `Q_PROPERTY(...)`, `signals:`, slots and `Q_INVOKABLE`. These are the parts
  QML can see ([Qt docs](https://doc.qt.io/qt-6/qtqml-cppintegration-definetypes.html)).
  There is no C++ semantic analysis. libclang was considered: it is large, tied
  to a version, and needs `compile_commands.json`.

## 6. Mapping tables

Key: **1:1** means converted with the same behaviour. **Closest** means
converted, with a note. **Gap** means not converted: the report entry gives a
suggested fix, and the output carries a stub that compiles.

Output conventions in every table (from `CLAUDE.md` and `NEW_SPEC.md`):

- Pages are private `@DVPage` functions under `lib/pages/`.
- Routes are typed: `DVRoutes.*`, with `DV.Navigation.to/navigate/push/back`
  and `DVNavLink`.
- State is `context.signal(...)`, derived signals through operators, and
  `DV.global<T>(...)` registered from an `@DVBoot` function.
- UI is `DVBox`/`DVText`/`DVModifier` and `@DVFunctionalWidget`.
- Every hoverable control has a tooltip.
- Assets are generated `DVAsset.*` members, never path strings.
- Native code is reached through FFI/ffigen or JNI/jnigen, never platform
  channels.

### 6.1 Flutter → Dartvel

**Routing** ([Flutter navigation docs](https://docs.flutter.dev/ui/navigation), [go_router](https://pub.dev/packages/go_router))

| Source | Dartvel | Outcome |
|---|---|---|
| `MaterialApp(routes: {'/settings': (_) => SettingsScreen()})` | `lib/pages/settings.dart` with `@DVPage` | 1:1 |
| `'/'` / `initialRoute` | `lib/pages/index.dart`, or a root `_guard.dart` redirect when `initialRoute` is not `/` | 1:1 |
| `Navigator.pushNamed(context, '/settings')` | `DV.Navigation.push(DVRoutes.settings)` | 1:1 |
| `onGenerateRoute` with a `switch` on literal `settings.name` values | one page per case | Closest: arguments taken from `settings.arguments` need a note |
| `Navigator.push(MaterialPageRoute(builder: (_) => Detail(id: id)))`, arguments are `String`/`int`/`enum` | page `detail/[id].dart`, call becomes `DV.Navigation.push(DVRoutes.detail(id: id))` | 1:1 |
| The same push with an object argument (`Detail(item: item)`) | The screen stays a widget and the push is kept | Gap: "an object cannot be part of a URL; pass its id and load it in the page". Flutter's docs say pageless routes are not deep-linkable. |
| go_router `GoRoute(path: 'users/:id')`, nested routes | `lib/pages/users/[id].dart`, reads `context.dvParams['id']` | 1:1. Dartvel's router runs on go_router (`NEW_SPEC.md`, Routing engine). |
| `context.go('/users/${user.id}')`, a literal or template string matching a route | `DV.Navigation.to(DVRoutes.…(id: user.id))` | 1:1 |
| `context.go(path)` with a computed string | kept as written, `go_router` stays a dependency | Gap: DV-CONV-004 says where |
| `ShellRoute` | `_layout.dart` in a route group folder | Closest |
| `StatefulShellRoute` (tabs with their own stacks) | `_layout.dart` extending `DartvelTabsLayout` (`NEW_SPEC.md`, "Tabs: a stack per tab") | 1:1 |
| `redirect:` on the router or a route | `_guard.dart` in the matching folder (root for the router-level redirect) | Closest: a guard covers a folder, not one route |
| go_router typed routes (`go_router_builder`) | `DVRoutes` | 1:1 |
| `auto_route` `@RoutePage` + router config | pages | 1:1 for paths. Guards are closest. |
| Navigator 2.0 with a hand-written `RouterDelegate` | not converted | Gap: names the delegate and suggests `dartvel init` with `dartvelNavigator2_0Routes` |
| A router package in `dvUnsupportedRouters` (beamer, routemaster, fluro, get…) | not converted | Gap: one item per route found |
| `showDialog`, `showModalBottomSheet` | kept | 1:1 (not routes) |

**State** ([Flutter state options](https://docs.flutter.dev/data-and-backend/state-mgmt/options), [Riverpod providers](https://riverpod.dev/docs/concepts2/providers), [Riverpod 3.0 migration](https://riverpod.dev/docs/3.0_migration), [Bloc concepts](https://bloclibrary.dev/bloc-concepts/))

| Source | Dartvel | Outcome |
|---|---|---|
| `StatefulWidget` whose fields change only inside `setState`, with no other lifecycle methods | `@DVFunctionalWidget` (or `@DVPage`) with one `context.signal` per field. `setState(() => n++)` becomes `n.value++`. | 1:1 |
| The same with `initState`/`dispose`/controllers/`TickerProvider` | kept as a `StatefulWidget` | Closest: DV-CONV-012 is reported, and the note suggests `DVClassWidget` |
| `ValueNotifier<T>` + `ValueListenableBuilder` | `DVSignal<T>`, read `.value` in build | 1:1 |
| `ChangeNotifier` + `ChangeNotifierProvider` at the root, `context.watch<T>()` / `Provider.of<T>` | `DV.global<T>(...)` in an `@DVBoot` function. Fields that call `notifyListeners` become `DVSignal` fields. Reads become `context.global<T>()` plus `.value`. | Closest: `context.global` rebuilds when the object is *replaced*, so field changes must go through signals. The note says so. |
| Riverpod `NotifierProvider` / `@riverpod` class | an object in `DV.global` holding signals, with the notifier's methods | Closest |
| Riverpod `Provider` whose body only combines other providers with operators | a derived signal (`a + b`, `price * quantity`) | 1:1 |
| Riverpod `FutureProvider`/`AsyncNotifierProvider` | not converted | Gap: suggests page data with `.loading.dart`/`.error.dart` siblings |
| Riverpod legacy `StateProvider`/`StateNotifierProvider` (behind `legacy.dart` since 3.0) | a signal / a `DV.global` object | Closest |
| `Cubit` with `emit` | an object with a signal and the cubit's methods | Closest |
| `Bloc` with `on<Event>` handlers | not converted | Gap: lists each event and state, and suggests one method per event |
| GetX, MobX, Redux | not converted | Gap |

**Widgets** (Phase 2. Phase 1 keeps widget bodies as they are.)

| Source | Dartvel | Outcome |
|---|---|---|
| `StatelessWidget` | private `@DVFunctionalWidget` function. Constructor fields become parameters. | 1:1 |
| `Text('x', style: …)` | `DVText('x')` + `.modifier(...)` for the style members `DVModifier` has | 1:1 for the text. Closest when some style fields have no modifier. |
| `Column`/`Row`/`Wrap`/`GridView` | `DVBox.list`/`DVBox.row`/`DVBox.wrapLine`/`DVBox.grid` | 1:1 |
| `ListView.builder` | `DVBox.scrollableList` (lazy by default in Dartvel) | Closest |
| `Container`/`Padding`/`SizedBox`/`DecoratedBox` | `DVBox` + `.padding .margin .width .height .backgroundColor .border .rounded .shadow` | 1:1 for these fields. Closest otherwise. |
| `GestureDetector`/`InkWell` `onTap` | `.onTap(...)` + `.tooltip(...)` taken from the child's text or `Semantics` label | 1:1 with a name. Gap without one: the build fails on an unnamed control. |
| `IconButton(tooltip: 'Close')` | `DVBox(Icon(...))` + `.tooltip('Close').minimumTapTarget(width: 48, height: 48).onTap(...)` | 1:1 with a tooltip. Gap without one. |
| `Scaffold` + `AppBar(title:)` on a screen | `@DVPage(title: ..., showAppBar: true)` | Closest |
| Material inputs with no Dartvel primitive (`TextField`, `Slider`, `Checkbox`, `DropdownButton`…) | kept | Closest: each is listed under "missing primitives", so the framework gets the primitive (owner rule: fix the framework, not the app) |
| `CustomPainter`, slivers, animations | kept | Closest |

**Network, native, assets, i18n, tests**

| Source | Dartvel | Outcome |
|---|---|---|
| `http`/`dio` calls | not rewritten. Grouped by host and path as `@DVBackendFunction` candidates, typed from the request and response types the analyzer sees. | Gap with a suggestion. `dartvel import openapi` is suggested when the API has a spec. |
| `MethodChannel`/`EventChannel`/`BasicMessageChannel` | not converted. The report lists channel names, method names and the Kotlin/Swift files handling them. | Gap: suggests jnigen for Kotlin/Java and ffigen with a C shim for Swift/Obj-C, behind `DV.Platform.*`. Flutter itself now recommends FFIgen/JNIgen/Pigeon for new projects ([platform channels](https://docs.flutter.dev/platform-integration/platform-channels)). |
| Pigeon definitions | a typed Dart interface stub | Closest |
| Plugins from pub | kept as dependencies and listed | 1:1. Where Dartvel has its own API, the report names it only after that is checked in code. |
| `flutter: assets:` / `fonts:` | copied. String asset paths become `DVAsset.*`. | 1:1 |
| `lib/l10n/*.arb` + `l10n.yaml` ([Flutter i18n](https://docs.flutter.dev/ui/internationalization)) | same files, same folder. `AppLocalizations.of(context)!.key` becomes `DV.I18n.t(...)` with a `DVTranslationKey`. | 1:1 for files. Calls are 1:1 (Phase 2). |
| Native folder edits (manifest permissions, Info.plist keys) | `pubspec.yaml` `dartvel:` keys where they exist | Closest, or Gap |
| `test/` widget and unit tests | copied. Imports are rewritten. | Closest: tests that pump a screen which became a page are flagged |
| `build_runner` generators (freezed, json_serializable) | kept as a dependency | Closest: notes that Dartvel data models generate serialisation |

### 6.2 Expo / React Native → Dartvel

Expo Router's file notation is close to Dartvel's pages. Both have `index`,
`[param]`, `(group)` and `_layout` ([Expo Router notation](https://docs.expo.dev/router/basics/notation/)).
`create-expo-app` sets up Expo Router by default ([Expo Router introduction](https://docs.expo.dev/router/introduction/)).

**Routing**

| Source | Dartvel | Outcome |
|---|---|---|
| `app/index.tsx`, `app/settings.tsx`, `app/profile/index.tsx` | `lib/pages/index.dart`, `settings.dart`, `profile/index.dart` | 1:1 |
| `app/[id].tsx` + `useLocalSearchParams()` ([URL parameters](https://docs.expo.dev/router/reference/url-parameters/)) | `[id].dart` + `context.dvParams['id']` | 1:1 |
| `app/(tabs)/…` route groups | `lib/pages/(tabs)/…` | 1:1 |
| `_layout.tsx` with `<Tabs>` | `_layout.dart` extending `DartvelTabsLayout` | Closest: tab bar styling is noted |
| `_layout.tsx` with `<Stack>` | `_layout.dart` | Closest |
| `[...rest].tsx` catch-all (array parameter) | a catch-all page, if the generator has one | To check in Phase 3. Gap if not, and then a framework item. |
| `+not-found.tsx` | Dartvel's not-found page | Closest |
| `+html.tsx` | not converted | Gap: Dartvel owns the document (one render path). Head content goes to SEO settings. |
| `+api.ts` with `GET`/`POST` exports ([API routes](https://docs.expo.dev/router/web/api-routes/), labelled beta; native deployment labelled alpha) | `lib/backend/functions/<name>.<method>.dart` with `@DVBackendFunction` | Closest: `Request`/`Response` becomes typed arguments and return values, and the note lists the fields used |
| `<Link href="/settings">`, `router.push('/settings')` | `DVNavLink(to: DVRoutes.settings, ...)`, `DV.Navigation.push(DVRoutes.settings)` | 1:1 |
| `` router.push(`/users/${id}`) `` or `{ pathname, params }` | `DVRoutes.users(id: id)` | 1:1 |
| A computed href | kept as a string in a stub | Gap |
| React Navigation without Expo Router (`createNativeStackNavigator`) | one page per screen. The path comes from the `linking` config when there is one, otherwise from the screen name. | Closest |
| React Server Components ([Expo docs](https://docs.expo.dev/guides/server-components/): experimental, beta) | not converted | Gap |

**State** ([useState](https://react.dev/reference/react/useState), [createSlice](https://redux.js.org/toolkit/api/createSlice), [Zustand create](https://zustand.docs.pmnd.rs/reference/apis/create))

| Source | Dartvel | Outcome |
|---|---|---|
| `const [n, setN] = useState(0)` in a function component | `final DVSignal<int> n = context.signal(0)`. `setN(x)` becomes `n.value = x`, and `setN(v => v + 1)` becomes `n.update((v) => v + 1)`. | 1:1 |
| `useMemo` whose body uses operators only | derived signal | 1:1. Other bodies are computed in build (closest). |
| `useReducer` | a signal + one method per action | Closest |
| `useEffect` on mount | `@DVBoot`, page data or a lifecycle listener, by what it does | Closest. Effects with dependencies become signal listeners, closest with a note. |
| `createContext` + Provider + `useContext` | `DV.global<T>` | Closest |
| Redux Toolkit `createSlice` | a `DV.global` object: state fields become signals, reducers become methods. Immer-style "mutations" map directly to signal writes. | Closest |
| `useSelector`/`useDispatch` | reads of the global's signals / method calls | Closest |
| Zustand `create((set, get) => ...)` | a `DV.global` object with signals and the store's methods. `useStore(s => s.x)` becomes a read of `x.value`. | Closest, 1:1 for plain `set({...})` stores |
| TanStack Query, RTK Query, MobX, Jotai, Recoil | not converted | Gap |

**Components** ([React Native core components](https://reactnative.dev/docs/components-and-apis), [flexbox](https://reactnative.dev/docs/flexbox))

| Source | Dartvel | Outcome |
|---|---|---|
| `View` | `DVBox` / `DVBox.list` / `DVBox.row` from `flexDirection` | Closest: React Native's flex defaults differ from the web (`flexDirection: column`, `flexShrink: 0`, `alignContent: flex-start`). The converter applies them, so layout matches, and the note records it. |
| `Text`, nested `Text` | `DVText` / rich text | 1:1 / Closest |
| `Image source={require('./a.png')}` / `{uri}` | image from `DVAsset.*` / network image | 1:1 |
| `Pressable`, `Touchable*`, `Button title` | `.onTap(...)` with `.tooltip(...)` from `accessibilityLabel` or the text | 1:1 with a name. Gap without one. |
| `ScrollView` | `DVBox.list([...]).scrollable()` | 1:1 |
| `FlatList`, `SectionList` | `DVBox.scrollableList` | Closest: `onEndReached` and `keyExtractor` are noted |
| `TextInput`, `Switch`, `Modal`, `ActivityIndicator` | Flutter widget | Closest: listed under "missing primitives" |
| `StyleSheet.create({...})` | top-level `DVModifier` constants | 1:1 for props with a modifier (padding, margin, backgroundColor, borderRadius → `rounded`, border, width, height, opacity, color). Closest otherwise. |
| `position: 'absolute'`, percentage sizes | Stack / fractional sizing | Closest |
| `Platform.OS` / `Platform.select` | `DV.Platform` checks | Closest |
| `className` styling (NativeWind and similar) | not converted | Gap |

**Network, native, assets, i18n, tests, logic**

| Source | Dartvel | Outcome |
|---|---|---|
| `fetch`, `axios` | `@DVBackendFunction` candidates, typed from TypeScript types where present | Gap with a suggestion |
| Expo SDK modules (`expo-camera`, `expo-location`…) | `DV.Platform.*` where the API exists, from a mapping table checked against code | Closest, or Gap |
| Custom Expo Modules (Swift/Kotlin, [Expo Modules API](https://docs.expo.dev/modules/overview/)) | not converted | Gap: jnigen for Kotlin, ffigen + C shim for Swift |
| Turbo Native Module specs (`interface Spec extends TurboModule`, [RN docs](https://reactnative.dev/docs/turbo-native-modules-introduction)) | typed Dart signatures as stubs from the TypeScript spec | Closest |
| `app.json` permissions, plugins, bundle ids | `pubspec.yaml` `dartvel:` keys | Closest, or Gap |
| images, `expo-font` fonts | `pubspec.yaml` assets/fonts + `DVAsset` | 1:1 |
| i18n-js / i18next JSON catalogues ([Expo localization](https://docs.expo.dev/guides/localization/)) | `lib/l10n/app_<locale>.arb` + `DVTranslationKey`. `t('key')` becomes `DV.I18n.t(...)`. | 1:1 for flat strings. Closest for plurals (`DVPluralForms`) and interpolation. |
| Lingui catalogues | ARB | Closest |
| Jest + React Native Testing Library ([Expo unit testing](https://docs.expo.dev/develop/unit-testing/)) | one Dart test file per test file, with the test names and the assertions to port | Gap (Phase 5: `getByText` / `fireEvent.press` become finders, closest) |
| TypeScript `interface`/`type` for plain data | Dart class with a primary constructor. A union of string literals becomes an `enum`. | Closest |
| Other TS/JS logic | translated where mechanical (Phase 5). Otherwise a stub, with the source carried in a comment. | Closest, or Gap |

### 6.3 Qt (QML + C++) → Dartvel

**Navigation** ([StackView](https://doc.qt.io/qt-6/qml-qtquick-controls-stackview.html))

| Source | Dartvel | Outcome |
|---|---|---|
| `StackView` with `initialItem` and `push(Component or "Page.qml")` | one page per pushed item. `initialItem` becomes `index.dart`. | Closest: pages get paths derived from file names |
| `push` / `pop` | `DV.Navigation.push(DVRoutes.…)` / `DV.Navigation.back()` | 1:1 |
| `replace` | `DV.Navigation.to(...)` | Closest |
| `TabBar` + `SwipeView`/`StackLayout` | `_layout.dart` extending `DartvelTabsLayout` | Closest |
| `Loader { source: cond ? "A.qml" : "B.qml" }` | a conditional in build | Closest |
| `ApplicationWindow` | the app's root layout and title | Closest |
| `Drawer`, `Popup`, `Dialog` | kept as overlays (Flutter) | Closest |

**State** ([property binding](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html), [signals](https://doc.qt.io/qt-6/qtqml-syntax-signals.html))

| Source | Dartvel | Outcome |
|---|---|---|
| `property int count: 0` | `context.signal(0)` | 1:1 |
| Binding `text: "Count " + count` | a derived signal, or reading `.value` in build. Both re-run when a source changes, as a QML binding does. | 1:1 |
| A JS assignment that breaks a binding (`x = 5` on a bound property) | an explicit write | Closest: a note says the binding was dropped there, as in QML |
| `signal clicked()` on a component, `onClicked:` at the use site | a callback parameter on the functional widget | 1:1 |
| `onCountChanged:` | a listener on the signal | Closest |
| `Connections { target: … }` | a listener | Closest |
| C++ `Q_PROPERTY(... NOTIFY ...)` on a `QML_ELEMENT`/singleton class | a `DV.global` object with one `DVSignal` per property and one method per `Q_INVOKABLE` | Closest for the shape. The C++ bodies are a gap (below). |
| `QAbstractListModel` subclasses | not converted | Gap: suggests a data model or a list signal |

**Elements**

| Source | Dartvel | Outcome |
|---|---|---|
| `Item` | `DVBox` | 1:1 |
| `Rectangle { color; radius; border }` | `DVBox` + `.backgroundColor .rounded .border` | 1:1 |
| `Text` | `DVText` | 1:1 |
| `Image { source: "qrc:/img/a.png" }` | `DVAsset.*` | 1:1 |
| `Column`/`Row`/`Grid`/`Flow` with `spacing` | `DVBox.list`/`row`/`grid`/`wrapLine` | 1:1 |
| `ColumnLayout`/`RowLayout`, `Layout.fillWidth` | `DVBox.list`/`row` + `.fill()` | Closest |
| `anchors.fill: parent`, `anchors.centerIn: parent` | fill / centre alignment | Closest |
| Other anchor graphs, absolute `x`/`y` | Stack/positioned | Closest, or Gap when the anchors form a graph |
| `MouseArea`/`TapHandler` `onClicked` | `.onTap(...)` + `.tooltip(...)` from `Accessible.name` or `ToolTip.text` | 1:1 with a name. Gap without one. |
| `Button { text }` | `DVBox(DVText(text))` + `.onTap` | 1:1 |
| `TextField`, `Slider`, `CheckBox`, `Switch`, `ComboBox` | Flutter widget | Closest: listed under "missing primitives" |
| `ListView { model; delegate }`, `Repeater` | `DVBox.scrollableList`, a collection `for` | Closest, 1:1 |
| `states`, `transitions`, `Behavior`, `NumberAnimation` | modifier animations where simple | Closest, or Gap |
| `Canvas`, `ShaderEffect`, Qt Quick 3D | not converted | Gap |

**Network, native, build, assets, i18n, tests**

| Source | Dartvel | Outcome |
|---|---|---|
| `XMLHttpRequest` in QML, `QNetworkAccessManager` in C++ | `@DVBackendFunction` candidates | Gap with a suggestion |
| C++ logic with no Qt types in its interface | kept as a native library, with an `extern "C"` shim bound through ffigen | Closest |
| C++ logic that needs QtCore (event loop, `QObject` trees) | not converted | Gap: a manual rewrite in Dart is suggested, and the report lists each class and method |
| `qt_add_qml_module` `QML_FILES`, `qmldir` modules | component folders in `lib/components/<module>/` | 1:1 |
| `.qrc` files, `RESOURCES` | `pubspec.yaml` assets + `DVAsset` | 1:1 |
| `qsTr("Back")` and `.ts` files ([Qt i18n](https://doc.qt.io/qt-6/qtquick-internationalization.html)) | `DVTranslationKey` + `lib/l10n/app_<locale>.arb` | 1:1 for plain strings. Closest for `%1` arguments and numerus forms (`DVPluralForms`). |
| gettext `.po` (KDE apps use `po/`) | ARB | Closest |
| Qt Quick Test `TestCase` with `test_` functions ([Qt Quick Test](https://doc.qt.io/qt-6/qtquicktest-index.html)) and Qt Test C++ | test skeletons with names and assertions to port | Gap |
| JS functions inside QML | the shared JS→Dart translator | Closest, or Gap |

## 7. `MIGRATION-REPORT.md`

Written at the root of the new project. Items are sorted by category, then
path, then line, so the same input always gives a byte-identical report.

```markdown
# Migration report

Source: ../shop_flutter (Flutter, 48 Dart files, 6,212 lines)
Command: dartvel flutter migrate ../shop_flutter ./shop_dv   (dartvel_cli 3.47.x)
Types: resolved            # or "NOT resolved: matched by import and name"

## Result

| | Items | Share |
|---|---|---|
| 1:1 | 41 | 63% |
| Closest (converted, with a note) | 14 | 22% |
| Gap (not converted) | 10 | 15% |
| **Converted (1:1 + closest)** | **55 of 65** | **85%** |

Source lines inside converted items: 4,102 of 6,212 (66%).
Source lines no rule recognised: 1,180 (19%). Listed under "Unrecognised".

Verification: `dartvel routes` ok · `dart analyze` 0 errors, 3 warnings · `dartvel build web` ok
Conventions left (dartvel doctor): DV-CONV-003 x 37, DV-CONV-012 x 4

## Gaps

| # | Where | Category | What | Suggested fix |
|---|---|---|---|---|
| G1 | lib/main.dart:88 | route | `context.go(path)` with a computed path | Build the path from a `DVRoutes` member; see the routes listed in "Routes". |
| G2 | lib/screens/cart.dart:14 | state | `CartBloc`: 4 events, 3 states | One method per event on a `DV.global<Cart>`; events: AddItem, RemoveItem, ... |
| G3 | lib/api/client.dart:31 | network | `http.post('https://api.shop.test/orders')` | Backend function candidate `orders.post`: `Future<Order> _createOrder(OrderDraft draft)` |

## Closest (converted, with a note)

| # | Where | Category | Became | Note |
|---|---|---|---|---|

## 1:1

| # | Where | Category | Became |
|---|---|---|---|

## Missing primitives
Flutter widgets kept because Dartvel has no primitive yet: TextField x 6, Slider x 1.

## Unrecognised
Files and line ranges no rule read, largest first.

## Next steps
Generated from the gaps, in order: routes, state, then everything else.
```

Every item carries a stable id (`G1`, `C3`, `S12`). Stubs in the output point
at it: `throw UnimplementedError('MIGRATION-REPORT.md G2')`, with a comment
above holding the original source. So `grep G2` finds both ends.

**How the percentage is measured:**

- An **item** is one thing a reader recognised:
  - a route, a navigation call or a state holder;
  - a widget class, a network call or a channel;
  - an asset group, a catalogue, a test file or a build entry.
- **Converted %** = (1:1 + closest) / all items. **Strict %** = 1:1 / all
  items. Both are printed.
- **Line coverage** = the source lines inside converted items, divided by all
  non-blank, non-comment source lines.
- **Unrecognised lines** are counted and listed separately. They never count
  as converted.
- A thing the reader saw but could not classify (a file that failed to parse,
  a construct a rule recognised but could not read) is an **unmeasured** item.
  It is counted as a gap, never dropped.
- `migration-report.json` (with `--json`) has the same items and numbers.

## 8. How success is tested

Following the repository's TDD rule: every test is written first and seen
failing. Tests assert behaviour (the output builds, the URL opens the right
page), not shape.

1. **Fixture apps** in `packages/dartvel_cli/test/fixtures/migrate/<source>/<name>/`.
   Each is small, written for one feature, and has an expected report. For
   example:
   - Flutter: `counter_setstate`, `named_routes`, `go_router_nested`,
     `go_router_shell_tabs`, `provider_cart`, `riverpod_notifier`,
     `bloc_gap`, `channels_gap`, `arb_i18n`.
   - Expo: `router_basic`, `router_tabs`, `api_route`, `zustand_store`,
     `redux_slice`, `stylesheet`, `i18next`.
   - Qt: `stackview`, `bindings`, `cpp_qproperty`, `qrc_assets`,
     `qstr_ts`, `qmake_pro`.
2. **Every fixture's output** must pass `dartvel routes` and `dart analyze`
   with zero errors, and its report must match the expected one. A tagged
   integration test also runs `dartvel build web` on it.
3. **The source is untouched:** every test hashes every file in the source
   folder before and after, and checks that no new file appeared there.
4. **Silent failures:** for each fixture, the number of route and state
   constructs in the source (counted by an independent AST query in the test)
   must equal the number of items in the report.
5. **One real open-source app per source**, cloned at a pinned commit by an
   opt-in test (`DARTVEL_MIGRATE_CORPUS=<folder>`, like the syntax
   differential test). Not vendored, so licences stay with their repos.

   | Source | Required | Why | Stretch |
   |---|---|---|---|
   | Flutter | [`flutter/samples` `compass_app`](https://github.com/flutter/samples/tree/main/compass_app) | go_router + provider + ARB-based localisation + a Dart server folder | — |
   | Expo | [`obytes/react-native-template-obytes`](https://github.com/obytes/react-native-template-obytes) (MIT) | expo-router, zustand, i18next, axios, TanStack Query | [`bluesky-social/social-app`](https://github.com/bluesky-social/social-app) (MIT; React Navigation, Lingui, very large) |
   | Qt | [`qt/qtdoc` `examples/demos/todolist`](https://github.com/qt/qtdoc/tree/dev/examples/demos/todolist) | QML + C++ + CMake, Qt's own demo | [`KDE/kalk`](https://github.com/KDE/kalk) (Kirigami, gettext `po/`) |

   Pass: the output analyzes with zero errors, and `dartvel build web`
   finishes. The first run records the conversion percentage as a baseline.
   Later changes may not lower it without saying why in the PR.
6. **Determinism:** two runs on the same input give byte-identical output and
   reports.

## 9. Free or paid (open question)

An earlier brief called `flutter migrate` Pro-only. This proposal does not
decide it. The owner does. The options:

| Option | What is free | What is paid |
|---|---|---|
| A | all three commands | nothing |
| B | `--dry-run` (the full report, no project written) | writing the project |
| C | nothing | all three commands |

What follows from each:

- **B or C:** the paid code must live in the private `dartvel_enterprise` repo
  ("no paid stuff stays in free history"). The public CLI then gets only a
  refusal with exit 69, like `dvTargetRefusal`/`dvRuntimeRefusal`, plus a
  public extension point, as `DVBuildTarget` is for paid targets. The Rust JS
  parser helper would also move to the private build.
- **A:** everything lives in this repo.

This proposal is safe to keep public either way: it describes behaviour, not
paid code.

## 10. Phased plan

Each phase ships on its own, with tests, the README, the `NEW_SPEC.md`
section, the site docs page and the `docs/spec-status.json` entry in the same
PR.

| Phase | Scope | Done when |
|---|---|---|
| 1 | **`dartvel flutter migrate`: routes + state + report.** The shared core (IR, planner, writer, verifier, report). Assets, ARB catalogues and dependencies are copied. Network calls and channels are reported only. Widget bodies are kept as they are. | All Flutter fixtures pass. `compass_app` output analyzes clean and builds web, with its baseline recorded. |
| 2 | Flutter widgets → `DVBox`/`DVText`/`DVModifier`/`@DVFunctionalWidget`, tooltips, `AppLocalizations` → `DV.I18n`, test import rewrites, backend function candidate typing | DV-CONV-003/012 counts on `compass_app` output fall, with the remaining ones listed |
| 3 | `rust/dartvel_jsparse` (oxc) + carry mechanism. **`dartvel expo migrate`:** Expo Router routes, `useState`/Zustand/RTK state, components, StyleSheet, i18n, report | Expo fixtures + obytes template analyze clean and build web |
| 4 | **`dartvel qt migrate`:** QML parser, CMake/qmake/qrc/ts readers, header scanner, properties/bindings/signals, elements, `qsTr` | Qt fixtures + qtdoc `todolist` analyze clean and build web |
| 5 | Logic translation subset (TS/JS and QML JS expressions and simple functions), React Navigation apps, Jest/RNTL → widget tests, ffigen shims for C++ with no Qt types | Stretch apps run, with their percentages recorded |

`docs/spec-status.json` entry (added with Phase 1):

```json
{ "id": "migrate-commands", "title": "Migrate from Flutter, Expo and Qt",
  "stability": "Draft", "status": "Partial",
  "evidence": ["packages/dartvel_cli/lib/src/commands/flutter_command.dart",
               "packages/dartvel_cli/test/migrate/flutter_migrate_test.dart"] }
```

## 11. The first command: `dartvel flutter migrate` (Phase 1)

### Surface

```text
dartvel flutter migrate <source> <destination>
    [--dry-run] [--name <package>] [--json] [--no-verify] [--fail-under <percent>]
```

- `FlutterCommand` (name `flutter`, description "Work with an existing
  Flutter app.") with one subcommand, `FlutterMigrateCommand` (name
  `migrate`). It is registered in `dartvel_impl.dart` next to `ImportCommand`.
- The body is `Future<int> dvRunFlutterMigrate(String source, String
  destination, {required DVMigrateOptions options, required void
  Function(String) out})`, which returns the exit code. This follows
  `dvRunMigrateCode`, so tests call it directly with temporary folders and
  never touch `Directory.current`.

### Phase 1 behaviour

1. Validate:
   - Source has a `pubspec.yaml` with `flutter: sdk`. Otherwise refuse
     (1): "No Flutter app at <source>: …".
   - Destination is absent or empty, and not nested in the source (or the
     other way round). Otherwise refuse (1). Nothing is written.
2. Copy the source to a temporary folder. Resolve it there (or fall back to
   the unresolved AST, Part 5.1). Delete the copy afterwards, also on failure.
3. Read:
   - **routes:** `MaterialApp`/`CupertinoApp` `routes`, `home`, `initialRoute`,
     `onGenerateRoute` literal cases; `Navigator.pushNamed`/`push` with
     `MaterialPageRoute`/`CupertinoPageRoute`; go_router `GoRoute` (nested),
     `ShellRoute`, `StatefulShellRoute`, `redirect`, `context.go/push`;
     unsupported routers.
   - **state:** `StatefulWidget` + `setState`; `ValueNotifier` +
     `ValueListenableBuilder`; `ChangeNotifier` + provider; Riverpod
     `Provider`/`NotifierProvider`/`@riverpod`/legacy providers; Cubit; Bloc.
   - **reported only:** `http`/`dio` calls, channels, native folder edits.
4. Write:
   - the scaffold;
   - one `@DVPage` per route (the screen widget's body moves into the page,
     and its constructor arguments become route parameters);
   - rewritten navigation calls;
   - signals and `DV.global` registrations in `lib/boot.dart`;
   - every other source file copied with imports rewritten;
   - assets, fonts and ARB catalogues copied;
   - dependencies carried over, minus go_router/auto_route/provider/riverpod
     when no gap still needs them.
5. Verify (unless `--no-verify`): `dartvel routes`, `dart analyze`,
   `dartvel build web`.
6. Write `MIGRATION-REPORT.md` (and the JSON with `--json`). Print the result
   table and the report's path.

### Failing tests to write first (`test/migrate/flutter_migrate_test.dart`)

1. **Refuses a folder that is not a Flutter app:** returns 1, prints the
   reason, and the destination does not exist afterwards.
2. **Refuses a non-empty destination:** returns 1, and the destination's
   existing file is unchanged and no new file is added.
3. **Never changes the source:** file hashes and the file list of every
   fixture are identical before and after a run. No `.dart_tool/` or
   `pubspec.lock` appears.
4. **Named routes (`named_routes`):** `routes: {'/': Home, '/settings':
   Settings}` gives `lib/pages/index.dart` and `lib/pages/settings.dart`. The
   output's own `dartvel routes` generates `DVRoutes.settings`. The source's
   `Navigator.pushNamed(context, '/settings')` becomes
   `DV.Navigation.push(DVRoutes.settings)`. The report lists 3 items as 1:1,
   each with its source `path:line`.
5. **go_router nested params (`go_router_nested`):** `/users/:id` under
   `/users` gives `lib/pages/users/[id].dart` reading
   `context.dvParams['id']`. A widget test on the output navigates to
   `/users/7` and finds the text the source screen showed for user 7.
6. **Computed path is a gap, not a drop:** `context.go(somePath)` becomes gap
   `G1` with its line. The stub compiles. The route count in the report
   equals the `GoRoute` count in the source.
7. **Object argument push is a gap:** `Navigator.push(MaterialPageRoute(builder:
   (_) => Detail(item: item)))` keeps `Detail` as a widget and is reported
   with the "pass its id" fix. A `String id` argument instead gives a page
   with a parameter, as 1:1.
8. **setState → signal (`counter_setstate`):** the counter screen becomes a
   page with `context.signal(0)`. A widget test on the output taps the button
   twice and finds `2`. The report shows 1:1.
9. **StatefulWidget with `initState`/`dispose`** is kept, reported as closest
   with the DV-CONV-012 note, and the output still analyzes clean.
10. **`ValueNotifier` + `ValueListenableBuilder`** become a `DVSignal` read in
    build. A widget test shows the same behaviour.
11. **Provider cart (`provider_cart`):** `ChangeNotifierProvider<Cart>`
    becomes `DV.global<Cart>` in `lib/boot.dart`. `notifyListeners` fields
    become signals. A widget test adds an item and sees the badge count
    change. The report shows closest with the replace-versus-mutate note.
12. **Riverpod:** `NotifierProvider` is closest, an operator-only `Provider`
    is a derived signal (1:1), `FutureProvider` is a gap.
13. **Bloc is a gap** listing every event class and state class by name.
14. **Report arithmetic:** converted % = (1:1 + closest) / items, strict % =
    1:1 / items, and unrecognised lines are listed, for a fixture where these
    are worked out by hand in the test.
15. **Unresolved fallback:** with resolution disabled, the report's header
    says "NOT resolved", and items found by name are marked.
16. **Determinism:** two runs give byte-identical reports.
17. **`--dry-run`** writes nothing, and prints the same report text.
18. **`--fail-under 90`** on a fixture at 85% returns 1, and still writes the
    project.
19. **Integration (tagged `migrate-build`):** every fixture's output passes
    `dart analyze` with zero errors and `dartvel build web`.
20. **Corpus (opt-in `DARTVEL_MIGRATE_CORPUS`):** `compass_app` at a pinned
    commit analyzes with zero errors. Its percentage is written to the test
    log as the baseline.

## 12. Open questions for the owner

1. **Free or paid?** Option A, B or C in Part 9. The earlier brief said Pro.
   B and C move the code to `dartvel_enterprise`.
2. **Names:** `dartvel flutter migrate` / `expo migrate` / `qt migrate`, as
   you named them. Should `dartvel migrate flutter|expo|qt` also work as an
   alias?
3. **JS/TS parsing:** the recommended Rust `oxc` helper is outside the
   current Rust rule in `CLAUDE.md`. That rule allows only package native
   libraries and Dart SDK/Flutter ports, with Dart still deciding. Do you
   allow this exception? If yes:
   - `expo migrate` and `qt migrate` will not work from a `dart pub global
     activate` install (no Dart fallback);
   - the Rust rule text gets a line for it.

   If no, the choices are:
   - a Node fallback using the app's own `typescript` package (puts a JS file
     in the repo);
   - a TS/JSX parser written in Dart (large, slow to reach parity).
4. **Widgets with no Dartvel primitive** (`TextField`, `Slider`, `Switch`,
   `Modal`, Qt `ComboBox`…): keep them as Flutter widgets with a note, so
   migration ships now? Or build the missing primitives in the framework
   first?
5. **Logic translation:** how far should Phase 5 go for TS/JS and C++? The
   proposal translates only mechanical cases, carries the rest as gaps, and
   keeps Qt-free C++ as an FFI library.
6. **Network calls:** report them as backend function candidates only (the
   proposal), or also generate backend function proxies that move the call to
   the server?
7. **Acceptance apps:** compass_app, the obytes template and qtdoc todolist
   as the required real apps, with Bluesky and KDE Kalk as stretch. Change
   any?
8. **`xml` package:** OK to add the pure-Dart `xml` package to `dartvel_cli`
   for `.qrc` and `.ts` files?

## 13. Sources

All checked on 15 November 2026.

Flutter and Dart
- Navigation and routing (named routes not recommended; pageless routes not deep-linkable): https://docs.flutter.dev/ui/navigation
- go_router (path parameters, ShellRoute, redirect; version 18.1.4): https://pub.dev/packages/go_router
- State management options: https://docs.flutter.dev/data-and-backend/state-mgmt/options
- Riverpod providers: https://riverpod.dev/docs/concepts2/providers
- Riverpod 3.0 migration (StateProvider/StateNotifierProvider/ChangeNotifierProvider moved to `legacy.dart`): https://riverpod.dev/docs/3.0_migration
- Bloc concepts (Cubit `emit`, Bloc `on<Event>`): https://bloclibrary.dev/bloc-concepts/
- Platform channels (FFIgen/JNIgen/Pigeon recommended for new projects): https://docs.flutter.dev/platform-integration/platform-channels
- Binding to native code (build hooks, ffigen): https://docs.flutter.dev/platform-integration/bind-native-code
- Internationalization (ARB in `lib/l10n`, `l10n.yaml`, `gen-l10n`): https://docs.flutter.dev/ui/internationalization
- `package:analyzer` (14.7.0; API will break): https://pub.dev/packages/analyzer

Expo and React Native
- Expo Router introduction (default in `create-expo-app`, typed routes): https://docs.expo.dev/router/introduction/
- Expo Router notation: https://docs.expo.dev/router/basics/notation/
- URL parameters and catch-all routes: https://docs.expo.dev/router/reference/url-parameters/
- API routes (`+api.ts`; beta, native deployment alpha): https://docs.expo.dev/router/web/api-routes/
- React Server Components in Expo (experimental, beta): https://docs.expo.dev/guides/server-components/
- Expo Modules API (Swift, Kotlin): https://docs.expo.dev/modules/overview/
- Localization: https://docs.expo.dev/guides/localization/
- Unit testing (jest-expo, React Native Testing Library): https://docs.expo.dev/develop/unit-testing/
- Core components: https://reactnative.dev/docs/components-and-apis
- Flexbox defaults: https://reactnative.dev/docs/flexbox
- Turbo Native Modules: https://reactnative.dev/docs/turbo-native-modules-introduction
- `useState`: https://react.dev/reference/react/useState
- Redux Toolkit `createSlice`: https://redux.js.org/toolkit/api/createSlice
- Zustand `create`: https://zustand.docs.pmnd.rs/reference/apis/create
- oxc parser: https://oxc.rs/docs/guide/usage/parser.html and ESTree conformance: https://docs.rs/crate/oxc_parser_napi/0.96.0/source/README.md

Qt
- Property binding: https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html
- Signals and handlers: https://doc.qt.io/qt-6/qtqml-syntax-signals.html
- Defining QML types from C++ (QML_ELEMENT, Q_PROPERTY): https://doc.qt.io/qt-6/qtqml-cppintegration-definetypes.html
- `qt_add_qml_module`: https://doc.qt.io/qt-6/qt-add-qml-module.html
- qmake manual: https://doc.qt.io/qt-6/qmake-manual.html
- StackView: https://doc.qt.io/qt-6/qml-qtquick-controls-stackview.html
- Internationalization (qsTr, .ts, lupdate/lrelease): https://doc.qt.io/qt-6/qtquick-internationalization.html
- Qt Quick Test: https://doc.qt.io/qt-6/qtquicktest-index.html

/// Opinionated architecture docs written into every Dartvel project.
///
/// Like the agent docs (AGENTS.md etc.), these come from one source so every
/// project gets the same guidance on initialisation, data, HTTP, UI, naming,
/// setup, Git, process, and Dartvel-specific areas (models, backend functions,
/// Studio, modules). They are refreshed by `dartvel dev` and set up by
/// `dartvel create` / `dartvel init`.
library;

import 'dart:io';

/// The sections of the architecture docs.
///
/// Each entry produces one file under `docs/architecture/`.
class DVArchitectureDocSection {
  const DVArchitectureDocSection({
    required this.filename,
    required this.title,
    required this.body,
  });

  final String filename;
  final String title;
  final String body;
}

/// Every architecture doc section.
List<DVArchitectureDocSection> dvArchitectureDocSections() => const [
      DVArchitectureDocSection(
        filename: 'init.md',
        title: 'Initialisation',
        body: "A new Dartvel project starts with `dartvel create <name>`. "
            "The command sets up pubspec.yaml with the core packages, creates "
            "the basic app scaffold, and writes the agent rules block. "
            "Run `dartvel dev` to start the development server; it refreshes "
            "the agent block and architecture docs before generating routes.",
      ),
      DVArchitectureDocSection(
        filename: 'data.md',
        title: 'Data',
        body: "Data models use `@DVModel`. Every model defines fields with "
            "primary constructors (`class const _Order({required final String id})`). "
            "Forms use `Model.Form(...)` — no callbacks, policies decide create/edit. "
            "Search is `Article.search(...)`; import is `Article.import(...)`. "
            "Never write through `DVRecordAdapter`, `DVRecordTable`, or SQL strings.",
      ),
      DVArchitectureDocSection(
        filename: 'http.md',
        title: 'HTTP',
        body: "Backend functions are annotated with `@DVBackendFunction`. "
            "When a backend function's first parameter is `DVContext`, it is "
            "injected and not a client argument. Raw HTTP exposure stays on "
            "`@DVBackendFunction` via `rawPath`/`rawPathSuffix` (mutually exclusive). "
            "Routing uses the generated `DVRoutes` member; never write literal paths.",
      ),
      DVArchitectureDocSection(
        filename: 'ui.md',
        title: 'UI',
        body: "Collection children use `DVBox.list([...])`, `DVBox.row([...])`, "
            "`DVBox.grid([...])`, etc. `DVBox(widget)` is only for a single child. "
            "Every page is reachable by keyboard and screen reader with nothing added: "
            "the page shell carries keyboard scrolling, a remote's D-pad and switch control.",
      ),
      DVArchitectureDocSection(
        filename: 'naming.md',
        title: 'Naming',
        body: "Application-facing Dart declares classes with primary constructors. "
            "New Dart uses dot shorthands (`mainAxisAlignment: .center`, `.fontWeight(.w600)`). "
            "Private generation inputs begin with `_`; application code references "
            "the generated public API (`User`, not `_User`).",
      ),
      DVArchitectureDocSection(
        filename: 'setup.md',
        title: 'Setup',
        body: "Local development is zero-config where possible, including SQLite "
            "for local DB/test workflows. `dartvel build` runs route/client/backend "
            "generation automatically. `build_runner` is retired; do not add new "
            "`Builder` or `build.yaml` files.",
      ),
      DVArchitectureDocSection(
        filename: 'git.md',
        title: 'Git',
        body: "Keep commits atomic: do not mix unrelated implementation, tests, "
            "generated artifacts, or documentation. Push each atomic commit "
            "before starting the next unrelated step. Never push to main/master "
            "unless the brief explicitly says so.",
      ),
      DVArchitectureDocSection(
        filename: 'process.md',
        title: 'Process',
        body: "Tests first: write the failing test, watch it fail for the right "
            "reason, then write the code. Never adjust a test so existing code "
            "passes. Assert on behaviour, not shape. Heavy builds go through "
            "`~/heavy.sh` (2 slots, memory-aware, nice 19).",
      ),
      DVArchitectureDocSection(
        filename: 'models.md',
        title: 'Dartvel-specific: Models',
        body: "Every data model is written, updated, deleted through the generated "
            "model class (`Order(...).save()`, `order.delete()`, `Order.find(...)`). "
            "Sensitive fields use `@DVModel.sensitiveField()`. "
            "Field-scoped annotations live under the model annotation.",
      ),
      DVArchitectureDocSection(
        filename: 'backend.md',
        title: 'Dartvel-specific: Backend Functions',
        body: "Background/durable work stays on `@DVJob`/`DV.Jobs`/`DVQueues`. "
            "`@DVBackendFunction(background: true, durable: true)` is sugar that "
            "compiles onto the job layer, not a new primitive. Job handlers are "
            "`@DVJob.handler()`.",
      ),
      DVArchitectureDocSection(
        filename: 'studio.md',
        title: 'Dartvel-specific: Studio',
        body: "Studio uses the app's one render path, with the app's theme "
            "(dartvel.dev's theme is the default for new projects). Every screen "
            "is selectable, keyboard-navigable and accessible by default. "
            "Studio is part of the app: its screens are guarded routes.",
      ),
      DVArchitectureDocSection(
        filename: 'modules.md',
        title: 'Dartvel-specific: Modules',
        body: "A Dartvel module is a full application boundary configured under "
            "`dartvel.module`/`dartvel.modules` in `pubspec.yaml`. Parents access "
            "it via `DV.Modules.<id>`. Module code must not hard-code its mount point.",
      ),
    ];

/// What a sync did.
class DVArchitectureDocsSyncResult {
  const DVArchitectureDocsSyncResult({
    required this.version,
    this.created = const <String>[],
    this.updated = const <String>[],
    this.failed = const <String>[],
  });
  final String version;
  final List<String> created;
  final List<String> updated;
  final List<String> failed;
  bool get isQuiet => created.isEmpty && updated.isEmpty && failed.isEmpty;
}

/// Sets up, or refreshes, the architecture docs directory in [root].
Future<DVArchitectureDocsSyncResult> dvSyncArchitectureDocs({
  required String root,
  String version = 'dev',
}) async {
  final List<String> created = <String>[];
  final List<String> updated = <String>[];
  final List<String> failed = <String>[];
  final directory = Directory('$root/docs/architecture');
  try {
    directory.createSync(recursive: true);
    for (final section in dvArchitectureDocSections()) {
      final file = File('${directory.path}/${section.filename}');
      final content = '# ${section.title}\n\n${section.body.trim()}\n';
      final bool exists = file.existsSync();
      file.writeAsStringSync(content);
      if (exists) {
        updated.add('docs/architecture/${section.filename}');
      } else {
        created.add('docs/architecture/${section.filename}');
      }
    }
  } catch (_) {
    failed.add('docs/architecture');
  }
  return DVArchitectureDocsSyncResult(
    version: version,
    created: created,
    updated: updated,
    failed: failed,
  );
}

/// Render the full architecture docs directory content.
String dvArchitectureDocsContent({required String version}) {
  final StringBuffer out = StringBuffer()
    ..writeln('# Dartvel Architecture Guide ($version)')
    ..writeln()
    ..writeln('Opinionated architecture docs written by `dartvel create` and '
        '`dartvel init`, refreshed by `dartvel dev`.')
    ..writeln();
  for (final DVArchitectureDocSection s in dvArchitectureDocSections()) {
    out
      ..writeln('## ${s.filename.replaceFirst(".md", "")}: ${s.title}')
      ..writeln()
      ..writeln(s.body)
      ..writeln();
  }
  return out.toString();
}

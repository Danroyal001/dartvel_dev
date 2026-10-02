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
        body: 'A new project starts with `dartvel create <name>`; an existing Flutter or Dart project adopts Dartvel with `dartvel init`, which shows its plan and changes nothing until you confirm. Both write the agent rules and these architecture notes. `dartvel dev` runs the app and refreshes both before generating.',
      ),
      DVArchitectureDocSection(
        filename: 'data.md',
        title: 'Data',
        body: 'Data models are `@DVModel` classes declared with primary constructors, for example `@DVModel() class const _Order({required final String id, final int total = 0});`. Create, update and delete through the generated model: `Order(...).save()`, `order.delete()`, `Order.find(id)`. Forms are `Order.Form()` to create and `order.Form()` to edit; they take no callback and policies decide who may do what. Search is `Article.search(text)`, import is `Article.importCsv(...)`, `importNdjson(...)` or `importExcel(...)`, export is `Article.exportCsv(items)`. Never write through record operations, table or column names, or SQL strings.',
      ),
      DVArchitectureDocSection(
        filename: 'http.md',
        title: 'HTTP',
        body: 'Server code is a private `@DVBackendFunction`; the generator writes the public client function every target calls. A first parameter of type `DVContext` is injected on the server and is not a client argument. Raw HTTP exposure uses `rawPath` or `rawPathSuffix` on the same annotation (never both). Navigate with the generated `DVRoutes` members, never literal paths; a query is `DVRoutes.signin.withQuery({...})`.',
      ),
      DVArchitectureDocSection(
        filename: 'ui.md',
        title: 'UI',
        body: 'Pages are private `@DVPage` functions or `DVClassWidget` classes and import the generated barrel `dartvel_client/dartvel_client.dart`. Children go in `DVBox.list([...])`, `DVBox.row([...])` or `DVBox.grid([...])`; `DVBox(widget)` is for one child. Every page is selectable, keyboard-navigable and readable by screen readers with nothing added, and forms submit with Enter.',
      ),
      DVArchitectureDocSection(
        filename: 'naming.md',
        title: 'Naming',
        body: 'Annotated inputs are private (`_Order`, `_ordersPage`, `_getOrder`) and application code uses the generated public names (`Order`, `getOrder`). Classes use primary constructors and dot shorthands where the context type allows (`mainAxisAlignment: .center`). Say data model, not model, in docs and UI.',
      ),
      DVArchitectureDocSection(
        filename: 'setup.md',
        title: 'Setup',
        body: 'Local development needs no database server: SQLite is the default locally. `dartvel dev` and `dartvel build` run generation themselves, so `dartvel routes` is rarely run by hand. Do not add `build_runner` or `build.yaml` for Dartvel; there is one generator and it is the CLI.',
      ),
      DVArchitectureDocSection(
        filename: 'git.md',
        title: 'Git',
        body: 'Files under `lib/dartvel_client/` are generated: change the annotated inputs and regenerate rather than editing them. Keep commits focused, one change each, so a regenerated client is reviewed with the input change that produced it.',
      ),
      DVArchitectureDocSection(
        filename: 'process.md',
        title: 'Process',
        body: 'Write the failing test first, see it fail for the right reason, then make it pass. Test behaviour rather than shape. Before calling UI work done, check it in a real browser on a web-server build: the page reads with JavaScript off, Ctrl+F finds its text, Tab reaches every control.',
      ),
      DVArchitectureDocSection(
        filename: 'models.md',
        title: 'Data models in depth',
        body: 'Sensitive fields are `@DVModel.sensitiveField()`: kept out of logs, AI context, search and public pages unless a policy allows. Field roles live under the model annotation (`@DVModel.searchableField()`, `@DVModel.featuredImage()`, `@DVModel.pageTitle()`). Every data model gets a public page per record unless it opts out with `@DVModel(generatePublicPages: false)`.',
      ),
      DVArchitectureDocSection(
        filename: 'backend.md',
        title: 'Backend functions and jobs',
        body: 'Request work is a backend function; durable or background work is a `@DVJob` with a `@DVJob.handler()`, run through `DV.Jobs` and `DVQueues`. Reversible operations use `DV.transaction((DVContext context) async { ... })` with `context.afterCommit(...)` and `context.compensate(...)`.',
      ),
      DVArchitectureDocSection(
        filename: 'studio.md',
        title: 'Studio',
        body: 'Studio is part of the application: its screens are guarded routes under the Studio mount, rendered by the same render path and theme as every other page. Access is granted per account with `dartvel admin grant <email or account id>`.',
      ),
      DVArchitectureDocSection(
        filename: 'modules.md',
        title: 'Modules',
        body: 'A module is a full Dartvel application boundary declared under `dartvel.module` or `dartvel.modules` in `pubspec.yaml`. A parent reaches it through `DV.Modules.<id>` and its typed routes through `DV.Modules.<id>Routes`. Module code never hard-codes its mount point.',
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

/// The block Dartvel owns inside each architecture doc. Text a team writes
/// above or below it is theirs and survives every refresh.
const String dvArchitectureBlockBegin = '<!-- dartvel:begin architecture -->';
const String dvArchitectureBlockEnd = '<!-- dartvel:end architecture -->';

/// [existing] with Dartvel's block set to [block], keeping everything outside
/// the markers; a file without markers keeps its text and gains the block below.
String dvMergeArchitectureBlock(String existing, String block) {
  final String managed = '$dvArchitectureBlockBegin\n$block\n$dvArchitectureBlockEnd';
  final int begin = existing.indexOf(dvArchitectureBlockBegin);
  final int end = existing.indexOf(dvArchitectureBlockEnd);
  if (begin >= 0 && end > begin) {
    return '${existing.substring(0, begin)}$managed${existing.substring(end + dvArchitectureBlockEnd.length)}';
  }
  final String kept = existing.trimRight();
  return kept.isEmpty ? '$managed\n' : '$kept\n\n$managed\n';
}

/// Sets up, or refreshes, `docs/architecture/` in [root]. Only Dartvel's
/// block changes, a file whose block is already current is not written, and a
/// file that cannot be written is reported rather than thrown.
Future<DVArchitectureDocsSyncResult> dvSyncArchitectureDocs({
  required String root,
  String version = 'dev',
}) async {
  final List<String> created = <String>[];
  final List<String> updated = <String>[];
  final List<String> failed = <String>[];
  final Directory directory = Directory('$root/docs/architecture');
  for (final DVArchitectureDocSection section in dvArchitectureDocSections()) {
    final String relative = 'docs/architecture/${section.filename}';
    try {
      directory.createSync(recursive: true);
      final File file = File('${directory.path}/${section.filename}');
      final String block = '# ${section.title}\n\n${section.body.trim()}';
      if (!file.existsSync()) {
        file.writeAsStringSync(dvMergeArchitectureBlock('', block));
        created.add(relative);
        continue;
      }
      final String existing = file.readAsStringSync();
      final String merged = dvMergeArchitectureBlock(existing, block);
      if (merged != existing) {
        file.writeAsStringSync(merged);
        updated.add(relative);
      }
    } on FileSystemException {
      failed.add(relative);
    }
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

/// `dartvel inspect adoption`: what in a project is Dartvel-managed and what
/// is not -- routes, models, screens and functions.
///
/// The managed half is the project graph and the generator's own page
/// discovery. The unmanaged half is read from source by named, narrow rules,
/// and each half says how it was counted, because a count of "0 unmanaged"
/// that only meant "nothing this could recognise" would tell a team they had
/// finished a migration they had not.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../graph/project_graph.dart';
import 'adoption_build_checks.dart';
import '../generators/primary_constructors.dart';

/// One thing counted.
class DVAdoptionItem {
  const DVAdoptionItem(this.name, this.source);

  final String name;

  /// `lib/file.dart:line`.
  final String source;

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'source': source};
}

/// One kind of thing, split into its two halves.
class DVAdoptionHalf {
  const DVAdoptionHalf({
    required this.managed,
    required this.unmanaged,
    required this.method,
    this.unmeasured = const <String>[],
  });

  final List<DVAdoptionItem> managed;
  final List<DVAdoptionItem> unmanaged;

  /// Things found but not counted on either side, and why.
  final List<String> unmeasured;

  /// How [unmanaged] was counted, including what it cannot see.
  final String method;

  Map<String, Object?> toJson() => <String, Object?>{
        'managed': managed.map((DVAdoptionItem i) => i.toJson()).toList(),
        'unmanaged': unmanaged.map((DVAdoptionItem i) => i.toJson()).toList(),
        'unmeasured': unmeasured,
        'method': method,
      };
}

/// The whole report.
class DVAdoptionInventory {
  const DVAdoptionInventory({
    required this.routes,
    required this.models,
    required this.screens,
    required this.functions,
  });

  final DVAdoptionHalf routes;
  final DVAdoptionHalf models;
  final DVAdoptionHalf screens;
  final DVAdoptionHalf functions;

  Map<String, DVAdoptionHalf> get halves => <String, DVAdoptionHalf>{
        'routes': routes,
        'models': models,
        'screens': screens,
        'functions': functions,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        for (final MapEntry<String, DVAdoptionHalf> e in halves.entries)
          e.key: e.value.toJson(),
      };

  /// The text `dartvel inspect adoption` prints.
  List<String> lines() {
    final List<String> out = <String>[
      '${'adoption'.padRight(12)}${'managed'.padLeft(8)}${'not managed'.padLeft(13)}',
    ];
    halves.forEach((String kind, DVAdoptionHalf half) {
      out.add('  ${kind.padRight(10)}${'${half.managed.length}'.padLeft(8)}'
          '${'${half.unmanaged.length}'.padLeft(13)}'
          '${half.unmeasured.isEmpty ? '' : '   (${half.unmeasured.length} not measured)'}');
    });
    halves.forEach((String kind, DVAdoptionHalf half) {
      out.add('');
      out.add(kind);
      for (final DVAdoptionItem item in half.managed) {
        out.add('  managed      ${item.name}  ${item.source}');
      }
      for (final DVAdoptionItem item in half.unmanaged) {
        out.add('  not managed  ${item.name}  ${item.source}');
      }
      for (final String note in half.unmeasured) {
        out.add('  not measured $note');
      }
      out.add('  (${half.method})');
    });
    out.add('');
    out.add('Stopping here is legitimate: what is not managed is a normal '
        'Flutter or Dart application, as it was before.');
    return out;
  }
}

/// Builds the inventory for the project at [root].
DVAdoptionInventory dvAdoptionInventory({
  required String root,
  required String pagesDir,
  required DartvelProjectGraph graph,
}) {
  final DVAdoptionBuildReport routes =
      dvAdoptionBuildCheck(root: root, pagesDir: pagesDir);
  final List<(String, String)> pages = dvGeneratedPageRoutes(root, pagesDir);

  final List<DVAdoptionItem> unmanagedModels = <DVAdoptionItem>[];
  final List<DVAdoptionItem> unmanagedScreens = <DVAdoptionItem>[];
  final List<DVAdoptionItem> unmanagedFunctions = <DVAdoptionItem>[];

  final String pagesPrefix = '${pagesDir.replaceAll(r'\', '/')}/';
  for (final (String rel, String source) in _handWrittenSources(root)) {
    final String code = dvBlankComments(source);
    final String masked = dvBlankStrings(code);
    unmanagedModels.addAll(_unmanagedModels(rel, masked));
    if (!rel.startsWith(pagesPrefix)) {
      final DVAdoptionItem? screen = _screen(rel, masked);
      if (screen != null) unmanagedScreens.add(screen);
    }
    unmanagedFunctions.addAll(_shelfRoutes(rel, code));
  }

  return DVAdoptionInventory(
    routes: DVAdoptionHalf(
      managed: <DVAdoptionItem>[
        for (final (String path, String source) in pages)
          DVAdoptionItem(path, source),
      ],
      unmanaged: <DVAdoptionItem>[
        for (final DVHostRoute r in routes.hostRoutes)
          DVAdoptionItem(r.path, r.source),
      ],
      unmeasured: routes.unchecked,
      method: 'not managed: GoRoute(path: ...) calls, joined to their parents; '
          'routes declared through other routers are not seen',
    ),
    models: DVAdoptionHalf(
      managed: <DVAdoptionItem>[
        for (final DVGraphModel m in graph.models) DVAdoptionItem(m.name, m.source),
      ],
      unmanaged: unmanagedModels,
      method: 'not managed: classes annotated @freezed, @JsonSerializable, '
          '@MappableClass or @collection, and drift tables; plain classes '
          'are not counted as models',
    ),
    screens: DVAdoptionHalf(
      managed: <DVAdoptionItem>[
        for (final (String path, String source) in pages)
          DVAdoptionItem(path, source),
      ],
      unmanaged: unmanagedScreens,
      method: 'not managed: files outside $pagesDir that build a Scaffold',
    ),
    functions: DVAdoptionHalf(
      managed: <DVAdoptionItem>[
        for (final DVGraphFunction f in graph.functions)
          DVAdoptionItem('${f.method} ${f.path}', f.source),
      ],
      unmanaged: unmanagedFunctions,
      method: 'not managed: shelf_router routes with a literal path; handlers '
          'written against other HTTP libraries are not seen',
    ),
  );
}

List<(String, String)> _handWrittenSources(String root) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return const <(String, String)>[];
  final List<File> files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return <(String, String)>[
    for (final File file in files)
      if (_handWritten(p.relative(file.path, from: root).replaceAll(r'\', '/')))
        (
          p.relative(file.path, from: root).replaceAll(r'\', '/'),
          dvDesugarPrimaryConstructors(file.readAsStringSync()),
        ),
  ];
}

bool _handWritten(String rel) =>
    !rel.startsWith('lib/dartvel_client/') &&
    !rel.endsWith('.g.dart') &&
    !rel.endsWith('.freezed.dart');

const Set<String> _modelAnnotations = <String>{
  'freezed',
  'Freezed',
  'unfreezed',
  'JsonSerializable',
  'MappableClass',
  'collection',
  'Collection',
};

Iterable<DVAdoptionItem> _unmanagedModels(String rel, String masked) sync* {
  for (final RegExpMatch match in dvClassDeclaration.allMatches(masked)) {
    final List<String> names = dvAnnotationsBefore(masked, match.start)
        .map(((String, int) a) => a.$1)
        .toList();
    if (names.contains('DVModel')) continue;
    final String header = masked.substring(
      match.start,
      _indexOrEnd(masked, '{', match.end),
    );
    final bool table =
        RegExp(r'\bextends\s+(?:drift\.)?Table\b').hasMatch(header);
    if (table || names.any(_modelAnnotations.contains)) {
      yield DVAdoptionItem(match.group(1)!, '$rel:${_lineOf(masked, match.start)}');
    }
  }
}

final RegExp _scaffold = RegExp(r'(?<![A-Za-z0-9_$.])Scaffold\s*\(');
final RegExp _widgetClass = RegExp(
  r'class\s+(?:const\s+)?([A-Za-z_$][A-Za-z0-9_$]*)[^{]*?\bextends\s+'
  r'(?:StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|HookWidget|HookConsumerWidget)\b',
);

DVAdoptionItem? _screen(String rel, String masked) {
  final RegExpMatch? scaffold = _scaffold.firstMatch(masked);
  if (scaffold == null) return null;
  final RegExpMatch? widget = _widgetClass.firstMatch(masked);
  return widget == null
      ? DVAdoptionItem(p.basenameWithoutExtension(rel),
          '$rel:${_lineOf(masked, scaffold.start)}')
      : DVAdoptionItem(
          widget.group(1)!, '$rel:${_lineOf(masked, widget.start)}');
}

final RegExp _shelfCall = RegExp(
  r'''\.(get|post|put|delete|patch|head|options|all)\s*\(\s*(?:r?'(/[^'$\\]*)'|r?"(/[^"$\\]*)")''',
);
final RegExp _shelfAnnotation = RegExp(
  r'''@Route\.(get|post|put|delete|patch|head|options|all)\s*\(\s*(?:r?'(/[^'$\\]*)'|r?"(/[^"$\\]*)")''',
);

Iterable<DVAdoptionItem> _shelfRoutes(String rel, String code) sync* {
  if (!code.contains('package:shelf_router/')) return;
  final List<RegExpMatch> matches = <RegExpMatch>[
    ..._shelfAnnotation.allMatches(code),
    ..._shelfCall
        .allMatches(code)
        // `@Route.get(` is matched above; do not count it twice.
        .where((RegExpMatch m) => !code.substring(0, m.start).endsWith('@Route')),
  ]..sort((RegExpMatch a, RegExpMatch b) => a.start.compareTo(b.start));
  for (final RegExpMatch m in matches) {
    yield DVAdoptionItem(
      '${m.group(1)!.toUpperCase()} ${m.group(2) ?? m.group(3)}',
      '$rel:${_lineOf(code, m.start)}',
    );
  }
}

int _indexOrEnd(String s, String needle, int from) {
  final int at = s.indexOf(needle, from);
  return at == -1 ? s.length : at;
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

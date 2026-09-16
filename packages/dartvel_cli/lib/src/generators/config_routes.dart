/// Routes declared in code, read from the routes file.
///
/// `lib/routes.dart` declares a top-level `routes` list of `DVRoute`,
/// `DVShellRoute`, `DVStatefulShellRoute` and `DVGoRoutes`. The generated
/// router imports the file and mounts the list, so the routes run whatever
/// this reads. What this reads is the paths and names, which are what the
/// build needs and cannot get from a running application: a `DVRoutes`
/// member per route, the manifest the web build writes pages and a sitemap
/// from, and the checks against the pages.
///
/// Lexical, like the rest of the CLI, with comments and string contents
/// blanked so neither can look like a route. What it cannot read it refuses
/// (`DV-ROUTE-003`) rather than skips, because a route skipped here still
/// runs -- with no typed target, no conflict check and no page on the web.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVRouteOrderException, dvOrderRoutes, dvRouteShape;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../adoption/adoption_build_checks.dart';

/// The routes file when `dartvel.routes` does not name one.
const String dvDefaultRoutesFile = 'lib/routes.dart';

/// One route the routes file declares.
class DVConfigRoute {
  const DVConfigRoute({
    required this.path,
    required this.source,
    required this.guarded,
    this.name,
  });

  /// The full path, joined to its parents.
  final String path;

  /// `name:`, when the route gave one.
  final String? name;

  /// `lib/routes.dart:12`.
  final String source;

  /// Whether a redirect on the route or anything above it runs first. The
  /// application's root guard is not counted here; the generator adds it.
  final bool guarded;
}

/// What the routes file declares.
class DVConfigRoutes {
  const DVConfigRoutes({
    this.file,
    this.routes = const <DVConfigRoute>[],
    this.groups = const <List<String>>[],
    this.errors = const <String>[],
  });

  /// The file, relative to the project, or null when there is none.
  final String? file;

  /// Every route, parents before children.
  final List<DVConfigRoute> routes;

  /// The full paths of each top-level entry, which the router orders as a
  /// unit. A `DVGoRoutes` is not here: what it holds is not readable.
  final List<List<String>> groups;

  /// `DV-ROUTE-003` errors. Any one fails the build.
  final List<String> errors;

  bool get exists => file != null;

  /// The `package:` URI the generated router imports the file by.
  String importUri(String pkgName) =>
      file!.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');

  /// Reads the routes file of the project at [root].
  ///
  /// [dv] is the `dartvel:` section of pubspec.yaml. `routes:` there names the
  /// file; without it, `lib/routes.dart` is used when it exists.
  static DVConfigRoutes read({required String root, YamlMap? dv}) {
    final Object? declared = dv?['routes'];
    final String rel = declared is String && declared.trim().isNotEmpty
        ? declared.trim().replaceAll(r'\', '/')
        : dvDefaultRoutesFile;
    final File file = File(p.join(root, rel));
    if (!file.existsSync()) {
      if (declared == null) return const DVConfigRoutes();
      return DVConfigRoutes(
        file: null,
        errors: <String>[
          'DV-ROUTE-003: dartvel.routes names $rel, which does not exist.',
        ],
      );
    }
    if (!rel.startsWith('lib/')) {
      return DVConfigRoutes(
        errors: <String>[
          'DV-ROUTE-003: dartvel.routes names $rel, which is outside lib/, so '
              'the generated router cannot import it.',
        ],
      );
    }
    return _Reader(rel, file.readAsStringSync()).read();
  }
}

/// `DV-ROUTE-001` and `DV-ROUTE-004`: config routes against every other
/// route the router serves, given as `(path, where it comes from)`.
List<String> dvConfigRouteConflicts(
  DVConfigRoutes config, {
  required List<(String, String)> generated,
}) {
  final List<String> errors = <String>[];
  final Map<String, (String, String)> seen = <String, (String, String)>{
    for (final (String path, String source) in generated)
      dvRouteShape(path): (path, source),
  };
  for (final DVConfigRoute route in config.routes) {
    final String shape = dvRouteShape(route.path);
    final (String, String)? other = seen[shape];
    if (other != null) {
      errors.add(
        'DV-ROUTE-001: ${route.path} is declared at ${route.source} '
        'and ${other.$1 == route.path ? '' : 'as ${other.$1} '}by '
        '${other.$2}. Remove one of them. Neither takes precedence, because '
        'the one that lost would stop being reachable without a word.',
      );
      continue;
    }
    seen[shape] = (route.path, 'the config route at ${route.source}');
  }
  if (errors.isNotEmpty) return errors;

  try {
    dvOrderRoutes<List<String>>(<List<String>>[
      for (final (String path, String _) in generated) <String>[path],
      ...config.groups,
    ], (List<String> group) => group);
  } on DVRouteOrderException catch (error) {
    errors.add(error.toString());
  }
  return errors;
}

const Set<String> _nodes = <String>{
  'DVRoute',
  'DVShellRoute',
  'DVStatefulShellRoute',
  'DVGoRoutes',
};

final RegExp _declaration = RegExp(
  r'(?<![A-Za-z0-9_$.])(?:(?:late\s+)?final|const|var)\s+'
  r'(?:List\s*<\s*DVRouteNode\s*>\s+)?routes\s*=|'
  r'(?<![A-Za-z0-9_$.])List\s*<\s*DVRouteNode\s*>\s+get\s+routes\s*=>',
);

final RegExp _plainLiteral = RegExp(r'''^(?:r?'([^'\\]*)'|r?"([^"\\]*)")$''');

final RegExp _identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

enum _Context { top, shell, child }

class _Reader {
  _Reader(this.rel, String source)
    : code = dvBlankComments(source),
      masked = dvBlankStrings(dvBlankComments(source));

  final String rel;
  final String code;
  final String masked;
  final List<DVConfigRoute> routes = <DVConfigRoute>[];
  final List<String> errors = <String>[];

  String at(int offset) => '$rel:${dvLineOf(masked, offset)}';

  DVConfigRoutes read() {
    RegExpMatch? found;
    for (final RegExpMatch match in _declaration.allMatches(masked)) {
      if (_depth(match.start) == 0) {
        found = match;
        break;
      }
    }
    if (found == null) {
      return DVConfigRoutes(
        file: rel,
        errors: <String>[
          'DV-ROUTE-003: $rel declares no top-level `routes`. Declare '
              '`final List<DVRouteNode> routes = <DVRouteNode>[...];`, or remove '
              'the file if the application has no config routes.',
        ],
      );
    }
    final RegExpMatch? open = RegExp(
      r'^\s*(?:const\s+)?(?:<\s*DVRouteNode\s*>\s*)?\[',
    ).firstMatch(masked.substring(found.end));
    if (open == null) {
      return DVConfigRoutes(
        file: rel,
        errors: <String>[
          'DV-ROUTE-003: `routes` at ${at(found.start)} is not a list literal, '
              'so the build cannot read the routes in it. Write the routes '
              'inline: `routes = <DVRouteNode>[DVRoute(...), ...]`.',
        ],
      );
    }
    final int listOpen = found.end + open.end - 1;
    final List<List<String>> groups = <List<String>>[];
    for (final (int start, int end) in _elements(listOpen)) {
      final int before = routes.length;
      final bool readable = _node(start, end, '', _Context.top, false);
      if (!readable) continue;
      final List<String> leaves = <String>[
        for (final DVConfigRoute route in routes.sublist(before)) route.path,
      ];
      if (leaves.isNotEmpty) groups.add(leaves);
    }
    return DVConfigRoutes(
      file: rel,
      routes: routes,
      groups: groups,
      errors: errors,
    );
  }

  int _depth(int offset) {
    int depth = 0;
    for (int i = 0; i < offset; i += 1) {
      final String c = masked[i];
      if (c == '{' || c == '(' || c == '[') depth += 1;
      if (c == '}' || c == ')' || c == ']') depth -= 1;
    }
    return depth;
  }

  /// The elements of the list opening at [open], as trimmed spans.
  List<(int, int)> _elements(int open) {
    final int close = dvMatchingClose(masked, open);
    if (close == -1) return const <(int, int)>[];
    final List<(int, int)> out = <(int, int)>[];
    int start = open + 1;
    int depth = 0;
    void take(int end) {
      int s = start;
      int e = end;
      while (s < e && masked[s].trim().isEmpty) {
        s += 1;
      }
      while (e > s && masked[e - 1].trim().isEmpty) {
        e -= 1;
      }
      if (s < e) out.add((s, e));
    }

    for (int i = open + 1; i < close; i += 1) {
      final String c = masked[i];
      if (c == '(' || c == '[' || c == '{') depth += 1;
      if (c == ')' || c == ']' || c == '}') depth -= 1;
      if (c == ',' && depth == 0) {
        take(i);
        start = i + 1;
      }
    }
    take(close);
    return out;
  }

  /// Reads one route list element. False when it could not be read.
  bool _node(
    int start,
    int end,
    String parent,
    _Context context,
    bool guarded,
  ) {
    final RegExpMatch? ctor = RegExp(
      r'^(?:const\s+|new\s+)?([A-Za-z_]\w*)\s*\(',
    ).firstMatch(masked.substring(start, end));
    final String? type = ctor?.group(1);
    if (ctor == null || !_nodes.contains(type)) {
      final String text = code.substring(start, end).split('\n').first.trim();
      errors.add(
        'DV-ROUTE-003: `$text` at ${at(start)} is not a DVRoute, '
        'DVShellRoute, DVStatefulShellRoute or DVGoRoutes the build can read. '
        'A spread, a collection `if` or a variable hides its routes from the '
        'typed targets and the checks; write each route inline.',
      );
      return false;
    }
    final int open = start + ctor.end - 1;
    final int close = dvMatchingClose(masked, open);
    if (close == -1) return false;
    final Map<String, (int, int)> args = dvNamedArgs(masked, open, close);
    final bool redirect = args.containsKey('redirect');

    switch (type) {
      case 'DVGoRoutes':
        // Mounted as it is. Its GoRoutes are checked against the pages by
        // DV-ADOPT-002, which reads every GoRoute under lib/.
        if (context != _Context.top) {
          errors.add(
            'DV-ROUTE-003: DVGoRoutes at ${at(start)} is nested. It '
            'mounts a list at the top level of the routes file.',
          );
          return false;
        }
        return true;
      case 'DVShellRoute':
        final (int, int)? children = args['routes'];
        if (children == null) return true;
        _list(children, parent, _Context.shell, guarded || redirect);
        return true;
      case 'DVStatefulShellRoute':
        final (int, int)? branches = args['branches'];
        if (branches == null) return true;
        final int listOpen = masked.indexOf('[', branches.$1);
        if (listOpen == -1 || listOpen >= branches.$2) return true;
        for (final (int s, int e) in _elements(listOpen)) {
          final RegExpMatch? branch = RegExp(
            r'^(?:const\s+)?DVShellBranch\s*\(',
          ).firstMatch(masked.substring(s, e));
          if (branch == null) {
            final String text = code.substring(s, e).split('\n').first.trim();
            errors.add(
              'DV-ROUTE-003: `$text` at ${at(s)} is not a '
              'DVShellBranch the build can read.',
            );
            continue;
          }
          final int bOpen = s + branch.end - 1;
          final int bClose = dvMatchingClose(masked, bOpen);
          if (bClose == -1) continue;
          final (int, int)? children = dvNamedArgs(
            masked,
            bOpen,
            bClose,
          )['routes'];
          if (children != null) {
            _list(children, parent, _Context.shell, guarded || redirect);
          }
        }
        return true;
    }

    // DVRoute.
    final (int, int)? pathArg = args['path'];
    final String? segment = pathArg == null ? null : _literal(pathArg);
    if (segment == null) {
      errors.add(
        'DV-ROUTE-003: the DVRoute at ${at(start)} has a path that is '
        'not a plain string literal${pathArg == null ? '' : ' (${code.substring(pathArg.$1, pathArg.$2).trim()})'}. '
        'The build reads the path for its typed target and its checks, so '
        'it is written out once, as a literal.',
      );
      return false;
    }
    final bool absolute = segment.startsWith('/');
    if (context == _Context.child && absolute) {
      errors.add(
        "DV-ROUTE-003: the DVRoute '$segment' at ${at(start)} is under "
        "another DVRoute and starts with '/'. A child route's path is "
        "relative to its parent's: write '${segment.split('/').last}'.",
      );
      return false;
    }
    if (context != _Context.child && !absolute) {
      errors.add(
        "DV-ROUTE-003: the DVRoute '$segment' at ${at(start)} is not "
        "under another DVRoute and does not start with '/'. Only a child "
        'route is relative.',
      );
      return false;
    }
    String? name;
    final (int, int)? nameArg = args['name'];
    if (nameArg != null) {
      name = _literal(nameArg);
      if (name == null || !_identifier.hasMatch(name)) {
        errors.add(
          'DV-ROUTE-003: the DVRoute $segment at ${at(start)} has a '
          'name that is not a plain string literal holding a public Dart '
          'identifier (${code.substring(nameArg.$1, nameArg.$2).trim()}).',
        );
        return false;
      }
    }
    final String full = absolute
        ? segment
        : parent == '/'
        ? '/$segment'
        : '$parent/$segment';
    final bool covered = guarded || redirect;
    routes.add(
      DVConfigRoute(
        path: full,
        name: name,
        source: at(start),
        guarded: covered,
      ),
    );
    final (int, int)? children = args['routes'];
    if (children != null) {
      _list(children, full, _Context.child, covered);
    }
    return true;
  }

  void _list((int, int) span, String parent, _Context context, bool guarded) {
    final int listOpen = masked.indexOf('[', span.$1);
    if (listOpen == -1 || listOpen >= span.$2) {
      final String text = code.substring(span.$1, span.$2).trim();
      errors.add(
        'DV-ROUTE-003: `routes: $text` at ${at(span.$1)} is not a '
        'list literal the build can read.',
      );
      return;
    }
    for (final (int s, int e) in _elements(listOpen)) {
      _node(s, e, parent, context, guarded);
    }
  }

  String? _literal((int, int) span) {
    final String text = code.substring(span.$1, span.$2).trim();
    final RegExpMatch? literal = _plainLiteral.firstMatch(text);
    if (literal == null) return null;
    final bool raw = text.startsWith('r');
    final String value = literal.group(1) ?? literal.group(2)!;
    if (!raw && value.contains(r'$')) return null;
    return value;
  }
}

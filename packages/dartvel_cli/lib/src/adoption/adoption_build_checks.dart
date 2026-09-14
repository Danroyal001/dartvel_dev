/// The build errors Adoption defines for a project that already had a router
/// and a serializer before it had Dartvel.
///
/// * DV-ADOPT-002 -- a route defined by both the host router and a generated
///   page. Neither wins: a precedence rule makes the loser a page that stops
///   being reachable, and nobody notices.
/// * DV-ADOPT-003 -- an annotated model that already has a generated
///   serializer. Two `toJson`s for one type disagree as data, not as a stack
///   trace.
///
/// Both are read from source before anything is generated, so a build that is
/// going to fail writes nothing first. Like the rest of the CLI this reads
/// lexically rather than through the analyzer, with comments and string
/// contents blanked so that neither can look like code. What it cannot read
/// -- a route path that is not a plain string literal -- is reported as
/// unchecked rather than passed.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/route_utils.dart';

/// A route the host application's own router declares.
class DVHostRoute {
  const DVHostRoute(this.path, this.source);

  /// The full path, joined to its parent routes.
  final String path;

  /// `lib/file.dart:line` of the `GoRoute(`.
  final String source;
}

/// What the adoption build checks found.
class DVAdoptionBuildReport {
  const DVAdoptionBuildReport({
    required this.errors,
    required this.unchecked,
    required this.hostRoutes,
  });

  /// DV-ADOPT-002 and DV-ADOPT-003 errors. Any one fails the build.
  final List<String> errors;

  /// Host routes whose path could not be read, so could not be compared.
  final List<String> unchecked;

  final List<DVHostRoute> hostRoutes;
}

/// Runs both checks over the project at [root].
///
/// [extraRoutes] are generated routes that do not come from a page file --
/// a model's generated public page -- as `(path, description)`.
DVAdoptionBuildReport dvAdoptionBuildCheck({
  required String root,
  required String pagesDir,
  List<(String, String)> extraRoutes = const <(String, String)>[],
}) {
  final List<(String rel, String source)> files = _sources(root);
  final List<String> errors = <String>[];
  final List<String> unchecked = <String>[];
  final List<DVHostRoute> hostRoutes = <DVHostRoute>[];

  for (final (String rel, String source) in files) {
    final String code = dvBlankComments(source);
    final String masked = dvBlankStrings(code);
    _hostRoutesIn(rel, code, masked, hostRoutes, unchecked);
    errors.addAll(_serializerConflictsIn(rel, source, masked));
  }

  final Map<String, (String, String)> generated = <String, (String, String)>{};
  for (final (String path, String source) in <(String, String)>[
    ..._pageRoutes(root, pagesDir),
    ...extraRoutes,
  ]) {
    generated.putIfAbsent(_shape(path), () => (path, source));
  }
  for (final DVHostRoute host in hostRoutes) {
    final (String, String)? page = generated[_shape(host.path)];
    if (page == null) continue;
    errors.add('DV-ADOPT-002: ${page.$1} is defined by the host router at '
        '${host.source}${host.path == page.$1 ? '' : ' (as ${host.path})'} '
        'and generated from ${page.$2}. Remove one of them. Neither takes '
        'precedence, because the one that lost would stop being reachable '
        'without a word.');
  }

  // Serializer errors first by file, then routes; both already in file order.
  return DVAdoptionBuildReport(
    errors: errors,
    unchecked: unchecked,
    hostRoutes: hostRoutes,
  );
}

/// Every hand-written Dart file under `lib/`, sorted, as `(rel, source)`.
List<(String, String)> _sources(String root) {
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
          file.readAsStringSync(),
        ),
  ];
}

bool _handWritten(String rel) =>
    !rel.startsWith('lib/dartvel_client/') &&
    !rel.endsWith('.g.dart') &&
    !rel.endsWith('.freezed.dart');

/// Generated page routes, as the client generator discovers them: files
/// under [pagesDir] with `@DVPage`, or the legacy `*.page.dart`.
List<(String, String)> _pageRoutes(String root, String pagesDir) {
  final Directory dir = Directory(p.join(root, pagesDir));
  if (!dir.existsSync()) return const <(String, String)>[];
  final List<File> files = dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  final List<(String, String)> routes = <(String, String)>[];
  for (final File file in files) {
    final String rel = p.relative(file.path, from: root).replaceAll(r'\', '/');
    final String base = p.basename(rel);
    if (base == '_layout.dart' ||
        base == '_guard.dart' ||
        base.endsWith('.loading.dart') ||
        base.endsWith('.error.dart')) {
      continue;
    }
    final String masked = dvBlankStrings(dvBlankComments(file.readAsStringSync()));
    final int annotation = masked.indexOf(RegExp(r'@DVPage\b'));
    if (annotation == -1 && !rel.endsWith('.page.dart')) continue;
    final String route;
    try {
      route = RouteUtils.routeFor(rel, pagesDir);
    } on FormatException {
      // The client generator reports a malformed page path itself.
      continue;
    }
    routes.add((
      route,
      'the page $rel:${annotation == -1 ? 1 : _lineOf(masked, annotation)}',
    ));
  }
  return routes;
}

/// A route reduced to what matching sees: parameter names and a trailing
/// slash do not make two routes different.
String _shape(String path) {
  String shaped = path
      .split('/')
      .map((String s) => s.startsWith(':')
          ? ':'
          : s.startsWith('*')
              ? '*'
              : s)
      .join('/');
  if (shaped.length > 1 && shaped.endsWith('/')) {
    shaped = shaped.substring(0, shaped.length - 1);
  }
  return shaped.isEmpty ? '/' : shaped;
}

final RegExp _goRoute = RegExp(r'(?<![A-Za-z0-9_$.])GoRoute\s*\(');
final RegExp _plainLiteral = RegExp(r'''^(?:r?'([^'\\]*)'|r?"([^"\\]*)")$''');

void _hostRoutesIn(
  String rel,
  String code,
  String masked,
  List<DVHostRoute> into,
  List<String> unchecked,
) {
  // Every GoRoute, with its argument span and the span of its `routes:`.
  final List<_Route> found = <_Route>[];
  for (final RegExpMatch match in _goRoute.allMatches(masked)) {
    final int open = match.end - 1;
    final int close = _matchingClose(masked, open);
    if (close == -1) continue;
    final Map<String, (int, int)> args = _namedArgs(masked, open, close);
    found.add(_Route(
      start: match.start,
      open: open,
      close: close,
      path: args['path'],
      children: args['routes'],
    ));
  }

  for (final _Route route in found) {
    final String source = '$rel:${_lineOf(masked, route.start)}';
    if (route.path == null) {
      unchecked.add('$source: GoRoute has no path argument this can read; '
          'DV-ADOPT-002 could not check it against the generated routes.');
      route.full = null;
      continue;
    }
    final String text =
        code.substring(route.path!.$1, route.path!.$2).trim();
    final RegExpMatch? literal = _plainLiteral.firstMatch(text);
    final bool raw = text.startsWith('r');
    final String? value = literal == null
        ? null
        : (literal.group(1) ?? literal.group(2));
    if (value == null || (!raw && value.contains(r'$'))) {
      unchecked.add('$source: GoRoute path $text is not a plain string '
          'literal; DV-ADOPT-002 could not check it against the generated '
          'routes.');
      route.full = null;
      continue;
    }
    route.segment = value;
  }

  // Parents before children: `found` is in source order and a parent's
  // `GoRoute(` always precedes its children's.
  for (final _Route route in found) {
    if (route.segment == null) continue;
    final String segment = route.segment!;
    if (segment.startsWith('/')) {
      route.full = segment;
    } else {
      _Route? parent;
      for (final _Route candidate in found) {
        final (int, int)? kids = candidate.children;
        if (kids != null && route.start > kids.$1 && route.close < kids.$2) {
          // The innermost enclosing route is the last one that contains it.
          parent = candidate;
        }
      }
      if (parent == null || parent.full == null) {
        if (parent != null) {
          // Its parent's path could not be read, so neither can its own.
          unchecked.add('$rel:${_lineOf(masked, route.start)}: GoRoute '
              "'$segment' is under a route whose path could not be read.");
        }
        continue;
      }
      route.full = parent.full == '/' ? '/$segment' : '${parent.full}/$segment';
    }
    into.add(DVHostRoute(route.full!, '$rel:${_lineOf(masked, route.start)}'));
  }
}

class _Route {
  _Route({
    required this.start,
    required this.open,
    required this.close,
    required this.path,
    required this.children,
  });

  final int start;
  final int open;
  final int close;
  final (int, int)? path;
  final (int, int)? children;
  String? segment;
  String? full;
}

/// Serializer markers that generate `fromJson`/`toJson` for a class.
const Set<String> _serializerAnnotations = <String>{
  'freezed',
  'Freezed',
  'unfreezed',
  'JsonSerializable',
  'MappableClass',
};

final RegExp _classDeclaration = RegExp(
  r'(?<![A-Za-z0-9_$])(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+([A-Za-z_$][A-Za-z0-9_$]*)',
);

Iterable<String> _serializerConflictsIn(
  String rel,
  String source,
  String masked,
) sync* {
  for (final RegExpMatch match in _classDeclaration.allMatches(masked)) {
    final List<(String, int)> stack = _annotationsBefore(masked, match.start);
    final int dvModel = stack.indexWhere((( String, int) a) => a.$1 == 'DVModel');
    if (dvModel == -1) continue;

    final String declared = match.group(1)!;
    final String public =
        declared.startsWith('_') ? declared.substring(1) : declared;
    String? serializer;
    for (final (String name, int _) in stack) {
      if (_serializerAnnotations.contains(name)) {
        serializer = '@$name';
        break;
      }
    }
    if (serializer == null) {
      final int bodyOpen = masked.indexOf('{', match.end);
      final int bodyClose =
          bodyOpen == -1 ? -1 : _matchingClose(masked, bodyOpen);
      final String declaration = masked.substring(
        match.start,
        bodyClose == -1 ? masked.length : bodyClose,
      );
      final RegExpMatch? generated = RegExp(
        '_\\\$_?${RegExp.escape(public)}(?:FromJson|ToJson)?(?![A-Za-z0-9_])',
      ).firstMatch(declaration);
      if (generated != null) {
        serializer = 'generated code it refers to (${generated.group(0)})';
      }
    }
    if (serializer == null) continue;
    yield 'DV-ADOPT-003: $declared at $rel:${_lineOf(masked, stack[dvModel].$2)} '
        'is annotated @DVModel and already has a generated serializer: '
        '$serializer. Dartvel generates the model\'s serialization, and two '
        'serializers for one type disagree as data rather than as an error. '
        'Remove @DVModel to keep the class as it is, or remove the '
        'serializer to make it a Dartvel model.';
  }
}

/// The annotations directly above the declaration starting at [at], as
/// `(name, offset)` from the top, in [masked] source.
List<(String, int)> _annotationsBefore(String masked, int at) {
  final List<(String, int)> found = <(String, int)>[];
  int i = at;
  while (true) {
    int j = i - 1;
    while (j >= 0 && _isSpace(masked.codeUnitAt(j))) {
      j -= 1;
    }
    if (j < 0) break;
    int nameEnd = j + 1;
    if (masked[j] == ')') {
      final int open = _matchingOpenBackward(masked, j);
      if (open == -1) break;
      j = open - 1;
      while (j >= 0 && _isSpace(masked.codeUnitAt(j))) {
        j -= 1;
      }
      nameEnd = j + 1;
    }
    int k = j;
    while (k >= 0 && _isNameChar(masked.codeUnitAt(k))) {
      k -= 1;
    }
    if (k < 0 || masked[k] != '@' || k == j) break;
    final String qualified = masked.substring(k + 1, nameEnd);
    // `@DVModel.sensitiveField()` is a field annotation; only the class-level
    // `@DVModel(...)` makes a model. A prefixed import (`@fz.freezed`) is
    // named by its last part.
    final String name = qualified.startsWith('DVModel.')
        ? qualified
        : qualified.split('.').last;
    found.insert(0, (name, k));
    i = k;
  }
  return found;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isNameChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == 0x24 ||
    c == 0x2E;

/// Named arguments at depth zero between [open] and [close], as the span of
/// each value.
Map<String, (int, int)> _namedArgs(String masked, int open, int close) {
  final Map<String, (int, int)> args = <String, (int, int)>{};
  int start = open + 1;
  int depth = 0;
  void take(int end) {
    final RegExpMatch? named = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:')
        .firstMatch(masked.substring(start, end));
    if (named != null) {
      args[named.group(1)!] = (start + named.end, end);
    }
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
  return args;
}

int _matchingClose(String masked, int open) {
  final String o = masked[open];
  final String c = o == '(' ? ')' : o == '[' ? ']' : '}';
  int depth = 0;
  for (int i = open; i < masked.length; i += 1) {
    if (masked[i] == o) depth += 1;
    if (masked[i] == c) {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _matchingOpenBackward(String masked, int close) {
  int depth = 0;
  for (int i = close; i >= 0; i -= 1) {
    if (masked[i] == ')') depth += 1;
    if (masked[i] == '(') {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// [source] with every comment replaced by spaces, newlines kept, so offsets
/// and line numbers are unchanged. String literals are stepped over, so a
/// `//` inside a URL is not a comment.
String dvBlankComments(String source) => _scan(source, blankStrings: false);

/// [source] with the contents of every string literal replaced by spaces,
/// quotes and interpolated expressions kept. Apply to comment-blanked source.
String dvBlankStrings(String source) => _scan(source, blankStrings: true);

String _scan(String s, {required bool blankStrings}) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  String blank(String text) => text.replaceAll(RegExp(r'[^\n]'), ' ');
  // Declared ahead of both: a string can hold interpolated code, and code
  // holds strings.
  late final int Function(int start, {required bool untilBrace}) code;

  // Returns the index after the string starting at [i] (at the quote, after
  // any `r`), writing it to [out].
  int string(int i, bool raw) {
    final String q = s[i];
    final bool triple = s.startsWith('$q$q$q', i);
    final String close = triple ? '$q$q$q' : q;
    out.write(close);
    int j = i + close.length;
    while (j < s.length) {
      if (s.startsWith(close, j)) {
        out.write(close);
        return j + close.length;
      }
      final String c = s[j];
      if (!triple && c == '\n') {
        // An unterminated single-line string ends at the line.
        out.write(c);
        return j + 1;
      }
      if (!raw && c == r'\' && j + 1 < s.length) {
        out.write(blankStrings ? '  ' : s.substring(j, j + 2));
        j += 2;
        continue;
      }
      if (!raw && c == r'$' && j + 1 < s.length && s[j + 1] == '{') {
        // Interpolated code is code: keep it, strings inside it included.
        out.write(r'${');
        j = code(j + 2, untilBrace: true);
        continue;
      }
      out.write(blankStrings ? blank(c) : c);
      j += 1;
    }
    return j;
  }

  code = (int start, {required bool untilBrace}) {
    int j = start;
    int depth = 0;
    while (j < s.length) {
      final String c = s[j];
      if (untilBrace) {
        if (c == '{') depth += 1;
        if (c == '}') {
          if (depth == 0) {
            out.write('}');
            return j + 1;
          }
          depth -= 1;
        }
      }
      if (s.startsWith('//', j)) {
        final int end = s.indexOf('\n', j);
        final int stop = end == -1 ? s.length : end;
        out.write(blankStrings ? s.substring(j, stop) : blank(s.substring(j, stop)));
        j = stop;
        continue;
      }
      if (s.startsWith('/*', j)) {
        int nest = 0;
        int k = j;
        while (k < s.length) {
          if (s.startsWith('/*', k)) {
            nest += 1;
            k += 2;
          } else if (s.startsWith('*/', k)) {
            nest -= 1;
            k += 2;
            if (nest == 0) break;
          } else {
            k += 1;
          }
        }
        out.write(blankStrings ? s.substring(j, k) : blank(s.substring(j, k)));
        j = k;
        continue;
      }
      if (c == "'" || c == '"') {
        j = string(j, false);
        continue;
      }
      if (c == 'r' &&
          j + 1 < s.length &&
          (s[j + 1] == "'" || s[j + 1] == '"') &&
          (j == 0 || !_isNameChar(s.codeUnitAt(j - 1)))) {
        out.write('r');
        j = string(j + 1, true);
        continue;
      }
      out.write(c);
      j += 1;
    }
    return j;
  };

  i = code(0, untilBrace: false);
  assert(i >= s.length);
  return out.toString();
}

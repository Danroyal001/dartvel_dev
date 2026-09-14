/// The capabilities a module's code uses, read from the code.
///
/// The manifest is not a promise a module makes about itself: publishing
/// derives the list from this and refuses when the declaration disagrees, and
/// mounting checks this against the parent's grant. So what matters is not
/// finding the obvious call, it is not seeing less than the compiler does --
/// a use this misses is a use nobody is ever asked to grant.
///
/// It is a lexical analysis, the same kind the secrets check is: it knows
/// Dart's comments and strings exactly, and it knows the call shapes Dartvel
/// owns. It does not follow values through variables. Where a capability's
/// target is not a literal -- a URL, a secret name or a path built at runtime
/// -- the use is reported as unresolved rather than dropped, because a domain
/// the build cannot see is a domain nobody can grant.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'capabilities.dart';

/// One place in a module's code.
class DVModuleCodeUse {
  const DVModuleCodeUse({
    required this.file,
    required this.line,
    required this.what,
  });

  /// Relative to the module's project, with forward slashes.
  final String file;
  final int line;
  final String what;

  @override
  String toString() => '$file:$line: $what';
}

/// What a module's code reaches past its own boundary with.
class DVModuleCodeAnalysis {
  const DVModuleCodeAnalysis({
    required this.uses,
    this.ownNetwork = const <DVModuleCodeUse>[],
    this.unresolved = const <DVModuleCodeUse>[],
  });

  /// Every capability the code uses whose target is a literal.
  final DVModuleCapabilities uses;

  /// Connections the module opens itself instead of through a generated or
  /// Dartvel-owned call: DV-MODULE-008.
  final List<DVModuleCodeUse> ownNetwork;

  /// Uses whose target the build cannot read.
  final List<DVModuleCodeUse> unresolved;
}

/// A Dart source with its comments blanked ([code]), and with its comments and
/// string literals blanked ([masked]).
///
/// Both are the source's length, with every newline kept, so an offset found
/// in one is the same place in the other and in the original.
class DVDartSourceView {
  const DVDartSourceView(this.code, this.masked);

  final String code;
  final String masked;
}

const int _newline = 10;
const int _return = 13;
const int _space = 32;
const int _slash = 47;
const int _star = 42;
const int _backslash = 92;
const int _dollar = 36;
const int _lbrace = 123;
const int _rbrace = 125;
const int _single = 39;
const int _double = 34;

/// Splits [source] into what the analysis may read as code.
DVDartSourceView dvDartSourceView(String source) {
  final int n = source.length;
  final List<int> code = List<int>.of(source.codeUnits);
  final List<int> masked = List<int>.of(source.codeUnits);

  void blank(List<int> target, int from, int to) {
    for (var i = from; i < to && i < n; i++) {
      if (target[i] != _newline && target[i] != _return) target[i] = _space;
    }
  }

  var i = 0;
  while (i < n) {
    final int c = source.codeUnitAt(i);
    if (c == _slash && i + 1 < n) {
      final int next = source.codeUnitAt(i + 1);
      if (next == _slash) {
        final int end = _lineEnd(source, i);
        blank(code, i, end);
        blank(masked, i, end);
        i = end;
        continue;
      }
      if (next == _star) {
        final int end = _blockCommentEnd(source, i);
        blank(code, i, end);
        blank(masked, i, end);
        i = end;
        continue;
      }
    }
    final _StringStart? start = _stringStartAt(source, i);
    if (start != null) {
      final int end = _stringEnd(source, start);
      blank(masked, i, end);
      i = end;
      continue;
    }
    i++;
  }
  return DVDartSourceView(
    String.fromCharCodes(code),
    String.fromCharCodes(masked),
  );
}

class _StringStart {
  const _StringStart(this.at, this.quote, this.raw, this.triple);

  /// Where the literal begins, prefix included.
  final int at;

  /// Index of the first quote character.
  final int quote;
  final bool raw;
  final bool triple;

  int get contentStart => quote + (triple ? 3 : 1);
}

bool _identifierUnit(int u) =>
    (u >= 48 && u <= 57) ||
    (u >= 65 && u <= 90) ||
    (u >= 97 && u <= 122) ||
    u == 95 ||
    u == _dollar;

_StringStart? _stringStartAt(String s, int i) {
  final int n = s.length;
  int quote = i;
  var raw = false;
  final int c = s.codeUnitAt(i);
  if ((c == 114 || c == 82) &&
      i + 1 < n &&
      (s.codeUnitAt(i + 1) == _single || s.codeUnitAt(i + 1) == _double) &&
      (i == 0 || !_identifierUnit(s.codeUnitAt(i - 1)))) {
    raw = true;
    quote = i + 1;
  } else if (c != _single && c != _double) {
    return null;
  }
  final int q = s.codeUnitAt(quote);
  final bool triple =
      quote + 2 < n &&
      s.codeUnitAt(quote + 1) == q &&
      s.codeUnitAt(quote + 2) == q;
  return _StringStart(i, quote, raw, triple);
}

/// The index just past the literal that [start] opens.
int _stringEnd(String s, _StringStart start) {
  final int n = s.length;
  final int q = s.codeUnitAt(start.quote);
  var j = start.contentStart;
  while (j < n) {
    final int u = s.codeUnitAt(j);
    if (!start.raw && u == _backslash) {
      j += 2;
      continue;
    }
    if (!start.raw &&
        u == _dollar &&
        j + 1 < n &&
        s.codeUnitAt(j + 1) == _lbrace) {
      j = _interpolationEnd(s, j + 2);
      continue;
    }
    if (start.triple) {
      if (u == q &&
          j + 2 < n &&
          s.codeUnitAt(j + 1) == q &&
          s.codeUnitAt(j + 2) == q) {
        return j + 3;
      }
    } else {
      if (u == q) return j + 1;
      if (u == _newline) return j;
    }
    j++;
  }
  return n;
}

/// The index just past the `}` closing an interpolation whose body starts at
/// [j], with the strings and comments inside it skipped.
int _interpolationEnd(String s, int j) {
  final int n = s.length;
  var depth = 1;
  while (j < n) {
    final int u = s.codeUnitAt(j);
    if (u == _slash && j + 1 < n && s.codeUnitAt(j + 1) == _slash) {
      j = _lineEnd(s, j);
      continue;
    }
    if (u == _slash && j + 1 < n && s.codeUnitAt(j + 1) == _star) {
      j = _blockCommentEnd(s, j);
      continue;
    }
    final _StringStart? nested = _stringStartAt(s, j);
    if (nested != null) {
      j = _stringEnd(s, nested);
      continue;
    }
    if (u == _lbrace) depth++;
    if (u == _rbrace) {
      depth--;
      if (depth == 0) return j + 1;
    }
    j++;
  }
  return n;
}

int _lineEnd(String s, int i) {
  final int end = s.indexOf('\n', i);
  return end < 0 ? s.length : end;
}

/// Block comments nest in Dart.
int _blockCommentEnd(String s, int i) {
  final int n = s.length;
  var depth = 0;
  var j = i;
  while (j < n) {
    if (j + 1 < n &&
        s.codeUnitAt(j) == _slash &&
        s.codeUnitAt(j + 1) == _star) {
      depth++;
      j += 2;
      continue;
    }
    if (j + 1 < n &&
        s.codeUnitAt(j) == _star &&
        s.codeUnitAt(j + 1) == _slash) {
      depth--;
      j += 2;
      if (depth == 0) return j;
      continue;
    }
    j++;
  }
  return n;
}

/// The value of the string literal starting at or after [offset] in [code],
/// when it is one plain literal.
///
/// Null when the argument is not a literal, or is a literal the build cannot
/// read the value of: interpolated, escaped, or joined to another string by
/// adjacency or `+`. `'https://api.stripe.com' '.evil.example'` is one string
/// to the compiler, and reading the first half as the host would grant a
/// domain the code never calls.
String? _literalAt(String code, int offset) {
  var i = offset;
  while (i < code.length && _isSpace(code.codeUnitAt(i))) {
    i++;
  }
  if (i >= code.length) return null;
  final _StringStart? start = _stringStartAt(code, i);
  if (start == null) return null;
  final int end = _stringEnd(code, start);
  final int closeLength = start.triple ? 3 : 1;
  if (end - closeLength < start.contentStart) return null;
  final String content = code.substring(start.contentStart, end - closeLength);
  if (!start.raw && (content.contains(r'$') || content.contains(r'\'))) {
    return null;
  }
  if (content.contains('\n')) return null;
  var after = end;
  while (after < code.length && _isSpace(code.codeUnitAt(after))) {
    after++;
  }
  if (after < code.length) {
    final int next = code.codeUnitAt(after);
    if (next == 43 || _stringStartAt(code, after) != null) return null;
  }
  return content;
}

bool _isSpace(int u) => u == _space || u == _newline || u == _return || u == 9;

/// The host an absolute URL literal calls, or null when it is not one.
String? _hostOf(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (!const <String>['http', 'https', 'ws', 'wss'].contains(uri.scheme)) {
    return null;
  }
  return dvNormaliseEgressDomain(uri.host);
}

final RegExp _secretCall = RegExp(
  r'(?:\bDV\s*\.\s*Secrets|\bDVSecrets\s*\(\s*\))\s*\.\s*(?:get|maybeGet|getOr|has)\s*\(',
);
final RegExp _bearerSecret = RegExp(r'\bbearerSecret\s*:');
final RegExp _httpCall = RegExp(
  r'(?:\bDV\s*\.\s*Http|\bDVHttp\s*\(\s*\))\s*\.\s*(get|head|delete|post|put|patch|send)\s*\(',
);
final RegExp _baseUrl = RegExp(r'\bbaseUrl\s*:');
final RegExp _uriParse = RegExp(r'^\s*Uri\s*\.\s*(?:parse|tryParse)\s*\(');
final RegExp _uriBuild = RegExp(r'^\s*Uri\s*\.\s*(?:https|http)\s*\(');
final RegExp _rawSql = RegExp(
  r'(?:\bDV\s*\.\s*DB|\bDVDatabase\s*\(\s*\))\s*\.\s*(?:query|execute)\s*\(',
);
final RegExp _nativeImport = RegExp(
  r'''\b(?:import|export)\s+(['"])(?:dart:ffi|package:jni/[^'"]*)\1''',
);
final RegExp _nativeCall = RegExp(
  r'\bDynamicLibrary\s*\.\s*(?:open|process|executable)\s*\(|@\s*(?:ffi\s*\.\s*)?Native\s*<',
);
final RegExp _fileCall = RegExp(r'(?<![\w$])(?:File|Directory|Link)\s*\(');
final RegExp _cron = RegExp(
  r'@\s*DV(?:Backend|Client)Cron\s*\(|\bDVScheduler\s*\(',
);
final RegExp _ownNetworkCall = RegExp(
  r'(?<![\w$])(?:HttpClient\s*\(|IOClient\s*\('
  r'|(?:Raw)?(?:Secure)?Socket\s*\.\s*(?:connect|startConnect)\s*\('
  r'|RawDatagramSocket\s*\.\s*bind\s*\('
  r'|(?:Raw)?(?:Secure)?ServerSocket\s*\.\s*bind\s*\('
  r'|HttpServer\s*\.\s*(?:bind|bindSecure)\s*\('
  r'|WebSocket\s*\.\s*connect\s*\()',
);
final RegExp _ownNetworkImport = RegExp(
  r'''\b(?:import|export)\s+(['"])package:(?:http|web_socket_channel|dio)/[^'"]*\1''',
);

/// Analyses [files], path to source, and the module's `dartvel` pubspec
/// section.
DVModuleCodeAnalysis dvAnalyseModuleSources(
  Map<String, String> files, {
  Map<Object?, Object?> dartvel = const <Object?, Object?>{},
}) {
  final Set<String> secrets = <String>{};
  final Set<String> egress = <String>{};
  final Set<String> filesystem = <String>{};
  var rawSql = false;
  var nativeBindings = false;
  var cron = false;
  final List<DVModuleCodeUse> ownNetwork = <DVModuleCodeUse>[];
  final List<DVModuleCodeUse> unresolved = <DVModuleCodeUse>[];

  final List<String> paths = files.keys.toList()..sort();
  for (final String path in paths) {
    final String source = files[path]!;
    final DVDartSourceView view = dvDartSourceView(source);
    int lineOf(int offset) =>
        '\n'.allMatches(source.substring(0, offset)).length + 1;
    void unresolvedAt(int offset, String what) => unresolved.add(
      DVModuleCodeUse(file: path, line: lineOf(offset), what: what),
    );

    for (final RegExpMatch m in _secretCall.allMatches(view.masked)) {
      final String? name = _literalAt(view.code, m.end);
      if (name == null || name.isEmpty) {
        unresolvedAt(m.start, 'a secret named at runtime');
      } else {
        secrets.add(name);
      }
    }
    for (final RegExpMatch m in _bearerSecret.allMatches(view.masked)) {
      final String? name = _literalAt(view.code, m.end);
      if (name == null || name.isEmpty) {
        unresolvedAt(m.start, 'a bearer secret named at runtime');
      } else {
        secrets.add(name);
      }
    }

    for (final RegExpMatch m in _httpCall.allMatches(view.masked)) {
      final String? host =
          _hostOfArgument(view.code, m.end) ??
          // `send` takes the method first and the URL second.
          (m.group(1) == 'send' ? _hostOfSecondArgument(view, m.end) : null);
      if (host == null) {
        unresolvedAt(m.start, 'egress to a URL built at runtime');
      } else {
        egress.add(host);
      }
    }
    for (final RegExpMatch m in _baseUrl.allMatches(view.masked)) {
      final String? url = _literalAt(view.code, m.end);
      final String? host = url == null ? null : _hostOf(url);
      if (host == null) {
        unresolvedAt(m.start, 'egress to a base URL built at runtime');
      } else {
        egress.add(host);
      }
    }

    if (_rawSql.hasMatch(view.masked)) rawSql = true;
    if (_nativeImport.hasMatch(view.code) ||
        _nativeCall.hasMatch(view.masked)) {
      nativeBindings = true;
    }
    if (_cron.hasMatch(view.masked)) cron = true;

    for (final RegExpMatch m in _fileCall.allMatches(view.masked)) {
      final String? path = _literalAt(view.code, m.end);
      final String? root = path == null ? null : _rootOf(path);
      if (root == null) {
        unresolvedAt(m.start, 'a filesystem path built at runtime');
      } else {
        filesystem.add(root);
      }
    }

    for (final RegExpMatch m in _ownNetworkCall.allMatches(view.masked)) {
      ownNetwork.add(
        DVModuleCodeUse(
          file: path,
          line: lineOf(m.start),
          what: m.group(0)!.replaceAll(RegExp(r'\s+'), ''),
        ),
      );
    }
    for (final RegExpMatch m in _ownNetworkImport.allMatches(view.code)) {
      ownNetwork.add(
        DVModuleCodeUse(file: path, line: lineOf(m.start), what: m.group(0)!),
      );
    }
  }

  // Hosts declared in the module's own pubspec are called through DV.Http
  // by name, so the name is in the code and the domain is here.
  final Object? http = dartvel['http'];
  final Object? hosts = http is Map ? http['hosts'] : null;
  if (hosts is Map) {
    for (final MapEntry<Object?, Object?> entry in hosts.entries) {
      final Object? body = entry.value;
      if (body is! Map) continue;
      final Object? baseUrl = body['baseUrl'];
      final String? host = baseUrl is String ? _hostOf(baseUrl) : null;
      if (host == null) {
        unresolved.add(
          DVModuleCodeUse(
            file: 'pubspec.yaml',
            line: 0,
            what:
                'dartvel.http.hosts.${entry.key}.baseUrl is not an absolute URL',
          ),
        );
      } else {
        egress.add(host);
      }
      final Object? bearer = body['bearerSecret'];
      if (bearer is String && bearer.isNotEmpty) secrets.add(bearer);
    }
  }

  return DVModuleCodeAnalysis(
    uses: DVModuleCapabilities(
      secrets: secrets,
      rawSql: rawSql,
      nativeBindings: nativeBindings,
      egress: egress,
      filesystem: filesystem,
      cron: cron,
    ),
    ownNetwork: ownNetwork,
    unresolved: unresolved,
  );
}

String? _hostOfArgument(String code, int offset) {
  final String rest = code.substring(offset);
  final RegExpMatch? parse = _uriParse.firstMatch(rest);
  if (parse != null) {
    final String? url = _literalAt(code, offset + parse.end);
    return url == null ? null : _hostOf(url);
  }
  final RegExpMatch? build = _uriBuild.firstMatch(rest);
  if (build != null) {
    final String? authority = _literalAt(code, offset + build.end);
    if (authority == null) return null;
    return _hostOf('https://$authority');
  }
  final String? url = _literalAt(code, offset);
  return url == null ? null : _hostOf(url);
}

/// The host of the argument after the first, found by the first top-level
/// comma in [view.masked], where strings cannot contain one.
String? _hostOfSecondArgument(DVDartSourceView view, int offset) {
  var depth = 0;
  for (var i = offset; i < view.masked.length; i++) {
    final String c = view.masked[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return null;
      depth--;
    }
    if (c == ',' && depth == 0) return _hostOfArgument(view.code, i + 1);
  }
  return null;
}

/// The named root of a literal path: its first segment, with a leading slash
/// kept for an absolute one. Null when the path climbs out or is empty.
String? _rootOf(String path) {
  if (path.isEmpty || path.contains(r'\')) return null;
  final bool absolute = path.startsWith('/');
  final List<String> segments = p.posix
      .normalize(path)
      .split('/')
      .where((String s) => s.isNotEmpty && s != '.')
      .toList();
  if (segments.isEmpty) return absolute ? '/' : null;
  if (segments.first == '..') return null;
  return absolute ? '/${segments.first}' : segments.first;
}

/// Analyses the module project at [moduleRoot]: every Dart file under `lib`,
/// `bin` and `hook`, generated or not, and its pubspec.
///
/// Nothing that looks generated is skipped. An installed module's generated
/// files came from its publisher like the rest of it, so skipping
/// `lib/dartvel_client/` or `*.g.dart` would be a directory where a socket is
/// never asked about.
DVModuleCodeAnalysis dvAnalyseModuleProject(String moduleRoot) {
  final Map<String, String> files = <String, String>{};
  for (final String dir in const <String>['lib', 'bin', 'hook']) {
    final Directory directory = Directory(p.join(moduleRoot, dir));
    if (!directory.existsSync()) continue;
    for (final FileSystemEntity entity in directory.listSync(
      recursive: true,
      followLinks: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String rel = p
          .relative(entity.path, from: moduleRoot)
          .replaceAll(r'\', '/');
      files[rel] = entity.readAsStringSync();
    }
  }
  return dvAnalyseModuleSources(
    files,
    dartvel: dvModuleDartvelSection(moduleRoot),
  );
}

/// The `dartvel` section of the pubspec at [root], or an empty map.
Map<Object?, Object?> dvModuleDartvelSection(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return const <Object?, Object?>{};
  try {
    final Object? doc = loadYaml(file.readAsStringSync());
    final Object? section = doc is Map ? doc['dartvel'] : null;
    return section is Map ? section : const <Object?, Object?>{};
  } on Object {
    return const <Object?, Object?>{};
  }
}

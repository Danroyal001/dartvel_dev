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

import '../analysis/dart_source_lexer.dart';
import 'capabilities.dart';

export '../analysis/dart_source_lexer.dart'
    show DVDartSourceView, dvDartSourceView;

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

/// The host an absolute URL literal calls, or null when it is not one.
String? _hostOf(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (!const <String>['http', 'https', 'ws', 'wss'].contains(uri.scheme)) {
    return null;
  }
  return dvNormaliseEgressDomain(uri.host);
}

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

    for (final RegExpMatch m in dvSecretReadCall.allMatches(view.masked)) {
      final String? name = dvDartStringLiteralAt(view.code, m.end);
      if (name == null || name.isEmpty) {
        unresolvedAt(m.start, 'a secret named at runtime');
      } else {
        secrets.add(name);
      }
    }
    for (final RegExpMatch m in _bearerSecret.allMatches(view.masked)) {
      final String? name = dvDartStringLiteralAt(view.code, m.end);
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
      if (_registersGeneratedBackend(view.masked, m.start, m.end)) continue;
      final String? url = dvDartStringLiteralAt(view.code, m.end);
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
      final String? path = dvDartStringLiteralAt(view.code, m.end);
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

final RegExp _generatedBackendValue = RegExp(
  r'^\s*\(\s*\)\s*=>\s*DartvelRuntime\s*\.\s*baseUrl\b',
);
final RegExp _registerRuntimeCallee = RegExp(
  r'\bDV\s*\.\s*registerRuntime\s*$',
);

/// Whether the `baseUrl:` between [start] and [end] is the generated
/// runtime handing DV its own backend: `DV.registerRuntime(baseUrl: () =>
/// DartvelRuntime.baseUrl, ...)`, which every generated client writes.
///
/// That address is the application's backend, which a module reaches through
/// the calls Dartvel generates for it and which no grant names. Both halves
/// are required: the same value given to a declared host is a host the build
/// cannot read, and a registration pointed at anything else redirects every
/// generated call.
bool _registersGeneratedBackend(String masked, int start, int end) {
  if (!_generatedBackendValue.hasMatch(masked.substring(end))) return false;
  var depth = 0;
  for (var i = start - 1; i >= 0; i--) {
    final String c = masked[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) {
        return c == '(' &&
            _registerRuntimeCallee.hasMatch(masked.substring(0, i));
      }
      depth--;
    }
  }
  return false;
}

String? _hostOfArgument(String code, int offset) {
  final String rest = code.substring(offset);
  final RegExpMatch? parse = _uriParse.firstMatch(rest);
  if (parse != null) {
    final String? url = dvDartStringLiteralAt(code, offset + parse.end);
    return url == null ? null : _hostOf(url);
  }
  final RegExpMatch? build = _uriBuild.firstMatch(rest);
  if (build != null) {
    final String? authority = dvDartStringLiteralAt(code, offset + build.end);
    if (authority == null) return null;
    return _hostOf('https://$authority');
  }
  final String? url = dvDartStringLiteralAt(code, offset);
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

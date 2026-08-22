import 'dart:io';
import 'package:path/path.dart' as p;

class RouteUtils {
  static String routeFor(String rel, String pagesDir) {
    var path = rel
        .replaceFirst(RegExp('^$pagesDir/?'), '')
        .replaceAll('\\', '/');
    path = path
        .replaceFirst(RegExp(r'\.page\.dart$'), '')
        .replaceFirst(RegExp(r'\.dart$'), '');

    // Validation
    if (path.contains('[') && !path.contains(']')) {
      throw FormatException('Unclosed parameter bracket in path: $rel');
    }
    if (path.contains(']') && !path.contains('[')) {
      throw FormatException('Unopened parameter bracket in path: $rel');
    }

    // index at root → '/'
    if (path == 'index') return '/';
    // strip group folders
    path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (m) => '');
    // dynamic and catch-all segments
    path = path.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
      final seg = m.group(1)!;
      if (seg.contains('...') && !seg.startsWith('...')) {
        throw FormatException(
          'Malformed catch-all parameter (ellipsis must be at start): $rel',
        );
      }
      if (seg.startsWith('...')) return '*${seg.substring(3)}';
      return ':$seg';
    });
    // support nested index: foo/index → /foo
    path = path.replaceFirst(RegExp(r'/index$'), '');
    if (path.isEmpty) return '/';
    return '/$path';
  }

  static String patternToRegex(String pattern) {
    final esc = pattern.replaceAllMapped(
      RegExp(r'([.+*?^${}()\[\]|\\])'),
      (m) => '\\${m[1]}',
    );
    final named = esc.replaceAllMapped(
      RegExp(r':([a-zA-Z0-9_]+)'),
      (m) => '(?<${m[1]!}>[^/]+)',
    );
    return '^$named\$';
  }

  static Map<String, String> parseEnvFile(String path, String root) {
    final file = File(p.join(root, path));
    final out = <String, String>{};
    if (!file.existsSync()) return out;
    final lines = file.readAsLinesSync();
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var val = line.substring(eq + 1).trim();
      // strip quotes
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      out[key] = val;
    }
    return out;
  }

  static String obfuscate(String value) {
    final key = DateTime.now().millisecondsSinceEpoch % 255;
    final chars = value.codeUnits;
    final xored = chars.map((c) => c ^ key).toList();
    return 'const [${xored.join(', ')}], $key';
  }

  static String routeFromRel(String rel, String backendDir) {
    // rel like lib/backend/functions/blog/[id].get.dart
    // Normalised first, and on both sides: stripping the prefix before
    // normalising cannot work when `rel` uses backslashes and `backendDir`
    // does not. Mirrors dartvel_cli's copy of this function.
    final normalisedRel = rel.replaceAll(r'\', '/');
    final normalisedBackendDir = backendDir.replaceAll(r'\', '/');
    var path = normalisedRel.replaceFirst(
      RegExp('^$normalisedBackendDir/functions/?'),
      '',
    );
    // strip group folders (parentheses)
    path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (_) => '');
    // strip extension .dart and method suffix
    if (path.endsWith('.dart')) path = path.substring(0, path.length - 5);
    // split last segment by '.' to separate name and method
    final lastSlash = path.lastIndexOf('/');
    final dir = lastSlash == -1 ? '' : path.substring(0, lastSlash);
    final base = lastSlash == -1 ? path : path.substring(lastSlash + 1);
    final dot = base.lastIndexOf('.');
    final name = dot == -1 ? base : base.substring(0, dot);

    final dirConv = dir
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(segConv)
        .join('/');
    final nameConv = (name == 'index') ? '' : segConv(name);
    final combined = [dirConv, nameConv].where((s) => s.isNotEmpty).join('/');
    return combined.isEmpty ? '' : '/$combined';
  }

  static String segConv(String s) {
    return s.replaceAllMapped(
      RegExp(r'\[(\.\.\.)?([^\]]+)\]'),
      (m) => m[1] == '...' ? '<${m[2] ?? ''}|.*>' : '<${m[2] ?? ''}>',
    );
  }

  static String toColonPath(String pth) {
    return pth
        .replaceAllMapped(
          RegExp(r'<([^>|]+)\|\. *>').pattern == ''
              ? RegExp('')
              : RegExp(r'<([^>|]+)\|\. *>'),
          (m) => ':${m.group(1)!}',
        )
        .replaceAllMapped(RegExp(r'<([^>]+)>'), (m) => ':${m.group(1)!}');
  }

  static String toUpperCamel(String s) {
    final parts = s.split(RegExp(r'[_]+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join();
  }

  static String funcNameForFromUrl(String method, String urlPath) {
    var pth = urlPath.replaceAll(RegExp(r'^/+'), '');
    pth = pth.replaceAllMapped(
      RegExp(r'<([^>|]+)\|\.*>'),
      (m) => 'by_${m.group(1)!}',
    );
    pth = pth.replaceAllMapped(
      RegExp(r'<([^>]+)>'),
      (m) => 'by_${m.group(1)!}',
    );
    pth = pth.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    pth = pth.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final base = pth.isEmpty ? 'root' : pth;
    return '${method.toLowerCase()}${toUpperCamel(base)}';
  }

  static String paramsListFor(String colonPath) {
    final names = RegExp(
      r':([a-zA-Z0-9_]+)',
    ).allMatches(colonPath).map((m) => m.group(1)!).toList();
    if (names.isEmpty) return '';
    return names.map((n) => 'required String $n').join(', ');
  }

  static String coerce(String name, String type) {
    final src =
        "(req.params['$name'] ?? req.url.queryParameters['$name'] ?? ((body is Map) ? (body['$name']) : null))";
    final t = type.replaceAll('?', '').trim();
    if (t == 'String' || t.isEmpty || t == 'dynamic') {
      return '(($src)?.toString() ?? "")';
    }
    if (t == 'int') {
      return '((){ final v = $src; if (v is int) return v; return int.tryParse((v)?.toString() ?? "") ?? 0; }())';
    }
    if (t == 'double') {
      return '((){ final v = $src; if (v is double) return v; return double.tryParse((v)?.toString() ?? "") ?? 0.0; }())';
    }
    if (t == 'bool') {
      return '((){ final s = ($src )?.toString().toLowerCase() ?? ""; return s=="true"||s=="1"||s=="1"||s=="yes"; }())';
    }
    if (t.startsWith('List<String>')) {
      return '((){ final v = $src; if (v is List) return v.map((e)=>e.toString()).toList(); final s = (v)?.toString() ?? ""; if (s.isEmpty) return <String>[]; return s.contains("/") ? s.split("/") : s.split(","); }())';
    }
    if (t.endsWith('Request') || t.endsWith('RequestType')) return 'req';
    return src; // fallback
  }

  static void extractParams(
    String rawFull,
    Function(String, String) onParam, {
    Function(String)? onNamed,
  }) {
    if (rawFull.contains('{') && onNamed != null) onNamed('1');
    final raw = rawFull.replaceAll(RegExp(r'[\{\}\[\]]'), '');
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final pstr0 in parts) {
      var pstr = pstr0.replaceAll(RegExp(r'^required\s+'), '');
      // strip default value
      final eq = pstr.indexOf('=');
      if (eq != -1) pstr = pstr.substring(0, eq).trim();
      final toks = pstr
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (toks.isEmpty) continue;
      final nameTok = toks.last.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
      final typeTok =
          (toks.length > 1
                  ? toks.sublist(0, toks.length - 1).join(' ')
                  : 'dynamic')
              .trim();
      if (nameTok.isEmpty) continue;
      onParam(nameTok, typeTok);
    }
  }
}

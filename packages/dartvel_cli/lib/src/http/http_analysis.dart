/// DV-HTTP-001 and DV-HTTP-005: outbound HTTP the build can see is wrong.
///
/// DV-HTTP-001 is a request to a host nobody declared -- by name, or by an
/// absolute URL no declared base URL covers. The running client refuses both
/// with the same code, so this is not the guarantee; it moves the refusal from
/// the first time a code path runs to the build.
///
/// DV-HTTP-005 is a declared host whose credential is a backend-scoped secret,
/// reached from client code. That is the DV-SECRETS-001 violation, raised
/// where it is introduced: a device cannot resolve the secret, so the request
/// fails there, and the fix somebody reaches for is making it resolvable.
///
/// Only what the source states is checked: a host name or URL written as one
/// plain literal. A URL assembled at runtime is a false negative here and a
/// DV-HTTP-001 refusal at runtime, which is why reporting a guess at it would
/// only add findings about URLs that may not exist.
library dartvel_cli.http.http_analysis;

import 'package:dartvel_core/dartvel.dart';

import '../analysis/dart_source_lexer.dart';
import '../secrets/secrets_analysis.dart';

/// A problem worth failing a build over.
class DVHttpFinding {
  const DVHttpFinding({
    required this.code,
    required this.file,
    required this.line,
    required this.message,
  });

  final String code;
  final String file;

  /// 1-based.
  final int line;
  final String message;

  @override
  String toString() => '$code $file:$line: $message';
}

const String _receiver = r'(?:\bDV\s*\.\s*Http|\bDVHttp\s*\(\s*\))\s*\.\s*';
final RegExp _hostCall = RegExp('${_receiver}host\\s*\\(');
final RegExp _urlCall =
    RegExp('$_receiver(get|head|delete|post|put|patch|send)\\s*\\(');
final RegExp _uriParse = RegExp(r'^\s*Uri\s*\.\s*(?:parse|tryParse)\s*\(');

/// Every finding in [clientFiles] and [backendFiles], ordered by file and line.
///
/// [clientFiles] is what the client bundle can reach -- lib/ minus the backend
/// directory and the generated client -- and is checked for both codes.
/// [backendFiles] is checked for DV-HTTP-001 only: a backend-scoped credential
/// used from the backend is the arrangement working.
List<DVHttpFinding> dvAnalyseHttp({
  required Map<String, DVHttpHostConfig> hosts,
  required Map<String, DVSecretDeclaration> secrets,
  required Map<String, String> clientFiles,
  Map<String, String> backendFiles = const <String, String>{},
}) {
  final List<DVHttpFinding> findings = <DVHttpFinding>[];

  void scan(String path, String source, {required bool client}) {
    final DVDartSourceView view = dvDartSourceView(source);

    void used(String host, int offset) {
      if (!client) return;
      final String? secret = hosts[host]!.bearerSecret;
      if (secret == null) return;
      // Undeclared is backend-scoped, as it is for DV.Secrets: a secret
      // nobody thought about must not be the one that ships.
      if (secrets[secret]?.scope == DVSecretScope.client) return;
      findings.add(DVHttpFinding(
        code: 'DV-HTTP-005',
        file: path,
        line: dvDartLineOf(source, offset),
        message: 'the declared host "$host" authenticates with "$secret", '
            'which is backend-scoped, and is used from client code. A device '
            'cannot resolve that secret, and a secret made resolvable there '
            'ships to every visitor. Call "$host" from a backend function, or '
            'declare the credential scope: client with a PUBLIC_ prefix if it '
            'is genuinely publishable.',
      ));
    }

    for (final RegExpMatch m in _hostCall.allMatches(view.masked)) {
      final String? name = dvDartStringLiteralAt(view.code, m.end);
      if (name == null || name.isEmpty) continue;
      if (!hosts.containsKey(name)) {
        findings.add(DVHttpFinding(
          code: 'DV-HTTP-001',
          file: path,
          line: dvDartLineOf(source, m.start),
          message: 'no host named "$name" is declared. Declare it under '
              'dartvel.http.hosts${_known(hosts)}.',
        ));
        continue;
      }
      used(name, m.start);
    }

    for (final RegExpMatch m in _urlCall.allMatches(view.masked)) {
      final int argument = m.group(1) == 'send'
          ? _secondArgument(view.masked, m.end) ?? -1
          : m.end;
      if (argument < 0) continue;
      final Uri? url = _urlAt(view.code, argument);
      if (url == null) continue;
      final String? host = DVHttp.coveringHost(hosts, url);
      if (host == null) {
        findings.add(DVHttpFinding(
          code: 'DV-HTTP-001',
          file: path,
          line: dvDartLineOf(source, m.start),
          message: 'no declared host covers '
              '${url.scheme}://${url.authority}${url.path}, so the request is '
              'refused when it runs. Declare its base URL under '
              'dartvel.http.hosts${_known(hosts)}.',
        ));
        continue;
      }
      used(host, m.start);
    }
  }

  for (final String path in clientFiles.keys.toList()..sort()) {
    scan(path, clientFiles[path]!, client: true);
  }
  for (final String path in backendFiles.keys.toList()..sort()) {
    scan(path, backendFiles[path]!, client: false);
  }
  findings.sort((DVHttpFinding a, DVHttpFinding b) {
    final int byFile = a.file.compareTo(b.file);
    return byFile != 0 ? byFile : a.line.compareTo(b.line);
  });
  return findings;
}

String _known(Map<String, DVHttpHostConfig> hosts) {
  if (hosts.isEmpty) return '; none are declared';
  final List<String> names = hosts.keys.toList()..sort();
  return ' (declared: ${names.join(', ')})';
}

/// The absolute http(s) URL written as the argument at [offset], directly or
/// through `Uri.parse`, or null when the build cannot read one there.
Uri? _urlAt(String code, int offset) {
  final RegExpMatch? parse = _uriParse.firstMatch(code.substring(offset));
  final String? text = dvDartStringLiteralAt(
      code, parse == null ? offset : offset + parse.end);
  if (text == null) return null;
  final Uri? url = Uri.tryParse(text);
  if (url == null || url.host.isEmpty) return null;
  if (url.scheme != 'http' && url.scheme != 'https') return null;
  return url;
}

/// The offset just after the first top-level comma from [offset] in
/// [masked], where strings and comments cannot contain one.
int? _secondArgument(String masked, int offset) {
  int depth = 0;
  for (int i = offset; i < masked.length; i++) {
    final String c = masked[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return null;
      depth--;
    }
    if (c == ',' && depth == 0) return i + 1;
  }
  return null;
}

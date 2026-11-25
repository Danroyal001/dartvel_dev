/// The application's own classes a backend function takes as parameters.
///
/// The client sends such an argument as JSON (it is encoded with the class's
/// `toJson`), so the generated route has to decode it with `fromJson` before
/// the function is called. Until it did, the function was handed the raw
/// decoded map and failed when it first used it as the class.
///
/// The route file imports nothing of the application's, so each class is
/// imported under an alias, from the file that declares it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'client_type_imports.dart';

/// Names the generated route already decodes or that are never a class the
/// application declares.
const Set<String> _notClasses = <String>{
  'String', 'int', 'double', 'num', 'bool', 'dynamic', 'Object', 'Map',
  'List', 'Set', 'Request', 'RequestType', 'DVContext', 'DateTime',
  'Duration', 'Uri', 'BigInt',
};

final RegExp _plainTypeName = RegExp(r'^[A-Z][A-Za-z0-9_$]*$');

/// The class a parameter of type [type] is decoded into: `OrderDraft`,
/// `OrderDraft?` and `List<OrderDraft>` all name `OrderDraft`. Null for a
/// primitive, a collection of primitives, a prefixed name or anything else
/// the route does not decode with `fromJson`.
String? dvDecodedClassName(String type) {
  String bare = type.trim();
  if (bare.endsWith('?')) bare = bare.substring(0, bare.length - 1).trim();
  if (bare.startsWith('List<') && bare.endsWith('>')) {
    bare = bare.substring(5, bare.length - 1).trim();
    if (bare.endsWith('?')) bare = bare.substring(0, bare.length - 1).trim();
  }
  if (!_plainTypeName.hasMatch(bare) || _notClasses.contains(bare)) {
    return null;
  }
  return bare;
}

/// For each class named by [types]: the package URI of the file that
/// declares it, among the files [source] imports and [source] itself
/// ([selfImport] is its package URI). A class with no `fromJson` there, an
/// enum, or a class declared nowhere the application owns is left out, and
/// the route keeps passing such a parameter through unchanged.
Map<String, String> dvBackendParameterClassImports({
  required String source,
  required String sourcePath,
  required String selfImport,
  required String projectRoot,
  required String packageName,
  required List<String> types,
  required Set<String> alreadyDecoded,
}) {
  final Map<String, String> found = <String, String>{};
  final String lib = p.join(projectRoot, 'lib');
  for (final String type in types) {
    final String? name = dvDecodedClassName(type);
    if (name == null || alreadyDecoded.contains(name) || found.containsKey(name)) {
      continue;
    }
    final List<String> candidates = <String>[
      ...dvClientTypeImports(
        source: source,
        sourcePath: sourcePath,
        projectRoot: projectRoot,
        packageName: packageName,
        types: <String>[name],
      ),
      selfImport,
    ];
    for (final String uri in candidates) {
      final String? text = uri == selfImport
          ? source
          : _readPackageFile(uri, lib: lib, packageName: packageName);
      if (text == null) continue;
      final bool isClass = RegExp(
        r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
        '(?:class)\\s+(?:const\\s+)?${RegExp.escape(name)}\\b',
        multiLine: true,
      ).hasMatch(text);
      final bool decodes = RegExp(
        '\\b${RegExp.escape(name)}\\s*\\.\\s*fromJson\\b',
      ).hasMatch(text);
      if (isClass && decodes) {
        found[name] = uri;
        break;
      }
    }
  }
  return found;
}

String? _readPackageFile(
  String uri, {
  required String lib,
  required String packageName,
}) {
  final String prefix = 'package:$packageName/';
  if (!uri.startsWith(prefix)) return null;
  final File file = File(
    p.joinAll(<String>[lib, ...uri.substring(prefix.length).split('/')]),
  );
  return file.existsSync() ? file.readAsStringSync() : null;
}

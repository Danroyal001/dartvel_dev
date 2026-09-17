/// `@DVBackendFunction(rawPath:)` and `(rawPathSuffix:)`, read from source.
///
/// Raw HTTP exposure stays on the backend function annotation: `rawPath`
/// serves the function at exactly that path, outside the API base path, and
/// `rawPathSuffix` keeps the generated path and appends to it. The two are
/// mutually exclusive.
library;

import 'annotation_args.dart';

/// What a backend function declares about its raw path.
class DVRawPath {
  const DVRawPath({this.rawPath, this.rawPathSuffix});

  /// The exact path the function is served at, or null.
  final String? rawPath;

  /// What is appended to the generated path, or null.
  final String? rawPathSuffix;
}

/// A literal path segment list: no parameters, no traversal, no empty segment.
final RegExp _servable = RegExp(r'^(/[A-Za-z0-9._~\-]+)+/?$');

/// The raw path [source]'s `@DVBackendFunction` declares.
///
/// Read literally, like `policy:`. A value that is not a string literal, or
/// not a path the router can serve as written, stops the build naming [rel]:
/// skipped, the function would be served at its generated path while the
/// annotation said somewhere else, and whatever calls the raw path would get
/// a 404 nobody could explain.
DVRawPath dvRawPathFromSource(String source, {required String rel}) {
  final String? args = dvAnnotationArgs(source, 'DVBackendFunction');
  if (args == null) return const DVRawPath();
  final String? rawPath = _literal(args, 'rawPath', rel);
  final String? suffix = _literal(args, 'rawPathSuffix', rel);
  if (rawPath != null && suffix != null) {
    throw StateError(
      '$rel declares both rawPath and rawPathSuffix on @DVBackendFunction. '
      'They are mutually exclusive: rawPath is the whole path, rawPathSuffix '
      'is added to the generated one. Keep one.',
    );
  }
  return DVRawPath(rawPath: rawPath, rawPathSuffix: suffix);
}

String? _literal(String args, String name, String rel) {
  final RegExpMatch? declared =
      RegExp('\\b$name\\s*:\\s*([^,)]*)').firstMatch(args);
  if (declared == null) return null;
  final String value = declared.group(1)!.trim();
  if (value == 'null') return null;
  final RegExpMatch? quoted =
      RegExp(r'''^(['"])(.*)\1$''').firstMatch(value);
  if (quoted == null) {
    throw StateError(
      '$rel declares @DVBackendFunction($name: $value). Write the path as a '
      "string literal, such as $name: '/payments/webhook', so the build can "
      'register it.',
    );
  }
  final String path = quoted.group(2)!;
  if (!_servable.hasMatch(path) || path.split('/').contains('..')) {
    throw StateError(
      "$rel declares @DVBackendFunction($name: '$path'), which is not a path "
      'Dartvel serves: it must start with /, and its segments may hold '
      'letters, digits and . _ ~ - only. Path parameters are not supported '
      'in a raw path.',
    );
  }
  return path;
}

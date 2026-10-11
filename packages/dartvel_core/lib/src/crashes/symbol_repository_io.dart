import 'dart:convert';
import 'dart:io';

import 'symbols.dart';

/// Symbols as files: `<directory>/<release>/<file>`.
///
/// Written to a temporary name and renamed, so a reader never sees half a
/// mapping and a crash of the server mid-upload leaves the previous file (or
/// none), not a truncated one that reads as a valid mapping with fewer
/// classes.
class DVDirectorySymbolRepository implements DVSymbolRepository {
  DVDirectorySymbolRepository(this.directory);

  final String directory;

  File? _file(String release, String name) {
    if (!dvSymbolReleaseOk(release) || !dvSymbolFileNameOk(name)) return null;
    return File('$directory/$release/$name');
  }

  @override
  Future<void> putFile(String release, String name, List<int> bytes) async {
    final File? target = _file(release, name);
    if (target == null) {
      throw ArgumentError('not a symbols path: $release/$name');
    }
    await target.parent.create(recursive: true);
    final File partial = File('${target.path}.partial-$pid-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(target.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  @override
  Future<List<int>?> readFile(String release, String name) async {
    final File? target = _file(release, name);
    if (target == null || !await target.exists()) return null;
    return target.readAsBytes();
  }

  @override
  Future<void> putManifest(DVSymbolsManifest manifest) => putFile(
      manifest.release,
      DVSymbolsManifest.fileName,
      utf8.encode(jsonEncode(manifest.toJson())));

  @override
  Future<DVSymbolsManifest?> manifest(String release) async {
    final List<int>? bytes = await readFile(release, DVSymbolsManifest.fileName);
    if (bytes == null) return null;
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      return json is Map
          ? DVSymbolsManifest.fromJson(json.cast<String, Object?>())
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<bool> hasRelease(String release) async =>
      await manifest(release) != null;
}

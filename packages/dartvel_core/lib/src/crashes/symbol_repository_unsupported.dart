import 'symbols.dart';

/// Symbols in a directory, which a target with no file system does not have.
class DVDirectorySymbolRepository implements DVSymbolRepository {
  DVDirectorySymbolRepository(String directory) {
    throw UnsupportedError(
        'Symbols are kept in a directory, and this platform has no file system.');
  }

  @override
  Future<bool> hasRelease(String release) => throw UnimplementedError();

  @override
  Future<DVSymbolsManifest?> manifest(String release) => throw UnimplementedError();

  @override
  Future<void> putFile(String release, String name, List<int> bytes) =>
      throw UnimplementedError();

  @override
  Future<void> putManifest(DVSymbolsManifest manifest) => throw UnimplementedError();

  @override
  Future<List<int>?> readFile(String release, String name) =>
      throw UnimplementedError();
}

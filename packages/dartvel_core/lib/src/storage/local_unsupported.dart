/// `DVLocalFileStorageAdapter` where there is no filesystem to stand on.
///
/// On the web there is no directory the application owns in this sense, so
/// the adapter exists and says so rather than being absent: code that names
/// it compiles everywhere, and a web build that reaches it is told which
/// adapter to configure instead of failing to resolve a name.
library;

import 'adapters.dart';

/// Refuses every call, naming what to use instead.
class DVLocalFileStorageAdapter implements DVFileStorageAdapter {
  DVLocalFileStorageAdapter({required this.root});

  final String root;

  Never _noFilesystem(String operation, String key) =>
      throw DVFileStorageException(
        'local',
        operation,
        key,
        statusCode: 501,
      );

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) async =>
      _noFilesystem('put', key);

  @override
  Future<List<int>> get(String key) async => _noFilesystem('get', key);

  @override
  Future<void> delete(String key) async => _noFilesystem('delete', key);

  @override
  Future<bool> exists(String key) async => _noFilesystem('exists', key);

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      _noFilesystem('list', prefix);
}

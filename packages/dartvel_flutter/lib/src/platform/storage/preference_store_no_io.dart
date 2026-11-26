// A browser has no dart:io; DVFilePreferenceStore is never constructed there.
// These stand in so the shared library compiles.
class FileSystemException implements Exception {}

class File {
  File(String path);
  File get parent => this;
  bool existsSync() => false;
  String readAsStringSync() => '';
  void createSync({bool recursive = false}) {}
  File writeAsStringSync(String contents, {bool flush = false}) => this;
  void renameSync(String path) {}
  void deleteSync() {}
}

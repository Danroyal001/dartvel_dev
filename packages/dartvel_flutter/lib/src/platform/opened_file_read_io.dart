import 'dart:io';

/// The bytes of an opened file at [path]. Not `files.readBytes`, which is
/// confined to the application's own directories: an opened file is wherever
/// the person keeps it, or a copy the platform made into the cache.
Future<List<int>> dvReadOpenedFile(String path) => File(path).readAsBytes();

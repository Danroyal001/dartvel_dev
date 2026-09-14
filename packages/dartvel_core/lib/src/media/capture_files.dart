/// Private storage for recordings, where the platform has a filesystem.
library;

export 'capture_files_stub.dart'
    if (dart.library.ffi) 'capture_files_io.dart';

/// No filesystem: a browser records into a Blob, which is private to the page
/// by construction and has no path to protect.
library;

import 'capture_backend.dart';

final class DVPrivateCaptureFiles implements DVCaptureFiles {
  DVPrivateCaptureFiles(this.directory);

  final String directory;

  Never _unsupported() => throw UnsupportedError(
      'DVPrivateCaptureFiles needs a filesystem; this target has none.');

  @override
  Future<String> reserve(String extension) async => _unsupported();

  @override
  Future<int> seal(String path) async => _unsupported();

  @override
  Future<void> discard(String path) async => _unsupported();
}

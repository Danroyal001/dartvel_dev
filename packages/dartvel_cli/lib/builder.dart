import 'dart:async';
import 'dart:io';
import 'package:build/build.dart';

Builder dartvelBuilder(BuilderOptions options) => _DartvelBuilder();

class _DartvelBuilder implements Builder {
  static bool _ran = false;
  @override
  final buildExtensions = const {
    // No declared outputs; this builder shells out to the CLI which writes
    // source files directly (build_to: source style). We keep extensions empty
    // to avoid UnexpectedOutputException.
    '.dart': <String>[],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Run once per build. Subsequent files become no-ops.
    if (_ran) return;
    _ran = true;
    try {
      await Process.run('dart', ['run', 'dartvel_cli:dartvel', 'routes'],
          workingDirectory: Directory.current.path);
    } catch (_) {
      // Ignore; build may still succeed if files already exist.
    }
  }
}

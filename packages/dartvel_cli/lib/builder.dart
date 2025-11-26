import 'package:build/build.dart';

/// Dartvel builder for build_runner integration
/// This is a placeholder - actual code generation is done via 'dartvel routes' command
Builder dartvelBuilder(BuilderOptions options) => _DartvelBuilder();

class _DartvelBuilder implements Builder {
  @override
  final buildExtensions = const {
    r'$lib$': const [],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Placeholder - use 'dartvel routes' CLI command for code generation
    // Future: Integrate actual route generation here
  }
}

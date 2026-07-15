import 'package:build/build.dart';

/// Dartvel builder for build_runner integration
Builder dartvelBuilder(BuilderOptions options) => _DartvelBuilder();

class _DartvelBuilder implements Builder {
  @override
  final buildExtensions = {
    r'$lib$': [],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!input.path.startsWith('lib/')) return;
    log.fine('dartvel builder observed ${input.path}');
  }
}

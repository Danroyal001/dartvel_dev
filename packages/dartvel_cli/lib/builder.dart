import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'generators/routes_generator.dart' as routes_gen;

/// Dartvel builder for build_runner integration
Builder dartvelBuilder(BuilderOptions options) => _DartvelBuilder();

class _DartvelBuilder implements Builder {
  @override
  final buildExtensions = const {
    r'$lib$': [
      'dartvel_client/router.g.dart',
      'dartvel_client/functions.g.dart',
      'dartvel_client/env.g.dart',
      'dartvel_client/dartvel_runtime.dart',
      'dartvel_client/dartvel_config.g.dart',
      'dartvel_client/dartvel_client.dart',
    ],
    r'$.dart_tool$': [
      'dartvel_backend_routes.g.dart',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // This builder triggers on the package root
    // and runs the full route generation

    final packagePath = buildStep.inputId.package;
    print('[Dartvel] Running route generation for package: $packagePath');

    try {
      // Run the existing route generation logic
      await routes_gen.generate();

      print('[Dartvel] ✅ Code generation complete');
    } catch (e, stack) {
      print('[Dartvel] ❌ Error during code generation: $e');
      print(stack);
      rethrow;
    }
  }
}

/// Post-process builder that runs after main generation
PostProcessBuilder dartvelPostBuilder(BuilderOptions options) =>
    _DartvelPostBuilder();

class _DartvelPostBuilder implements PostProcessBuilder {
  @override
  final inputExtensions = const ['.dart'];

  @override
  Future<void> build(PostProcessBuildStep buildStep) async {
    // Optional: Post-processing steps
    // For now, just a no-op
  }
}

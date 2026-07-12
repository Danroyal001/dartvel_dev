import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/util/performance/operation_performance.dart';
import 'package:collection/collection.dart';
import 'package:linter/src/rules.dart';

void main() async {
  var resourceProvider = OverlayResourceProvider(
    PhysicalResourceProvider.INSTANCE,
  );
  var co19 = '/Users/scheglov/Source/Dart/sdk.git/sdk/tests/co19';
  resourceProvider.setOverlay(
    // '$co19/src/LanguageFeatures/Parts-with-imports/analysis_options.yaml',
    '$co19/src/LanguageFeatures/Augmentation-libraries/analysis_options.yaml',
    content: r'''
analyzer:
  enable-experiment:
    - macros
    - enhanced-parts
''',
    modificationStamp: 0,
  );

  registerLintRules();

  var byteStore = MemoryByteStore();

  for (var i = 0; i < 2; i++) {
    var collection = AnalysisContextCollectionImpl(
      sdkPath: '/Users/scheglov/Applications/dart-sdk',
      resourceProvider: resourceProvider,
      includedPaths: [
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analysis_server',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/linter',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer_plugin',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/element',
        // '/Users/scheglov/dart/admin-portal',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/tests/language/class/large_class_declaration_test.dart',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/_fe_analyzer_shared/lib/src/scanner/token_impl.dart',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/test/generated/test_support.dart',
        // '/Users/scheglov/dart/flutter-packages/packages/metrics_center',
        '/Users/scheglov/dart/flutter-packages/packages/webview_flutter/webview_flutter_android',
        // '/Users/scheglov/Source/flutter/packages/flutter/lib',
        // '/Users/scheglov/Source/flutter/engine/src/flutter/lib/web_ui/lib/pointer.dart',
        // '/Users/scheglov/Source/flutter/packages/flutter/lib/src/painting/alignment.dart',
        // '/Users/scheglov/Source/flutter/packages/flutter/lib/src/animation/animation_controller.dart',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/tests/co19/src/Language/Classes/Getters/static_getter_t03.dart',
      ],
      byteStore: byteStore,
    );

    var timer = Stopwatch()..start();
    for (var analysisContext in collection.contexts) {
      print(analysisContext.contextRoot.root.path);
      var analysisSession = analysisContext.currentSession;
      for (var path in analysisContext.contextRoot.analyzedFiles().sorted()) {
        if (path.endsWith('.dart')) {
          print(path);
          var libResult = await analysisSession.getResolvedLibrary(path);
          if (libResult is ResolvedLibraryResult) {
            for (var unitResult in libResult.units) {
              print('    ${unitResult.path}');
              var ep = '\n        ';
              print('      errors:$ep${unitResult.diagnostics.join(ep)}');
              // print('---');
              // print(unitResult.content);
              // print('---');
            }
          }
        }
      }
    }

    print('[time: ${timer.elapsedMilliseconds} ms]');

    {
      var buffer = StringBuffer();
      collection.scheduler.accumulatedPerformance.write(buffer: buffer);
      print(buffer);
      collection.scheduler.accumulatedPerformance = OperationPerformanceImpl(
        '<scheduler>',
      );
    }

    await collection.dispose();
  }
}

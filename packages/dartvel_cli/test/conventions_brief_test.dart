import 'dart:io';

import 'package:dartvel_cli/src/analysis/conventions_check.dart';
import 'package:test/test.dart';

void main() {
  test('flags Flutter widget classes and builders', () {
    for (final name in [
      'StatelessWidget',
      'StatefulWidget',
      'ListenableBuilder',
      'ValueListenableBuilder',
    ]) {
      expect(
        dvFindConventionIssues(
          path: 'lib/page.dart',
          source: 'class _Page extends $name {} $name();',
        ),
        isNotEmpty,
        reason: name,
      );
    }
  });
  test('rejects a widget passed to DV.run', () {
    expect(
      dvFindConventionIssues(
        path: 'lib/main.dart',
        source: 'void main() => DV.run(MyApp());',
      ),
      isNotEmpty,
    );
    expect(
      dvFindConventionIssues(
        path: 'lib/main.dart',
        source: 'void main(List<String> args) => DV.run(args);',
      ),
      isEmpty,
    );
    expect(
      dvFindConventionIssues(
        path: 'lib/main.dart',
        source: 'void main() => DV.run();',
      ),
      isEmpty,
    );
  });
  test('flags legacy middleware and manual backend serialization', () {
    expect(
      dvFindConventionIssues(
        path: 'lib/backend/functions/save.dart',
        source: '@DVUseMiddleware([DVMiddlewares.auth])\n@DVBackendFunction()\nFuture<Object> _save(Object input) async => input.toJson();',
      ),
      isNotEmpty,
    );
  });
  test('ignores comments and strings in Dart', () {
    expect(
      dvFindConventionIssues(
        path: 'lib/main.dart',
        source: '// runApp(Container());\nconst sample = "DV.Mail MethodChannel Text()";\nvoid main() => DV.run();',
      ),
      isEmpty,
    );
  });
  test(
    'project scan checks root page, tooling, docs and excludes generated',
    () {
      final root = Directory.systemTemp.createTempSync('dv-conventions-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/lib/main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() => DV.run();');
      File('${root.path}/lib/dartvel_client/widgets.g.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('Text();');
      File('${root.path}/tool/helper.py')
        ..createSync(recursive: true)
        ..writeAsStringSync('pass');
      File('${root.path}/tool/build.sh').writeAsStringSync('exit 0');
      File('${root.path}/README.md').writeAsStringSync(
        'Run ~/heavy.sh dartvel build, from /home/alice/project.',
      );
      final findings = dvScanProjectForConventions(root.path);
      expect(
        findings.map((f) => f.rule),
        containsAll([
          'missingRootPage',
          'nonDartTooling',
          'privateHostTooling',
        ]),
      );
      expect(findings.any((f) => f.path.contains('dartvel_client')), isFalse);
      File('${root.path}/lib/pages/index.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('@DVPage() Widget _index() => DVText("Hello");');
      expect(
        dvScanProjectForConventions(root.path)
            .any((f) => f.rule == 'missingRootPage'),
        isFalse,
      );
    },
  );
}

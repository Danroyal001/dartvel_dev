// Home widgets on a target that cannot show them.
//
// The specification: "Unsupported targets are excluded from the compiled
// binary/artifact or fail validation based on project configuration." Both
// halves matter and the default matters more -- a web build of an
// application that also ships an Android widget is an ordinary thing to do,
// and refusing it by default would make the feature cost more than it gives.
//
// What must never happen is the third option: a build that quietly carries a
// home widget onto a platform with no home screen and says nothing, which is
// dead code in the artifact and a feature the developer believes shipped.
import 'dart:io';

import 'package:dartvel_cli/src/build/home_widget_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _widget = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVHomeWidget()
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) => const DVText('1,204');
''';

Directory workspace({String dartvel = '', bool widget = true}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_home_target_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
$dartvel
''');
  if (widget) {
    File(p.join(root.path, 'lib', 'widgets', 'step_counter.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_widget);
  }
  return root;
}

void main() {
  test('a target with a home screen carries them', () {
    for (final String target in const <String>['android', 'ios', 'macos']) {
      final DVHomeWidgetCheck check =
          DVHomeWidgetCheck.run(workspace().path, target: target);

      expect(check.ok, isTrue, reason: target);
      expect(check.excluded, isFalse, reason: target);
    }
  });

  test('a target with none leaves them out, and says so', () {
    final DVHomeWidgetCheck check =
        DVHomeWidgetCheck.run(workspace().path, target: 'web');

    expect(check.ok, isTrue);
    expect(check.excluded, isTrue);
    // Said, because the alternative is a developer who believes the widget
    // shipped: the code is there, the build was green, and nothing on the
    // machine shows it.
    expect(check.lines.join(' '), contains('step-counter'));
    expect(check.lines.join(' '), contains('web'));
  });

  test('a project that asks to be refused is refused', () {
    final DVHomeWidgetCheck check = DVHomeWidgetCheck.run(
      workspace(dartvel: '''
dartvel:
  homeWidgets:
    onUnsupported: fail
''').path,
      target: 'web',
    );

    expect(check.ok, isFalse);
    expect(check.lines.join(' '), contains('DV-WIDGET-001'));
  });

  test('an application with no home widgets says nothing anywhere', () {
    for (final String target in const <String>['web', 'android']) {
      final DVHomeWidgetCheck check =
          DVHomeWidgetCheck.run(workspace(widget: false).path, target: target);

      expect(check.ok, isTrue, reason: target);
      expect(check.lines, isEmpty, reason: target);
    }
  });

  test('a declaration nobody understands is refused rather than assumed', () {
    // exclude and fail are the two the specification names. A third word is
    // a typo, and reading it as either is how a project that asked to be
    // refused ships silently.
    final Directory root = workspace(dartvel: '''
dartvel:
  homeWidgets:
    onUnsupported: warn
''');

    final DVHomeWidgetCheck check = DVHomeWidgetCheck.run(root.path, target: 'web');

    expect(check.ok, isFalse);
    expect(check.lines.join(' '), contains('onUnsupported'));
  });
}

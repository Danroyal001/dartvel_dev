// TDD fixtures: each convention rule must have a failing fixture first.
import 'package:dartvel_cli/src/analysis/conventions_check.dart';
import 'package:test/test.dart';

void main() {
  group('DV-CONV-001 main uses runApp', () {
    test('failing fixture: runApp in main.dart', () {
      final findings = dvFindConventionIssues(
        path: 'lib/main.dart',
        source: '''
void main() {
  runApp(MyApp());
}
''',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-001');
      expect(conv.isNotEmpty, isTrue,
          reason: 'Expected DV-CONV-001 finding for runApp()');
      expect(conv.first.rule, 'mainUsesRunApp');
    });

    test('passes when main uses DV.run', () {
      final findings = dvFindConventionIssues(
        path: 'lib/main.dart',
        source: 'void main() { DV.run(args); }',
      );
      expect(findings.where((f) => f.code == 'DV-CONV-001').isEmpty, isTrue);
    });
  });

  group('DV-CONV-002 no primary constructor', () {
    test('failing fixture: old constructor shape', () {
      final findings = dvFindConventionIssues(
        path: 'lib/x.dart',
        source: '''
class Order {
  final String id;
  Order(this.id);
}
''',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-002');
      expect(conv.isNotEmpty, isTrue,
          reason: 'Expected DV-CONV-002 for non-primary constructor');
    });

    test('passes with primary constructor', () {
      final findings = dvFindConventionIssues(
        path: 'lib/x.dart',
        source: 'class Order({required final String id});',
      );
      expect(findings.where((f) => f.code == 'DV-CONV-002').isEmpty, isTrue);
    });
  });

  group('DV-CONV-003 Flutter widgets', () {
    test('failing fixture: Container instead of DVBox', () {
      final findings = dvFindConventionIssues(
        path: 'lib/page.dart',
        source: 'Widget build() => Container();',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-003');
      expect(conv.any((f) => f.rule == 'flutterWidgetInsteadOfDv'), isTrue);
    });
  });

  group('DV-CONV-004 string routes', () {
    test('failing fixture: DVRouteTarget with literal', () {
      final findings = dvFindConventionIssues(
        path: 'lib/routes.dart',
        source: "DVRouteTarget('/home');",
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-004');
      expect(conv.isNotEmpty, isTrue);
    });

    test('failing fixture: Navigator.pushNamed literal', () {
      final findings = dvFindConventionIssues(
        path: 'lib/page.dart',
        source: "Navigator.pushNamed(context, '/account');",
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-004');
      expect(conv.any((f) => f.rule == 'navigatorPushNamedString'), isTrue);
    });
  });

  group('DV-CONV-005 records/SQL', () {
    test('failing fixture: records.insert', () {
      final findings = dvFindConventionIssues(
        path: 'lib/backend.dart',
        source: 'records.insert(\'users\', {...});',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-005');
      expect(conv.isNotEmpty, isTrue);
    });
  });

  group('DV-CONV-006 public annotated inputs', () {
    test('failing fixture: public @DVModel class', () {
      final findings = dvFindConventionIssues(
        path: 'lib/models/user.dart',
        source: '@DVModel() class User {}',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-006');
      expect(conv.isNotEmpty, isTrue,
          reason: 'Expected DV-CONV-006 for public annotated input');
      expect(conv.first.message.contains('User'), isTrue);
    });

    test('passes with private annotated input', () {
      final findings = dvFindConventionIssues(
        path: 'lib/models/user.dart',
        source: '@DVModel() class _User {}',
      );
      expect(findings.where((f) => f.code == 'DV-CONV-006').isEmpty, isTrue);
    });
  });

  group('DV-CONV-007 build_runner', () {
    test('failing fixture: build_runner dependency', () {
      final findings = dvFindConventionIssues(
        path: 'pubspec.yaml',
        source: 'dev_dependencies:\n  build_runner: ^2.4.0',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-007');
      expect(conv.isNotEmpty, isTrue);
    });
  });

  group('DV-CONV-008 sibling imports', () {
    test('failing fixture: direct router.g.dart import', () {
      final findings = dvFindConventionIssues(
        path: 'lib/page.dart',
        source: "import 'dartvel_client/router.g.dart';",
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-008');
      expect(conv.isNotEmpty, isTrue);
    });
  });

  group('DV-CONV-009 platform channels', () {
    test('failing fixture: MethodChannel usage', () {
      final findings = dvFindConventionIssues(
        path: 'lib/native.dart',
        source: 'final channel = MethodChannel(\'com/example\');',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-009');
      expect(conv.isNotEmpty, isTrue);
    });
  });

  group('DV-CONV-010 deprecated namespaces', () {
    test('failing fixture: DV.Mail', () {
      final findings = dvFindConventionIssues(
        path: 'lib/mail.dart',
        source: 'DV.Mail.send(...)',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-010');
      expect(conv.any((f) => f.rule == 'deprecatedNamespaceMail'), isTrue);
    });
  });

  group('DV-CONV-011 dot shorthands', () {
    test('failing fixture: full MainAxisAlignment form', () {
      final findings = dvFindConventionIssues(
        path: 'lib/style.dart',
        source: 'mainAxisAlignment: MainAxisAlignment.center',
      );
      final conv = findings.where((f) => f.code == 'DV-CONV-011');
      expect(conv.isNotEmpty, isTrue);
    });
  });
}

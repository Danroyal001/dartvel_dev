import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectTemplates', () {
    test('pubspec contains package name', () {
      final content = ProjectTemplates.pubspec('my_app');
      expect(content, contains('name: my_app'));
      expect(content, contains('dartvel_flutter:'));
    });

    test('readme contains project name', () {
      final content = ProjectTemplates.readme('My App');
      expect(content, contains('# My App'));
      expect(content, contains('dartvel new'));
    });

    test('indexPage contains DartvelPage', () {
      expect(ProjectTemplates.indexPage, contains('extends DartvelPage'));
    });

    test('layoutPage contains DartvelLayout', () {
      expect(ProjectTemplates.layoutPage, contains('extends DartvelLayout'));
    });

    test('helloFunction contains handler', () {
      expect(ProjectTemplates.helloFunction, contains('Future<ResponseType> handler'));
    });

    test('gitignore contains .env', () {
      expect(ProjectTemplates.gitignore, contains('.env'));
      expect(ProjectTemplates.gitignore, contains('.dart_tool'));
    });
  });
}

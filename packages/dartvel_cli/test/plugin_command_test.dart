import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/plugin_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PluginCommand', () {
    late Directory tempDir;
    late Directory previousDirectory;
    late CommandRunner<void> runner;

    setUp(() {
      previousDirectory = Directory.current;
      tempDir = Directory.systemTemp.createTempSync('dartvel_plugin_test');
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(PluginCommand());
      Directory.current = tempDir;
      exitCode = 0;
    });

    tearDown(() {
      Directory.current = previousDirectory;
      tempDir.deleteSync(recursive: true);
      exitCode = 0;
    });

    test('add auth plugin creates files', () async {
      await runner.run(['plugin', 'add', '--name', 'auth']);

      final loginPage = File(p.join(tempDir.path, 'lib/pages/login.page.dart'));
      final authLogin =
          File(p.join(tempDir.path, 'lib/backend/functions/auth/login.dart'));
      final authLogout =
          File(p.join(tempDir.path, 'lib/backend/functions/auth/logout.dart'));
      final authMe =
          File(p.join(tempDir.path, 'lib/backend/functions/auth/me.get.dart'));

      expect(loginPage.existsSync(), isTrue);
      expect(authLogin.existsSync(), isTrue);
      expect(authLogout.existsSync(), isTrue);
      expect(authMe.existsSync(), isTrue);

      final loginSource = loginPage.readAsStringSync();
      expect(loginSource, contains('@DVPage(title: \'Login\')'));
      expect(
          loginSource, contains('Widget _loginPage(BuildContext context) =>'));
      expect(loginSource, contains('DV.Auth.SignInWithEmailAndPasswordPage()'));
      expect(loginSource, isNot(contains('Scaffold(')));
      expect(loginSource, isNot(contains('class LoginPage')));

      expect(authLogin.readAsStringSync(), contains('@DVBackendFunction'));
      expect(authLogin.readAsStringSync(), contains('_login('));
      expect(authLogin.readAsStringSync(),
          isNot(contains('Map<String, dynamic>')));
      expect(authLogout.readAsStringSync(),
          isNot(contains('Map<String, dynamic>')));
      expect(
          authMe.readAsStringSync(), isNot(contains('Map<String, dynamic>')));
    });

    test('unknown plugin fails', () async {
      await runner.run(<String>['plugin', 'add', 'unknown']);

      expect(exitCode, 64);
    });

    test('missing plugin name fails with usage code', () async {
      await runner.run(<String>['plugin', 'add']);

      expect(exitCode, 64);
    });
  });
}

// `dartvel build <target> --profile development|profile|release`: one way to
// say the mode, and what each value hands Flutter.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/build_profile.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

void main() {
  group('DVBuildProfile', () {
    test('each profile maps to the Flutter mode it builds', () {
      expect(DVBuildProfile.parse('development').flutterFlag, '--debug');
      expect(DVBuildProfile.parse('profile').flutterFlag, '--profile');
      expect(DVBuildProfile.parse('release').flutterFlag, '--release');
    });

    test('only development is a JIT build a dev server can reload', () {
      expect(DVBuildProfile.development.isDevelopment, isTrue);
      expect(DVBuildProfile.profile.isDevelopment, isFalse);
      expect(DVBuildProfile.release.isDevelopment, isFalse);
    });

    test('a name that is not a profile is refused, naming the three', () {
      expect(
        () => DVBuildProfile.parse('debug'),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            allOf(
              contains('development'),
              contains('profile'),
              contains('release'),
            ),
          ),
        ),
      );
    });
  });

  group('dartvel build', () {
    final BuildCommand command = BuildCommand();

    test('--profile is an option defaulting to release', () {
      final option = command.argParser.options['profile'];
      expect(option, isNotNull);
      expect(option!.isFlag, isFalse);
      expect(option.defaultsTo, 'release');
      expect(option.allowed, <String>['development', 'profile', 'release']);
    });

    test('there is no second way to say the mode', () {
      expect(command.argParser.options.containsKey('release'), isFalse);
      expect(command.argParser.options.containsKey('debug'), isFalse);
    });

    test('--no-release is a usage error rather than silently ignored', () {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(BuildCommand());
      expect(
        () => runner.run(<String>['build', 'android', '--no-release']),
        throwsA(isA<UsageException>()),
      );
    });

    test('dev-client is not a build target or a subcommand', () {
      expect(buildPlatformArguments, isNot(contains('dev-client')));
      expect(
        () => resolveRequestedPlatform(
          positional: <String>['dev-client'],
          optionValue: 'all',
          optionWasParsed: false,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(command.argParser.usage, isNot(contains('build dev-client')));
      expect(command.invocation, isNot(contains('dev-client')));
    });

    test('the plan for the old subcommand is gone from the library', () {
      final String source = File(
        'lib/src/devclient/dev_client_project.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('dvDevClientBuildPlan')));
      expect(source, isNot(contains('dvDevClientFlavor')));
    });
  });
}

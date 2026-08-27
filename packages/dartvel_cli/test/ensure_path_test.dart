// Putting the CLI on the PATH, for someone who downloaded the binary.
//
// A binary from a GitHub release lands wherever the browser put it. It runs,
// and then it is not on the PATH, so the next terminal cannot find it.
//
// One premise this was built on is worth stating because it is wrong: Windows
// does not need administrator rights for this. The *user* PATH lives under
// HKCU and any process can write it. Only the *machine* PATH, under HKLM,
// needs elevation — and a single-user install has no reason to touch it. So
// the default is user scope on every platform, and nothing elevates unless
// --system is asked for.
import 'dart:io';

import 'package:dartvel_cli/src/build/ensure_path.dart';
import 'package:test/test.dart';

void main() {
  group('deciding whether anything is needed', () {
    test('a directory already on the PATH needs no change', () {
      final plan = ensurePathPlan(
        directory: '/home/me/.local/bin',
        currentPath: '/usr/bin:/home/me/.local/bin',
        platform: PathPlatform.linux,
      );

      expect(plan.alreadyPresent, isTrue);
      expect(plan.changesNeeded, isFalse);
    });

    test('a trailing separator does not hide a match', () {
      // PATH entries are written both ways and they are the same directory.
      final plan = ensurePathPlan(
        directory: '/home/me/.local/bin',
        currentPath: '/usr/bin:/home/me/.local/bin/',
        platform: PathPlatform.linux,
      );

      expect(plan.alreadyPresent, isTrue);
    });

    test('a prefix of another entry is not a match', () {
      // /usr/local/bin2 contains /usr/local/bin as a prefix and is a
      // different directory. A substring check would call this present.
      final plan = ensurePathPlan(
        directory: '/usr/local/bin',
        currentPath: '/usr/local/bin2:/usr/bin',
        platform: PathPlatform.linux,
      );

      expect(plan.alreadyPresent, isFalse);
    });

    test('Windows compares case-insensitively, and Linux does not', () {
      expect(
        ensurePathPlan(
          directory: r'C:\Tools\Dartvel',
          currentPath: r'C:\tools\dartvel;C:\Windows',
          platform: PathPlatform.windows,
        ).alreadyPresent,
        isTrue,
      );
      expect(
        ensurePathPlan(
          directory: '/home/me/Bin',
          currentPath: '/home/me/bin',
          platform: PathPlatform.linux,
        ).alreadyPresent,
        isFalse,
      );
    });
  });

  group('where the change goes', () {
    test('a POSIX shell gets its own rc file, and no elevation', () {
      final plan = ensurePathPlan(
        directory: '/opt/dartvel',
        currentPath: '/usr/bin',
        platform: PathPlatform.linux,
        shell: '/bin/zsh',
        home: '/home/me',
      );

      expect(plan.targets.single.file, '/home/me/.zshrc');
      expect(plan.needsElevation, isFalse);
    });

    test('bash and zsh are told apart by the shell, not guessed', () {
      // Appending to .bashrc for a zsh user changes nothing they will ever
      // read, and the command would report success.
      expect(
        ensurePathPlan(
          directory: '/opt/dartvel',
          currentPath: '',
          platform: PathPlatform.linux,
          shell: '/usr/bin/bash',
          home: '/home/me',
        ).targets.single.file,
        '/home/me/.bashrc',
      );
    });

    test('macOS defaults to zsh, which is its default shell', () {
      expect(
        ensurePathPlan(
          directory: '/opt/dartvel',
          currentPath: '',
          platform: PathPlatform.macos,
          home: '/Users/me',
        ).targets.single.file,
        '/Users/me/.zshrc',
      );
    });

    test('an unknown shell writes to profile rather than nothing', () {
      final plan = ensurePathPlan(
        directory: '/opt/dartvel',
        currentPath: '',
        platform: PathPlatform.linux,
        shell: '/usr/bin/fish',
        home: '/home/me',
      );

      expect(plan.targets.single.file, '/home/me/.profile');
    });
  });

  group('Windows', () {
    test('user scope needs no elevation', () {
      final plan = ensurePathPlan(
        directory: r'C:\Users\me\dartvel',
        currentPath: r'C:\Windows',
        platform: PathPlatform.windows,
      );

      expect(plan.needsElevation, isFalse);
      expect(plan.scope, PathScope.user);
    });

    test('system scope does, and says so', () {
      final plan = ensurePathPlan(
        directory: r'C:\Program Files\dartvel',
        currentPath: r'C:\Windows',
        platform: PathPlatform.windows,
        scope: PathScope.system,
      );

      expect(plan.needsElevation, isTrue);
    });

    test('it does not use setx, which truncates a long PATH', () {
      // setx caps the value at 1024 characters and silently cuts the rest,
      // which destroys a PATH rather than extending it.
      final plan = ensurePathPlan(
        directory: r'C:\Users\me\dartvel',
        currentPath: r'C:\Windows',
        platform: PathPlatform.windows,
      );

      expect(plan.command, isNot(contains('setx')));
      expect(plan.command, contains('SetEnvironmentVariable'));
    });
  });

  group('the line it writes', () {
    test('it is idempotent, marked so a second run finds it', () {
      final plan = ensurePathPlan(
        directory: '/opt/dartvel',
        currentPath: '',
        platform: PathPlatform.linux,
        shell: '/bin/bash',
        home: '/home/me',
      );
      final target = plan.targets.single;

      expect(target.marker, isNotEmpty);
      expect(target.line, contains(target.marker));
      expect(ensurePathAlreadyWritten('${target.line}\n', target.marker),
          isTrue);
      expect(ensurePathAlreadyWritten('unrelated\n', target.marker), isFalse);
    });

    test('a path with a space survives the shell', () {
      // Asserted by running the line, not by matching its text. The whole
      // value is quoted rather than the directory alone, which is the safer
      // arrangement and not the one this test first expected.
      //
      // Written to a file and run, rather than passed through `bash -c`:
      // nesting the quoting inside another shell is its own source of
      // failure, and it produced a wrong answer here before the line was.
      final line = ensurePathPlan(
        directory: '/home/me/My Tools/dartvel',
        currentPath: '',
        platform: PathPlatform.linux,
        shell: '/bin/bash',
        home: '/home/me',
      ).targets.single.line;

      final dir = Directory.systemTemp.createTempSync('dartvel-path-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/probe.sh')
        ..writeAsStringSync('PATH=/usr/bin\n$line\nprintf %s "\$PATH"\n');

      final result = Process.runSync('bash', <String>[script.path]);

      expect(result.exitCode, 0);
      expect(result.stdout, '/usr/bin:/home/me/My Tools/dartvel');
    });

    test('it appends rather than replacing the PATH', () {
      // A line that assigns PATH instead of extending it removes every other
      // tool from the shell.
      final line = ensurePathPlan(
        directory: '/opt/dartvel',
        currentPath: '',
        platform: PathPlatform.linux,
        shell: '/bin/bash',
        home: '/home/me',
      ).targets.single.line;

      expect(line, contains(r'$PATH'));
    });
  });
}

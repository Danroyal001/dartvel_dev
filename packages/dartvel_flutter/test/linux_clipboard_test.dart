// The clipboard as another application sees it, and the PRIMARY selection.
//
// Every earlier clipboard check read the value back inside the process that
// wrote it, which GTK answers out of its own cache. That cannot tell a
// working clipboard from one nothing else can read, so these tests put a
// second X client in front of it.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_clipboard_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart on PATH, which is the SDK's rather than `flutter_tester`.
///
/// `Platform.resolvedExecutable` under `flutter test` is the tester engine,
/// which cannot run a script, so the child process needs the real thing.
String? _dartOnPath() {
  final String separator = Platform.isWindows ? ';' : ':';
  for (final String entry in (Platform.environment['PATH'] ?? '').split(
    separator,
  )) {
    if (entry.isEmpty) continue;
    final File candidate = File('$entry${Platform.pathSeparator}dart');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

/// What a second process reads off [selection], or `BLOCKED` when the owner
/// never answers.
///
/// Blocking is the interesting outcome: a process that owns a selection and
/// does not answer requests for it does not merely fail to share, it makes
/// every other application's paste hang until that application gives up.
Future<String> _readInAnotherProcess(String dart, String selection) async {
  final Process reader = await Process.start(dart, <String>[
    'test/fixtures/clipboard_reader.dart',
    selection,
  ]);
  final Future<String> output = reader.stdout
      .transform(utf8.decoder)
      .join()
      .then((String s) => s.trim());
  final int code = await reader.exitCode.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      reader.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  if (code != 0) return 'BLOCKED';
  return output;
}

void main() {
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  final String? dart = _dartOnPath();
  if (!hasDisplay || dart == null) {
    test(
      'linux clipboard (skipped)',
      () {},
      skip: hasDisplay
          ? 'No dart on PATH, so no second process can read the selection.'
          : 'Run under an X server (Xvfb :99 works) to exercise the real '
                'GTK clipboard.',
    );
    return;
  }

  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
  });
  tearDownAll(DVLinuxBindings.unregister);
  tearDown(dvResetKioskContainment);

  test('a copy is readable by another application', () async {
    const String value = 'dartvel-clipboard-cross-process';
    await DV.Platform.clipboard.copy(value);
    expect(await _readInAnotherProcess(dart, 'CLIPBOARD'), 'TEXT:$value');
  });

  test('the PRIMARY selection is a second, separate selection', () async {
    // Middle-click paste on X11 reads PRIMARY, and Ctrl+V reads CLIPBOARD.
    // Writing one must not disturb the other: an application that put its
    // highlighted text on PRIMARY and wiped whatever the user had copied
    // half an hour ago has destroyed something it never owned.
    await DV.Platform.clipboard.copy('dartvel-clipboard-value');
    await DV.Platform.clipboard.writeSelection('dartvel-primary-value');

    expect(
      await DV.Platform.clipboard.readSelection(),
      'dartvel-primary-value',
    );
    expect(await DV.Platform.clipboard.paste(), 'dartvel-clipboard-value');
  });

  test('the PRIMARY selection is readable by another application', () async {
    const String value = 'dartvel-primary-cross-process';
    await DV.Platform.clipboard.writeSelection(value);
    expect(await _readInAnotherProcess(dart, 'PRIMARY'), 'TEXT:$value');
  });

  test('a kiosk that locks the clipboard locks the selection too', () async {
    dvApplyKioskContainment(
      DVKioskPolicy.parse(const <String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': true,
          'input': <String, Object?>{'clipboard': 'disabled'},
        },
      }),
    );
    // Every one of the four as a failed future rather than a synchronous
    // throw. The signature says Future, so a caller is entitled to write
    // `clipboard.paste().catchError(...)` -- and a refusal thrown before the
    // future exists walks straight past that and out of the caller's frame.
    await expectLater(
      DV.Platform.clipboard.copy('leaks'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      DV.Platform.clipboard.paste(),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      DV.Platform.clipboard.writeSelection('leaks'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      DV.Platform.clipboard.readSelection(),
      throwsA(isA<StateError>()),
    );
  });

  test('serving a selection stops with the bindings', () async {
    // The pump is a repeating timer, and one that outlives `unregister` is a
    // process still iterating GTK's main loop after it has said it is done
    // with GTK. In a suite that shows up as a timer firing during somebody
    // else's test.
    await DV.Platform.clipboard.copy('dartvel-pump-lifetime');
    expect(DVLinuxClipboard.isPumping, isTrue);

    DVLinuxBindings.unregister();
    expect(DVLinuxClipboard.isPumping, isFalse);

    expect(DVLinuxBindings.register(), isTrue);
  });
}

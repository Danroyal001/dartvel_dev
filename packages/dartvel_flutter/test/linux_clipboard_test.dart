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

/// Writes [value] and checks a second process can read it off [selection].
///
/// Retried, because an X selection is one resource per display and
/// `flutter test` runs its files side by side: a sibling suite copying its
/// own text takes ownership away between the write here and the read there.
/// That comes back as `EMPTY` -- nobody owns the selection, or the owner has
/// since exited -- which is a different answer from `BLOCKED`, and `BLOCKED`
/// is the whole point of the test: an owner that is present and never
/// replies. So a steal is retried and a block fails on the spot.
Future<void> _expectReadableElsewhere(
  String dart,
  String selection,
  Future<void> Function(String value) write,
  String value,
) async {
  for (int attempt = 0; attempt < 5; attempt++) {
    await write(value);
    final String seen = await _readInAnotherProcess(dart, selection);
    expect(
      seen,
      isNot('BLOCKED'),
      reason: 'this process owns $selection and is not answering requests '
          'for it, so every paste on the display hangs',
    );
    if (seen == 'TEXT:$value') return;
  }
  fail('another process kept taking $selection away; five attempts, no read');
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
    await _expectReadableElsewhere(
      dart,
      'CLIPBOARD',
      DV.Platform.clipboard.copy,
      'dartvel-clipboard-cross-process',
    );
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
    // Not `equals('dartvel-clipboard-value')`: a suite running beside this
    // one shares the display and can take the clipboard between these two
    // lines, and the clipboard holding somebody else's text is not this
    // test's business. The clipboard coming back as the PRIMARY value is,
    // because that is what writing one selection into the other looks like.
    expect(await DV.Platform.clipboard.paste(), isNot('dartvel-primary-value'));
  });

  test('the PRIMARY selection is readable by another application', () async {
    await _expectReadableElsewhere(
      dart,
      'PRIMARY',
      DV.Platform.clipboard.writeSelection,
      'dartvel-primary-cross-process',
    );
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

  test('unregistering hands the selection back rather than sitting on it',
      () async {
    // Stopping the pump without letting go puts the process straight back
    // into the state this binding exists to get out of: the display still
    // records this application as the owner of the clipboard, and every
    // paste anywhere waits for an answer that is not coming any more. It is
    // not hypothetical -- a suite that copied and then unregistered made the
    // suite running beside it fail, which is how it was found.
    // The display is asked who owns the selection, not a second process:
    // BLOCKED is the right symptom but the wrong instrument here, since a
    // suite running beside this one can be the one holding on.
    addTearDown(() => DVLinuxBindings.register());
    await DV.Platform.clipboard.copy('dartvel-released-on-unregister');
    expect(
      DVLinuxClipboard.ownsSelection(DVLinuxClipboard.clipboardAtom),
      isTrue,
      reason: 'a copy takes ownership; without that the next line proves '
          'nothing at all',
    );

    DVLinuxBindings.unregister();

    expect(
      DVLinuxClipboard.ownsSelection(DVLinuxClipboard.clipboardAtom),
      isFalse,
    );
  });

  test('serving a selection stops with the bindings', () async {
    // The pump is a repeating timer, and one that outlives `unregister` is a
    // process still iterating GTK's main loop after it has said it is done
    // with GTK. In a suite that shows up as a timer firing during somebody
    // else's test.
    addTearDown(() => DVLinuxBindings.register());
    await DV.Platform.clipboard.copy('dartvel-pump-lifetime');
    expect(DVLinuxClipboard.isPumping, isTrue);

    DVLinuxBindings.unregister();
    expect(DVLinuxClipboard.isPumping, isFalse);
  });
}

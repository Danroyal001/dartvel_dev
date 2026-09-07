// The Dart an embedder bundles, against the one Dartvel needs.
//
// dartvel build webos failed on every run and the reason had nothing to do
// with the project: the embedder's Flutter carries Dart 3.10.9, so `pub get`
// inside the generated scaffold refused to solve, the scaffold was deleted,
// and the build reported "could not generate the webos/ scaffold". A true
// message about the wrong thing, on a job that had been red for weeks.
//
// The toolchain rule says a target whose toolchain cannot serve skips
// cleanly with a clear message. An embedder that is installed and too old is
// that case, and it is the one nothing was checking.
import 'package:dartvel_cli/src/build/sdk_floor.dart';
import 'package:test/test.dart';

/// What a vendor CLI prints. Every one of them wraps Flutter's own.
String _version({required String flutter, required String dart}) =>
    'Flutter $flutter • channel stable • '
    'https://github.com/Danroyal001/dartvel_webos\n'
    'Framework • revision abc1234 (2 weeks ago) • 2026-08-20\n'
    'Engine • revision def5678\n'
    'Tools • Dart $dart • DevTools 2.37.2';

void main() {
  group('reading the version', () {
    test('the Dart line, not the Flutter one', () {
      // The interesting case is a fork whose Flutter version says nothing
      // about how old its Dart is, so the Flutter number must not be what
      // this reads.
      expect(
        dvEmbedderDartVersion(_version(flutter: '3.35.0', dart: '3.10.9')),
        '3.10.9',
      );
    });

    test('a prerelease keeps its suffix', () {
      expect(
        dvEmbedderDartVersion(
          _version(flutter: '3.44.0', dart: '3.12.0-1.0.dev'),
        ),
        '3.12.0-1.0.dev',
      );
    });

    test('output with no Dart in it is unreadable rather than old', () {
      expect(dvEmbedderDartVersion('some other tool, version 9'), isNull);
    });
  });

  group('comparing against the floor', () {
    test('numbers, not strings', () {
      // 3.9.0 sorts after 3.12.0 as text. Reasoning from that is how a
      // target that cannot resolve at all was recorded as merely unproven.
      expect(dvMeetsDartFloor('3.9.0'), isFalse);
      expect(dvMeetsDartFloor('3.12.0'), isTrue);
      expect(dvMeetsDartFloor('3.10.9'), isFalse);
      expect(dvMeetsDartFloor('3.7.2'), isFalse);
      expect(dvMeetsDartFloor('4.0.1'), isTrue);
      expect(dvMeetsDartFloor('3.13.0'), isTrue);
    });

    test('a prerelease of the floor is below it', () {
      // Which is what pub does, and pub is the thing that will refuse.
      expect(dvMeetsDartFloor('3.12.0-1.0.dev'), isFalse);
      expect(dvMeetsDartFloor('3.13.0-1.0.dev'), isTrue);
    });

    test('something unreadable is not treated as old', () {
      // A refusal on a version nobody could parse would block a target for a
      // formatting change in somebody else's CLI.
      expect(dvMeetsDartFloor('not a version'), isTrue);
    });
  });

  group('what the build says', () {
    test('an old embedder is named with both numbers and the wall it hit', () {
      final String? said = dvEmbedderTooOld(
        target: 'webos',
        executable: 'flutter-webos',
        versionOutput: _version(flutter: '3.35.0', dart: '3.10.9'),
      );

      expect(said, isNotNull);
      expect(said, contains('3.10.9'));
      expect(said, contains('3.12.0'));
      // The distinction that matters: it is installed, and being installed
      // is not the problem. Without this somebody goes looking for a
      // toolchain that is already there.
      expect(said, contains('installed'));
      expect(said, contains('nothing to fix in this project'));
    });

    test('a current embedder says nothing', () {
      expect(
        dvEmbedderTooOld(
          target: 'tizen',
          executable: 'flutter-tizen',
          versionOutput: _version(flutter: '3.44.5', dart: '3.12.2'),
        ),
        isNull,
      );
    });

    test('an unreadable version says nothing either', () {
      // A vendor CLI that prints something else is a reason to try the build
      // and let it say what is wrong, not a reason to refuse it here.
      expect(
        dvEmbedderTooOld(
          target: 'fuchsia',
          executable: 'dartvel_fuchsia',
          versionOutput: 'built from source',
        ),
        isNull,
      );
    });
  });

  group('reading a refusal out of a build', () {
    test('pub saying no is a skip with the version it had', () {
      // Fuchsia's embedder is a Bazel workspace with no CLI to ask, so the
      // first thing that says which wall was hit is pub, mid-build. The job
      // reported "fuchsia build failed" for weeks, which is true and says
      // nothing about the Dart from 2022 underneath it.
      const String output = '''
Warning: pubspec.yaml has overrides from pubspec_overrides.yaml
The current Dart SDK version is 2.19.0-415.0.dev.

Because dartvel_example requires SDK version >=3.12.0 <4.0.0, version solving failed.
pub get failed
''';

      final String? said =
          dvSdkFloorRefusal(target: 'fuchsia', output: output);

      expect(said, isNotNull);
      expect(said, contains('2.19.0-415.0.dev'));
      expect(said, contains('3.12.0'));
      expect(said, contains('nothing to fix here'));
    });

    test('a version at the end of a sentence keeps its full stop out', () {
      // pub writes "The current Dart SDK version is 2.19.0-415.0.dev." and
      // the prerelease is allowed to contain dots, so a greedy read took the
      // sentence's full stop with it and the skip message said
      // "Dart 2.19.0-415.0.dev. and Dartvel needs".
      final String? said = dvSdkFloorRefusal(
        target: 'fuchsia',
        output: 'The current Dart SDK version is 2.19.0-415.0.dev.\n'
            'Because app requires SDK version >=3.12.0 <4.0.0, '
            'version solving failed.',
      );

      expect(said, contains('Dart 2.19.0-415.0.dev and'));
      expect(said, isNot(contains('dev. and')));
    });

    test('an ordinary build failure is still a failure', () {
      // The check has to be narrow. A compile error that happens to mention
      // an SDK must not be reported as a target nobody can build.
      expect(
        dvSdkFloorRefusal(
          target: 'webos',
          output: 'lib/main.dart:12:3: Error: undefined name "foo"\n'
              'Target kernel_snapshot failed',
        ),
        isNull,
      );
    });

    test('half the message is not the message', () {
      // Both halves, because either alone appears in output that is not
      // this: a package can require an SDK version in a warning, and a
      // solve can fail for a version conflict that has nothing to do with
      // Dart itself.
      expect(
        dvSdkFloorRefusal(
          target: 'webos',
          output: 'Because a requires SDK version >=1.0.0, resolving...',
        ),
        isNull,
      );
      expect(
        dvSdkFloorRefusal(
          target: 'webos',
          output: 'version solving failed: two packages want different foo',
        ),
        isNull,
      );
    });
  });
}

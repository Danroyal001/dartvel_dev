// Publishing to a store, as a plan the build can check before it runs.
//
// The specification asks Dartvel to handle publishing and distribution for
// every platform. Nothing did: `dartvel deploy` covers a web host and a
// server, and an application going to Google Play, App Store Connect or a
// tester group was a set of commands somebody kept in their head.
//
// The failures worth guarding are the ones that waste an upload rather than
// the ones that crash. A publish that starts, spends four minutes on a
// binary and then asks for a credential nobody gave it has failed after
// doing the expensive part; a publish to the wrong track has succeeded at
// the wrong thing. So the plan is resolved and validated first, and refuses
// with the line of pubspec.yaml that would fix it.
import 'dart:io';

import 'package:dartvel_cli/src/deploy/store_plan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory workspace(String publish) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_store_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
$publish
''');
  return root;
}

const String _play = '''
dartvel:
  deploy:
    stores:
      play:
        track: internal
        credentials: secrets/play.json
''';

const String _appStore = '''
dartvel:
  deploy:
    stores:
      appstore:
        apiKey: ABC123
        apiIssuer: 11111111-2222-3333-4444-555555555555
''';

const String _testFlight = '''
dartvel:
  deploy:
    stores:
      testflight:
        apiKey: ABC123
        apiIssuer: 11111111-2222-3333-4444-555555555555
''';

const String _firebase = '''
dartvel:
  deploy:
    stores:
      firebase-app-distribution:
        app: 1:123456789:android:abcdef
        groups: [testers]
''';

void main() {
  group('Google Play', () {
    test('the plan uploads the bundle to the track that was declared', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace(_play).path,
        host: 'linux',
      );

      expect(plan.problems, isEmpty);
      expect(plan.executable, 'fastlane');
      expect(
        plan.arguments,
        containsAllInOrder(<String>['--track', 'internal']),
      );
      // The bundle, not the APK. Play has taken app bundles for years and an
      // APK upload is refused at the end of the upload rather than the start.
      expect(plan.artifact, endsWith('.aab'));
      expect(plan.arguments, contains(plan.artifact));
    });

    test(
      'a service account key in DARTVEL_PLAY_SERVICE_ACCOUNT is used as declared',
      () {
        // A Cloud worker writes the kept key outside the project and names it
        // here, so the pubspec does not have to point at a file in the repo.
        final DVStorePlan plan = dvStorePlan(
          store: 'play',
          root: workspace(
            _play.replaceAll('      credentials: secrets/play.json\n', ''),
          ).path,
          host: 'linux',
          environment: const <String, String>{
            'DARTVEL_PLAY_SERVICE_ACCOUNT': '/run/keys/play.json',
          },
        );
        expect(plan.problems, isEmpty);
        expect(
          plan.arguments,
          containsAllInOrder(<String>['--json_key', '/run/keys/play.json']),
        );
      },
    );

    test('a track nobody publishes to is refused', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace(_play.replaceAll('internal', 'staging')).path,
        host: 'linux',
      );

      // Not corrected to the nearest: "staging" could mean internal or alpha,
      // and guessing puts a build in front of the wrong people.
      expect(plan.problems.join(' '), contains('staging'));
      expect(plan.problems.join(' '), contains('internal'));
    });

    test('no credentials is refused before the upload, not during', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace(
          _play.replaceAll('      credentials: secrets/play.json\n', ''),
        ).path,
        host: 'linux',
      );

      expect(plan.problems.join(' '), contains('credentials'));
      // The failure this prevents: fastlane prompts, and a pipeline with no
      // terminal waits for an answer until the job's cap.
      expect(plan.problems.join(' '), contains('pubspec.yaml'));
    });
  });

  group('App Store Connect', () {
    test('the plan uploads the archive with the key it was given', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'appstore',
        root: workspace(_appStore).path,
        host: 'macos',
      );

      expect(plan.problems, isEmpty);
      expect(plan.executable, 'xcrun');
      expect(plan.arguments, contains('--apiKey'));
      expect(plan.arguments, contains('ABC123'));
      expect(plan.artifact, endsWith('.ipa'));
    });

    test(
      'the IPA uploaded is the one flutter build ipa wrote, whatever its name',
      () {
        // Flutter names the IPA after the app, not "app.ipa".
        final Directory root = workspace(_appStore);
        File(p.join(root.path, 'build', 'ios', 'ipa', 'Shopfront.ipa'))
          ..createSync(recursive: true)
          ..writeAsStringSync('ipa');
        final DVStorePlan plan = dvStorePlan(
          store: 'appstore',
          root: root.path,
          host: 'macos',
        );
        expect(
          plan.artifact,
          p.join(root.path, 'build', 'ios', 'ipa', 'Shopfront.ipa'),
        );
        expect(plan.arguments, contains(plan.artifact));
      },
    );

    test('it is refused off macOS, before anything is built', () {
      // Apple's upload tools are part of Xcode. A plan that pretended
      // otherwise would fail at the end of a long build with "command not
      // found", which reads as a broken installation.
      final DVStorePlan plan = dvStorePlan(
        store: 'appstore',
        root: workspace(_appStore).path,
        host: 'linux',
      );

      expect(plan.problems.join(' '), contains('macOS'));
    });

    test('TestFlight is the same upload, said plainly', () {
      // Uploading to App Store Connect is what puts a build in TestFlight;
      // the difference is what a person does afterwards in the console.
      final DVStorePlan plan = dvStorePlan(
        store: 'testflight',
        root: workspace(_appStore.replaceAll('appstore', 'testflight')).path,
        host: 'macos',
      );

      expect(plan.problems, isEmpty);
      expect(plan.executable, 'xcrun');
    });
  });

  group('what is not declared', () {
    test('a store the project never declared is refused, naming the key', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace('').path,
        host: 'linux',
      );

      expect(plan.problems.join(' '), contains('dartvel.deploy.stores.play'));
    });

    test('the old dartvel.publish block is refused, naming where it goes', () {
      // Read quietly, it would keep a key the documentation no longer names;
      // ignored quietly, a declared store would look undeclared.
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace(
          'dartvel:\n  publish:\n    play:\n      track: internal\n'
          '      credentials: secrets/play.json\n',
        ).path,
        host: 'linux',
      );

      expect(plan.ok, isFalse);
      expect(plan.problems.join(' '), contains('dartvel.publish'));
      expect(plan.problems.join(' '), contains('dartvel.deploy.stores.play'));
    });

    test('an old firebase declaration is named as App Distribution', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'firebase-app-distribution',
        root: workspace(
          'dartvel:\n  publish:\n    firebase:\n      app: "1:1:android:ab"\n',
        ).path,
        host: 'linux',
      );

      expect(plan.ok, isFalse);
      expect(
        plan.problems.join(' '),
        contains(
          'dartvel.publish.firebase is now dartvel.deploy.stores.firebase-app-distribution',
        ),
      );
    });

    test('the old block is refused even beside the new one', () {
      final DVStorePlan plan = dvStorePlan(
        store: 'play',
        root: workspace(
          'dartvel:\n  publish:\n    play:\n      track: beta\n'
          '  deploy:\n    stores:\n      play:\n        track: internal\n'
          '        credentials: secrets/play.json\n',
        ).path,
        host: 'linux',
      );

      expect(plan.ok, isFalse);
      expect(plan.problems.join(' '), contains('dartvel.publish'));
    });

    test(
      'a store nobody has heard of is refused, naming the ones there are',
      () {
        final DVStorePlan plan = dvStorePlan(
          store: 'amazon',
          root: workspace(_play).path,
          host: 'linux',
        );

        expect(plan.problems.join(' '), contains('play'));
        expect(plan.problems.join(' '), contains('appstore'));
      },
    );
  });

  test('every store names the tool that has to be installed', () {
    // The build toolchain rule: check host support, then the tooling, before
    // doing any work. A plan whose executable nobody has is a build that
    // finishes and then cannot deliver.
    const Map<String, String> declarations = <String, String>{
      'play': _play,
      'appstore': _appStore,
      'testflight': _testFlight,
      'firebase-app-distribution': _firebase,
    };
    for (final String store in dvStores) {
      final DVStorePlan plan = dvStorePlan(
        store: store,
        root: workspace(declarations[store]!).path,
        host: 'macos',
      );

      expect(plan.problems, isEmpty, reason: store);
      expect(plan.toolchain, isNotEmpty, reason: store);
    }
  });
}

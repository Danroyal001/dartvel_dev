// The Dartvel Cloud protocol: what the CLI and the Cloud service say to each
// other. Pure Dart, so both sides read the same definitions rather than two
// copies that agree until one of them changes.
import 'package:dartvel_core/cloud.dart';
import 'package:test/test.dart';

void main() {
  group('targets', () {
    test('Apple targets build on a macOS worker, Windows on Windows, the rest on Linux', () {
      for (final String t in <String>['ios', 'macos', 'tvos']) {
        expect(dvCloudWorkerOs(t), DVCloudWorkerOs.macos, reason: t);
      }
      expect(dvCloudWorkerOs('windows'), DVCloudWorkerOs.windows);
      for (final String t in <String>[
        'android', 'fireos', 'web', 'web-server', 'linux', 'linux-cli',
        'chrome-extension', 'firefox-extension', 'vscode', 'sony-elinux', 'tizen',
      ]) {
        expect(dvCloudWorkerOs(t), DVCloudWorkerOs.linux, reason: t);
      }
    });

    test('a target whose local build cannot finish is not offered in the cloud', () {
      // webOS's embedder bundles Dart 3.10.9 and Fuchsia's is older still, so
      // `dartvel build` skips both; the terminal embedder builds for Linux
      // only. A worker would take the money and upload nothing.
      for (final String t in <String>['webos', 'fuchsia', 'windows-cli', 'macos-cli', 'tpk', 'linux-tui']) {
        expect(dvCloudWorkerOs(t), isNull, reason: t);
      }
    });
  });

  group('DVCloudBuildSpec', () {
    test('survives JSON', () {
      const DVCloudBuildSpec spec = DVCloudBuildSpec(
        project: 'shop',
        target: 'ios',
        profile: 'development',
        publish: 'testflight',
        dryRun: true,
        app: 'apps/shop',
      );
      final DVCloudBuildSpec back = DVCloudBuildSpec.fromJson(spec.toJson());
      expect(back.app, 'apps/shop');
      expect(back.project, 'shop');
      expect(back.target, 'ios');
      expect(back.profile, 'development');
      expect(back.publish, 'testflight');
      expect(back.dryRun, isTrue);
      expect(back.format, isNull);
      expect(back.codesign, isTrue);
    });

    test('a store package and its signing choice survive JSON', () {
      const DVCloudBuildSpec spec = DVCloudBuildSpec(
          project: 'shop', target: 'ios', format: 'ipa', codesign: false);
      final DVCloudBuildSpec back = DVCloudBuildSpec.fromJson(spec.toJson());
      expect(back.format, 'ipa');
      expect(back.codesign, isFalse);
    });

    test('a store package on the wrong target is refused', () {
      Map<String, Object?> json(String target, String format) =>
          <String, Object?>{'project': 'shop', 'target': target, 'format': format};
      expect(() => DVCloudBuildSpec.fromJson(json('ios', 'aab')), throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json('android', 'ipa')), throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json('android', 'zip')), throwsFormatException);
      expect(DVCloudBuildSpec.fromJson(json('android', 'aab')).format, 'aab');
    });

    test('refuses what a worker could not build, instead of queueing it', () {
      Map<String, Object?> json(Map<String, Object?> change) => <String, Object?>{
            'project': 'shop',
            'target': 'android',
            'profile': 'release',
            ...change,
          };
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'target': 'webos'})),
          throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'profile': 'debug'})),
          throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'project': '../etc'})),
          throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'publish': 'itch'})),
          throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'app': '../elsewhere'})),
          throwsFormatException);
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{'app': '/abs'})),
          throwsFormatException);
      expect(DVCloudBuildSpec.fromJson(json(<String, Object?>{})).publish, isNull);
      expect(DVCloudBuildSpec.fromJson(json(<String, Object?>{})).app, '.');
    });

    test('tvOS builds for the simulator, which is the only tvOS build with nothing to sign', () {
      Map<String, Object?> json(Map<String, Object?> change) =>
          <String, Object?>{'project': 'shop', 'target': 'tvos', ...change};
      final DVCloudBuildSpec spec = DVCloudBuildSpec.fromJson(json(<String, Object?>{'simulator': true}));
      expect(spec.simulator, isTrue);
      expect(DVCloudBuildSpec.fromJson(spec.toJson()).simulator, isTrue);
      expect(const DVCloudBuildSpec(project: 'shop', target: 'android').toJson().containsKey('simulator'), isFalse);
      // A device build needs a signing team the service does not hold for
      // tvOS, so it is refused when asked for rather than failing on the worker.
      expect(() => DVCloudBuildSpec.fromJson(json(<String, Object?>{})), throwsFormatException);
      expect(
          () => DVCloudBuildSpec.fromJson(
              <String, Object?>{'project': 'shop', 'target': 'android', 'simulator': true}),
          throwsFormatException);
    });
  });

  group('DVCloudBuild', () {
    test('survives JSON, artifacts and all', () {
      const DVCloudBuild build = DVCloudBuild(
        id: 'b_1',
        spec: const DVCloudBuildSpec(project: 'shop', target: 'android'),
        status: DVCloudBuildStatus.succeeded,
        queuePosition: 0,
        installUrl: 'https://cloud.example/i/b_1',
        message: 'built',
        artifacts: const <DVCloudArtifact>[
          DVCloudArtifact(name: 'app-release.apk', size: 12, sha256: 'ab'),
        ],
      );
      final DVCloudBuild back = DVCloudBuild.fromJson(build.toJson());
      expect(back.id, 'b_1');
      expect(back.status, DVCloudBuildStatus.succeeded);
      expect(back.status.isFinished, isTrue);
      expect(back.artifacts.single.name, 'app-release.apk');
      expect(back.artifacts.single.size, 12);
      expect(back.installUrl, 'https://cloud.example/i/b_1');
      expect(DVCloudBuildStatus.queued.isFinished, isFalse);
      expect(DVCloudBuildStatus.running.isFinished, isFalse);
    });

    test('an artifact name that is a path is refused', () {
      for (final String name in <String>['../x', 'a/../../b', '/etc/passwd', r'a\b', '']) {
        expect(() => DVCloudArtifact.fromJson(<String, Object?>{'name': name, 'size': 1, 'sha256': 'a'}),
            throwsFormatException, reason: name);
      }
      expect(DVCloudArtifact.fromJson(<String, Object?>{'name': 'Runner.app/Info.plist', 'size': 1, 'sha256': 'a'}).name,
          'Runner.app/Info.plist');
    });
  });

  group('log events', () {
    test('a log line and a status change survive the event stream, split anywhere', () {
      final String wire = dvCloudEncodeEvent(const DVCloudEvent.log(1, 'Running Gradle task'))
          + dvCloudEncodeEvent(const DVCloudEvent.log(2, 'line one\nline two'))
          + dvCloudEncodeEvent(const DVCloudEvent.status(3, DVCloudBuildStatus.failed));
      for (int cut = 0; cut <= wire.length; cut++) {
        final DVCloudEventParser parser = DVCloudEventParser();
        final List<DVCloudEvent> events = <DVCloudEvent>[
          ...parser.add(wire.substring(0, cut)),
          ...parser.add(wire.substring(cut)),
        ];
        expect(events.map((DVCloudEvent e) => e.id), <int>[1, 2, 3], reason: 'cut at $cut');
        expect(events[0].line, 'Running Gradle task');
        expect(events[1].line, 'line one\nline two');
        expect(events[2].status, DVCloudBuildStatus.failed);
      }
    });

    test('comments keep a connection open and are not events', () {
      final DVCloudEventParser parser = DVCloudEventParser();
      expect(parser.add(': keep-alive\n\n'), isEmpty);
    });
  });

  group('credentials', () {
    test('names what a build signs and publishes with, and nothing else', () {
      expect(dvCloudCredentialNames, containsAll(<String>[
        'android-keystore',
        'android-keystore-password',
        'android-key-alias',
        'firebase-service-account',
        'play-service-account',
        'appstore-api-key',
        'appstore-api-key-id',
        'appstore-api-issuer',
        'ios-distribution-certificate',
        'ios-provisioning-profile',
      ]));
      expect(dvCloudIsCredentialName('android-keystore'), isTrue);
      expect(dvCloudIsCredentialName('AWS_SECRET'), isFalse);
    });
  });

  group('what is uploaded', () {
    test('leaves out build output, tool caches, VCS and env files', () {
      for (final String path in <String>[
        'build/app/outputs/app.apk',
        'android/app/build/intermediates/x',
        '.dart_tool/package_config.json',
        '.git/HEAD',
        'ios/Pods/Manifest.lock',
        'android/.gradle/cache',
        'node_modules/a/index.js',
        '.env',
        '.env.local',
        'config/.env.production',
      ]) {
        expect(dvCloudSourceExcluded(path), isTrue, reason: path);
      }
      for (final String path in <String>[
        'lib/main.dart',
        'lib/build.dart',
        'lib/pages/build/index.dart',
        'examples/shop/lib/pages/build/index.dart',
        '.env.example',
        'pubspec.yaml',
        'android/app/src/main/AndroidManifest.xml',
      ]) {
        expect(dvCloudSourceExcluded(path, app: 'examples/shop'), isFalse, reason: path);
      }
    });

    test('an application inside a repository has its own build output left out', () {
      expect(dvCloudSourceExcluded('examples/shop/build/web/index.html', app: 'examples/shop'), isTrue);
      expect(dvCloudSourceExcluded('examples/shop/android/app/build/x', app: 'examples/shop'), isTrue);
      expect(dvCloudSourceExcluded('examples/shop/ios/build/x', app: 'examples/shop'), isTrue);
      expect(dvCloudSourceExcluded('packages/core/lib/build.dart', app: 'examples/shop'), isFalse);
    });
  });

  group('refusals', () {
    test('an account with no plan is told so, with where to get one', () {
      final DVCloudRefusal refusal = DVCloudRefusal.fromResponse(402, <String, Object?>{
        'code': 'plan_required',
        'message': 'Cloud builds need a plan.',
        'url': 'https://dartvel.dev/cloud#plans',
      });
      expect(refusal.planRequired, isTrue);
      expect(refusal.url, 'https://dartvel.dev/cloud#plans');
    });

    test('a 402 that says nothing still names the plans page', () {
      final DVCloudRefusal refusal = DVCloudRefusal.fromResponse(402, null);
      expect(refusal.planRequired, isTrue);
      expect(refusal.url, dvCloudPlansUrl);
      expect(refusal.message, isNotEmpty);
    });

    test('other refusals are not about the plan', () {
      final DVCloudRefusal refusal =
          DVCloudRefusal.fromResponse(401, <String, Object?>{'message': 'bad token'});
      expect(refusal.planRequired, isFalse);
      expect(refusal.message, 'bad token');
    });
  });

  test('a project is named the way pubspec.yaml names a package', () {
    expect(dvCloudIsProjectName('shop_app'), isTrue);
    expect(dvCloudIsProjectName('Shop'), isFalse);
    expect(dvCloudIsProjectName('shop/app'), isFalse);
    expect(dvCloudIsProjectName(''), isFalse);
  });
}

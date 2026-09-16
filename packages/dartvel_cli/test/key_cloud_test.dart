// `dartvel key cloud`: signing and store credentials into the repository's
// Actions secrets, where the cloud build workflow reads them. Dartvel keeps
// none of it, and prints none of it.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/key_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Map<String, String> set;
  late List<String> repos;
  late List<String> logs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_key_cloud_');
    set = <String, String>{};
    repos = <String>[];
    logs = <String>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  Future<void> key(List<String> args, {Map<String, String>? environment, bool ghMissing = false}) =>
      (CommandRunner<void>('dartvel', 'test')
            ..addCommand(KeyCommand(
              cloud: KeyCloudCommand(
                root: root.path,
                environment: environment ??
                    <String, String>{'DARTVEL_ANDROID_KEYSTORE_PASSWORD': 'store-pass-1'},
                log: logs.add,
                remote: (String dir) async => 'git@github.com:acme/shop.git',
                setSecret: (String name, String value, String repo) async {
                  if (ghMissing) throw const ProcessException('gh', <String>[]);
                  set[name] = value;
                  repos.add(repo);
                  return 0;
                },
              ),
            )))
          .run(<String>['key', 'cloud', ...args]);

  File file(String name, List<int> bytes) =>
      File(p.join(root.path, name))..writeAsBytesSync(bytes);

  test('sets the Android keystore the workflow signs with, and prints no value', () async {
    final List<int> jks = <int>[0xfe, 0xed, 0xfe, 0xed, 0, 1, 2];
    file('upload.jks', jks);
    await key(<String>['--android-keystore', 'upload.jks', '--android-key-alias', 'upload']);
    expect(exitCode, 0, reason: logs.join('\n'));
    expect(set['DARTVEL_ANDROID_KEYSTORE_BASE64'], base64.encode(jks));
    expect(set['DARTVEL_ANDROID_KEYSTORE_PASSWORD'], 'store-pass-1');
    expect(set['DARTVEL_ANDROID_KEY_ALIAS'], 'upload');
    expect(set.containsKey('DARTVEL_ANDROID_KEY_PASSWORD'), isFalse,
        reason: 'the workflow falls back to the store password');
    expect(repos, everyElement('acme/shop'));
    final String out = logs.join('\n');
    expect(out, contains('DARTVEL_ANDROID_KEYSTORE_BASE64'));
    expect(out, isNot(contains('store-pass-1')));
    expect(out, isNot(contains(base64.encode(jks))));
  });

  test('a keystore with no password is refused before anything is set', () async {
    file('upload.jks', <int>[1]);
    await key(<String>['--android-keystore', 'upload.jks', '--android-key-alias', 'upload'],
        environment: <String, String>{});
    expect(exitCode, 78);
    expect(logs.join('\n'), contains('DARTVEL_ANDROID_KEYSTORE_PASSWORD'));
    expect(set, isEmpty);
  });

  test('a keystore with no alias is refused', () async {
    file('upload.jks', <int>[1]);
    await key(<String>['--android-keystore', 'upload.jks']);
    expect(exitCode, 64);
    expect(set, isEmpty);
  });

  test('a file that is not there is refused before anything is set', () async {
    file('firebase.json', utf8.encode('{}'));
    await key(<String>['--firebase-service-account', 'firebase.json',
        '--android-keystore', 'missing.jks', '--android-key-alias', 'upload']);
    expect(exitCode, 66);
    expect(set, isEmpty);
  });

  test('the Firebase service account goes in as it is', () async {
    file('firebase.json', utf8.encode('{"type":"service_account"}'));
    await key(<String>['--firebase-service-account', 'firebase.json', '--repo', 'acme/other']);
    expect(set, <String, String>{'DARTVEL_FIREBASE_SERVICE_ACCOUNT': '{"type":"service_account"}'});
    expect(repos, <String>['acme/other']);
  });

  test('--dry-run names the secrets and sets none', () async {
    file('firebase.json', utf8.encode('{}'));
    await key(<String>['--firebase-service-account', 'firebase.json', '--dry-run']);
    expect(exitCode, 0);
    expect(set, isEmpty);
    expect(logs.join('\n'), contains('DARTVEL_FIREBASE_SERVICE_ACCOUNT'));
  });

  test('nothing to set is a usage error', () async {
    await key(<String>[]);
    expect(exitCode, 64);
  });

  test('without gh it says so, rather than failing somewhere inside', () async {
    file('firebase.json', utf8.encode('{}'));
    await key(<String>['--firebase-service-account', 'firebase.json'], ghMissing: true);
    expect(exitCode, 69);
    expect(logs.join('\n'), contains('gh'));
  });
}

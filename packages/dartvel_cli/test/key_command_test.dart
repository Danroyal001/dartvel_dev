import 'dart:convert';
// dartvel key generate | rotate | status.
//
// The application key is generated per install and per user, into the
// platform key store and never the repo. The command is the developer's
// hand on that: generate refuses to replace a key that exists, because a
// replaced key is every encrypted store on the machine lost; rotate is the
// deliberate version of the same thing and says both fingerprints; status
// says whether there is a key, where it is held, and never what it is.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/key_command.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  late DVFileAppKeyStore store;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dv_keycmd_');
    store = DVFileAppKeyStore('${home.path}/.dartvel/keys/shop.key');
  });
  tearDown(() => home.deleteSync(recursive: true));

  group('the tool', () {
    test('generate writes a key and says where; a second generate refuses', () async {
      final DVKeyTool tool = DVKeyTool(store);
      final DVKeyResult first = await tool.generate();
      expect(first.ok, isTrue);
      expect(await store.read(), isNotNull);
      expect(first.message, contains(first.fingerprint!));
      expect(first.message, contains(home.path), reason: 'where it is held');

      final DVKeyResult second = await tool.generate();
      expect(second.ok, isFalse);
      expect(second.message, contains('rotate'));
      expect(second.message, isNot(contains('--force')), reason: 'there is no force; rotate is the deliberate path');
    });

    test('status says absent, then present with the fingerprint, never the key', () async {
      final DVKeyTool tool = DVKeyTool(store);
      expect((await tool.status()).message, contains('No application key'));
      await tool.generate();
      final DVKeyResult status = await tool.status();
      expect(status.ok, isTrue);
      expect(status.fingerprint, hasLength(16));
      expect(status.message, contains(status.fingerprint!));
      expect(status.message, isNot(contains(base64Encode((await store.read())!))));
      expect(status.message, isNot(contains((await store.read())!.map((int b) => b.toRadixString(16).padLeft(2, '0')).join())));
    });

    test('rotate replaces the key and names both fingerprints', () async {
      final DVKeyTool tool = DVKeyTool(store);
      final String before = (await tool.generate()).fingerprint!;
      final DVKeyResult rotated = await tool.rotate();
      expect(rotated.ok, isTrue);
      expect(rotated.fingerprint, isNot(before));
      expect(rotated.message, contains(before));
      expect(rotated.message, contains(rotated.fingerprint!));
      expect((await tool.status()).fingerprint, rotated.fingerprint);
    });

    test('rotate with no key is a generate, and says so', () async {
      final DVKeyResult rotated = await DVKeyTool(store).rotate();
      expect(rotated.ok, isTrue);
      expect(rotated.message, contains('no key to rotate'));
      expect(await store.read(), isNotNull);
    });

    test('the fingerprint is the same for the same key', () async {
      final DVKeyTool tool = DVKeyTool(store);
      final String a = (await tool.generate()).fingerprint!;
      expect((await DVKeyTool(DVFileAppKeyStore(store.path)).status()).fingerprint, a);
    });
  });

  group('the command', () {
    test('key generate --store file --home writes under that home', () async {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')..addCommand(KeyCommand());
      await runner.run(<String>['key', 'generate', '--store', 'file', '--home', home.path, '--app', 'shop']);
      expect(File('${home.path}/.dartvel/keys/shop.key').existsSync(), isTrue);
    });

    test('a second generate exits non-zero', () async {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')..addCommand(KeyCommand());
      await runner.run(<String>['key', 'generate', '--store', 'file', '--home', home.path, '--app', 'shop']);
      await expectLater(
        runner.run(<String>['key', 'generate', '--store', 'file', '--home', home.path, '--app', 'shop']),
        throwsA(isA<UsageException>().having((UsageException e) => e.message, 'message', contains('rotate'))),
      );
    });

    test('--app defaults to the pubspec name in the working directory', () {
      expect(KeyCommand.appNameFrom('name: shop_app\nversion: 1.0.0\n'), 'shop_app');
      expect(KeyCommand.appNameFrom('version: 1.0.0\n'), 'dartvel');
    });
  });
}

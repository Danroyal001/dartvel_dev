// Secrets a supervisor hands the process as credential files.
//
// dartvel infra delivers a secret as an encrypted systemd credential, which
// systemd decrypts into a private directory named by $CREDENTIALS_DIRECTORY
// while the unit runs. DV.Secrets read the process environment and .env and
// nothing else, so a secret provisioned that way reached the host and not the
// application: the first request that needed it failed on a machine where it
// was correctly installed.
//
// The quiet failures: a key used as a path, so `../` reads a file outside the
// directory; a .env checked into the repository shadowing what was
// provisioned; a directory that does not exist throwing instead of resolving
// nothing; and a test's directory outliving the test.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory credentials;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_credentials_');
    credentials = Directory('${root.path}/credentials')..createSync();
    DVSecrets.reset();
    DVSecrets.useEnvFile('${root.path}/.env');
    DVSecrets.useCredentialsDirectory(credentials.path);
  });

  tearDown(() {
    DVSecrets.reset();
    root.deleteSync(recursive: true);
  });

  test('a credential file resolves when nothing else supplies the key', () {
    File('${credentials.path}/DV_TEST_PAYSTACK_SECRET')
        .writeAsStringSync('sk_live_from-the-credential');
    expect(
      const DVSecrets().maybeGet('DV_TEST_PAYSTACK_SECRET'),
      'sk_live_from-the-credential',
    );
  });

  test('the value is exactly the file, with nothing trimmed or added', () {
    File('${credentials.path}/DV_TEST_TOKEN').writeAsStringSync(' spaced value\n');
    expect(const DVSecrets().maybeGet('DV_TEST_TOKEN'), ' spaced value\n');
  });

  test('a .env value does not shadow a provisioned credential', () {
    File('${root.path}/.env').writeAsStringSync('DV_TEST_DB=from-the-repo\n');
    File('${credentials.path}/DV_TEST_DB').writeAsStringSync('from-the-host');
    expect(const DVSecrets().maybeGet('DV_TEST_DB'), 'from-the-host');
  });

  test('configured values still come first', () {
    File('${credentials.path}/DV_TEST_KEY').writeAsStringSync('from-the-host');
    DVSecrets.configure(<String, String>{'DV_TEST_KEY': 'from-the-test'});
    expect(const DVSecrets().maybeGet('DV_TEST_KEY'), 'from-the-test');
  });

  test('a key that is not a plain name is never read as a path', () {
    File('${root.path}/outside').writeAsStringSync('not a credential');
    Directory('${credentials.path}/nested').createSync();
    File('${credentials.path}/nested/inner').writeAsStringSync('nested');
    for (final String key in <String>[
      '../outside',
      'nested/inner',
      '/etc/passwd',
      '..',
      '.',
      '',
    ]) {
      expect(const DVSecrets().maybeGet(key), isNull, reason: key);
    }
  });

  test('an empty credential file is absent, like an empty variable', () {
    File('${credentials.path}/DV_TEST_EMPTY').writeAsStringSync('');
    expect(const DVSecrets().has('DV_TEST_EMPTY'), isFalse);
  });

  test('a directory that does not exist resolves nothing and does not throw',
      () {
    DVSecrets.useCredentialsDirectory('${root.path}/missing');
    expect(const DVSecrets().maybeGet('DV_TEST_ANYTHING'), isNull);
  });

  test('a resolved credential is struck out of text like any other secret',
      () {
    File('${credentials.path}/DV_TEST_REDACT')
        .writeAsStringSync('sk_live_redact-me-please');
    const DVSecrets().get('DV_TEST_REDACT');
    expect(
      DVSecrets.redact('upstream said sk_live_redact-me-please was wrong'),
      isNot(contains('sk_live_redact-me-please')),
    );
  });

  test('reset stops reading the directory a test pointed at', () {
    File('${credentials.path}/DV_TEST_AFTER_RESET').writeAsStringSync('leaked');
    DVSecrets.reset();
    DVSecrets.useEnvFile('${root.path}/.env');
    expect(const DVSecrets().maybeGet('DV_TEST_AFTER_RESET'), isNull);
  });
}

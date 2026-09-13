// Second factors: TOTP and recovery codes.
//
// The failures worth testing are the quiet ones. A TOTP check with no replay
// protection accepts the same six digits for the whole window, so a code read
// over a shoulder is a second sign-in. A TOTP secret stored in the clear makes
// the second factor a copy of the first. Recovery codes stored as themselves,
// or readable back, turn a database dump or a support ticket into account
// takeover — which is why they are hashed, shown once, and single use.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVFieldCipher _cipher() => DVFieldCipher.secure(
      DVFieldKeyring(<DVFieldKey>[
        DVFieldKey('k1', Uint8List.fromList(List<int>.generate(32, (int i) => i))),
      ]),
    );

void main() {
  group('TOTP (RFC 6238)', () {
    // Appendix B: the SHA-1 secret is the ASCII bytes of "12345678901234567890"
    // and the codes are eight digits.
    final Uint8List secret = Uint8List.fromList(utf8.encode('12345678901234567890'));
    const DVTotp eight = DVTotp(digits: 8);

    for (final (int seconds, String code) vector in <(int, String)>[
      (59, '94287082'),
      (1111111109, '07081804'),
      (1111111111, '14050471'),
      (1234567890, '89005924'),
      (2000000000, '69279037'),
      (20000000000, '65353130'),
    ]) {
      test('T=${vector.$1} gives ${vector.$2}', () {
        expect(
          eight.generate(secret,
              at: DateTime.fromMillisecondsSinceEpoch(vector.$1 * 1000,
                  isUtc: true)),
          vector.$2,
        );
      });
    }

    test('base32 round-trips the secret an authenticator app is given', () {
      final String encoded = DVTotp.base32Encode(secret);
      expect(encoded, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(DVTotp.base32Decode(encoded), secret);
      expect(DVTotp.base32Decode('gezd gnbv-gy3t qojq gezd gnbv gy3t qojq'),
          secret, reason: 'people type these with spaces and lower case');
    });

    test('the provisioning URI is what a QR code encodes', () {
      final Uri uri = const DVTotp().provisioningUri(
        secret: 'GEZDGNBVGY3TQOJQ',
        issuer: 'Acme Cloud',
        account: 'ada@example.com',
      );
      expect(uri.scheme, 'otpauth');
      expect(uri.host, 'totp');
      // Percent-encoded on the wire, as the key-uri format requires; decoded
      // here to compare what the app will show.
      expect(Uri.decodeComponent(uri.path), '/Acme Cloud:ada@example.com');
      expect(uri.queryParameters['secret'], 'GEZDGNBVGY3TQOJQ');
      expect(uri.queryParameters['issuer'], 'Acme Cloud');
      expect(uri.queryParameters['digits'], '6');
      expect(uri.queryParameters['period'], '30');
    });

    test('a code is accepted one step either side, and not beyond', () {
      const DVTotp totp = DVTotp();
      final DateTime at = DateTime.utc(2026, 9, 13, 12);
      final String code = totp.generate(secret, at: at);

      expect(totp.verify(code, secret, at: at.add(const Duration(seconds: 29))),
          isNotNull);
      expect(totp.verify(code, secret, at: at.add(const Duration(seconds: 61))),
          isNull);
      expect(totp.verify('12345', secret, at: at), isNull);
      expect(totp.verify('abcdef', secret, at: at), isNull);
    });

    test('a step already used is refused even inside its window', () {
      const DVTotp totp = DVTotp();
      final DateTime at = DateTime.utc(2026, 9, 13, 12);
      final String code = totp.generate(secret, at: at);

      final int? step = totp.verify(code, secret, at: at);
      expect(step, isNotNull);
      expect(totp.verify(code, secret, at: at, lastUsedStep: step), isNull,
          reason: 'the same six digits must not sign in twice');
    });
  });

  group('second factors', () {
    late DateTime now;
    late DVSecondFactorStore store;
    late DVSecondFactors factors;

    setUp(() {
      now = DateTime.utc(2026, 9, 13, 12);
      store = DVDatabaseSecondFactorStore(MemoryDVDatabaseAdapter());
      factors = DVSecondFactors(
        store: store,
        cipher: _cipher(),
        issuer: 'Acme Cloud',
        clock: () => now,
      );
    });

    group('TOTP enrollment', () {
      test('enrollment is pending until a code proves the app has it',
          () async {
        final DVTotpEnrollment enrollment =
            await factors.beginTotp('user-1', account: 'ada@example.com');
        expect(enrollment.uri.queryParameters['secret'], enrollment.secret);
        expect(await factors.hasTotp('user-1'), isFalse);

        final String code = const DVTotp()
            .generate(DVTotp.base32Decode(enrollment.secret), at: now);
        expect(await factors.confirmTotp('user-1', code), isTrue);
        expect(await factors.hasTotp('user-1'), isTrue);
      });

      test('a wrong confirmation code does not enroll', () async {
        await factors.beginTotp('user-1', account: 'ada@example.com');
        expect(await factors.confirmTotp('user-1', '000000'), isFalse);
        expect(await factors.hasTotp('user-1'), isFalse);
      });

      test('the stored secret is sealed, never the base32 a QR code shows',
          () async {
        final DVTotpEnrollment enrollment =
            await factors.beginTotp('user-1', account: 'ada@example.com');
        final String dump = jsonEncode(await store.debugRows());
        expect(dump, isNot(contains(enrollment.secret)));
        expect(dump, contains('dvf1:'),
            reason: 'sealed with the field cipher, not merely renamed');
      });

      test('a verified code cannot be replayed', () async {
        final DVTotpEnrollment enrollment =
            await factors.beginTotp('user-1', account: 'ada@example.com');
        final Uint8List secret = DVTotp.base32Decode(enrollment.secret);
        await factors.confirmTotp(
            'user-1', const DVTotp().generate(secret, at: now));

        now = now.add(const Duration(seconds: 30));
        final String code = const DVTotp().generate(secret, at: now);
        expect(await factors.verifyTotp('user-1', code), isTrue);
        expect(await factors.verifyTotp('user-1', code), isFalse);
      });

      test('the confirmation code cannot then be used to sign in', () async {
        final DVTotpEnrollment enrollment =
            await factors.beginTotp('user-1', account: 'ada@example.com');
        final String code = const DVTotp()
            .generate(DVTotp.base32Decode(enrollment.secret), at: now);
        await factors.confirmTotp('user-1', code);
        expect(await factors.verifyTotp('user-1', code), isFalse);
      });

      test('an account with no TOTP does not verify any code', () async {
        expect(await factors.verifyTotp('nobody', '123456'), isFalse);
      });
    });

    group('recovery codes', () {
      test('ten are shown once, and each works exactly once', () async {
        final DVRecoveryCodes codes =
            await factors.regenerateRecoveryCodes('user-1');
        expect(codes.codes, hasLength(10));
        expect(codes.codes.toSet(), hasLength(10));

        expect(await factors.redeemRecoveryCode('user-1', codes.codes[3]),
            isTrue);
        expect(await factors.redeemRecoveryCode('user-1', codes.codes[3]),
            isFalse);
        expect(await factors.remainingRecoveryCodes('user-1'), 9);
      });

      test('typing a code in lower case or without its hyphen still works',
          () async {
        final DVRecoveryCodes codes =
            await factors.regenerateRecoveryCodes('user-1');
        final String typed =
            codes.codes.first.replaceAll('-', '').toLowerCase();
        expect(await factors.redeemRecoveryCode('user-1', typed), isTrue);
      });

      test('a wrong code, or another person\'s, is refused', () async {
        final DVRecoveryCodes mine =
            await factors.regenerateRecoveryCodes('user-1');
        await factors.regenerateRecoveryCodes('user-2');
        expect(await factors.redeemRecoveryCode('user-1', 'AAAAA-AAAAA'),
            isFalse);
        expect(await factors.redeemRecoveryCode('user-2', mine.codes.first),
            isFalse);
      });

      test('codes are stored hashed and cannot be read back', () async {
        final DVRecoveryCodes codes =
            await factors.regenerateRecoveryCodes('user-1');
        final String dump = jsonEncode(await store.debugRows());
        for (final String code in codes.codes) {
          expect(dump, isNot(contains(code)));
          expect(dump, isNot(contains(code.replaceAll('-', ''))));
        }
        expect(codes.toString(), isNot(contains(codes.codes.first)),
            reason: 'a codes object printed into a log must not print them');
      });

      test('regenerating invalidates every earlier code', () async {
        final DVRecoveryCodes first =
            await factors.regenerateRecoveryCodes('user-1');
        final DVRecoveryCodes second =
            await factors.regenerateRecoveryCodes('user-1');
        expect(await factors.redeemRecoveryCode('user-1', first.codes.first),
            isFalse);
        expect(await factors.redeemRecoveryCode('user-1', second.codes.first),
            isTrue);
      });
    });
  });
}

import 'dart:math';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVAuthTokens tokens;

  setUp(() {
    tokens = DVAuthTokens();
  });

  group('magic links', () {
    test('a link carries the token and redeems to its identifier', () async {
      final link = await tokens.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/signin'),
      );

      expect(link.url.queryParameters['token'], link.token);
      final result = await tokens.redeemMagicLink(link.token);
      expect(result.isSuccess, isTrue);
      expect(result.identifier, 'ada@example.com');
    });

    test('a link is single use', () async {
      // Links sit in mailboxes indefinitely; a replayable one is a standing
      // credential.
      final link = await tokens.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/signin'),
      );
      await tokens.redeemMagicLink(link.token);

      final again = await tokens.redeemMagicLink(link.token);
      expect(again.isSuccess, isFalse);
    });

    test('an expired link does not redeem', () async {
      final shortLived = DVAuthTokens(lifetime: const Duration(milliseconds: 20));
      final link = await shortLived.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/signin'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await shortLived.redeemMagicLink(link.token)).isSuccess, isFalse);
    });

    test('an unknown token is refused', () async {
      expect(
        (await tokens.redeemMagicLink('not-a-real-token')).isSuccess,
        isFalse,
      );
    });

    test('existing query parameters on the base URL survive', () async {
      final link = await tokens.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/signin?next=/dashboard'),
      );

      expect(link.url.queryParameters['next'], '/dashboard');
      expect(link.url.queryParameters['token'], isNotEmpty);
    });

    test('the URL reveals nothing about the recipient', () async {
      final link = await tokens.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/signin'),
      );

      expect(link.url.toString(), isNot(contains('ada')));
      expect(link.url.toString(), isNot(contains('example.com/signin?token=ada')));
    });
  });

  group('one-time passcodes', () {
    test('a code redeems for its identifier', () async {
      final code = await tokens.issueOtp('ada@example.com');

      expect(code, hasLength(6));
      expect(int.tryParse(code), isNotNull);
      final result = await tokens.redeemOtp('ada@example.com', code);
      expect(result.identifier, 'ada@example.com');
    });

    test('a code is single use', () async {
      final code = await tokens.issueOtp('ada@example.com');
      await tokens.redeemOtp('ada@example.com', code);

      expect(
        (await tokens.redeemOtp('ada@example.com', code)).isSuccess,
        isFalse,
      );
    });

    test('a code does not work for a different identifier', () async {
      final code = await tokens.issueOtp('ada@example.com');

      expect((await tokens.redeemOtp('bob@example.com', code)).isSuccess,
          isFalse);
      // And the real owner can still use it.
      expect(
        (await tokens.redeemOtp('ada@example.com', code)).isSuccess,
        isTrue,
      );
    });

    test('wrong attempts throttle rather than run forever', () async {
      // Six digits is a million possibilities; without a cap that is
      // guessable in minutes.
      final limited = DVAuthTokens(maxAttempts: 3);
      await limited.issueOtp('ada@example.com');

      for (var i = 0; i < 3; i++) {
        final wrong = await limited.redeemOtp('ada@example.com', '000000');
        expect(wrong.failure, DVAuthTokenFailure.invalid);
      }

      final blocked = await limited.redeemOtp('ada@example.com', '000000');
      expect(blocked.failure, DVAuthTokenFailure.throttled);
      expect(blocked.reveal, contains('Too many attempts'));
    });

    test('a wrong guess does not cancel a pending sign-in', () async {
      // Deleting on the first wrong digit would let anyone lock out a user
      // by guessing once.
      final code = await tokens.issueOtp('ada@example.com');
      await tokens.redeemOtp('ada@example.com', '999999');

      expect(
        (await tokens.redeemOtp('ada@example.com', code)).isSuccess,
        isTrue,
      );
    });

    test('reissuing replaces the outstanding code', () async {
      final first = await tokens.issueOtp('ada@example.com');
      final second = await tokens.issueOtp('ada@example.com');

      expect((await tokens.redeemOtp('ada@example.com', first)).isSuccess,
          isFalse);
      expect((await tokens.redeemOtp('ada@example.com', second)).isSuccess,
          isTrue);
    });

    test('an expired code does not redeem', () async {
      final shortLived =
          DVAuthTokens(lifetime: const Duration(milliseconds: 20));
      final code = await shortLived.issueOtp('ada@example.com');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        (await shortLived.redeemOtp('ada@example.com', code)).isSuccess,
        isFalse,
      );
    });

    test('code length is configurable', () async {
      expect(await tokens.issueOtp('ada@example.com', digits: 8), hasLength(8));
    });
  });

  group('disclosure', () {
    test('every failure reads the same to a user', () async {
      // Distinguishing "no such code" from "expired" from "already used"
      // lets an attacker enumerate which codes existed.
      final unknown = await tokens.redeemMagicLink('nope');
      final shortLived =
          DVAuthTokens(lifetime: const Duration(milliseconds: 10));
      final link = await shortLived.issueMagicLink(
        'ada@example.com',
        baseUrl: Uri.parse('https://example.com/s'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final expired = await shortLived.redeemMagicLink(link.token);

      expect(unknown.reveal, expired.reveal);
    });
  });

  group('storage', () {
    test('the secret is never stored, only its hash', () async {
      final store = DVMemoryAuthTokenStore();
      final withStore = DVAuthTokens(store: store);
      final code = await withStore.issueOtp('ada@example.com');

      final record = await store.get('otp:ada@example.com');
      // A dump of this table must not let anyone sign in.
      expect(record, isNotNull);
      expect(record!.hash, isNot(code));
      expect(record.hash, hasLength(64)); // sha256 hex
    });

    test('a seeded Random makes codes reproducible for tests only', () async {
      final a = DVAuthTokens(random: Random(42));
      final b = DVAuthTokens(random: Random(42));

      expect(
        await a.issueOtp('x'),
        await b.issueOtp('x'),
      );
    });
  });
}

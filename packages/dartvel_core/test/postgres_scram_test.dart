// SCRAM-SHA-256, the password exchange Postgres has used by default since 14.
//
// The adapter spoke trust and md5 only, so against a stock Postgres 14+ it
// never got past authentication: the server asked for SASL, the adapter had
// no answer, and the connection hung until the next query wrote a Parse
// message into the middle of the exchange ("expected SASL response, got
// message type 80").
//
// The exchange is pure: four messages and a password. RFC 7677 publishes one
// complete run of it, which is the first test here.
import 'package:dartvel_core/src/database/postgres_scram.dart';
import 'package:test/test.dart';

const String _rfcServerFirst =
    r'r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,'
    's=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096';
const String _rfcClientFinal =
    r'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,'
    'p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=';
const String _rfcServerFinal = 'v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=';

DVScramSha256 _rfcClient() => DVScramSha256(
      password: 'pencil',
      username: 'user',
      clientNonce: 'rOprNGfwEbeRWgbNEkqO',
    );

void main() {
  group('RFC 7677 section 3 test vector', () {
    test('client-first carries the gs2 header, the user and the nonce', () {
      expect(_rfcClient().clientFirstMessage(), 'n,,n=user,r=rOprNGfwEbeRWgbNEkqO');
    });

    test('client-final carries the proof the RFC computes', () {
      final DVScramSha256 scram = _rfcClient();
      scram.clientFirstMessage();
      expect(scram.clientFinalMessage(_rfcServerFirst), _rfcClientFinal);
    });

    test("the server's signature is accepted when it is the right one", () {
      final DVScramSha256 scram = _rfcClient();
      scram.clientFirstMessage();
      scram.clientFinalMessage(_rfcServerFirst);
      expect(() => scram.verifyServerFinal(_rfcServerFinal), returnsNormally);
      expect(scram.isVerified, isTrue);
    });
  });

  group('what the client refuses', () {
    test('a wrong server signature: the server never knew the password', () {
      final DVScramSha256 scram = _rfcClient();
      scram.clientFirstMessage();
      scram.clientFinalMessage(_rfcServerFirst);
      expect(
        () => scram.verifyServerFinal(
          'v=AAAATRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=',
        ),
        throwsA(isA<DVScramException>()),
      );
      expect(scram.isVerified, isFalse);
    });

    test('a server nonce that does not extend the client nonce', () {
      final DVScramSha256 scram = _rfcClient();
      scram.clientFirstMessage();
      expect(
        () => scram.clientFinalMessage(
          'r=somebodyElse123,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096',
        ),
        throwsA(isA<DVScramException>()),
      );
    });

    test('a server-first missing its salt or iteration count', () {
      for (final String broken in <String>[
        r'r=rOprNGfwEbeRWgbNEkqO%hvY,i=4096',
        r'r=rOprNGfwEbeRWgbNEkqO%hvY,s=W22ZaJ0SNY7soEsUEjb6gQ==',
        r'r=rOprNGfwEbeRWgbNEkqO%hvY,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=0',
      ]) {
        final DVScramSha256 scram = _rfcClient();
        scram.clientFirstMessage();
        expect(
          () => scram.clientFinalMessage(broken),
          throwsA(isA<DVScramException>()),
          reason: broken,
        );
      }
    });

    test('a server-final that reports an error', () {
      final DVScramSha256 scram = _rfcClient();
      scram.clientFirstMessage();
      scram.clientFinalMessage(_rfcServerFirst);
      expect(
        () => scram.verifyServerFinal('e=invalid-proof'),
        throwsA(
          isA<DVScramException>().having(
            (DVScramException e) => e.message,
            'message',
            contains('invalid-proof'),
          ),
        ),
      );
    });

    test('messages out of order', () {
      final DVScramSha256 scram = _rfcClient();
      expect(
        () => scram.clientFinalMessage(_rfcServerFirst),
        throwsA(isA<DVScramException>()),
      );
      expect(
        () => scram.verifyServerFinal(_rfcServerFinal),
        throwsA(isA<DVScramException>()),
      );
    });
  });

  test('a generated nonce is fresh, printable and comma-free', () {
    final String first = DVScramSha256(password: 'x').clientFirstMessage();
    final String second = DVScramSha256(password: 'x').clientFirstMessage();
    // Postgres ignores the SCRAM user name (it has the startup one), and
    // libpq sends it empty; so does this client.
    expect(first, startsWith('n,,n=,r='));
    final String nonce = first.substring('n,,n=,r='.length);
    expect(nonce.length, greaterThanOrEqualTo(18));
    expect(nonce, isNot(contains(',')));
    expect(RegExp(r'^[\x21-\x7e]+$').hasMatch(nonce), isTrue);
    expect(second, isNot(first));
  });
}

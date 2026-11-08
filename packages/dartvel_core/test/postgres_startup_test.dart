// The startup conversation, against a scripted server.
//
// Three failures here made the adapter unusable against a current Postgres,
// and all three showed up only as "connection closed" or a 30-second hang:
//
// - The server asked for SASL (SCRAM-SHA-256, the default since Postgres 14)
//   and the adapter had no answer. It recorded an error and waited for a
//   ReadyForQuery that a server mid-authentication never sends.
// - The connection counted as open from the moment the socket was, so a
//   second query arriving during that wait wrote its Parse message into the
//   authentication exchange ("expected SASL response, got message type 80").
// - A server that refuses a login sends an ErrorResponse and hangs up without
//   a ReadyForQuery, so the real reason ("password authentication failed",
//   28P01) was dropped and the caller saw only that the socket closed.
//
// The live tests cover a real server; these pin each failure down without one.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A connection whose far end is [onMessage], called with each frontend
/// message (the untyped startup message gets type 0).
class _ScriptedConnection implements DVPostgresConnection {
  _ScriptedConnection(this.onMessage);

  final void Function(_ScriptedConnection connection, int type, Uint8List body)
      onMessage;
  final StreamController<List<int>> _input = StreamController<List<int>>();
  final List<int> _pending = <int>[];
  final List<int> types = <int>[];
  bool _startupSeen = false;
  bool closed = false;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void write(List<int> bytes) {
    _pending.addAll(bytes);
    while (true) {
      if (!_startupSeen) {
        if (_pending.length < 4) return;
        final int length = _int32(_pending, 0);
        if (_pending.length < length) return;
        final Uint8List body = Uint8List.fromList(_pending.sublist(4, length));
        _pending.removeRange(0, length);
        _startupSeen = true;
        types.add(0);
        onMessage(this, 0, body);
        continue;
      }
      if (_pending.length < 5) return;
      final int length = _int32(_pending, 1);
      if (_pending.length < length + 1) return;
      final int type = _pending[0];
      final Uint8List body = Uint8List.fromList(_pending.sublist(5, length + 1));
      _pending.removeRange(0, length + 1);
      types.add(type);
      onMessage(this, type, body);
    }
  }

  void send(int type, List<int> body) {
    if (closed) return;
    _input.add(<int>[type, ..._be32(body.length + 4), ...body]);
  }

  void auth(int code, [List<int> extra = const <int>[]]) =>
      send(0x52, <int>[..._be32(code), ...extra]);

  void ready() => send(0x5A, <int>[0x49]);

  void error(String code, String message) => send(0x45, <int>[
        0x53, ...utf8.encode('FATAL'), 0,
        0x43, ...utf8.encode(code), 0,
        0x4D, ...utf8.encode(message), 0,
        0,
      ]);

  /// The server hanging up.
  void hangUp() {
    if (closed) return;
    closed = true;
    unawaited(_input.close());
  }

  @override
  Future<void> close() async => hangUp();

  static int _int32(List<int> bytes, int offset) =>
      ByteData.sublistView(Uint8List.fromList(bytes.sublist(offset, offset + 4)))
          .getInt32(0);

  static List<int> _be32(int value) =>
      (ByteData(4)..setInt32(0, value)).buffer.asUint8List();
}

List<int> _cstring(String value) => <int>[...utf8.encode(value), 0];

/// Answers a query the way Postgres does to `SELECT 1 AS one`.
void _answerSelectOne(_ScriptedConnection server, int type) {
  if (type != 0x53) return; // wait for Sync
  server.send(0x31, const <int>[]); // ParseComplete
  server.send(0x32, const <int>[]); // BindComplete
  server.send(0x54, <int>[
    0, 1, ..._cstring('one'),
    0, 0, 0, 0, 0, 0, // table oid, column
    0, 0, 0, 23, // int4
    0, 4, 255, 255, 255, 255, 0, 0,
  ]);
  server.send(0x44, <int>[0, 1, 0, 0, 0, 1, 0x31]);
  server.send(0x43, _cstring('SELECT 1'));
  server.ready();
}

DVPostgresDatabaseAdapter _adapter(
  _ScriptedConnection connection, {
  String? password = 'secret',
}) =>
    DVPostgresDatabaseAdapter(
      database: 'app',
      password: password,
      connector: (String host, int port) async => connection,
    );

const Duration _quick = Duration(seconds: 5);

void main() {
  test('a refused login surfaces the server error, not "connection closed"',
      () async {
    final _ScriptedConnection server =
        _ScriptedConnection((_ScriptedConnection s, int type, Uint8List body) {
      if (type == 0) s.auth(5, <int>[1, 2, 3, 4]); // md5
      if (type == 0x70) {
        s.error('28P01', 'password authentication failed for user "postgres"');
        s.hangUp();
      }
    });

    await expectLater(
      _adapter(server).query('SELECT 1').timeout(_quick),
      throwsA(
        isA<DVPostgresException>()
            .having((DVPostgresException e) => e.code, 'code', '28P01')
            .having((DVPostgresException e) => e.message, 'message',
                contains('password authentication failed')),
      ),
    );
  });

  test('an unsupported authentication method fails at once, without a hang',
      () async {
    final _ScriptedConnection server =
        _ScriptedConnection((_ScriptedConnection s, int type, Uint8List body) {
      // AuthenticationGSS. The server now waits for a GSS response forever.
      if (type == 0) s.auth(7);
    });

    await expectLater(
      _adapter(server).query('SELECT 1').timeout(_quick),
      throwsA(
        isA<DVPostgresException>().having((DVPostgresException e) => e.message,
            'message', contains('Unsupported Postgres authentication method')),
      ),
    );
    expect(server.types, <int>[0], reason: 'nothing may follow the startup');
    expect(server.closed, isTrue, reason: 'the half-open socket is closed');
  });

  test('a SASL server offering only SCRAM-SHA-256-PLUS is refused clearly',
      () async {
    final _ScriptedConnection server =
        _ScriptedConnection((_ScriptedConnection s, int type, Uint8List body) {
      if (type == 0) {
        s.auth(10, <int>[..._cstring('SCRAM-SHA-256-PLUS'), 0]);
      }
    });

    await expectLater(
      _adapter(server).query('SELECT 1').timeout(_quick),
      throwsA(
        isA<DVPostgresException>().having((DVPostgresException e) => e.message,
            'message', contains('SCRAM-SHA-256-PLUS')),
      ),
    );
    expect(server.types, <int>[0]);
  });

  test('no query is written into an authentication exchange in progress',
      () async {
    late _ScriptedConnection server;
    final Completer<void> passwordSeen = Completer<void>();
    server = _ScriptedConnection((_ScriptedConnection s, int type, Uint8List b) {
      if (type == 0) s.auth(3); // cleartext password
      if (type == 0x70) passwordSeen.complete();
      if (type == 0x50 && !passwordSeen.isCompleted) {
        fail('a Parse message arrived before authentication finished');
      }
      _answerSelectOne(s, type);
    });
    final DVPostgresDatabaseAdapter adapter = _adapter(server);

    final Future<List<Map<String, Object?>>> first =
        adapter.query('SELECT 1 AS one');
    final Future<List<Map<String, Object?>>> second =
        adapter.query('SELECT 1 AS one');
    await passwordSeen.future.timeout(_quick);
    // Only now does the server finish authenticating.
    expect(server.types.where((int t) => t == 0x50), isEmpty);
    server
      ..auth(0)
      ..ready();

    expect(await first.timeout(_quick), <Map<String, Object?>>[
      <String, Object?>{'one': 1},
    ]);
    expect(await second.timeout(_quick), <Map<String, Object?>>[
      <String, Object?>{'one': 1},
    ]);
  });

  group('SCRAM-SHA-256', () {
    /// Runs the server side of SCRAM-SHA-256 for [password], ending with
    /// [serverSignature] instead of the real one when given.
    _ScriptedConnection scramServer(
      String password, {
      bool forgeSignature = false,
      List<String>? received,
    }) {
      String? clientFirstBare;
      String? serverFirst;
      final List<int> salt = utf8.encode('saltysaltysalt');
      const int iterations = 4096;
      return _ScriptedConnection((_ScriptedConnection s, int type, Uint8List b) {
        if (type == 0) {
          s.auth(10, <int>[
            ..._cstring('SCRAM-SHA-256-PLUS'),
            ..._cstring('SCRAM-SHA-256'),
            0,
          ]);
          return;
        }
        if (type == 0x70 && clientFirstBare == null) {
          // SASLInitialResponse: mechanism, int32 length, client-first.
          final int nul = b.indexOf(0);
          final String mechanism = utf8.decode(b.sublist(0, nul));
          received?.add(mechanism);
          final String clientFirst = utf8.decode(b.sublist(nul + 5));
          expect(clientFirst, startsWith('n,,'));
          clientFirstBare = clientFirst.substring(3);
          final String nonce = clientFirstBare!.split(',')[1].substring(2);
          serverFirst = 'r=${nonce}SERVERPART,s=${base64.encode(salt)},'
              'i=$iterations';
          s.auth(11, utf8.encode(serverFirst!));
          return;
        }
        if (type == 0x70) {
          final String clientFinal = utf8.decode(b);
          final int proofAt = clientFinal.lastIndexOf(',p=');
          final String withoutProof = clientFinal.substring(0, proofAt);
          final List<int> proof =
              base64.decode(clientFinal.substring(proofAt + 3));
          final List<int> salted = _hi(utf8.encode(password), salt, iterations);
          final List<int> clientKey = _hmac(salted, utf8.encode('Client Key'));
          final List<int> storedKey = crypto.sha256.convert(clientKey).bytes;
          final List<int> authMessage =
              utf8.encode('$clientFirstBare,$serverFirst,$withoutProof');
          final List<int> signature = _hmac(storedKey, authMessage);
          final List<int> recovered = <int>[
            for (var i = 0; i < proof.length; i++) proof[i] ^ signature[i],
          ];
          if (crypto.sha256.convert(recovered).toString() !=
              crypto.sha256.convert(clientKey).toString()) {
            s.error('28P01', 'password authentication failed');
            s.hangUp();
            return;
          }
          final List<int> serverKey = _hmac(salted, utf8.encode('Server Key'));
          final List<int> serverSignature = forgeSignature
              ? List<int>.filled(32, 7)
              : _hmac(serverKey, authMessage);
          s.auth(12, utf8.encode('v=${base64.encode(serverSignature)}'));
          if (!forgeSignature) {
            s
              ..auth(0)
              ..ready();
          }
          return;
        }
        if (forgeSignature && type == 0x50) {
          fail('a query was sent after the server signature failed');
        }
        _answerSelectOne(s, type);
      });
    }

    test('connects with the right password and picks the plain mechanism',
        () async {
      final List<String> mechanisms = <String>[];
      final _ScriptedConnection server =
          scramServer('secret', received: mechanisms);
      expect(
        await _adapter(server).query('SELECT 1 AS one').timeout(_quick),
        <Map<String, Object?>>[
          <String, Object?>{'one': 1},
        ],
      );
      expect(mechanisms, <String>['SCRAM-SHA-256']);
    });

    test('a wrong password surfaces the server error', () async {
      await expectLater(
        _adapter(scramServer('secret'), password: 'wrong')
            .query('SELECT 1')
            .timeout(_quick),
        throwsA(isA<DVPostgresException>()
            .having((DVPostgresException e) => e.code, 'code', '28P01')),
      );
    });

    test('a server that cannot prove it knows the password is refused',
        () async {
      final _ScriptedConnection server =
          scramServer('secret', forgeSignature: true);
      await expectLater(
        _adapter(server).query('SELECT 1').timeout(_quick),
        throwsA(isA<DVPostgresException>().having(
            (DVPostgresException e) => e.message,
            'message',
            contains('server signature'))),
      );
      expect(server.closed, isTrue);
    });

    test('no password configured is refused before anything is sent',
        () async {
      final _ScriptedConnection server = scramServer('secret');
      await expectLater(
        _adapter(server, password: null).query('SELECT 1').timeout(_quick),
        throwsA(isA<DVPostgresException>().having(
            (DVPostgresException e) => e.message,
            'message',
            contains('password'))),
      );
      expect(server.types, <int>[0]);
    });
  });
}

List<int> _hmac(List<int> key, List<int> data) =>
    crypto.Hmac(crypto.sha256, key).convert(data).bytes;

List<int> _hi(List<int> password, List<int> salt, int iterations) {
  List<int> block = _hmac(password, <int>[...salt, 0, 0, 0, 1]);
  final List<int> result = List<int>.of(block);
  for (var round = 1; round < iterations; round++) {
    block = _hmac(password, block);
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return result;
}

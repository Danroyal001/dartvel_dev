/// PostgreSQL support: a wire-protocol (v3) client and the database adapter
/// built on it. Pure Dart over a socket — no native driver.
library dartvel_core.database.postgres;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'adapter.dart';
import 'postgres_socket_unsupported.dart'
    if (dart.library.io) 'postgres_socket_io.dart';

/// One Postgres connection. Abstracted like the Redis and SMTP transports so
/// the protocol layer stays testable and web builds get a stub.
abstract class DVPostgresConnection {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

typedef DVPostgresConnect = Future<DVPostgresConnection> Function(
  String host,
  int port,
);

/// Thrown when Postgres reports an error.
class DVPostgresException implements Exception {
  /// SQLSTATE code, e.g. `42P01` for an undefined table.
  final String? code;
  final String message;

  const DVPostgresException(this.message, {this.code});

  @override
  String toString() =>
      'DVPostgresException${code == null ? '' : '($code)'}: $message';
}

/// `DV.Database` on PostgreSQL.
///
/// Placeholders use the adapter contract's `?` and are translated to
/// Postgres's `$1..$n` outside string literals, so SQL written against the
/// SQLite adapter runs unchanged. Parameters travel through the extended
/// query protocol — never interpolated into SQL.
class DVPostgresDatabaseAdapter implements DVDatabaseAdapter {
  final String host;
  final int port;
  final String database;
  final String user;
  final String? password;
  final DVPostgresConnect? _connector;

  DVPostgresConnection? _connection;
  final List<int> _buffer = [];
  final List<Completer<_Reply>> _pending = [];
  Future<void>? _connecting;

  DVPostgresDatabaseAdapter({
    this.host = '127.0.0.1',
    this.port = 5432,
    required this.database,
    this.user = 'postgres',
    this.password,
    DVPostgresConnect? connector,
  }) : _connector = connector;

  // --- protocol plumbing ----------------------------------------------------

  Future<void> _ensureConnected() {
    if (_connection != null) return Future<void>.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final connection = await (_connector ?? dvConnectPostgres)(host, port);
    _connection = connection;
    connection.input.listen(
      (List<int> chunk) {
        _buffer.addAll(chunk);
        _drain();
      },
      onError: (Object error) => _failAll('connection error: $error'),
      onDone: () {
        _connection = null;
        _failAll('connection closed');
      },
    );

    // Startup message: protocol 3.0 plus user/database, no type byte.
    final body = BytesBuilder()
      ..add(_int32(196608))
      ..add(_cstring('user'))
      ..add(_cstring(user))
      ..add(_cstring('database'))
      ..add(_cstring(database))
      ..addByte(0);
    final startup = BytesBuilder()
      ..add(_int32(body.length + 4))
      ..add(body.toBytes());
    connection.write(startup.toBytes());

    await _awaitReady();
  }

  void _failAll(String reason) {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(DVPostgresException(reason));
      }
    }
    _pending.clear();
  }

  /// Completes the startup conversation through authentication to the first
  /// ReadyForQuery.
  Future<void> _awaitReady() {
    final completer = Completer<_Reply>();
    _pending.add(completer);
    return completer.future.then((_Reply reply) {});
  }

  void _drain() {
    while (_pending.isNotEmpty) {
      final message = _tryReadMessage();
      if (message == null) return;
      final handled = _handle(message);
      if (handled != null) {
        final completer = _pending.removeAt(0);
        if (handled.error != null) {
          completer.completeError(handled.error!);
        } else {
          completer.complete(handled);
        }
      }
    }
  }

  _Reply? _inFlight;

  /// Routes one backend message; returns a finished reply on ReadyForQuery.
  _Reply? _handle(({int type, Uint8List body}) message) {
    final reply = _inFlight ??= _Reply();
    switch (message.type) {
      case 0x52: // 'R' Authentication
        final code = _readInt32(message.body, 0);
        switch (code) {
          case 0: // AuthenticationOk
            break;
          case 5: // MD5Password
            final salt = message.body.sublist(4, 8);
            _connection!.write(_password(_md5Password(salt)));
          default:
            reply.error = DVPostgresException(
              'Unsupported Postgres authentication method (code $code). '
              'Supported: trust, md5. Configure pg_hba accordingly or use a '
              'connection proxy.',
            );
        }
      case 0x54: // 'T' RowDescription
        reply.columns = _readRowDescription(message.body);
      case 0x44: // 'D' DataRow
        reply.rows.add(_readDataRow(message.body, reply.columns));
      case 0x43: // 'C' CommandComplete
        final tag = utf8.decode(
          message.body.sublist(0, message.body.length - 1),
        );
        final parts = tag.split(' ');
        reply.affected = int.tryParse(parts.last) ?? 0;
      case 0x45: // 'E' ErrorResponse
        reply.error = _readError(message.body);
      case 0x5A: // 'Z' ReadyForQuery — the reply is complete.
        _inFlight = null;
        return reply;
      default:
        // ParameterStatus, BackendKeyData, ParseComplete, BindComplete,
        // NoticeResponse, EmptyQueryResponse: nothing to record.
        break;
    }
    return null;
  }

  ({int type, Uint8List body})? _tryReadMessage() {
    if (_buffer.length < 5) return null;
    final length = _readInt32(Uint8List.fromList(_buffer.sublist(1, 5)), 0);
    if (_buffer.length < length + 1) return null;
    final type = _buffer[0];
    final body = Uint8List.fromList(_buffer.sublist(5, length + 1));
    _buffer.removeRange(0, length + 1);
    return (type: type, body: body);
  }

  // --- public adapter surface -----------------------------------------------

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final reply = await _run(sql, params ?? const <Object?>[]);
    return reply.rows;
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final reply = await _run(sql, params ?? const <Object?>[]);
    return reply.affected;
  }

  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      // Terminate message, then the socket.
      connection.write(<int>[0x58, 0, 0, 0, 4]);
      await connection.close();
    }
  }

  Future<_Reply> _run(String sql, List<Object?> params) async {
    await _ensureConnected();
    final translated = translatePlaceholders(sql);

    final message = BytesBuilder()
      // Parse: unnamed statement, inferred parameter types.
      ..add(_typed(0x50, (BytesBuilder b) {
        b
          ..add(_cstring(''))
          ..add(_cstring(translated))
          ..add(_int16(0));
      }))
      // Bind: text-format parameters in, text-format results out.
      ..add(_typed(0x42, (BytesBuilder b) {
        b
          ..add(_cstring(''))
          ..add(_cstring(''))
          ..add(_int16(0))
          ..add(_int16(params.length));
        for (final param in params) {
          final encoded = _encodeParam(param);
          if (encoded == null) {
            b.add(_int32(-1));
          } else {
            b
              ..add(_int32(encoded.length))
              ..add(encoded);
          }
        }
        b.add(_int16(0));
      }))
      // Describe the portal so results carry column names.
      ..add(_typed(0x44, (BytesBuilder b) {
        b
          ..addByte(0x50)
          ..add(_cstring(''));
      }))
      // Execute without a row limit, then Sync.
      ..add(_typed(0x45, (BytesBuilder b) {
        b
          ..add(_cstring(''))
          ..add(_int32(0));
      }))
      ..add(_typed(0x53, (BytesBuilder b) {}));

    final completer = Completer<_Reply>();
    _pending.add(completer);
    _connection!.write(message.toBytes());
    return completer.future;
  }

  // --- encoding helpers -----------------------------------------------------

  /// `?` placeholders become `$1..$n`, skipping quoted strings so a literal
  /// question mark in data is left alone.
  static String translatePlaceholders(String sql) {
    final out = StringBuffer();
    var index = 0;
    var inString = false;
    for (var i = 0; i < sql.length; i++) {
      final char = sql[i];
      if (char == "'") {
        inString = !inString;
        out.write(char);
      } else if (char == '?' && !inString) {
        out.write('\$${++index}');
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  static List<int>? _encodeParam(Object? value) {
    if (value == null) return null;
    if (value is bool) return utf8.encode(value ? 'true' : 'false');
    if (value is DateTime) return utf8.encode(value.toIso8601String());
    return utf8.encode('$value');
  }

  List<int> _password(String value) => _typed(0x70, (BytesBuilder b) {
        b.add(_cstring(value));
      });

  /// `md5` + md5(md5(password + user) + salt), Postgres's md5 scheme.
  String _md5Password(List<int> salt) {
    final inner =
        crypto.md5.convert(utf8.encode('${password ?? ''}$user')).toString();
    final outer =
        crypto.md5.convert(<int>[...utf8.encode(inner), ...salt]).toString();
    return 'md5$outer';
  }

  static List<int> _typed(int type, void Function(BytesBuilder) build) {
    final body = BytesBuilder();
    build(body);
    final message = BytesBuilder()
      ..addByte(type)
      ..add(_int32(body.length + 4))
      ..add(body.toBytes());
    return message.toBytes();
  }

  static List<int> _cstring(String value) => <int>[...utf8.encode(value), 0];

  static List<int> _int32(int value) =>
      (ByteData(4)..setInt32(0, value)).buffer.asUint8List();

  static List<int> _int16(int value) =>
      (ByteData(2)..setInt16(0, value)).buffer.asUint8List();

  static int _readInt32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getInt32(offset);

  // --- decoding helpers -----------------------------------------------------

  static List<({String name, int typeOid})> _readRowDescription(
    Uint8List body,
  ) {
    final data = ByteData.sublistView(body);
    final count = data.getInt16(0);
    final columns = <({String name, int typeOid})>[];
    var offset = 2;
    for (var i = 0; i < count; i++) {
      final end = body.indexOf(0, offset);
      final name = utf8.decode(body.sublist(offset, end));
      offset = end + 1;
      final typeOid = data.getInt32(offset + 6);
      offset += 18;
      columns.add((name: name, typeOid: typeOid));
    }
    return columns;
  }

  Map<String, Object?> _readDataRow(
    Uint8List body,
    List<({String name, int typeOid})> columns,
  ) {
    final data = ByteData.sublistView(body);
    final count = data.getInt16(0);
    final row = <String, Object?>{};
    var offset = 2;
    for (var i = 0; i < count; i++) {
      final length = data.getInt32(offset);
      offset += 4;
      final column = i < columns.length
          ? columns[i]
          : (name: 'column$i', typeOid: 25);
      if (length == -1) {
        row[column.name] = null;
        continue;
      }
      final text = utf8.decode(body.sublist(offset, offset + length));
      offset += length;
      row[column.name] = _decode(text, column.typeOid);
    }
    return row;
  }

  /// Text-format value → Dart value, by type OID.
  static Object? _decode(String text, int typeOid) => switch (typeOid) {
        16 => text == 't', // bool
        20 || 21 || 23 || 26 => int.parse(text), // int8/2/4, oid
        700 || 701 || 1700 => num.parse(text), // float4/8, numeric
        // timestamp without time zone is zoneless; Dart has no zoneless
        // DateTime, so it reads as UTC — the convention Postgres drivers use.
        1114 => DateTime.parse('${text}Z'),
        1184 => DateTime.parse(text), // timestamptz carries its offset
        _ => text,
      };

  static DVPostgresException _readError(Uint8List body) {
    String? code;
    String message = 'unknown error';
    var offset = 0;
    while (offset < body.length && body[offset] != 0) {
      final field = body[offset];
      final end = body.indexOf(0, offset + 1);
      final value = utf8.decode(body.sublist(offset + 1, end));
      if (field == 0x43) code = value; // 'C' SQLSTATE
      if (field == 0x4D) message = value; // 'M' message
      offset = end + 1;
    }
    return DVPostgresException(message, code: code);
  }
}

/// One extended-query round trip's accumulated state.
class _Reply {
  List<({String name, int typeOid})> columns = [];
  final List<Map<String, Object?>> rows = [];
  int affected = 0;
  DVPostgresException? error;
}

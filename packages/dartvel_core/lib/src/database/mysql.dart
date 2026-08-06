/// MySQL/MariaDB support: the client protocol and the database adapter built
/// on it. Pure Dart over a socket — no native driver.
library dartvel_core.database.mysql;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'adapter.dart';
import 'mysql_socket_unsupported.dart'
    if (dart.library.io) 'mysql_socket_io.dart';

/// One MySQL connection. Abstracted like the Postgres and Redis transports.
abstract class DVMySqlConnection {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

typedef DVMySqlConnect = Future<DVMySqlConnection> Function(
  String host,
  int port,
);

/// Thrown when MySQL reports an error.
class DVMySqlException implements Exception {
  /// The server error code, e.g. 1146 for an unknown table.
  final int code;

  /// The SQLSTATE, when the server sent one.
  final String? sqlState;

  final String message;

  const DVMySqlException(this.code, this.message, {this.sqlState});

  @override
  String toString() =>
      'DVMySqlException($code${sqlState == null ? '' : '/$sqlState'}): '
      '$message';
}

/// `DV.Database` on MySQL or MariaDB.
///
/// Statements go through prepare/execute, so a parameter is never
/// interpolated into SQL — the same guarantee the Postgres adapter makes.
/// `?` is MySQL's own placeholder, so the adapter contract's SQL needs no
/// translation at all here.
class DVMySqlDatabaseAdapter implements DVDatabaseAdapter {
  final String host;
  final int port;
  final String database;
  final String user;
  final String password;
  final DVMySqlConnect? _connector;

  DVMySqlConnection? _connection;
  final List<int> _buffer = [];
  final List<Completer<List<_Packet>>> _pending = [];
  final List<_Packet> _collected = [];
  Future<void>? _connecting;

  DVMySqlDatabaseAdapter({
    this.host = '127.0.0.1',
    this.port = 3306,
    required this.database,
    this.user = 'root',
    this.password = '',
    DVMySqlConnect? connector,
  }) : _connector = connector;

  // --- connection and handshake ---------------------------------------------

  Future<void> _ensureConnected() {
    if (_connection != null) return Future<void>.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final connection = await (_connector ?? dvConnectMySql)(host, port);
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

    final greeting = (await _receive()).first;
    final handshake = _readHandshake(greeting.payload);
    connection.write(
      _packet(
        _handshakeResponse(handshake),
        greeting.sequence + 1,
      ),
    );
    final auth = (await _receive()).first;
    if (auth.payload.isNotEmpty && auth.payload[0] == 0xFF) {
      throw _readError(auth.payload);
    }
    if (auth.payload.isNotEmpty && auth.payload[0] == 0xFE) {
      throw const DVMySqlException(
        2059,
        'The server asked to switch authentication plugin. Only '
        'mysql_native_password is implemented; configure the account with it, '
        'or connect through a proxy.',
      );
    }
  }

  void _failAll(String reason) {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(DVMySqlException(2013, reason));
      }
    }
    _pending.clear();
  }

  ({int sequence, List<int> authData, String plugin}) _readHandshake(
    List<int> payload,
  ) {
    var offset = 1; // protocol version
    while (payload[offset] != 0) {
      offset++;
    }
    offset += 1 + 4; // server version, connection id
    final authData = <int>[...payload.sublist(offset, offset + 8)];
    offset += 8 + 1; // scramble part 1, filler
    offset += 2 + 1 + 2 + 2 + 1; // capabilities lo, charset, status, caps hi
    final authDataLength = payload[offset - 1];
    offset += 10; // reserved
    final rest = authDataLength > 8 ? authDataLength - 8 : 12;
    authData.addAll(payload.sublist(offset, offset + rest - 1));
    offset += rest;
    var plugin = 'mysql_native_password';
    if (offset < payload.length) {
      final end = payload.indexOf(0, offset);
      plugin = utf8.decode(
        payload.sublist(offset, end == -1 ? payload.length : end),
      );
    }
    return (sequence: 0, authData: authData, plugin: plugin);
  }

  List<int> _handshakeResponse(
    ({int sequence, List<int> authData, String plugin}) handshake,
  ) {
    // CLIENT_PROTOCOL_41 | LONG_PASSWORD | LONG_FLAG | CONNECT_WITH_DB |
    // SECURE_CONNECTION | PLUGIN_AUTH | MULTI_RESULTS
    const capabilities = 0x00000001 |
        0x00000004 |
        0x00000008 |
        0x00000200 |
        0x00008000 |
        0x00080000 |
        0x00020000;
    final auth = _nativePassword(handshake.authData);
    return <int>[
      ..._int32(capabilities),
      ..._int32(16 * 1024 * 1024), // max packet
      45, // utf8mb4_general_ci
      ...List<int>.filled(23, 0),
      ...utf8.encode(user), 0,
      auth.length, ...auth,
      ...utf8.encode(database), 0,
      ...utf8.encode('mysql_native_password'), 0,
    ];
  }

  /// mysql_native_password:
  /// SHA1(password) XOR SHA1(scramble + SHA1(SHA1(password)))
  List<int> _nativePassword(List<int> scramble) {
    if (password.isEmpty) return const <int>[];
    final stage1 = crypto.sha1.convert(utf8.encode(password)).bytes;
    final stage2 = crypto.sha1.convert(stage1).bytes;
    final scrambled =
        crypto.sha1.convert(<int>[...scramble, ...stage2]).bytes;
    return <int>[
      for (var i = 0; i < stage1.length; i++) stage1[i] ^ scrambled[i],
    ];
  }

  // --- packet plumbing ------------------------------------------------------

  static List<int> _packet(List<int> payload, int sequence) => <int>[
        payload.length & 0xFF,
        (payload.length >> 8) & 0xFF,
        (payload.length >> 16) & 0xFF,
        sequence & 0xFF,
        ...payload,
      ];

  Future<List<_Packet>> _receive() {
    final completer = Completer<List<_Packet>>();
    _pending.add(completer);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_pending.isNotEmpty) {
      final packet = _tryReadPacket();
      if (packet == null) return;
      _collected.add(packet);
      if (_isTerminal(packet)) {
        final completer = _pending.removeAt(0);
        final packets = List<_Packet>.of(_collected);
        _collected.clear();
        completer.complete(packets);
      }
    }
  }

  /// Whether a packet ends the current exchange.
  ///
  /// The exchange boundary is what makes a reply complete; getting it wrong
  /// leaves the next query reading this one's tail.
  bool _isTerminal(_Packet packet) {
    if (packet.payload.isEmpty) return true;
    final first = packet.payload[0];
    if (first == 0xFF) return true; // ERR
    if (first == 0x00 && _expecting == _Expect.single) return true; // OK
    if (first == 0xFE && packet.payload.length < 9) {
      // EOF/OK_Packet in the deprecate-EOF sense. A result set has two of
      // them, one after columns and one after rows.
      _eofSeen++;
      if (_expecting == _Expect.single) return true;
      return _eofSeen >= _expectedEof;
    }
    return _expecting == _Expect.single;
  }

  _Expect _expecting = _Expect.single;
  int _eofSeen = 0;
  int _expectedEof = 2;

  _Packet? _tryReadPacket() {
    if (_buffer.length < 4) return null;
    final length = _buffer[0] | (_buffer[1] << 8) | (_buffer[2] << 16);
    if (_buffer.length < 4 + length) return null;
    final packet = _Packet(
      sequence: _buffer[3],
      payload: Uint8List.fromList(_buffer.sublist(4, 4 + length)),
    );
    _buffer.removeRange(0, 4 + length);
    return packet;
  }

  // --- adapter surface ------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final result = await _run(sql, params ?? const <Object?>[]);
    return result.rows;
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final result = await _run(sql, params ?? const <Object?>[]);
    return result.affected;
  }

  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      connection.write(_packet(<int>[0x01], 0)); // COM_QUIT
      await connection.close();
    }
  }

  Future<({List<Map<String, Object?>> rows, int affected})> _run(
    String sql,
    List<Object?> params,
  ) async {
    await _ensureConnected();

    // COM_STMT_PREPARE. Parameters travel separately from the statement, so
    // nothing a caller passes can become SQL.
    _expecting = _Expect.single;
    _connection!.write(_packet(<int>[0x16, ...utf8.encode(sql)], 0));
    final prepared = (await _receive()).first;
    if (prepared.payload[0] == 0xFF) throw _readError(prepared.payload);

    final statementId = prepared.payload[1] |
        (prepared.payload[2] << 8) |
        (prepared.payload[3] << 16) |
        (prepared.payload[4] << 24);
    final columnCount = prepared.payload[5] | (prepared.payload[6] << 8);
    final paramCount = prepared.payload[7] | (prepared.payload[8] << 8);

    // The server sends definition packets for parameters and columns; they
    // must be consumed or they arrive as part of the next reply.
    if (paramCount > 0 || columnCount > 0) {
      _expecting = _Expect.multi;
      _eofSeen = 0;
      _expectedEof = (paramCount > 0 ? 1 : 0) + (columnCount > 0 ? 1 : 0);
      await _receive();
    }

    _expecting = columnCount > 0 ? _Expect.multi : _Expect.single;
    _eofSeen = 0;
    _expectedEof = 2;
    _connection!.write(
      _packet(_executePayload(statementId, params), 0),
    );
    final packets = await _receive();
    if (packets.first.payload[0] == 0xFF) throw _readError(packets.first.payload);

    if (columnCount == 0) {
      final ok = _readOk(packets.first.payload);
      return (rows: <Map<String, Object?>>[], affected: ok);
    }
    return (
      rows: _readBinaryRows(packets, columnCount),
      affected: 0,
    );
  }

  List<int> _executePayload(int statementId, List<Object?> params) {
    final nullBitmap = List<int>.filled((params.length + 7) ~/ 8, 0);
    for (var i = 0; i < params.length; i++) {
      if (params[i] == null) nullBitmap[i ~/ 8] |= 1 << (i % 8);
    }
    final types = <int>[];
    final values = <int>[];
    for (final param in params) {
      if (param == null) {
        types.addAll(<int>[0x06, 0x00]); // MYSQL_TYPE_NULL
        continue;
      }
      if (param is int) {
        types.addAll(<int>[0x08, 0x00]); // LONGLONG
        values.addAll(_int64(param));
      } else if (param is double) {
        types.addAll(<int>[0x05, 0x00]); // DOUBLE
        final data = ByteData(8)..setFloat64(0, param, Endian.little);
        values.addAll(data.buffer.asUint8List());
      } else if (param is bool) {
        types.addAll(<int>[0x01, 0x00]); // TINY
        values.add(param ? 1 : 0);
      } else {
        // Everything else goes as a string. A DateTime is formatted the way
        // MySQL parses temporal literals — it rejects ISO-8601's T separator
        // and trailing zone outright.
        types.addAll(<int>[0xFE, 0x00]); // STRING
        final encoded = utf8.encode(
          param is DateTime ? _mysqlDateTime(param) : '$param',
        );
        values
          ..addAll(_lengthEncoded(encoded.length))
          ..addAll(encoded);
      }
    }

    return <int>[
      0x17, // COM_STMT_EXECUTE
      ..._int32(statementId),
      0x00, // no cursor
      ..._int32(1), // iteration count
      ...nullBitmap,
      if (params.isEmpty) 0x00 else 0x01, // new-params-bound
      ...types,
      ...values,
    ];
  }

  List<Map<String, Object?>> _readBinaryRows(
    List<_Packet> packets,
    int columnCount,
  ) {
    final columns = <({String name, int type})>[];
    var index = 1; // packet 0 is the column count
    while (index < packets.length && columns.length < columnCount) {
      columns.add(_readColumnDefinition(packets[index].payload));
      index++;
    }
    // Skip the EOF that ends the column definitions.
    if (index < packets.length && packets[index].payload.isNotEmpty &&
        packets[index].payload[0] == 0xFE) {
      index++;
    }

    final rows = <Map<String, Object?>>[];
    for (; index < packets.length; index++) {
      final payload = packets[index].payload;
      if (payload.isEmpty) continue;
      if (payload[0] == 0xFE && payload.length < 9) break; // trailing EOF
      if (payload[0] != 0x00) continue;
      rows.add(_readBinaryRow(payload, columns));
    }
    return rows;
  }

  ({String name, int type}) _readColumnDefinition(Uint8List payload) {
    var offset = 0;
    for (var i = 0; i < 4; i++) {
      final length = _readLengthEncoded(payload, offset);
      offset = length.offset + length.value;
    }
    // The fifth string is the column's own name.
    final name = _readLengthEncoded(payload, offset);
    final columnName = utf8.decode(
      payload.sublist(name.offset, name.offset + name.value),
    );
    offset = name.offset + name.value;
    final original = _readLengthEncoded(payload, offset);
    offset = original.offset + original.value;
    offset += 1 + 2 + 4; // length of fixed fields, charset, column length
    final type = payload[offset];
    return (name: columnName, type: type);
  }

  Map<String, Object?> _readBinaryRow(
    Uint8List payload,
    List<({String name, int type})> columns,
  ) {
    final nullBitmapLength = (columns.length + 7 + 2) ~/ 8;
    final nullBitmap = payload.sublist(1, 1 + nullBitmapLength);
    var offset = 1 + nullBitmapLength;
    final row = <String, Object?>{};

    for (var i = 0; i < columns.length; i++) {
      // The binary protocol offsets the null bitmap by two bits.
      final bit = i + 2;
      if ((nullBitmap[bit ~/ 8] & (1 << (bit % 8))) != 0) {
        row[columns[i].name] = null;
        continue;
      }
      final column = columns[i];
      switch (column.type) {
        case 0x01: // TINY
          row[column.name] = payload[offset];
          offset += 1;
        case 0x02: // SHORT
          row[column.name] = payload[offset] | (payload[offset + 1] << 8);
          offset += 2;
        case 0x03: // LONG
        case 0x09: // INT24
          row[column.name] = ByteData.sublistView(payload, offset, offset + 4)
              .getInt32(0, Endian.little);
          offset += 4;
        case 0x08: // LONGLONG
          row[column.name] = ByteData.sublistView(payload, offset, offset + 8)
              .getInt64(0, Endian.little);
          offset += 8;
        case 0x04: // FLOAT
          row[column.name] = ByteData.sublistView(payload, offset, offset + 4)
              .getFloat32(0, Endian.little);
          offset += 4;
        case 0x05: // DOUBLE
          row[column.name] = ByteData.sublistView(payload, offset, offset + 8)
              .getFloat64(0, Endian.little);
          offset += 8;
        case 0x0A: // DATE
        case 0x0C: // DATETIME
        case 0x07: // TIMESTAMP
          final length = payload[offset];
          offset += 1;
          if (length == 0) {
            row[column.name] = null;
          } else {
            final year = payload[offset] | (payload[offset + 1] << 8);
            final month = payload[offset + 2];
            final day = payload[offset + 3];
            final hour = length > 4 ? payload[offset + 4] : 0;
            final minute = length > 4 ? payload[offset + 5] : 0;
            final second = length > 4 ? payload[offset + 6] : 0;
            row[column.name] =
                DateTime.utc(year, month, day, hour, minute, second);
          }
          offset += length;
        default:
          final value = _readLengthEncoded(payload, offset);
          row[column.name] = utf8.decode(
            payload.sublist(value.offset, value.offset + value.value),
          );
          offset = value.offset + value.value;
      }
    }
    return row;
  }

  // --- primitives -----------------------------------------------------------

  /// `YYYY-MM-DD HH:MM:SS`, in UTC so a round trip is stable regardless of
  /// the server's own time zone.
  static String _mysqlDateTime(DateTime value) {
    final utc = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}';
  }

  static List<int> _int32(int value) => <int>[
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];

  static List<int> _int64(int value) => <int>[
        for (var i = 0; i < 8; i++) (value >> (8 * i)) & 0xFF,
      ];

  static List<int> _lengthEncoded(int value) {
    if (value < 251) return <int>[value];
    if (value < 65536) return <int>[0xFC, value & 0xFF, (value >> 8) & 0xFF];
    return <int>[0xFD, value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF];
  }

  static ({int value, int offset}) _readLengthEncoded(
    Uint8List payload,
    int offset,
  ) {
    final first = payload[offset];
    if (first < 251) return (value: first, offset: offset + 1);
    if (first == 0xFC) {
      return (
        value: payload[offset + 1] | (payload[offset + 2] << 8),
        offset: offset + 3,
      );
    }
    if (first == 0xFD) {
      return (
        value: payload[offset + 1] |
            (payload[offset + 2] << 8) |
            (payload[offset + 3] << 16),
        offset: offset + 4,
      );
    }
    return (
      value: ByteData.sublistView(payload, offset + 1, offset + 9)
          .getUint64(0, Endian.little),
      offset: offset + 9,
    );
  }

  static int _readOk(Uint8List payload) {
    final affected = _readLengthEncoded(payload, 1);
    return affected.value;
  }

  static DVMySqlException _readError(Uint8List payload) {
    final code = payload[1] | (payload[2] << 8);
    var offset = 3;
    String? sqlState;
    if (payload.length > 3 && payload[3] == 0x23) {
      sqlState = utf8.decode(payload.sublist(4, 9));
      offset = 9;
    }
    return DVMySqlException(
      code,
      utf8.decode(payload.sublist(offset)),
      sqlState: sqlState,
    );
  }
}

enum _Expect { single, multi }

class _Packet {
  final int sequence;
  final Uint8List payload;

  const _Packet({required this.sequence, required this.payload});
}

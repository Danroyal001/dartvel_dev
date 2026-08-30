/// A Kafka client, enough of it to run a queue on one partition.
library dartvel_core.queues.kafka_socket_io;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crc32c.dart';
import 'kafka_queue.dart';

/// Kafka over a socket, for a single-partition topic and a simple consumer.
///
/// Deliberately partial, and the two simplifications are load-bearing rather
/// than shortcuts.
///
/// **One partition.** Ordering is only defined within a partition, so a queue
/// spread across several would run work out of order while looking fine.
///
/// **A simple consumer, not a group member.** Kafka lets a client commit
/// offsets for a group id without joining it, by sending generation -1 and an
/// empty member id. That skips JoinGroup, SyncGroup and heartbeats entirely --
/// at the cost of no automatic partition rebalancing, which a single-partition
/// queue does not need.
class DVKafkaSocketClient implements DVKafkaClient {
  DVKafkaSocketClient._(this._socket, this._replies, this.group);

  final Socket _socket;
  final Stream<Uint8List> _replies;
  StreamSubscription<Uint8List>? _listener;
  final List<Completer<_Response>> _waiting = <Completer<_Response>>[];

  /// The consumer group whose committed offsets this client reads and writes.
  final String group;

  int _correlation = 0;

  static Future<DVKafkaSocketClient> connect({
    String host = 'localhost',
    int port = 9092,
    String group = 'dartvel',
  }) async {
    final Socket socket = await Socket.connect(host, port);
    final StreamController<Uint8List> messages = StreamController<Uint8List>();
    _pump(socket, messages);
    final DVKafkaSocketClient client =
        DVKafkaSocketClient._(socket, messages.stream, group);
    client._listen();
    return client;
  }

  /// Split the stream into length-prefixed messages.
  ///
  /// Every Kafka message is a four-byte length then that many bytes. A socket
  /// read is not a message: it can carry several or half of one.
  static void _pump(Socket socket, StreamController<Uint8List> out) {
    final List<int> buffer = <int>[];
    socket.listen(
      (List<int> chunk) {
        buffer.addAll(chunk);
        while (buffer.length >= 4) {
          final int size =
              Uint8List.fromList(buffer.sublist(0, 4)).buffer.asByteData()
                  .getUint32(0);
          if (buffer.length < 4 + size) break;
          out.add(Uint8List.fromList(buffer.sublist(4, 4 + size)));
          buffer.removeRange(0, 4 + size);
        }
      },
      onError: out.addError,
      onDone: out.close,
    );
  }

  void _listen() {
    _listener = _replies.listen((Uint8List message) {
      if (_waiting.isEmpty) return;
      final ByteData view = message.buffer.asByteData();
      _waiting.removeAt(0).complete(
            _Response(correlation: view.getInt32(0), body: message.sublist(4)),
          );
    });
  }

  Future<_Response> _call(int apiKey, int apiVersion, List<int> body) {
    final int correlation = ++_correlation;
    final _Writer header = _Writer()
      ..int16(apiKey)
      ..int16(apiVersion)
      ..int32(correlation)
      ..string('dartvel');

    final List<int> payload = <int>[...header.bytes, ...body];
    final _Writer framed = _Writer()..int32(payload.length);
    _socket.add(<int>[...framed.bytes, ...payload]);

    final Completer<_Response> completer = Completer<_Response>();
    _waiting.add(completer);
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _waiting.remove(completer);
        throw StateError(
          'Kafka did not answer api $apiKey v$apiVersion. It closes the '
          'connection on a malformed request rather than replying, so this '
          'usually means the request before it was wrong.',
        );
      },
    );
  }

  /// Ask for a topic's metadata, which is also what creates it when the
  /// broker allows auto-creation.
  Future<void> ensureTopic(String topic) async {
    final _Writer body = _Writer()
      ..int32(1)
      ..string(topic);
    await _call(3, 1, body.bytes); // Metadata v1
  }

  @override
  Future<int> produce(String topic, List<int> value) async {
    final List<int> batch = _recordBatch(value);
    final _Writer body = _Writer()
      ..int16(1) // acks: the leader must have written it
      ..int32(10000) // timeout
      ..int32(1) // one topic
      ..string(topic)
      ..int32(1) // one partition
      ..int32(0)
      ..int32(batch.length)
      ..raw(batch);

    final _Response response = await _call(0, 2, body.bytes); // Produce v2
    final _Reader read = _Reader(response.body);
    read.int32(); // topics
    read.string(); // topic name
    read.int32(); // partitions
    read.int32(); // partition
    final int error = read.int16();
    if (error != 0) {
      throw StateError('Kafka refused the produce with error $error.');
    }
    return read.int64(); // base offset
  }

  @override
  Future<DVKafkaRecord?> fetchOne(String topic) async {
    final int from = await committed(topic);
    // Fetch v4. The older versions this started on are the ones modern
    // brokers deprecate first, and v4 is where isolation_level arrives -- so
    // the request carries two fields v2 did not and the response carries
    // three, which is why parsing a v4 reply as a v2 one found a record set
    // of zero bytes in a log that demonstrably held a record.
    final _Writer body = _Writer()
      ..int32(-1) // replica id: a client, not a broker
      ..int32(500) // max wait
      ..int32(1) // min bytes
      ..int32(1048576) // max bytes, added in v3
      ..int8(0) // isolation level: read uncommitted, added in v4
      ..int32(1)
      ..string(topic)
      ..int32(1)
      ..int32(0)
      ..int64(from)
      ..int32(1048576);

    final _Response response = await _call(1, 4, body.bytes); // Fetch v4
    final _Reader read = _Reader(response.body);
    read.int32(); // throttle
    read.int32(); // topics
    read.string();
    read.int32(); // partitions
    read.int32(); // partition
    final int error = read.int16();
    if (error != 0) {
      throw StateError('Kafka refused the fetch with error $error.');
    }
    read.int64(); // high watermark
    read.int64(); // last stable offset, v4
    final int aborted = read.int32(); // aborted transactions, v4
    for (int i = 0; i < aborted && aborted > 0; i++) {
      read.int64(); // producer id
      read.int64(); // first offset
    }
    final int size = read.int32();
    if (size <= 0) return null;

    final Uint8List records = read.bytes(size);
    return _firstRecord(records, from);
  }

  @override
  Future<void> commit(String topic, int offset) async {
    final _Writer body = _Writer()
      ..string(group)
      ..int32(-1) // generation: a simple consumer, not a group member
      ..string('') // member id, empty for the same reason
      ..int64(-1) // retention: the broker's default
      ..int32(1)
      ..string(topic)
      ..int32(1)
      ..int32(0)
      ..int64(offset)
      ..string(''); // metadata

    final _Response response = await _call(8, 2, body.bytes); // OffsetCommit v2
    final _Reader read = _Reader(response.body);
    read.int32();
    read.string();
    read.int32();
    read.int32();
    final int error = read.int16();
    if (error != 0) {
      throw StateError('Kafka refused the offset commit with error $error.');
    }
  }

  @override
  Future<int> committed(String topic) async {
    final _Writer body = _Writer()
      ..string(group)
      ..int32(1)
      ..string(topic)
      ..int32(1)
      ..int32(0);

    final _Response response = await _call(9, 1, body.bytes); // OffsetFetch v1
    final _Reader read = _Reader(response.body);
    // A group that has never committed comes back with no topics at all, not
    // with an offset of -1. That is the normal state on a first run, so it is
    // read as the start of the log rather than walked off the end of the
    // buffer -- which is what it did, as a RangeError inside a getInt16.
    if (read.remaining < 4 || read.int32() == 0) return 0;
    read.string();
    if (read.remaining < 4 || read.int32() == 0) return 0;
    read.int32(); // partition
    final int offset = read.int64();
    read.string(); // metadata
    read.int16(); // error
    // -1 means the group exists and has committed nothing for this partition.
    return offset < 0 ? 0 : offset;
  }

  @override
  Future<int> endOffset(String topic) async {
    final _Writer body = _Writer()
      ..int32(-1)
      ..int32(1)
      ..string(topic)
      ..int32(1)
      ..int32(0)
      ..int64(-1) // -1 asks for the offset after the last record
      ..int32(1);

    final _Response response = await _call(2, 0, body.bytes); // ListOffsets v0
    final _Reader read = _Reader(response.body);
    read.int32();
    read.string();
    read.int32();
    read.int32();
    final int error = read.int16();
    if (error != 0) {
      throw StateError('Kafka refused the offset request with error $error.');
    }
    final int count = read.int32();
    return count > 0 ? read.int64() : 0;
  }

  Future<void> close() async {
    await _listener?.cancel();
    await _socket.close();
  }

  /// One record in a v2 batch.
  ///
  /// The checksum covers everything after the CRC field itself, so the batch
  /// is assembled first and the CRC written over the tail. Getting that range
  /// wrong is reported by the broker as a corrupt message.
  List<int> _recordBatch(List<int> value) {
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final _Writer record = _Writer()
      ..int8(0) // attributes
      ..varint(0) // timestamp delta
      ..varint(0) // offset delta
      ..varint(-1) // null key
      ..varint(value.length)
      ..raw(value)
      ..varint(0); // no headers
    final _Writer framed = _Writer()
      ..varint(record.bytes.length)
      ..raw(record.bytes);

    final _Writer tail = _Writer()
      ..int16(0) // attributes
      ..int32(0) // last offset delta
      ..int64(timestamp)
      ..int64(timestamp)
      ..int64(-1) // producer id
      ..int16(-1) // producer epoch
      ..int32(-1) // base sequence
      ..int32(1) // one record
      ..raw(framed.bytes);

    final _Writer head = _Writer()
      ..int32(0) // partition leader epoch
      ..int8(2); // magic

    final int crc = dvCrc32c(tail.bytes);
    final _Writer body = _Writer()
      ..raw(head.bytes)
      ..int32(crc)
      ..raw(tail.bytes);

    return <int>[
      ..._Writer().int64(0).bytes, // base offset
      ..._Writer().int32(body.bytes.length).bytes,
      ...body.bytes,
    ];
  }

  /// The first record in a batch, at [baseOffsetHint] or later.
  DVKafkaRecord? _firstRecord(Uint8List records, int from) {
    if (records.length < 61) return null;
    final ByteData view = records.buffer.asByteData(records.offsetInBytes);
    final int baseOffset = view.getInt64(0);
    final _Reader read = _Reader(records)..skip(61);

    final int length = read.varint();
    if (length <= 0) return null;
    read.int8(); // attributes
    read.varint(); // timestamp delta
    final int offsetDelta = read.varint();
    final int keyLength = read.varint();
    if (keyLength > 0) read.bytes(keyLength);
    final int valueLength = read.varint();
    if (valueLength <= 0) return null;

    return DVKafkaRecord(
      offset: baseOffset + offsetDelta,
      value: read.bytes(valueLength),
    );
  }
}

class _Response {
  const _Response({required this.correlation, required this.body});
  final int correlation;
  final Uint8List body;
}

/// Big-endian writer. Kafka is big-endian throughout.
class _Writer {
  final BytesBuilder _out = BytesBuilder();

  List<int> get bytes => _out.toBytes();

  _Writer int8(int v) {
    _out.addByte(v & 0xFF);
    return this;
  }

  _Writer int16(int v) {
    _out.add(<int>[(v >> 8) & 0xFF, v & 0xFF]);
    return this;
  }

  _Writer int32(int v) {
    _out.add(<int>[
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);
    return this;
  }

  _Writer int64(int v) {
    final ByteData d = ByteData(8)..setInt64(0, v);
    _out.add(d.buffer.asUint8List());
    return this;
  }

  /// A Kafka string is a two-byte length then the bytes; -1 is null.
  _Writer string(String value) {
    final List<int> encoded = utf8.encode(value);
    int16(encoded.length);
    _out.add(encoded);
    return this;
  }

  _Writer raw(List<int> value) {
    _out.add(value);
    return this;
  }

  /// Zigzag varint, which record batches use for every length and delta.
  _Writer varint(int value) {
    int zigzag = (value << 1) ^ (value >> 63);
    while ((zigzag & ~0x7F) != 0) {
      _out.addByte((zigzag & 0x7F) | 0x80);
      zigzag = zigzag >>> 7;
    }
    _out.addByte(zigzag & 0x7F);
    return this;
  }
}

class _Reader {
  _Reader(this._bytes) : _view = _bytes.buffer.asByteData(_bytes.offsetInBytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _at = 0;

  void skip(int count) => _at += count;

  /// Bytes left. Kafka omits whole arrays rather than sending empty ones in
  /// some responses, so a parser that assumes a fixed shape reads past the
  /// end instead of finding a zero.
  int get remaining => _bytes.length - _at;

  int int8() => _view.getInt8(_at++);

  int int16() {
    final int v = _view.getInt16(_at);
    _at += 2;
    return v;
  }

  int int32() {
    final int v = _view.getInt32(_at);
    _at += 4;
    return v;
  }

  int int64() {
    final int v = _view.getInt64(_at);
    _at += 8;
    return v;
  }

  String string() {
    final int length = int16();
    if (length < 0) return '';
    final String value = utf8.decode(_bytes.sublist(_at, _at + length));
    _at += length;
    return value;
  }

  Uint8List bytes(int count) {
    final Uint8List value = _bytes.sublist(_at, _at + count);
    _at += count;
    return value;
  }

  int varint() {
    int result = 0;
    int shift = 0;
    while (true) {
      final int byte = _bytes[_at++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (result >>> 1) ^ -(result & 1);
  }
}

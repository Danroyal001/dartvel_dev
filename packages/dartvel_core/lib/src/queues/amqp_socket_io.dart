/// An AMQP 0-9-1 client, enough of it to run a durable queue.
library dartvel_core.queues.amqp_socket_io;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'amqp_queue.dart';

/// A connection to RabbitMQ speaking AMQP 0-9-1 over a socket.
///
/// Deliberately partial. This implements the methods a durable queue needs --
/// declare, publish, get, ack, reject, purge -- and not the rest of the
/// protocol. A general AMQP client is a package of its own; this is the
/// transport one adapter requires, and it says so rather than
/// half-implementing a specification.
///
/// A frame is `type | channel | size | payload | 0xCE`. Method frames carry a
/// class and method id and then arguments packed by type. There is no room
/// for interpretation here: the byte layout is the protocol.
class DVAmqpSocketChannel implements DVAmqpChannel {
  DVAmqpSocketChannel._(this._socket, this._frames);

  final Socket _socket;
  final Stream<_Frame> _frames;
  StreamSubscription<_Frame>? _listener;
  final List<Completer<_Frame>> _waiting = <Completer<_Frame>>[];
  final List<int> _pendingBody = <int>[];

  static const int _frameEnd = 0xCE;
  static const int _channel = 1;

  /// Open a connection and one channel on it.
  static Future<DVAmqpSocketChannel> connect({
    String host = 'localhost',
    int port = 5672,
    String user = 'guest',
    String password = 'guest',
    String virtualHost = '/',
  }) async {
    final Socket socket = await Socket.connect(host, port);
    final StreamController<_Frame> frames = StreamController<_Frame>();
    _pump(socket, frames);

    final DVAmqpSocketChannel channel =
        DVAmqpSocketChannel._(socket, frames.stream);
    await channel._handshake(user, password, virtualHost);
    return channel;
  }

  /// Split the byte stream into frames.
  ///
  /// A socket read is not a frame: one read can carry several, or half of
  /// one. Reassembling here is what stops the rest of the client having to
  /// think about it.
  static void _pump(Socket socket, StreamController<_Frame> out) {
    final List<int> buffer = <int>[];
    socket.listen(
      (List<int> chunk) {
        buffer.addAll(chunk);
        while (buffer.length >= 7) {
          final ByteData head =
              Uint8List.fromList(buffer.sublist(0, 7)).buffer.asByteData();
          final int size = head.getUint32(3);
          if (buffer.length < 7 + size + 1) break;
          out.add(_Frame(
            type: head.getUint8(0),
            channel: head.getUint16(1),
            payload: Uint8List.fromList(buffer.sublist(7, 7 + size)),
          ));
          buffer.removeRange(0, 7 + size + 1);
        }
      },
      onError: out.addError,
      onDone: out.close,
    );
  }

  void _send(int type, int channel, List<int> payload) {
    final BytesBuilder frame = BytesBuilder()
      ..addByte(type)
      ..add(_u16(channel))
      ..add(_u32(payload.length))
      ..add(payload)
      ..addByte(_frameEnd);
    _socket.add(frame.toBytes());
  }

  /// The next method frame, or an error saying which step went unanswered.
  ///
  /// Bounded on purpose. Every wrong byte in this handshake is answered by the
  /// server closing the connection, so an unbounded wait turns a protocol
  /// mistake into a job that hangs until CI kills it and reports nothing.
  Future<_Frame> _next([String step = 'a reply']) {
    final Completer<_Frame> completer = Completer<_Frame>();
    _waiting.add(completer);
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _waiting.remove(completer);
        throw StateError(
          'The AMQP server did not send $step. It closes the connection on a '
          'malformed frame rather than replying, so this usually means the '
          'frame before it was wrong.',
        );
      },
    );
  }

  Future<void> _handshake(String user, String password, String vhost) async {
    _listener = _frames.listen((_Frame frame) {
      // Content arrives as a header frame and then body frames. A Get is
      // three frames on the wire and one answer to the caller, so the body
      // is collected here rather than surfacing as replies nobody awaited.
      if (frame.type == 2) {
        _pendingBody.clear();
        return;
      }
      if (frame.type == 3) {
        _pendingBody.addAll(frame.payload);
        return;
      }
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete(frame);
    });

    // The protocol header is not a frame. It is eight literal bytes, and the
    // server sends Connection.Start only after seeing exactly these.
    _socket.add(<int>[0x41, 0x4D, 0x51, 0x50, 0, 0, 9, 1]);

    await _next('Connection.Start'); // Connection.Start
    _send(1, 0, <int>[
      ..._u16(10), ..._u16(11), // Connection.StartOk
      ..._u32(0), // no client properties
      ..._shortString('PLAIN'),
      // PLAIN is NUL, user, NUL, password -- not spaces. A wrong separator
      // fails as "access refused", which reads like bad credentials.
      ..._longString(<int>[0, ...utf8.encode(user), 0, ...utf8.encode(password)]),
      ..._shortString('en_US'),
    ]);

    // TuneOk must not exceed what the server proposed. Answering 0 for
    // channel-max means "no limit", which is larger than the 2047 RabbitMQ
    // offers -- the server closes the connection and the client waits for a
    // reply that is never coming. That is a twelve-minute hang, not an error.
    final _Frame tune = await _next('Connection.Tune');
    final ByteData proposal = tune.payload.buffer.asByteData();
    final int channelMax = proposal.getUint16(4);
    final int frameMax = proposal.getUint32(6);
    _send(1, 0, <int>[
      ..._u16(10), ..._u16(31), // Connection.TuneOk
      ..._u16(channelMax == 0 ? 1 : channelMax),
      ..._u32(frameMax == 0 ? 131072 : frameMax),
      ..._u16(0), // heartbeats off: this client is request and response only
    ]);

    _send(1, 0, <int>[
      ..._u16(10), ..._u16(40), // Connection.Open
      ..._shortString(vhost), ..._shortString(''), 0,
    ]);
    await _next('Connection.OpenOk'); // Connection.OpenOk

    _send(1, _channel, <int>[..._u16(20), ..._u16(10), ..._shortString('')]);
    await _next('Channel.OpenOk'); // Channel.OpenOk
  }

  @override
  Future<void> declareQueue(String name, {required bool durable}) async {
    _send(1, _channel, <int>[
      ..._u16(50), ..._u16(10), // Queue.Declare
      ..._u16(0), // reserved
      ..._shortString(name),
      // passive, durable, exclusive, auto-delete and no-wait share one byte.
      durable ? 0x02 : 0x00,
      ..._u32(0), // no arguments
    ]);
    await _next('Queue.DeclareOk'); // Queue.DeclareOk
  }

  @override
  Future<void> publish(
    String queue,
    List<int> body, {
    required bool persistent,
    int priority = 0,
  }) async {
    _send(1, _channel, <int>[
      ..._u16(60), ..._u16(40), // Basic.Publish
      ..._u16(0),
      ..._shortString(''), // the default exchange
      ..._shortString(queue), // where the routing key is the queue name
      0, // not mandatory, not immediate
    ]);

    // delivery-mode lives in the content header, and it is what makes a
    // message survive a restart. A durable queue without it comes back empty.
    _send(2, _channel, <int>[
      ..._u16(60), ..._u16(0),
      ..._u64(body.length),
      // Property flags: bit 12 is delivery-mode, bit 11 is priority.
      ..._u16(priority > 0 ? 0x0018 : 0x0010),
      persistent ? 2 : 1,
      if (priority > 0) priority,
    ]);
    _send(3, _channel, body);
    // Basic.Publish is not acknowledged unless publisher confirms are on, so
    // there is nothing to await.
  }

  @override
  Future<DVAmqpMessage?> get(String queue) async {
    _send(1, _channel, <int>[
      ..._u16(60), ..._u16(70), // Basic.Get
      ..._u16(0),
      ..._shortString(queue),
      0, // no-ack off: this adapter acknowledges explicitly
    ]);

    final _Frame reply = await _next();
    final ByteData view = reply.payload.buffer.asByteData();
    if (view.getUint16(0) == 60 && view.getUint16(2) == 72) {
      return null; // Basic.GetEmpty
    }

    final int deliveryTag = view.getUint64(4);
    final bool redelivered = reply.payload[12] != 0;

    // The header and body are already in flight behind the method frame and
    // are collected by the listener.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final List<int> body = List<int>.from(_pendingBody);
    _pendingBody.clear();

    return DVAmqpMessage(
      deliveryTag: deliveryTag,
      body: body,
      redelivered: redelivered,
    );
  }

  @override
  Future<void> ack(int deliveryTag) async {
    _send(1, _channel, <int>[
      ..._u16(60), ..._u16(80), // Basic.Ack
      ..._u64(deliveryTag),
      0, // this delivery only
    ]);
  }

  @override
  Future<void> nack(int deliveryTag, {required bool requeue}) async {
    _send(1, _channel, <int>[
      ..._u16(60), ..._u16(90), // Basic.Reject
      ..._u64(deliveryTag),
      requeue ? 1 : 0,
    ]);
  }

  @override
  Future<int> purge(String queue) async {
    _send(1, _channel, <int>[
      ..._u16(50), ..._u16(30), // Queue.Purge
      ..._u16(0),
      ..._shortString(queue),
      0,
    ]);
    final _Frame reply = await _next();
    return reply.payload.buffer.asByteData().getUint32(4);
  }

  /// Close the channel's socket.
  Future<void> close() async {
    await _listener?.cancel();
    await _socket.close();
  }

  static List<int> _u16(int v) => <int>[(v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u32(int v) =>
      <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u64(int v) => <int>[..._u32(v >> 32), ..._u32(v)];

  /// A short string is one length byte then the bytes, so 255 is the ceiling.
  static List<int> _shortString(String value) {
    final List<int> bytes = utf8.encode(value);
    if (bytes.length > 255) {
      throw ArgumentError.value(
        value,
        'value',
        'AMQP short strings are 255 bytes at most.',
      );
    }
    return <int>[bytes.length, ...bytes];
  }

  static List<int> _longString(List<int> bytes) =>
      <int>[..._u32(bytes.length), ...bytes];
}

class _Frame {
  const _Frame({
    required this.type,
    required this.channel,
    required this.payload,
  });

  final int type;
  final int channel;
  final Uint8List payload;
}

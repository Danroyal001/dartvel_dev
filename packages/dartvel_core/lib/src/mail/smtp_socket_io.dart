/// Socket-backed SMTP connection for platforms with `dart:io`.
library dartvel_core.mail.smtp_socket_io;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'smtp_client.dart';

/// Connects to [host]:[port]. [context] supplies trusted certificates for a
/// server whose certificate is not signed by a public root (tests, private CAs).
Future<DVSmtpConnection> dvConnectSmtp(
  String host,
  int port, {
  required bool secure,
  SecurityContext? context,
}) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = secure
      ? await SecureSocket.connect(host, port, context: context)
      : await Socket.connect(host, port);
  return _SocketSmtpConnection(socket, host: host, context: context);
}

class _SocketSmtpConnection implements DVSmtpConnection {
  final Socket _socket;
  final String _host;
  final SecurityContext? _context;
  final StreamQueue<String> _lines;

  /// Set once [startTls] has handed the socket to TLS.
  bool _upgraded = false;
  bool _closed = false;

  _SocketSmtpConnection(
    this._socket, {
    required String host,
    SecurityContext? context,
  }) : _host = host,
       _context = context,
       _lines = StreamQueue<String>(
         _socket
             .cast<List<int>>()
             .transform(utf8.decoder)
             .transform(const LineSplitter()),
       );

  @override
  Future<String> readLine() => _lines.next;

  @override
  Future<void> write(String data) async {
    _socket.write(data);
    await _socket.flush();
  }

  @override
  Future<DVSmtpConnection> startTls() async {
    // The plaintext line queue is left as it is: SecureSocket.secure detaches
    // the raw socket from it and takes over reading. Cancelling it first shut
    // the socket's read side, so the handshake was cut off mid-way. The
    // certificate is checked against the host the caller connected to, not the
    // socket's address.
    _upgraded = true;
    // ignore: close_sinks — ownership passes to the returned connection.
    final secured = await SecureSocket.secure(
      _socket,
      host: _host,
      context: _context,
    );
    return _SocketSmtpConnection(secured, host: _host, context: _context);
  }

  @override
  Future<void> close() async {
    // Safe to call twice and after a failed upgrade, so a TLS error is what
    // the caller sees rather than a complaint about closing.
    if (_closed) return;
    _closed = true;
    if (!_upgraded) await _lines.cancel(immediate: true);
    await _socket.close();
    _socket.destroy();
  }
}

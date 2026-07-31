/// Socket-backed SMTP connection for platforms with `dart:io`.
library dartvel_core.mail.smtp_socket_io;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'smtp_client.dart';

Future<DVSmtpConnection> dvConnectSmtp(
  String host,
  int port, {
  required bool secure,
}) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = secure
      ? await SecureSocket.connect(host, port)
      : await Socket.connect(host, port);
  return _SocketSmtpConnection(socket);
}

class _SocketSmtpConnection implements DVSmtpConnection {
  final Socket _socket;
  final StreamQueue<String> _lines;

  _SocketSmtpConnection(this._socket)
      : _lines = StreamQueue<String>(
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
    // The line queue is bound to the plaintext socket, so it is released
    // before the underlying socket is upgraded.
    await _lines.cancel(immediate: true);
    // ignore: close_sinks — ownership passes to the returned connection.
    final secured = await SecureSocket.secure(_socket);
    return _SocketSmtpConnection(secured);
  }

  @override
  Future<void> close() async {
    await _lines.cancel(immediate: true);
    await _socket.close();
    _socket.destroy();
  }
}

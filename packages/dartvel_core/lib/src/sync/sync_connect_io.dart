import 'dart:io';

import 'sync_wire.dart';

Future<DVSyncWire> dvConnectSyncWire(Uri url) async {
  final WebSocket socket = await WebSocket.connect(url.toString());
  return DVSyncWire.of(socket, socket);
}

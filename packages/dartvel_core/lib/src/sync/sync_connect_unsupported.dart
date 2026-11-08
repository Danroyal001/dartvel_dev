import 'sync_wire.dart';

Future<DVSyncWire> dvConnectSyncWire(Uri url) => Future<DVSyncWire>.error(
      UnsupportedError('This platform has no WebSocket for model sync.'),
    );

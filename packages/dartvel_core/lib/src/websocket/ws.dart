// WebSocket support for real-time features
import 'dart:async';
import 'dart:convert';

/// WebSocket message
class WsMessage {
  final String type;
  final Object? data;
  final String? id;

  WsMessage({required this.type, this.data, this.id});

  factory WsMessage.fromJson(Map<String, Object?> json) {
    return WsMessage(
      type: json['type'] as String,
      data: json['data'],
      id: json['id'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': type,
      if (data != null) 'data': data,
      if (id != null) 'id': id,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

/// WebSocket connection
abstract class WsConnection {
  String get id;

  void send(WsMessage message);

  void sendRaw(String data);

  Stream<WsMessage> get messages;

  Future<void> close([int? code, String? reason]);

  bool get isOpen;
}

/// WebSocket room/channel
class WsRoom {
  final String name;
  final Set<WsConnection> _connections = {};

  WsRoom(this.name);

  void join(WsConnection connection) {
    _connections.add(connection);
  }

  void leave(WsConnection connection) {
    _connections.remove(connection);
  }

  void broadcast(WsMessage message, {WsConnection? except}) {
    for (final conn in _connections) {
      if (conn != except && conn.isOpen) {
        conn.send(message);
      }
    }
  }

  int get size => _connections.length;

  List<String> get connectionIds => _connections.map((c) => c.id).toList();
}

/// WebSocket manager
class WsManager {
  static final _instance = WsManager._();
  WsManager._();

  static WsManager get instance => _instance;

  final Map<String, WsRoom> _rooms = {};
  final Map<String, WsConnection> _connections = {};

  WsRoom getOrCreateRoom(String name) {
    return _rooms.putIfAbsent(name, () => WsRoom(name));
  }

  void registerConnection(WsConnection connection) {
    _connections[connection.id] = connection;
  }

  void unregisterConnection(String id) {
    final conn = _connections.remove(id);
    if (conn != null) {
      // Remove from all rooms
      for (final room in _rooms.values) {
        room.leave(conn);
      }
    }
  }

  WsConnection? getConnection(String id) => _connections[id];

  void broadcast(WsMessage message, {String? exceptId}) {
    for (final conn in _connections.values) {
      if (conn.id != exceptId && conn.isOpen) {
        conn.send(message);
      }
    }
  }

  Map<String, int> getRoomSizes() {
    return Map.fromEntries(
      _rooms.entries.map((e) => MapEntry(e.key, e.value.size)),
    );
  }
}

/// WebSocket handler for backend
typedef WsHandler = Future<void> Function(
    WsConnection connection, WsMessage message);

class WsRoute {
  final String path;
  final WsHandler handler;

  const WsRoute(this.path, this.handler);
}

/// Example WebSocket handlers
class WsHandlers {
  static Future<void> echo(WsConnection connection, WsMessage message) async {
    connection.send(WsMessage(
      type: 'echo',
      data: message.data,
      id: message.id,
    ));
  }

  static Future<void> joinRoom(
      WsConnection connection, WsMessage message) async {
    final roomName = message.data as String?;
    if (roomName != null) {
      final room = WsManager.instance.getOrCreateRoom(roomName);
      room.join(connection);
      connection.send(WsMessage(
        type: 'joined',
        data: {'room': roomName, 'size': room.size},
      ));
    }
  }

  static Future<void> broadcastToRoom(
      WsConnection connection, WsMessage message) async {
    final rawData = message.data;
    if (rawData is! Map<Object?, Object?>) {
      return;
    }

    final data = <String, Object?>{};
    for (final entry in rawData.entries) {
      final key = entry.key;
      if (key is! String) {
        return;
      }
      data[key] = entry.value;
    }

    final roomName = data['room'] as String?;
    final payload = data['message'];

    if (roomName != null) {
      final room = WsManager.instance.getOrCreateRoom(roomName);
      room.broadcast(
        WsMessage(type: 'message', data: payload),
        except: connection,
      );
    }
  }
}

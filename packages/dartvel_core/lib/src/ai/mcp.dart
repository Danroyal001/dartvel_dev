/// Model Context Protocol, both directions.
///
/// [DVMcpServer] exposes Dartvel's registered AI tools to an MCP client, and
/// [DVMcpClient] adopts an external MCP server's tools so `DV.AI` can call
/// them like its own. Both speak JSON-RPC 2.0 over a transport, which is what
/// MCP is underneath.
library dartvel_core.ai.mcp;

import 'dart:async';
import 'dart:convert';

import 'ai.dart';

/// The MCP revision these implementations negotiate.
const String dvMcpProtocolVersion = '2024-11-05';

/// A bidirectional JSON-RPC channel — stdio, a socket, a WebSocket.
abstract class DVMcpTransport {
  /// One decoded JSON-RPC message per event.
  Stream<Map<String, Object?>> get incoming;

  Future<void> send(Map<String, Object?> message);

  Future<void> close();
}

/// A transport over a pair of byte streams, framed as newline-delimited JSON.
///
/// This is the stdio transport MCP servers launched as subprocesses use.
class DVMcpStreamTransport implements DVMcpTransport {
  final Stream<List<int>> _input;
  final void Function(List<int> bytes) _write;
  final Future<void> Function()? _onClose;

  DVMcpStreamTransport({
    required Stream<List<int>> input,
    required void Function(List<int> bytes) write,
    Future<void> Function()? onClose,
  })  : _input = input,
        _write = write,
        _onClose = onClose;

  @override
  Stream<Map<String, Object?>> get incoming => _input
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((String line) => line.trim().isNotEmpty)
      .map((String line) {
        try {
          final decoded = jsonDecode(line);
          return decoded is Map
              ? decoded.cast<String, Object?>()
              : <String, Object?>{};
        } on FormatException {
          // A malformed line must not kill the stream: the peer may recover
          // on the next message, and killing it strands every pending call.
          return <String, Object?>{};
        }
      })
      .where((Map<String, Object?> message) => message.isNotEmpty);

  @override
  Future<void> send(Map<String, Object?> message) async {
    _write(utf8.encode('${jsonEncode(message)}\n'));
  }

  @override
  Future<void> close() async => _onClose?.call();
}

/// Thrown when a peer reports a JSON-RPC error.
class DVMcpException implements Exception {
  final int code;
  final String message;

  const DVMcpException(this.code, this.message);

  @override
  String toString() => 'DVMcpException($code): $message';
}

/// Serves Dartvel's registered AI tools over MCP.
///
/// The tools are exactly the ones `DV.AI.registerTool` knows about, so an MCP
/// client and Dartvel's own agent runs see the same surface — there is no
/// second registry to drift.
class DVMcpServer {
  final DVMcpTransport transport;

  /// Reported to clients during initialization.
  final String name;
  final String version;

  StreamSubscription<Map<String, Object?>>? _subscription;

  DVMcpServer(
    this.transport, {
    this.name = 'dartvel',
    this.version = '1.0.0',
  });

  /// Starts serving. Completes when the transport closes.
  Future<void> serve() async {
    final done = Completer<void>();
    _subscription = transport.incoming.listen(
      (Map<String, Object?> message) => unawaited(_handle(message)),
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await transport.close();
  }

  Future<void> _handle(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'];
    if (method is! String) return;

    // A notification has no id and takes no reply, per JSON-RPC.
    if (id == null) return;

    try {
      final result = await _dispatch(
        method,
        (message['params'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      );
      await transport.send(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });
    } on DVMcpException catch (error) {
      await transport.send(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': error.code,
          'message': error.message,
        },
      });
    } catch (error) {
      await transport.send(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': -32603,
          'message': '$error',
        },
      });
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String method,
    Map<String, Object?> params,
  ) async {
    const registry = DVAIToolRegistry();
    switch (method) {
      case 'initialize':
        return <String, Object?>{
          'protocolVersion': dvMcpProtocolVersion,
          'capabilities': <String, Object?>{
            'tools': <String, Object?>{},
          },
          'serverInfo': <String, Object?>{
            'name': name,
            'version': version,
          },
        };
      case 'tools/list':
        return <String, Object?>{
          'tools': <Object?>[
            for (final toolName in registry.names)
              if (registry.definition(toolName) case final tool?)
                <String, Object?>{
                  'name': tool.name,
                  'description': tool.description,
                  'inputSchema': tool.jsonSchema,
                },
          ],
        };
      case 'tools/call':
        final toolName = params['name'];
        if (toolName is! String || !registry.contains(toolName)) {
          // -32602 is JSON-RPC's invalid-params: naming the tool is more
          // useful to a client than a generic failure.
          throw DVMcpException(-32602, 'No tool named "$toolName".');
        }
        final arguments = (params['arguments'] as Map?)
                ?.map((Object? k, Object? v) =>
                    MapEntry('$k', DVJsonCodec.fromJson(v))) ??
            const <String, DVJsonValue>{};
        try {
          final value = await registry.call(toolName, arguments);
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': '${DVJsonCodec.toJson(value)}',
              },
            ],
            'isError': false,
          };
        } catch (error) {
          // A throwing tool is a tool result flagged as an error, not a
          // protocol error: the model should see it and can recover.
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': '$error'},
            ],
            'isError': true,
          };
        }
      case 'ping':
        return <String, Object?>{};
      default:
        throw DVMcpException(-32601, 'Unknown method "$method".');
    }
  }
}

/// Consumes an external MCP server.
///
/// [adoptTools] registers the peer's tools into Dartvel's own registry, so an
/// agent run calls them exactly like a local tool.
class DVMcpClient {
  final DVMcpTransport transport;

  int _nextId = 1;
  final Map<Object, Completer<Object?>> _pending = {};
  StreamSubscription<Map<String, Object?>>? _subscription;

  DVMcpClient(this.transport);

  /// Handshakes with the peer and returns its server info.
  Future<Map<String, Object?>> initialize({
    String clientName = 'dartvel',
    String clientVersion = '1.0.0',
  }) async {
    _subscription ??= transport.incoming.listen(
      _receive,
      onDone: _failAll,
      onError: (Object _) => _failAll(),
    );
    final result = await _call('initialize', <String, Object?>{
      'protocolVersion': dvMcpProtocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{
        'name': clientName,
        'version': clientVersion,
      },
    });
    return (result as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
  }

  /// The peer's tools, as advertised.
  Future<List<Map<String, Object?>>> listTools() async {
    final result = await _call('tools/list', const <String, Object?>{});
    final tools = (result as Map?)?['tools'];
    return <Map<String, Object?>>[
      for (final tool in (tools as List?) ?? const <Object?>[])
        (tool! as Map).cast<String, Object?>(),
    ];
  }

  /// Calls one of the peer's tools.
  Future<DVJsonValue> callTool(
    String name, [
    DVJsonObject arguments = const <String, DVJsonValue>{},
  ]) async {
    final result = await _call('tools/call', <String, Object?>{
      'name': name,
      'arguments': <String, Object?>{
        for (final entry in arguments.entries)
          entry.key: DVJsonCodec.toJson(entry.value),
      },
    });
    final map = (result as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final text = <String>[
      for (final item in (map['content'] as List?) ?? const <Object?>[])
        if ((item! as Map)['type'] == 'text') '${(item as Map)['text']}',
    ].join();
    if (map['isError'] == true) {
      // The peer flagged its own failure; surfacing it as a value would let
      // an agent treat an error message as an answer.
      throw DVMcpException(-32000, text);
    }
    return DVJsonString(text);
  }

  /// Registers the peer's tools into Dartvel's registry.
  ///
  /// Names are prefixed so a peer cannot shadow a local tool — silently
  /// replacing one would reroute calls an application already relies on.
  /// Returns the registered names.
  Future<List<String>> adoptTools({String prefix = 'mcp.'}) async {
    const registry = DVAIToolRegistry();
    final adopted = <String>[];
    for (final tool in await listTools()) {
      final remoteName = '${tool['name']}';
      final localName = '$prefix$remoteName';
      registry.register(
        localName,
        (DVJsonObject input) => callTool(remoteName, input),
        description: '${tool['description'] ?? ''}',
      );
      adopted.add(localName);
    }
    return adopted;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _failAll();
    await transport.close();
  }

  Future<Object?> _call(String method, Map<String, Object?> params) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    unawaited(transport.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));
    return completer.future;
  }

  void _receive(Map<String, Object?> message) {
    final id = message['id'];
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = message['error'];
    if (error is Map) {
      completer.completeError(
        DVMcpException(
          (error['code'] as num?)?.toInt() ?? -32603,
          '${error['message'] ?? 'unknown error'}',
        ),
      );
      return;
    }
    completer.complete(message['result']);
  }

  void _failAll() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const DVMcpException(-32000, 'The MCP connection closed.'),
        );
      }
    }
    _pending.clear();
  }
}

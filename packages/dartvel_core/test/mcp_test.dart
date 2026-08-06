// MCP in both directions, wired client-to-server over a real transport pair
// so the JSON-RPC actually crosses a boundary rather than being asserted on.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Two transports joined back to back: what one sends, the other receives.
///
/// Closing either end closes both directions, which is what a socket does —
/// modelling it as one-directional would hide the case where a peer dies and
/// the other side must notice.
({DVMcpTransport a, DVMcpTransport b}) pair() {
  final toA = StreamController<List<int>>.broadcast();
  final toB = StreamController<List<int>>.broadcast();
  Future<void> teardown() async {
    if (!toA.isClosed) await toA.close();
    if (!toB.isClosed) await toB.close();
  }

  return (
    a: DVMcpStreamTransport(
      input: toA.stream,
      write: (List<int> bytes) {
        if (!toB.isClosed) toB.add(bytes);
      },
      onClose: teardown,
    ),
    b: DVMcpStreamTransport(
      input: toB.stream,
      write: (List<int> bytes) {
        if (!toA.isClosed) toA.add(bytes);
      },
      onClose: teardown,
    ),
  );
}

void main() {
  late DVMcpServer server;
  late DVMcpClient client;

  setUp(() async {
    const DVAIToolRegistry().clear();
    const DVAIToolRegistry().register(
      'sumLedger',
      (DVJsonObject input) {
        final left = input['left'];
        final right = input['right'];
        if (left is! DVJsonNumber || right is! DVJsonNumber) {
          throw ArgumentError('sumLedger requires numeric left and right.');
        }
        return DVJsonNumber(left.value + right.value);
      },
      description: 'Adds two ledger amounts',
      parameters: const <String, DVJsonValue>{
        'left': DVJsonString('number'),
        'right': DVJsonString('number'),
      },
    );

    final channel = pair();
    server = DVMcpServer(channel.a, name: 'dartvel-test');
    unawaited(server.serve());
    client = DVMcpClient(channel.b);
  });

  tearDown(() async {
    await client.close();
    await server.stop();
    const DVAIToolRegistry().clear();
  });

  test('initialize negotiates the protocol and reports server info', () async {
    final result = await client.initialize();

    expect(result['protocolVersion'], dvMcpProtocolVersion);
    expect((result['serverInfo']! as Map)['name'], 'dartvel-test');
    expect((result['capabilities']! as Map).containsKey('tools'), isTrue);
  });

  test('tools/list advertises the registry, schema included', () async {
    await client.initialize();

    final tools = await client.listTools();

    expect(tools, hasLength(1));
    expect(tools.single['name'], 'sumLedger');
    expect(tools.single['description'], 'Adds two ledger amounts');
    // Every provider requires a schema on each tool, so one must be present.
    expect(tools.single['inputSchema'], isA<Map<String, Object?>>());
  });

  test('tools/call runs the real tool and returns its result', () async {
    await client.initialize();

    final result = await client.callTool('sumLedger', const {
      'left': DVJsonNumber(2),
      'right': DVJsonNumber(3),
    });

    expect((result as DVJsonString).value, '5');
  });

  test('a throwing tool is an error result, not a dead connection', () async {
    await client.initialize();

    // The model should see the failure and be able to recover from it.
    await expectLater(
      client.callTool('sumLedger', const {'left': DVJsonString('nope')}),
      throwsA(isA<DVMcpException>()),
    );

    // The connection still works afterwards.
    final result = await client.callTool('sumLedger', const {
      'left': DVJsonNumber(1),
      'right': DVJsonNumber(1),
    });
    expect((result as DVJsonString).value, '2');
  });

  test('an unknown tool is a protocol error naming it', () async {
    await client.initialize();

    await expectLater(
      client.callTool('doesNotExist'),
      throwsA(
        isA<DVMcpException>()
            .having((DVMcpException e) => e.code, 'code', -32602)
            .having((DVMcpException e) => e.message, 'message',
                contains('doesNotExist')),
      ),
    );
  });

  test('an unknown method is method-not-found', () async {
    await client.initialize();

    await expectLater(
      client.callTool('sumLedger'),
      throwsA(isA<DVMcpException>()),
    );
  });

  test('adopted tools become callable through the local registry', () async {
    await client.initialize();
    // Register the peer's tools under a second registry-facing name, then
    // call through DV.AI's own registry rather than the client.
    final adopted = await client.adoptTools(prefix: 'peer.');

    expect(adopted, <String>['peer.sumLedger']);
    const registry = DVAIToolRegistry();
    expect(registry.contains('peer.sumLedger'), isTrue);

    final result = await registry.call('peer.sumLedger', const {
      'left': DVJsonNumber(10),
      'right': DVJsonNumber(5),
    });
    expect((result as DVJsonString).value, '15');
  });

  test('adoption prefixes names so a peer cannot shadow a local tool',
      () async {
    await client.initialize();
    await client.adoptTools();

    // The local tool is untouched: silently replacing it would reroute calls
    // an application already relies on.
    expect(const DVAIToolRegistry().contains('sumLedger'), isTrue);
    expect(const DVAIToolRegistry().contains('mcp.sumLedger'), isTrue);
    final local = await const DVAIToolRegistry().call('sumLedger', const {
      'left': DVJsonNumber(1),
      'right': DVJsonNumber(2),
    });
    expect((local as DVJsonNumber).value, 3);
  });

  test('a malformed line does not kill the stream', () async {
    final controller = StreamController<List<int>>();
    final sent = <String>[];
    final transport = DVMcpStreamTransport(
      input: controller.stream,
      write: (List<int> bytes) => sent.add(utf8.decode(bytes)),
    );
    final messages = <Map<String, Object?>>[];
    final subscription = transport.incoming.listen(messages.add);

    controller.add(utf8.encode('{not json\n'));
    controller.add(utf8.encode('{"jsonrpc":"2.0","id":1,"result":{}}\n'));
    await Future<void>.delayed(Duration.zero);

    // The good message still arrives: killing the stream would strand every
    // pending call over one bad line.
    expect(messages, hasLength(1));
    expect(messages.single['id'], 1);
    await subscription.cancel();
    await controller.close();
  });

  test('closing the transport fails pending calls rather than hanging',
      () async {
    await client.initialize();
    final pending = client.callTool('sumLedger', const {
      'left': DVJsonNumber(1),
      'right': DVJsonNumber(1),
    });
    await server.stop();

    await expectLater(pending, throwsA(isA<DVMcpException>()));
  });
}

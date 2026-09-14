// The handshake: a client states what it is, the backend decides what it
// serves.
//
// The silent failures here are a stale client that is never told (its calls
// just break), a report per call where the specification says per session,
// and a client ahead of the backend -- a rolling deploy's normal state --
// being told to go and upgrade to a binary it already has.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

DVProtocolContract contract(List<String> roles, {String? fallback}) =>
    DVProtocolContract(
      models: const <DVProtocolModel>[
        DVProtocolModel('User', <DVProtocolField>[
          DVProtocolField('id', 'int'),
          DVProtocolField('role', 'Role'),
        ]),
      ],
      enums: <DVProtocolEnum>[
        DVProtocolEnum('Role', roles, fallback: fallback),
      ],
      functions: const <DVProtocolFunction>[
        DVProtocolFunction('me', returns: 'User'),
      ],
    );

/// Protocol 1 and 2 were superseded long ago; 3 degrades; 4 is current.
DVProtocolPlan plan() {
  final DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[])
      .bump(contract(<String>['a']), at: DateTime.utc(2025, 1, 1))
      .bump(contract(<String>['a', 'b']), at: DateTime.utc(2025, 2, 1))
      .bump(contract(<String>['a', 'b', 'c']), at: DateTime.utc(2025, 3, 1))
      .bump(
        contract(<String>['a', 'b', 'c', 'd'], fallback: 'a'),
        at: DateTime.utc(2025, 4, 1),
      );
  return DVProtocolPlan.build(
    lock: lock,
    window: const DVProtocolWindow(versions: 1, minimumAge: Duration.zero),
    now: DateTime.utc(2026, 9, 14),
    onDiagnostic: (_, _) {},
  );
}

void main() {
  group('the backend decides', () {
    late List<(String, String)> diagnostics;
    late DVProtocolServer server;

    setUp(() {
      diagnostics = <(String, String)>[];
      server = DVProtocolServer(
        plan: plan(),
        onDiagnostic: (String code, String message) =>
            diagnostics.add((code, message)),
      );
    });

    test('a current client is compatible and needs no adapter', () {
      final DVProtocolDecision decision = server.decide('4');
      expect(decision.result, DVProtocolResult.compatible);
      expect(decision.adapter, isNull);
      expect(decision.refusalStatus, isNull);
    });

    test('a windowed client is degraded and carries its adapter', () {
      final DVProtocolDecision decision = server.decide('3');
      expect(decision.result, DVProtocolResult.degraded);
      expect(
        decision.adapter!.model('User', <String, Object?>{
          'id': 1,
          'role': 'd',
        }),
        <String, Object?>{'id': 1, 'role': 'a'},
      );
      expect(decision.refusalStatus, isNull);
    });

    test('a client outside the window is refused with 426', () {
      final DVProtocolDecision decision = server.decide('1');
      expect(decision.result, DVProtocolResult.upgradeRequired);
      expect(decision.refusalStatus, 426);
    });

    test('DV-PROTO-002 is reported once per session, not per call', () {
      server.decide('1', session: 's1');
      server.decide('1', session: 's1');
      server.decide('1', session: 's1');
      server.decide('2', session: 's2');
      expect(
        diagnostics.where(((String, String) d) => d.$1 == 'DV-PROTO-002'),
        hasLength(2),
      );
    });

    test('a call with no session is still not reported on every call', () {
      for (int i = 0; i < 5; i += 1) {
        server.decide('1');
      }
      expect(
        diagnostics.where(((String, String) d) => d.$1 == 'DV-PROTO-002'),
        hasLength(1),
      );
    });

    test('the sessions it remembers are bounded', () {
      final DVProtocolServer small = DVProtocolServer(
        plan: plan(),
        sessionMemory: 2,
        onDiagnostic: (String code, String message) =>
            diagnostics.add((code, message)),
      );
      small.decide('1', session: 'a');
      small.decide('1', session: 'b');
      small.decide('1', session: 'c'); // forgets a
      small.decide('1', session: 'a');
      expect(
        diagnostics.where(((String, String) d) => d.$1 == 'DV-PROTO-002'),
        hasLength(4),
      );
    });

    test('a client ahead of the backend is not told to upgrade', () {
      final DVProtocolDecision decision = server.decide('5');
      expect(decision.result, isNull);
      expect(decision.backendBehind, isTrue);
      expect(decision.refusalStatus, 503);
      expect(
        diagnostics.where(((String, String) d) => d.$1 == 'DV-PROTO-002'),
        isEmpty,
      );
    });

    test('an unversioned caller is passed through and says so', () {
      // Raw routes, webhooks and curl carry no protocol. Refusing them would
      // turn every non-generated caller into an upgrade prompt.
      final DVProtocolDecision decision = server.decide(null);
      expect(decision.unversioned, isTrue);
      expect(decision.result, DVProtocolResult.compatible);
      expect(decision.refusalStatus, isNull);
    });

    test('a header it cannot read is refused, not treated as unversioned', () {
      for (final String bad in <String>['', 'seven', '-1', '3.0']) {
        expect(() => server.decide(bad), throwsFormatException, reason: bad);
      }
    });

    test('the handshake body names the result', () {
      expect(server.handshake('3'), <String, Object?>{
        'protocol': 4,
        'client': 3,
        'result': 'degraded',
      });
      expect(server.handshake('5'), <String, Object?>{
        'protocol': 4,
        'client': 5,
        'backendBehind': true,
      });
    });
  });

  group('the client', () {
    test('states what it is on every request', () {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 7,
        fetch: (_) async => <String, Object?>{},
      );
      expect(client.headers, <String, String>{'x-dartvel-protocol': '7'});
    });

    test('its version is the one a crash report records', () {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 7,
        fetch: (_) async => <String, Object?>{},
      );
      final DVCrashContext context = DVCrashContext(
        release: '1.0.0',
        installId: 'i',
        protocolVersion: client.protocolVersion,
      );
      expect(context.toJson()['protocolVersion'], '7');
    });

    test('the state is unknown until the handshake answers', () async {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 3,
        fetch: (Map<String, String> headers) async => DVProtocolServer(
          plan: plan(),
          onDiagnostic: (_, _) {},
        ).handshake(headers[DVProtocolServer.header]),
      );
      expect(client.state.value, isNull);
      final List<DVProtocolResult?> seen = <DVProtocolResult?>[];
      client.state.changes.listen(seen.add);
      expect(await client.handshake(), DVProtocolResult.degraded);
      expect(client.state.value, DVProtocolResult.degraded);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <DVProtocolResult?>[DVProtocolResult.degraded]);
    });

    test('runs once however many calls are waiting on it', () async {
      int fetches = 0;
      final DVProtocolClient client = DVProtocolClient(
        protocol: 4,
        fetch: (_) async {
          fetches += 1;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return <String, Object?>{
            'protocol': 4,
            'client': 4,
            'result': 'compatible',
          };
        },
      );
      await Future.wait(<Future<DVProtocolResult>>[
        client.handshake(),
        client.handshake(),
        client.handshake(),
      ]);
      await client.handshake();
      expect(fetches, 1);
    });

    test('a failed handshake is retried rather than remembered', () async {
      int fetches = 0;
      final DVProtocolClient client = DVProtocolClient(
        protocol: 4,
        fetch: (_) async {
          fetches += 1;
          if (fetches == 1) throw const SocketException('offline');
          return <String, Object?>{
            'protocol': 4,
            'client': 4,
            'result': 'compatible',
          };
        },
      );
      await expectLater(client.handshake(), throwsA(isA<SocketException>()));
      expect(client.state.value, isNull);
      expect(await client.handshake(), DVProtocolResult.compatible);
    });

    test('a result it does not know is refused, not guessed', () async {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 4,
        fetch: (_) async => <String, Object?>{
          'protocol': 4,
          'client': 4,
          'result': 'mostlyFine',
        },
      );
      await expectLater(client.handshake(), throwsFormatException);
      expect(client.state.value, isNull);
    });

    test('a backend behind the client is an error of its own', () async {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 5,
        fetch: (Map<String, String> headers) async => DVProtocolServer(
          plan: plan(),
          onDiagnostic: (_, _) {},
        ).handshake(headers[DVProtocolServer.header]),
      );
      await expectLater(
        client.handshake(),
        throwsA(
          isA<DVProtocolBackendBehind>()
              .having((DVProtocolBackendBehind e) => e.server, 'server', 4)
              .having((DVProtocolBackendBehind e) => e.client, 'client', 5),
        ),
      );
      expect(client.state.value, isNull);
    });

    test('a 426 on any later call moves the state to upgradeRequired', () {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 3,
        fetch: (_) async => <String, Object?>{},
      );
      client.observe(200, const <String, String>{});
      expect(client.state.value, isNull);
      client.observe(426, const <String, String>{});
      expect(client.state.value, DVProtocolResult.upgradeRequired);
    });

    test('a result header on a later response is taken as the state', () {
      final DVProtocolClient client = DVProtocolClient(
        protocol: 3,
        fetch: (_) async => <String, Object?>{},
      );
      client.observe(200, const <String, String>{
        'x-dartvel-protocol-result': 'degraded',
      });
      expect(client.state.value, DVProtocolResult.degraded);
    });
  });

  test(
    'over HTTP, the version rides a header on the existing request',
    () async {
      final DVProtocolServer backend = DVProtocolServer(
        plan: plan(),
        onDiagnostic: (_, _) {},
      );
      final HttpServer http_ = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => http_.close(force: true));
      http_.listen((HttpRequest request) async {
        final DVProtocolDecision decision = backend.decide(
          request.headers.value(DVProtocolServer.header),
        );
        final int? refused = decision.refusalStatus;
        if (refused != null) {
          request.response.statusCode = refused;
          if (decision.result != null) {
            request.response.headers.set(
              DVProtocolServer.resultHeader,
              decision.result!.name,
            );
          }
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path == '/api/protocol'
                ? backend.handshake(
                    request.headers.value(DVProtocolServer.header),
                  )
                : decision.adapter == null
                ? <String, Object?>{'id': 1, 'role': 'd'}
                : decision.adapter!.result('me', <String, Object?>{
                    'id': 1,
                    'role': 'd',
                  }),
          ),
        );
        await request.response.close();
      });
      final Uri base = Uri.parse('http://127.0.0.1:${http_.port}/api');

      Future<DVProtocolClient> connect(int protocol) async {
        final DVProtocolClient client = DVProtocolClient(
          protocol: protocol,
          fetch: (Map<String, String> headers) async {
            final http.Response response = await http.get(
              base.replace(path: '${base.path}/protocol'),
              headers: headers,
            );
            return (jsonDecode(response.body) as Map<Object?, Object?>)
                .cast<String, Object?>();
          },
        );
        return client;
      }

      final DVProtocolClient windowed = await connect(3);
      expect(await windowed.handshake(), DVProtocolResult.degraded);
      final http.Response me = await http.get(
        base.replace(path: '${base.path}/me'),
        headers: windowed.headers,
      );
      expect(jsonDecode(me.body), <String, Object?>{'id': 1, 'role': 'a'});

      final DVProtocolClient stale = await connect(1);
      final http.Response refused = await http.get(
        base.replace(path: '${base.path}/me'),
        headers: stale.headers,
      );
      expect(refused.statusCode, 426);
      stale.observe(refused.statusCode, refused.headers);
      expect(stale.state.value, DVProtocolResult.upgradeRequired);
    },
  );
}

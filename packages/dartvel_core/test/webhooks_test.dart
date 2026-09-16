// Outbound webhooks: what an application sends to its customers' servers.
//
// A 200 was never going to be the problem. What these tests spend their effort
// on are the failures nobody sees until a customer asks why an event never
// arrived — or why their server was used to read a cloud metadata service:
//
// - a slow subscriber stalling every other customer's deliveries;
// - a retry that overtakes the event it should have followed;
// - a redirect onto 169.254.169.254, followed;
// - a sensitive field serialized into a payload the application cannot recall;
// - a replay that goes out with an empty body;
// - a retry re-signed with a key that was rotated out.
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A transport that answers from [answer] and records what it was asked.
class _Wire {
  _Wire(this.answer);

  final FutureOr<DVHttpStreamedResponse> Function(DVHttpRequest request, int n)
      answer;
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpStreamedResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return answer(request, requests.length);
  }
}

DVHttpStreamedResponse _reply(int status,
        {Map<String, String> headers = const <String, String>{}}) =>
    DVHttpStreamedResponse(
      statusCode: status,
      headers: headers,
      body: Stream<List<int>>.value(const <int>[]),
    );

Map<String, Object?> _body(DVHttpRequest request) =>
    jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;

String _header(DVHttpRequest request, String name) =>
    request.headers[name] ?? request.headers[name.toLowerCase()] ?? '';

/// The v1 signatures on a request, in the order they were sent.
List<String> _signatures(DVHttpRequest request) =>
    _header(request, 'dartvel-webhook-signature')
        .split(',')
        .map((String part) => part.trim())
        .where((String part) => part.startsWith('v1='))
        .map((String part) => part.substring(3))
        .toList();

String _expected(String key, DVHttpRequest request) {
  final String timestamp = _header(request, 'dartvel-webhook-timestamp');
  return Hmac(sha256, utf8.encode(key))
      .convert(utf8.encode('$timestamp.${utf8.decode(request.body)}'))
      .toString();
}

/// A model the way the generator writes one: `toJson` for storage and
/// `toPublicJson` for anything that leaves the application.
class _Customer {
  _Customer(this.name, this.password);
  final String name;
  final String password;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'password': password,
      };

  Map<String, Object?> toPublicJson() => <String, Object?>{'name': name};
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> _settle() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DateTime now;
  late Map<String, List<String>> dns;
  late List<DVWebhookSubscription> disabled;

  setUp(() {
    DVHttp.reset();
    DVWebhooks.reset();
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    const DVDatabase().configure(MemoryDVDatabaseAdapter());
    DVSecrets.reset();
    DVSecrets.configure(<String, String>{
      'WEBHOOK_KEY_A_V1': 'first-key-for-a',
      'WEBHOOK_KEY_A_V2': 'second-key-for-a',
      'WEBHOOK_KEY_B': 'key-for-b',
    });
    now = DateTime.utc(2026, 9, 13, 12);
    DVWebhooks.clock = () => now;
    dns = <String, List<String>>{
      'hooks.acme.test': <String>['93.184.216.34'],
      'hooks.beta.test': <String>['93.184.216.35'],
      'moved.acme.test': <String>['93.184.216.36'],
      'internal.acme.test': <String>['10.0.0.5'],
    };
    DVWebhooks.resolveHost = (String host) async => dns[host] ?? <String>[];
    disabled = <DVWebhookSubscription>[];
    DVWebhooks.onDisabled = (DVWebhookSubscription s) async => disabled.add(s);
    const DVWebhooks()
      ..declare(const DVWebhookEvent('order.shipped'))
      ..declare(const DVWebhookEvent('customer.updated',
          sensitiveFields: <String>{'ssn'}));
  });

  tearDown(() {
    DVHttp.reset();
    DVWebhooks.reset();
    const DVDatabase().unconfigure();
    DVSecrets.reset();
  });

  Future<DVWebhookSubscription> subscribe(
    String url, {
    String key = 'WEBHOOK_KEY_A_V1',
    Set<String> events = const <String>{'order.shipped', 'customer.updated'},
  }) =>
      const DVWebhooks().subscribe(url: url, events: events, signingSecret: key);

  group('the catalog is declared', () {
    test('emitting an event nobody declared is refused, and nothing is sent',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      await expectLater(
        const DVWebhooks().emit('order.shiped', <String, Object?>{'id': 1}),
        throwsA(isA<DVWebhookUndeclaredEventException>()
            .having((e) => e.code, 'code', 'DV-WEBHOOK-006')),
      );
      await const DVWebhooks().drainAll();
      expect(wire.requests, isEmpty);
    });
  });

  group('the endpoint address is untrusted input', () {
    for (final (String label, String url) in <(String, String)>[
      ('loopback', 'https://127.0.0.1/hook'),
      ('localhost by name', 'https://localhost/hook'),
      ('a 10.x private address', 'https://10.1.2.3/hook'),
      ('a 172.16/12 private address', 'https://172.20.0.1/hook'),
      ('a 192.168 private address', 'https://192.168.1.10/hook'),
      ('the cloud metadata address', 'https://169.254.169.254/latest'),
      ('carrier-grade NAT', 'https://100.64.0.1/hook'),
      ('the unspecified address', 'https://0.0.0.0/hook'),
      ('IPv6 loopback', 'https://[::1]/hook'),
      ('IPv6 link-local', 'https://[fe80::1]/hook'),
      ('an IPv6 unique local address', 'https://[fd00:ec2::254]/hook'),
      ('the metadata address mapped into IPv6',
          'https://[::ffff:169.254.169.254]/hook'),
      ('a name that resolves to a private address',
          'https://internal.acme.test/hook'),
      ('a name that does not resolve', 'https://nowhere.acme.test/hook'),
      ('Google\'s metadata host by name',
          'https://metadata.google.internal/computeMetadata/v1/'),
    ]) {
      test('refuses $label', () async {
        await expectLater(
          subscribe(url),
          throwsA(isA<DVWebhookAddressRefusedException>()
              .having((e) => e.code, 'code', 'DV-WEBHOOK-002')),
        );
      });
    }

    test('refuses plain http, because deliveries are HTTPS POSTs', () async {
      await expectLater(
        subscribe('http://hooks.acme.test/in'),
        throwsA(isA<DVWebhookAddressRefusedException>()),
      );
    });

    test('accepts a public address', () async {
      final DVWebhookSubscription s = await subscribe('https://hooks.acme.test/in');
      expect(s.url.host, 'hooks.acme.test');
    });

    test('allowPrivateAddresses lets a deployment with no metadata service '
        'deliver inside its own network', () async {
      DVWebhooks.config = const DVWebhooksConfig(allowPrivateAddresses: true);
      final DVWebhookSubscription s = await subscribe('https://10.1.2.3/hook');
      expect(s.url.host, '10.1.2.3');
    });

    test('a redirect onto the metadata address is refused, not followed',
        () async {
      final _Wire wire = _Wire((DVHttpRequest request, int n) => _reply(302,
          headers: <String, String>{
            'location': 'https://169.254.169.254/latest/meta-data/iam',
          }));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 7});
      await const DVWebhooks().drainAll();

      expect(wire.requests.map((DVHttpRequest r) => r.url.host),
          everyElement('hooks.acme.test'),
          reason: 'the metadata service must never be asked for anything');
      final DVWebhookDelivery delivery =
          (await const DVWebhooks().delivery(sent.single.id))!;
      expect(delivery.state, DVWebhookDeliveryState.refused);
      expect(delivery.lastError, contains('DV-WEBHOOK-002'));
    });

    test('a redirect to another public address is followed, re-checked',
        () async {
      final _Wire wire = _Wire((DVHttpRequest request, int n) =>
          request.url.host == 'hooks.acme.test'
              ? _reply(307, headers: <String, String>{
                  'location': 'https://moved.acme.test/in',
                })
              : _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 8});
      await const DVWebhooks().drainAll();

      expect(wire.requests.map((DVHttpRequest r) => r.url.host).toList(),
          <String>['hooks.acme.test', 'moved.acme.test']);
      expect(wire.requests.map((DVHttpRequest r) => r.connectAddress).toList(),
          <String>['93.184.216.34', '93.184.216.36'],
          reason: 'each hop connects to the address its own check approved');
      expect((await const DVWebhooks().delivery(sent.single.id))!.state,
          DVWebhookDeliveryState.delivered);
    });

    test('the connection goes to the address the check approved, so a name '
        'that answers a public address and then 127.0.0.1 cannot rebind',
        () async {
      int lookups = 0;
      DVWebhooks.resolveHost = (String host) async {
        lookups++;
        // Subscribing and the attempt's own check see a public address; every
        // lookup after that answers loopback, the way a rebinding name does.
        return lookups <= 2 ? <String>['93.184.216.34'] : <String>['127.0.0.1'];
      };
      final List<String> connectedTo = <String>[];
      DVHttp.transport = (DVHttpRequest request) async {
        // A wire that is not told where to connect resolves the host itself.
        connectedTo.add(request.connectAddress ??
            (await DVWebhooks.resolveHost(request.url.host)).first);
        return _reply(200);
      };
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 10});
      await const DVWebhooks().drainAll();

      expect(connectedTo, <String>['93.184.216.34'],
          reason: 'loopback passed no check and must never be connected to');
      expect((await const DVWebhooks().delivery(sent.single.id))!.state,
          DVWebhookDeliveryState.delivered);
    });

    test('a subscriber URL nobody declared is delivered to, and one under a '
        'declared host never carries that host\'s credential', () async {
      // Outbound HTTP refuses an absolute URL no declared host covers, and a
      // subscriber's endpoint is data no pubspec can list, so deliveries opt
      // out of the declaration -- and out of it entirely. A subscriber who
      // points an endpoint at the payment gateway's own API must not have
      // the application's secret key sent there for them.
      DVSecrets.configure(<String, String>{
        'WEBHOOK_KEY_A_V1': 'first-key-for-a',
        'GATEWAY_KEY': 'sk_live_gateway',
      });
      const DVHttp().declare(
        'gateway',
        const DVHttpHostConfig(
          baseUrl: 'https://hooks.acme.test',
          bearerSecret: 'GATEWAY_KEY',
        ),
      );
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');
      await subscribe('https://hooks.beta.test/in');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 11});
      await const DVWebhooks().drainAll();

      expect(wire.requests.map((DVHttpRequest r) => r.url.host).toSet(),
          <String>{'hooks.acme.test', 'hooks.beta.test'});
      for (final DVHttpRequest request in wire.requests) {
        expect(request.headers.containsKey('authorization'), isFalse,
            reason: request.url.toString());
        expect(request.connectAddress, isNotNull,
            reason: 'still pinned to the address its check approved');
      }
    });

    test('the address is checked again when the delivery goes out, because '
        'DNS can change after subscribing', () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');
      dns['hooks.acme.test'] = <String>['169.254.169.254'];

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 9});
      await const DVWebhooks().drainAll();

      expect(wire.requests, isEmpty);
      expect((await const DVWebhooks().delivery(sent.single.id))!.state,
          DVWebhookDeliveryState.refused);
    });
  });

  group('payloads', () {
    test('a model is serialized through toPublicJson, so a sensitive field '
        'never reaches the wire', () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks()
          .emit('order.shipped', _Customer('Ada', 'hunter2'));
      await const DVWebhooks().drainAll();

      final String raw = utf8.decode(wire.requests.single.body);
      expect(raw, isNot(contains('hunter2')));
      expect(raw, isNot(contains('password')));
      expect(_body(wire.requests.single)['data'],
          <String, Object?>{'name': 'Ada'});
    });

    test('a field the event declares sensitive is absent from a map payload',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().emit('customer.updated', <String, Object?>{
        'name': 'Ada',
        'ssn': '078-05-1120',
        'address': <String, Object?>{'city': 'Lagos', 'ssn': '078-05-1120'},
      });
      await const DVWebhooks().drainAll();

      final String raw = utf8.decode(wire.requests.single.body);
      expect(raw, isNot(contains('078-05-1120')),
          reason: 'nested too: the endpoint belongs to somebody else');
    });

    test('the envelope names the event and carries a stable delivery id',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().drainAll();

      final Map<String, Object?> body = _body(wire.requests.single);
      expect(body['event'], 'order.shipped');
      expect(body['id'], sent.single.id);
      expect(_header(wire.requests.single, 'dartvel-webhook-id'), sent.single.id);
      expect(wire.requests.single.method, 'POST');
    });
  });

  group('signing', () {
    test('each delivery is signed over timestamp.body with the subscription '
        'key', () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().drainAll();

      final DVHttpRequest request = wire.requests.single;
      expect(_signatures(request),
          <String>[_expected('first-key-for-a', request)]);
      expect(
        DVWebhookSignature.verify(
          secret: 'first-key-for-a',
          timestamp: _header(request, 'dartvel-webhook-timestamp'),
          body: utf8.decode(request.body),
          header: _header(request, 'dartvel-webhook-signature'),
        ),
        isTrue,
      );
      expect(
        DVWebhookSignature.verify(
          secret: 'somebody-elses-key',
          timestamp: _header(request, 'dartvel-webhook-timestamp'),
          body: utf8.decode(request.body),
          header: _header(request, 'dartvel-webhook-signature'),
        ),
        isFalse,
      );
    });

    test('rotation sends both signatures through the overlap, and a retry '
        'after it is not signed with the rotated-out key', () async {
      final _Wire wire = _Wire((_, int n) => _reply(n == 1 ? 500 : 200));
      DVHttp.transport = wire.send;
      final DVWebhookSubscription s = await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().rotateSigningKey(s.id, 'WEBHOOK_KEY_A_V2',
          overlap: const Duration(hours: 1));
      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().drainOnce(s.id);

      final DVHttpRequest during = wire.requests.single;
      expect(_signatures(during), <String>[
        _expected('second-key-for-a', during),
        _expected('first-key-for-a', during),
      ]);

      now = now.add(const Duration(hours: 2));
      await const DVWebhooks().drainAll();

      final DVHttpRequest after = wire.requests.last;
      expect(wire.requests, hasLength(2));
      expect(_signatures(after), <String>[_expected('second-key-for-a', after)]);
      expect(_signatures(after), isNot(contains(_expected('first-key-for-a', after))));
      expect(_header(after, 'dartvel-webhook-id'),
          _header(during, 'dartvel-webhook-id'),
          reason: 'a retry is the same delivery, so a consumer can deduplicate');
    });
  });

  group('delivery is partitioned per endpoint', () {
    test('a retry does not let the next event overtake it', () async {
      final List<Object?> delivered = <Object?>[];
      final _Wire wire = _Wire((DVHttpRequest request, int n) {
        if (n == 1) return _reply(500);
        delivered.add((_body(request)['data'] as Map<String, Object?>)['id']);
        return _reply(200);
      });
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 2});
      await const DVWebhooks().drainAll();

      expect(delivered, <Object?>[1, 2]);
      expect(
          wire.requests
              .map((DVHttpRequest r) =>
                  (_body(r)['data'] as Map<String, Object?>)['id'])
              .toList(),
          <Object?>[1, 1, 2],
          reason: 'event 2 must not go out while event 1 is still failing');
    });

    test('a slow subscriber delays its own deliveries and nobody else\'s',
        () async {
      final Completer<DVHttpStreamedResponse> slow =
          Completer<DVHttpStreamedResponse>();
      final _Wire wire = _Wire((DVHttpRequest request, int n) =>
          request.url.host == 'hooks.acme.test' ? slow.future : _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');
      final DVWebhookSubscription b =
          await subscribe('https://hooks.beta.test/in', key: 'WEBHOOK_KEY_B');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      final Future<void> draining = const DVWebhooks().drainAll();
      await _settle();

      final List<DVWebhookDelivery> forB = (await const DVWebhooks().deliveries(b.id));
      expect(forB.single.state, DVWebhookDeliveryState.delivered,
          reason: 'beta must not wait for acme\'s endpoint to answer');

      slow.complete(_reply(200));
      await draining;
    });

    test('a delivery that exhausts its attempts is dead-lettered, and the '
        'next one proceeds', () async {
      DVWebhooks.config = const DVWebhooksConfig(maxAttempts: 3, disableAfter: 50);
      final _Wire wire = _Wire((DVHttpRequest request, int n) =>
          (_body(request)['data'] as Map<String, Object?>)['id'] == 1
              ? _reply(503)
              : _reply(200));
      DVHttp.transport = wire.send;
      final DVWebhookSubscription s = await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 2});
      await const DVWebhooks().drainAll();

      final List<DVWebhookDelivery> all = (await const DVWebhooks().deliveries(s.id));
      expect(all.first.state, DVWebhookDeliveryState.deadLettered);
      expect(all.first.attempts, 3);
      expect(all.first.lastStatus, 503);
      expect(all.last.state, DVWebhookDeliveryState.delivered);
    });

    test('an endpoint that keeps failing is disabled, its owner told, and its '
        'queue stops', () async {
      DVWebhooks.config = const DVWebhooksConfig(maxAttempts: 10, disableAfter: 3);
      final _Wire wire = _Wire((_, __) => _reply(500));
      DVHttp.transport = wire.send;
      final DVWebhookSubscription s = await subscribe('https://hooks.acme.test/in');

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().drainAll();

      expect(wire.requests, hasLength(3));
      expect((await const DVWebhooks().subscription(s.id))!.disabled, isTrue);
      expect(disabled.map((DVWebhookSubscription d) => d.id), <String>[s.id]);

      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 2});
      await const DVWebhooks().drainAll();
      expect(wire.requests, hasLength(3),
          reason: 'a disabled endpoint is not retried forever');
    });
  });

  group('retention and replay', () {
    test('replay inside the window resends the same delivery with its payload',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 5});
      await const DVWebhooks().drainAll();
      await const DVWebhooks().replay(sent.single.id);
      await const DVWebhooks().drainAll();

      expect(wire.requests, hasLength(2));
      expect(_body(wire.requests.last)['data'], <String, Object?>{'id': 5});
      expect(_header(wire.requests.last, 'dartvel-webhook-id'), sent.single.id);
    });

    test('after retention the payload is gone, the record stays, and replay is '
        'refused rather than sent empty', () async {
      DVWebhooks.config =
          const DVWebhooksConfig(retention: Duration(days: 30));
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 6});
      await const DVWebhooks().drainAll();
      now = now.add(const Duration(days: 31));
      expect((await const DVWebhooks().purgeExpiredPayloads()), 1);

      final DVWebhookDelivery kept = (await const DVWebhooks().delivery(sent.single.id))!;
      expect(kept.payload, isNull);
      expect(kept.state, DVWebhookDeliveryState.delivered);
      expect(kept.lastStatus, 200);

      await expectLater(
        const DVWebhooks().replay(sent.single.id),
        throwsA(isA<DVWebhookReplayRefusedException>()
            .having((e) => e.code, 'code', 'DV-WEBHOOK-005')),
      );
      await const DVWebhooks().drainAll();
      expect(wire.requests, hasLength(1),
          reason: 'an empty delivery cannot be told from a real event');
    });

    test('replay past the window is refused even before the purge has run',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');

      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 6});
      await const DVWebhooks().drainAll();
      now = now.add(const Duration(days: 45));

      await expectLater(const DVWebhooks().replay(sent.single.id),
          throwsA(isA<DVWebhookReplayRefusedException>()));
    });
  });
  group('the record survives a restart', () {
    late Directory dir;
    late String path;
    SqliteDVDatabaseAdapter? open;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dv_webhooks_restart_');
      path = '${dir.path}/app.db';
    });

    tearDown(() {
      open?.close();
      open = null;
      dir.deleteSync(recursive: true);
    });

    /// Starts a process against the database file: nothing carried over but
    /// the file, and whatever queue [durableQueue] says there is.
    void boot({required bool durableQueue}) {
      open?.close();
      final SqliteDVDatabaseAdapter database = SqliteDVDatabaseAdapter.file(path);
      open = database;
      DVWebhooks.reset();
      const DVDatabase().configure(database);
      const DVQueues().useAdapter(durableQueue
          ? DVDatabaseQueueAdapter(database)
          : DVInMemoryQueueAdapter());
      DVWebhooks.clock = () => now;
      DVWebhooks.resolveHost = (String host) async => dns[host] ?? <String>[];
      const DVWebhooks()
        ..declare(const DVWebhookEvent('order.shipped'))
        ..declare(const DVWebhookEvent('customer.updated'));
    }

    for (final bool durableQueue in <bool>[true, false]) {
      test(
          'a delivery that failed before the restart is retried after it, as '
          'the same delivery and still ahead of the next '
          '(${durableQueue ? 'queue in the database' : 'queue lost with the process'})',
          () async {
        boot(durableQueue: durableQueue);
        final _Wire before = _Wire((_, __) => _reply(500));
        DVHttp.transport = before.send;
        final DVWebhookSubscription s =
            await subscribe('https://hooks.acme.test/in');
        final List<DVWebhookDelivery> first = await const DVWebhooks()
            .emit('order.shipped', <String, Object?>{'id': 1});
        await const DVWebhooks()
            .emit('order.shipped', <String, Object?>{'id': 2});
        await const DVWebhooks().drainOnce(s.id);
        expect(before.requests, hasLength(1));

        boot(durableQueue: durableQueue);
        final _Wire after = _Wire((_, __) => _reply(200));
        DVHttp.transport = after.send;

        final DVWebhookSubscription? kept =
            (await const DVWebhooks().subscription(s.id));
        expect(kept?.url, Uri.parse('https://hooks.acme.test/in'));
        expect(kept?.consecutiveFailures, 1);

        await const DVWebhooks().drainAll();

        expect(
            after.requests
                .map((DVHttpRequest r) =>
                    (_body(r)['data'] as Map<String, Object?>)['id'])
                .toList(),
            <Object?>[1, 2]);
        expect(_header(after.requests.first, 'dartvel-webhook-id'),
            first.single.id);
        final List<DVWebhookDelivery> all = (await const DVWebhooks().deliveries(s.id));
        expect(all.map((DVWebhookDelivery d) => d.state), <DVWebhookDeliveryState>[
          DVWebhookDeliveryState.delivered,
          DVWebhookDeliveryState.delivered,
        ]);
        expect(all.first.attempts, 2,
            reason: 'the attempt before the restart still counts');
      });
    }

    test('resume queues what every endpoint is still owed, for a process '
        'starting up with an empty queue', () async {
      boot(durableQueue: false);
      DVHttp.transport = _Wire((_, __) => _reply(500)).send;
      final DVWebhookSubscription s =
          await subscribe('https://hooks.acme.test/in');
      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 1});
      await const DVWebhooks().emit('order.shipped', <String, Object?>{'id': 2});

      boot(durableQueue: false);
      expect(await const DVQueues().pending('dv.webhooks.${s.id}'), isEmpty);
      await const DVWebhooks().resume();
      expect(await const DVQueues().pending('dv.webhooks.${s.id}'), hasLength(2),
          reason: 'one job per delivery still owed');
      await const DVWebhooks().resume();
      expect(await const DVQueues().pending('dv.webhooks.${s.id}'), hasLength(2),
          reason: 'resuming twice does not send anything twice');
    });

    test('a payload kept before the restart can be replayed after it, and a '
        'purged one is still refused', () async {
      boot(durableQueue: true);
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      await subscribe('https://hooks.acme.test/in');
      final List<DVWebhookDelivery> sent = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 5});
      final List<DVWebhookDelivery> old = await const DVWebhooks()
          .emit('order.shipped', <String, Object?>{'id': 6});
      await const DVWebhooks().drainAll();

      boot(durableQueue: true);
      DVHttp.transport = wire.send;
      expect((await const DVWebhooks().delivery(sent.single.id))?.payload,
          contains('"id":5'));
      await const DVWebhooks().replay(sent.single.id);
      await const DVWebhooks().drainAll();
      expect(_body(wire.requests.last)['data'], <String, Object?>{'id': 5});

      now = now.add(const Duration(days: 31));
      boot(durableQueue: true);
      expect((await const DVWebhooks().purgeExpiredPayloads()), 2);
      boot(durableQueue: true);
      expect((await const DVWebhooks().delivery(old.single.id))?.payload, isNull);
      expect((await const DVWebhooks().delivery(old.single.id))?.state,
          DVWebhookDeliveryState.delivered);
    });
  });
}

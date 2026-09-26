// The AsyncAPI 3.0 document for an application's outbound webhooks.
//
// It is generated from the DVWebhookEvent declarations the runtime already
// refuses to emit without, so the catalog a customer reads and the events the
// code can send come from one place. The failures that matter are a document
// that silently leaves an event out, and one describing an envelope or
// signature other than the one configured.
import 'dart:convert';

import 'package:dartvel_cli/src/generators/asyncapi_generator.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVWebhooksConfig;
import 'package:test/test.dart';

Map<String, Object?> _build(List<String> events, {Map<String, Object?>? config}) =>
    buildAsyncApiDocument(
      title: 'shop',
      version: '1.2.3',
      events: events,
      config: DVWebhooksConfig.read(config, application: 'shop'),
    );

Map<String, Object?> _at(Object? value, List<String> path) {
  Object? current = value;
  for (final String key in path) {
    current = (current as Map<String, Object?>)[key];
  }
  return current as Map<String, Object?>;
}

void main() {
  group('discovering the declarations', () {
    test('finds every DVWebhookEvent name, in every file, once', () {
      final List<String> names = discoverWebhookEvents(<(String, String)>[
        (
          'lib/backend/events.dart',
          '''
void declare() {
  DV.Webhooks.declare(const DVWebhookEvent(
    'order.paid',
    sensitiveFields: <String>{'cardLast4'},
  ));
  const DVWebhooks().declare(DVWebhookEvent("order.shipped"));
}
''',
        ),
        (
          'lib/other.dart',
          "final e = const DVWebhookEvent(r'customer.updated');\n"
              "final again = DVWebhookEvent('order.paid');\n",
        ),
      ]);
      expect(names, <String>['customer.updated', 'order.paid', 'order.shipped']);
    });

    test('a declaration in a comment is not an event', () {
      expect(
        discoverWebhookEvents(<(String, String)>[
          (
            'lib/a.dart',
            "// DV.Webhooks.declare(const DVWebhookEvent('old.event'));\n"
                "/* DVWebhookEvent('older.event') */\n",
          ),
        ]),
        isEmpty,
      );
    });

    for (final (String label, String source) in <(String, String)>[
      ('a variable', 'DVWebhookEvent(eventName)'),
      ('an interpolated string', r"DVWebhookEvent('order.$kind')"),
      ('adjacent strings', "DVWebhookEvent('order.' 'paid')"),
    ]) {
      test('a name written as $label is refused, naming the file and line, '
          'because the document could not list it', () {
        expect(
          () => discoverWebhookEvents(<(String, String)>[
            ('lib/backend/events.dart', 'void f() {\n  $source;\n}\n'),
          ]),
          throwsA(isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('DV-WEBHOOK-010'),
                contains('lib/backend/events.dart:2')),
          )),
        );
      });
    }
  });

  group('the document', () {
    test('is AsyncAPI 3.0.0 with one send operation per event, each on its '
        'own channel whose address is the subscriber\'s and so unknown', () {
      final Map<String, Object?> doc = _build(<String>['order.paid', 'order.shipped']);
      expect(doc['asyncapi'], '3.0.0');
      expect(_at(doc, <String>['info']),
          allOf(containsPair('title', 'shop'), containsPair('version', '1.2.3')));
      expect((doc['channels'] as Map<String, Object?>).keys,
          <String>['order.paid', 'order.shipped']);
      final Map<String, Object?> channel = _at(doc, <String>['channels', 'order.paid']);
      expect(channel.containsKey('address'), isTrue);
      expect(channel['address'], isNull);

      final Map<String, Object?> operation =
          _at(doc, <String>['operations', 'order.paid']);
      expect(operation['action'], 'send');
      expect(operation['channel'],
          <String, Object?>{r'$ref': '#/channels/order.paid'});
      expect(operation['messages'], <Object?>[
        <String, Object?>{r'$ref': '#/channels/order.paid/messages/order.paid'},
      ], reason: 'an operation\'s messages must point into its channel');
      expect(_at(operation, <String>['bindings', 'http'])['method'], 'POST');
    });

    test('every \$ref resolves inside the document', () {
      final Map<String, Object?> doc = _build(<String>['order.paid'],
          config: <String, Object?>{'format': 'cloudevents', 'signature': 'standard'});
      void walk(Object? node) {
        if (node is Map) {
          final Object? ref = node[r'$ref'];
          if (ref is String) {
            expect(ref, startsWith('#/'));
            Object? target = doc;
            for (final String part in ref.substring(2).split('/')) {
              expect(target, isA<Map<String, Object?>>(), reason: ref);
              expect((target as Map<String, Object?>).containsKey(part), isTrue,
                  reason: ref);
              target = target[part];
            }
          }
          node.values.forEach(walk);
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      walk(doc);
    });

    test('the default describes Dartvel\'s envelope and signature headers', () {
      final Map<String, Object?> message =
          _at(_build(<String>['order.paid']), <String>['components', 'messages', 'order.paid']);
      expect(message['contentType'], 'application/json');
      final Map<String, Object?> payload = message['payload'] as Map<String, Object?>;
      expect(payload['required'], <String>['id', 'event', 'created', 'data']);
      expect(_at(payload, <String>['properties', 'event'])['const'], 'order.paid');
      final Map<String, Object?> headers = message['headers'] as Map<String, Object?>;
      expect(headers['required'], containsAll(<String>[
        'dartvel-webhook-id',
        'dartvel-webhook-event',
        'dartvel-webhook-timestamp',
        'dartvel-webhook-signature',
      ]));
    });

    test('cloudevents structured describes the CloudEvent body', () {
      final Map<String, Object?> message = _at(
          _build(<String>['order.paid'],
              config: <String, Object?>{'format': 'cloudevents'}),
          <String>['components', 'messages', 'order.paid']);
      expect(message['contentType'], 'application/cloudevents+json');
      final Map<String, Object?> payload = message['payload'] as Map<String, Object?>;
      expect(payload['required'],
          containsAll(<String>['specversion', 'id', 'source', 'type']));
      expect(_at(payload, <String>['properties', 'type'])['const'], 'order.paid');
      expect(_at(payload, <String>['properties', 'source'])['const'], '/shop');
      expect(_at(payload, <String>['properties', 'specversion'])['const'], '1.0');
    });

    test('cloudevents binary describes ce- headers and the data as the body',
        () {
      final Map<String, Object?> message = _at(
          _build(<String>['order.paid'], config: <String, Object?>{
            'format': 'cloudevents',
            'mode': 'binary',
            'signature': 'standard',
          }),
          <String>['components', 'messages', 'order.paid']);
      expect(message['contentType'], 'application/json');
      final Map<String, Object?> headers = message['headers'] as Map<String, Object?>;
      expect(headers['required'], containsAll(<String>[
        'ce-specversion',
        'ce-id',
        'ce-source',
        'ce-type',
        'webhook-id',
        'webhook-timestamp',
        'webhook-signature',
      ]));
      expect(_at(headers, <String>['properties', 'ce-type'])['const'], 'order.paid');
      expect((headers['required'] as List<Object?>)
          .where((Object? h) => '$h'.startsWith('dartvel-webhook-')), isEmpty);
    });

    test('a name with characters a component key cannot hold still gets a '
        'valid key, and keeps its name', () {
      final Map<String, Object?> doc = _build(<String>['order/paid:v2']);
      final String key = (doc['channels'] as Map<String, Object?>).keys.single;
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(key), isTrue);
      expect(_at(doc, <String>['components', 'messages', key])['name'],
          'order/paid:v2');
    });

    test('no events is still a valid document, not a missing one', () {
      final Map<String, Object?> doc = _build(const <String>[]);
      expect(doc['asyncapi'], '3.0.0');
      expect(doc['channels'], isEmpty);
      expect(doc['operations'], isEmpty);
    });

    test('encodes as JSON', () {
      final String json = encodeAsyncApiDocument(_build(<String>['order.paid']));
      expect(jsonDecode(json), isA<Map<String, Object?>>());
    });
  });
}

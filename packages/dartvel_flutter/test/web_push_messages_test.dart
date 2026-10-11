// The message the generated worker posts to the page, read by the page. The
// worker is JavaScript and the page is Dart; neither compiler can see the
// other's idea of the shape, so this holds both ends to one literal.
import 'package:dartvel_flutter/src/platform/web/web_push_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 10, 11, 12);

  test('a push forwarded to an open window becomes a received message', () {
    final Map<String, Object?>? entry = dvWebPushEntryFrom(
      <String, Object?>{
        'type': 'dartvel-push',
        'payload': <String, Object?>{
          'title': 'Order shipped',
          'body': 'On the way',
          'data': <String, Object?>{'orderId': 42},
        },
      },
      now: now,
      sequence: 3,
    );
    expect(entry!['id'], 'web-${now.millisecondsSinceEpoch}-3');
    expect(entry['title'], 'Order shipped');
    expect(entry['body'], 'On the way');
    // Data values are strings, as FCM's are, so one handler serves both.
    expect(entry['data'], <String, Object?>{'orderId': '42'});
    expect(entry['opened'], isFalse);
    expect(entry['receivedAt'], now.millisecondsSinceEpoch);
  });

  test('a notification click becomes an opened message carrying its url', () {
    final Map<String, Object?>? entry = dvWebPushEntryFrom(
      <String, Object?>{
        'type': 'dartvel-push-open',
        'title': 'Order shipped',
        'body': 'On the way',
        'url': '/orders/42',
        'data': <String, Object?>{'orderId': '42'},
      },
      now: now,
      sequence: 0,
    );
    expect(entry!['opened'], isTrue);
    expect(entry['title'], 'Order shipped');
    expect((entry['data']! as Map)['url'], '/orders/42');
    expect((entry['data']! as Map)['orderId'], '42');
  });

  test('anything else on the worker channel is ignored', () {
    for (final Object? other in <Object?>[
      null,
      'text',
      <String, Object?>{'type': 'something-else'},
      <String, Object?>{'type': 'dartvel-push'},
      <String, Object?>{'type': 'dartvel-push', 'payload': 'not a map'},
    ]) {
      expect(dvWebPushEntryFrom(other, now: now, sequence: 0), isNull,
          reason: '$other');
    }
  });

  test('a title that is not text is dropped rather than shown as an object', () {
    final Map<String, Object?>? entry = dvWebPushEntryFrom(
      <String, Object?>{
        'type': 'dartvel-push',
        'payload': <String, Object?>{'title': 7, 'body': <Object?>[]},
      },
      now: now,
      sequence: 0,
    );
    expect(entry!['title'], isNull);
    expect(entry['body'], isNull);
  });
}

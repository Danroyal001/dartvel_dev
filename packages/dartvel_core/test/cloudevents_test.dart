// CloudEvents 1.0.2 over HTTP, both content modes.
//
// The vectors are the specification's own: the JSON event format's examples
// (formats/json-format.md, section 3) with their binary-mode re-encodings, and
// the HTTP binding's percent-encoding example (bindings/http-protocol-binding.md,
// 3.1.3.2). An envelope that only round-trips through this library proves the
// library agrees with itself; these prove it agrees with the specification.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// json-format.md, "JSON Object-valued data".
const String _exampleC = '''
{
    "specversion" : "1.0",
    "type" : "com.example.someevent",
    "source" : "/mycontext",
    "subject": null,
    "id" : "C234-1234-1234",
    "time" : "2018-04-05T17:31:00Z",
    "comexampleextension1" : "value",
    "comexampleothervalue" : 5,
    "datacontenttype" : "application/json",
    "data" : {
        "appinfoA" : "abc",
        "appinfoB" : 123,
        "appinfoC" : true
    }
}''';

// Its binary-mode re-encoding.
const Map<String, String> _exampleCHeaders = <String, String>{
  'ce-specversion': '1.0',
  'ce-type': 'com.example.someevent',
  'ce-source': '/mycontext',
  'ce-id': 'C234-1234-1234',
  'ce-time': '2018-04-05T17:31:00Z',
  'ce-comexampleextension1': 'value',
  'ce-comexampleothervalue': '5',
  'content-type': 'application/json',
};
const String _exampleCBody = '''
{
  "appinfoA" : "abc",
  "appinfoB" : 123,
  "appinfoC" : true
}''';

// json-format.md, a serialized XML document as String-valued data.
const String _exampleB = r'''
{
    "specversion" : "1.0",
    "type" : "com.example.someevent",
    "source" : "/mycontext",
    "id" : "B234-1234-1234",
    "time" : "2018-04-05T17:31:00Z",
    "comexampleextension1" : "value",
    "comexampleothervalue" : 5,
    "unsetextension": null,
    "datacontenttype" : "application/xml",
    "data" : "<much wow=\"xml\"/>"
}''';

// json-format.md, a literal JSON string and no datacontenttype.
const String _exampleD = '''
{
    "specversion" : "1.0",
    "type" : "com.example.someevent",
    "source" : "/mycontext",
    "subject": null,
    "id" : "D234-1234-1234",
    "time" : "2018-04-05T17:31:00Z",
    "comexampleextension1" : "value",
    "comexampleothervalue" : 5,
    "data" : "I'm just a string"
}''';

const Map<String, String> _structured = <String, String>{
  'content-type': 'application/cloudevents+json; charset=utf-8',
};

Matcher _refused(String why) => throwsA(isA<DVCloudEventFormatException>()
    .having((DVCloudEventFormatException e) => e.code, 'code', 'DV-WEBHOOK-008')
    .having((DVCloudEventFormatException e) => e.message, 'message',
        contains(why)));

void main() {
  group('reading the specification\'s examples', () {
    test('C, structured: attributes, extensions and JSON data', () {
      final DVCloudEvent event =
          DVCloudEvent.fromHttp(headers: _structured, body: _exampleC);
      expect(event.id, 'C234-1234-1234');
      expect(event.source, '/mycontext');
      expect(event.type, 'com.example.someevent');
      expect(event.time, DateTime.utc(2018, 4, 5, 17, 31));
      expect(event.subject, isNull, reason: 'null is unset');
      expect(event.datacontenttype, 'application/json');
      expect(event.data, <String, Object?>{
        'appinfoA': 'abc',
        'appinfoB': 123,
        'appinfoC': true,
      });
      expect(event.extensions, <String, Object?>{
        'comexampleextension1': 'value',
        'comexampleothervalue': 5,
      });
    });

    test('C, binary: the same event from ce- headers and the data as body',
        () {
      final DVCloudEvent event =
          DVCloudEvent.fromHttp(headers: _exampleCHeaders, body: _exampleCBody);
      expect(event.id, 'C234-1234-1234');
      expect(event.source, '/mycontext');
      expect(event.type, 'com.example.someevent');
      expect(event.time, DateTime.utc(2018, 4, 5, 17, 31));
      expect(event.datacontenttype, 'application/json');
      expect(event.data, <String, Object?>{
        'appinfoA': 'abc',
        'appinfoB': 123,
        'appinfoC': true,
      });
      expect(event.extensions, <String, Object?>{
        'comexampleextension1': 'value',
        'comexampleothervalue': '5',
      }, reason: 'a header carries a string');
    });

    test('B: non-JSON data stays the string it was, in both modes', () {
      final DVCloudEvent structured =
          DVCloudEvent.fromHttp(headers: _structured, body: _exampleB);
      expect(structured.data, '<much wow="xml"/>');
      expect(structured.extensions.containsKey('unsetextension'), isFalse);

      final DVCloudEvent binary = DVCloudEvent.fromHttp(
        headers: <String, String>{
          'ce-specversion': '1.0',
          'ce-type': 'com.example.someevent',
          'ce-source': '/mycontext',
          'ce-id': 'B234-1234-1234',
          'content-type': 'application/xml',
        },
        body: '<much wow="xml"/>',
      );
      expect(binary.data, '<much wow="xml"/>');
      expect(binary.datacontenttype, 'application/xml');
    });

    test('D: data with no datacontenttype is JSON, and its binary form is '
        'the quoted JSON string', () {
      final DVCloudEvent structured =
          DVCloudEvent.fromHttp(headers: _structured, body: _exampleD);
      expect(structured.data, "I'm just a string");

      final DVCloudEvent binary = DVCloudEvent.fromHttp(
        headers: <String, String>{
          'ce-specversion': '1.0',
          'ce-type': 'com.example.someevent',
          'ce-source': '/mycontext',
          'ce-id': 'D234-1234-1234',
          'content-type': 'application/json',
        },
        body: '"I\'m just a string"',
      );
      expect(binary.data, "I'm just a string");
    });

    test('header names are read without regard to case', () {
      final DVCloudEvent event = DVCloudEvent.fromHttp(
        headers: <String, String>{
          for (final MapEntry<String, String> e in _exampleCHeaders.entries)
            e.key.toUpperCase(): e.value,
        },
        body: _exampleCBody,
      );
      expect(event.id, 'C234-1234-1234');
    });
  });

  group('writing', () {
    final DVCloudEvent event = DVCloudEvent(
      id: 'whdel_1',
      source: '/shop',
      type: 'order.paid',
      time: DateTime.utc(2026, 9, 26, 12),
      data: <String, Object?>{'orderId': 'o-42'},
    );

    test('structured: application/cloudevents+json with every attribute in '
        'the body', () {
      final DVCloudEventMessage message = event.toHttp();
      expect(message.headers['content-type'],
          'application/cloudevents+json; charset=utf-8');
      expect(message.headers.keys.where((String k) => k.startsWith('ce-')),
          isEmpty);
      expect(jsonDecode(message.body), <String, Object?>{
        'specversion': '1.0',
        'id': 'whdel_1',
        'source': '/shop',
        'type': 'order.paid',
        'time': '2026-09-26T12:00:00.000Z',
        'datacontenttype': 'application/json',
        'data': <String, Object?>{'orderId': 'o-42'},
      });
    });

    test('binary: ce- headers, the data\'s content type and the data alone '
        'as the body', () {
      final DVCloudEventMessage message =
          event.toHttp(mode: DVCloudEventMode.binary);
      expect(message.headers, <String, String>{
        'ce-specversion': '1.0',
        'ce-id': 'whdel_1',
        'ce-source': '/shop',
        'ce-type': 'order.paid',
        'ce-time': '2026-09-26T12:00:00.000Z',
        'content-type': 'application/json; charset=utf-8',
      });
      expect(jsonDecode(message.body), <String, Object?>{'orderId': 'o-42'});
    });

    for (final DVCloudEventMode mode in DVCloudEventMode.values) {
      test('${mode.name}: what is written reads back as the same event', () {
        final DVCloudEvent withExtension = DVCloudEvent(
          id: 'id 1',
          source: 'https://shop.example/€',
          type: 'order.paid',
          subject: 'orders/42',
          time: DateTime.utc(2026, 9, 26, 12),
          data: <String, Object?>{'n': 1},
          extensions: const <String, Object?>{'tenant': 'acme'},
        );
        final DVCloudEventMessage message = withExtension.toHttp(mode: mode);
        final DVCloudEvent back =
            DVCloudEvent.fromHttp(headers: message.headers, body: message.body);
        expect(back.id, 'id 1');
        expect(back.source, 'https://shop.example/€');
        expect(back.type, 'order.paid');
        expect(back.subject, 'orders/42');
        expect(back.time, DateTime.utc(2026, 9, 26, 12));
        expect(back.data, <String, Object?>{'n': 1});
        expect(back.extensions, <String, Object?>{'tenant': 'acme'});
      });
    }
  });

  group('header values', () {
    test('are percent-encoded as the binding\'s example is', () {
      final DVCloudEventMessage message = const DVCloudEvent(
        id: '1',
        source: '/s',
        type: 'Euro € \u{1F600}',
      ).toHttp(mode: DVCloudEventMode.binary);
      expect(message.headers['ce-type'], 'Euro%20%E2%82%AC%20%F0%9F%98%80');
    });

    test('space, double quote and percent are encoded; other printable ASCII '
        'is not', () {
      final DVCloudEventMessage message = const DVCloudEvent(
        id: '1',
        source: '/s?a=b&c',
        type: 'a "b" 100%',
      ).toHttp(mode: DVCloudEventMode.binary);
      expect(message.headers['ce-type'], 'a%20%22b%22%20100%25');
      expect(message.headers['ce-source'], '/s?a=b&c');
    });

    test('are decoded, lower-case hex and legacy quoted strings included', () {
      final DVCloudEvent event = DVCloudEvent.fromHttp(
        headers: <String, String>{
          'ce-specversion': '1.0',
          'ce-id': '"quoted \\"id\\""',
          'ce-source': '/s',
          'ce-type': 'Euro%20%e2%82%ac',
        },
        body: '',
      );
      expect(event.id, 'quoted "id"');
      expect(event.type, 'Euro €');
      expect(event.data, isNull);
    });

    test('an overlong UTF-8 sequence is refused, as the binding requires', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: <String, String>{
            'ce-specversion': '1.0',
            'ce-id': '1',
            'ce-source': '/s',
            'ce-type': 'a%C0%A0b',
          },
          body: '',
        ),
        _refused('ce-type'),
      );
    });
  });

  group('what is not a CloudEvent is refused, not guessed at', () {
    test('a plain JSON body with no ce- headers', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: <String, String>{'content-type': 'application/json'},
          body: '{"id":"1"}',
        ),
        _refused('not a CloudEvent'),
      );
    });

    test('a batch, which this receiver does not accept', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: <String, String>{
            'content-type': 'application/cloudevents-batch+json',
          },
          body: '[$_exampleC]',
        ),
        _refused('batch'),
      );
    });

    for (final String attribute in <String>['id', 'source', 'type']) {
      test('a structured event with no $attribute', () {
        final Map<String, Object?> json =
            jsonDecode(_exampleC) as Map<String, Object?>..remove(attribute);
        expect(
          () => DVCloudEvent.fromHttp(
              headers: _structured, body: jsonEncode(json)),
          _refused(attribute),
        );
      });

      test('a binary event with no ce-$attribute', () {
        expect(
          () => DVCloudEvent.fromHttp(
            headers: Map<String, String>.of(_exampleCHeaders)
              ..remove('ce-$attribute'),
            body: _exampleCBody,
          ),
          _refused(attribute),
        );
      });
    }

    test('a specversion other than 1.0', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: Map<String, String>.of(_exampleCHeaders)
            ..['ce-specversion'] = '0.3',
          body: _exampleCBody,
        ),
        _refused('specversion'),
      );
    });

    test('a structured body that is not a JSON object', () {
      expect(
        () => DVCloudEvent.fromHttp(headers: _structured, body: '[1, 2]'),
        _refused('JSON object'),
      );
    });

    test('a time that is not a timestamp', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: Map<String, String>.of(_exampleCHeaders)
            ..['ce-time'] = 'yesterday',
          body: _exampleCBody,
        ),
        _refused('time'),
      );
    });

    test('binary data declared JSON that is not JSON', () {
      expect(
        () => DVCloudEvent.fromHttp(
          headers: _exampleCHeaders,
          body: "I'm just a string",
        ),
        _refused('data'),
      );
    });
  });
}

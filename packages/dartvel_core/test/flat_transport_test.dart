// The flat-buffer envelope on the wire.
//
// The spec transmits backend data as form-data whose fields are packed as
// binary flat buffers. The codec is tested on its own; this covers the part
// that decides whether a part is one -- getting that wrong means either a
// typed value arriving as the characters that spell it, or a text field being
// refused because it is not a buffer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/http/flat_buffer.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as shelf;
import 'package:test/test.dart';

const String boundary = 'dvb';

/// Builds a multipart body. [flat] names the fields whose values are flat
/// buffers rather than text.
List<int> multipart(Map<String, Object?> fields, {Set<String> flat = const {}}) {
  final BytesBuilder out = BytesBuilder();
  void line(String value) => out.add(utf8.encode('$value\r\n'));

  fields.forEach((String name, Object? value) {
    line('--$boundary');
    line('content-disposition: form-data; name="$name"');
    if (flat.contains(name)) {
      line('content-type: $dvFlatContentType');
      line('');
      out.add(dvFlatEncode(value));
      out.add(utf8.encode('\r\n'));
    } else {
      line('');
      line('$value');
    }
  });
  line('--$boundary--');
  return out.takeBytes();
}

shelf.Request requestWith(List<int> body) => shelf.Request(
      method: 'POST',
      url: Uri.parse('https://example.test/fn'),
      headers: shelf.Headers(<String, String>{
        'content-type': 'multipart/form-data; boundary=$boundary',
      }),
      bodyStream: Stream<List<int>>.value(body),
    );

void main() {
  test('a flat field arrives as its typed value, not as text', () async {
    // The whole point of the binary envelope: over text multipart every one of
    // these arrives as a String and the type is gone by the time a parameter
    // is decoded.
    final Map<String, Object?> data = await requestWith(
      multipart(
        <String, Object?>{
          'count': 42,
          'ratio': 0.5,
          'enabled': true,
          'missing': null,
        },
        flat: <String>{'count', 'ratio', 'enabled', 'missing'},
      ),
    ).formData();

    expect(data['count'], isA<int>());
    expect(data['count'], 42);
    expect(data['ratio'], isA<double>());
    expect(data['enabled'], isA<bool>());
    expect(data.containsKey('missing'), isTrue);
    expect(data['missing'], isNull);
  });

  test('a text field is still text', () async {
    // Backwards compatibility: a client that has not adopted the envelope must
    // keep working.
    final Map<String, Object?> data = await requestWith(
      multipart(<String, Object?>{'name': 'Ada'}),
    ).formData();

    expect(data['name'], 'Ada');
  });

  test('the two mix in one request', () async {
    final Map<String, Object?> data = await requestWith(
      multipart(
        <String, Object?>{'name': 'Ada', 'count': 7},
        flat: <String>{'count'},
      ),
    ).formData();

    expect(data['name'], 'Ada');
    expect(data['count'], 7);
  });

  test('a structured field survives the envelope', () async {
    final Map<String, Object?> data = await requestWith(
      multipart(
        <String, Object?>{
          'order': <String, Object?>{
            'sku': 'DV-1',
            'quantity': 2,
            'tags': <String>['rush', 'gift'],
          },
        },
        flat: <String>{'order'},
      ),
    ).formData();

    expect(data['order'], <String, Object?>{
      'sku': 'DV-1',
      'quantity': 2,
      'tags': <String>['rush', 'gift'],
    });
  });

  test('bytes stay bytes without a base64 detour', () async {
    final Uint8List blob = Uint8List.fromList(<int>[0, 1, 254, 255]);
    final Map<String, Object?> data = await requestWith(
      multipart(<String, Object?>{'blob': blob}, flat: <String>{'blob'}),
    ).formData();

    expect(data['blob'], blob);
  });

  test('a corrupt flat field is refused, not silently read as text', () async {
    // Falling back to text here would hand a parameter the raw bytes of a
    // damaged buffer, which is exactly the plausible-looking wrong value the
    // envelope exists to prevent.
    final BytesBuilder out = BytesBuilder();
    void line(String value) => out.add(utf8.encode('$value\r\n'));
    line('--$boundary');
    line('content-disposition: form-data; name="count"');
    line('content-type: $dvFlatContentType');
    line('');
    out.add(<int>[0x00, 0x01, 0x02, 0x03]);
    out.add(utf8.encode('\r\n'));
    line('--$boundary--');

    expect(
      () => requestWith(out.takeBytes()).formData(),
      throwsA(isA<FormatException>()),
    );
  });
}

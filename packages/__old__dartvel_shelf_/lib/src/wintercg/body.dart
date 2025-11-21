import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class Body {
  final Stream<List<int>> _stream;
  bool _used = false;
  Body(Stream<List<int>> stream) : _stream = stream;
  Stream<List<int>> get stream {
    if (_used) throw StateError('Body already used');
    _used = true;
    return _stream;
  }

  Future<List<int>> bytes() async => (await bytesU8());
  Future<Uint8List> bytesU8() async {
    final chunks = <Uint8List>[];
    int total = 0;
    await for (final chunk in stream) {
      final u8 = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      chunks.add(u8);
      total += u8.length;
    }
    if (chunks.length == 1) return chunks.first;
    final out = Uint8List(total);
    var offset = 0;
    for (final c in chunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }
  Future<String> text([Encoding enc = utf8]) async => enc.decode(await bytesU8());
  Future<dynamic> jsonDecode([Encoding enc = utf8]) async =>
      _jsonDecode(await text(enc));
}

dynamic _jsonDecode(String s) {
  try {
    return json.decode(s);
  } catch (_) {
    return s;
  }
}

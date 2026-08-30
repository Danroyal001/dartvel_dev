/// The binary envelope encoding for backend transport.
///
/// The spec transmits backend data as form-data whose fields are packed as
/// binary flat buffers: form-data so large bodies stream and the web can send
/// them, binary so a typed value survives the trip. Text multipart cannot do
/// the second part -- everything arrives as a string, so an `int` and the
/// characters `"1"` are indistinguishable by the time a parameter is decoded,
/// and bytes have to be base64'd at a third more size.
///
/// The layout is length-prefixed and read in place: a value is `tag` followed
/// by its payload, and a container is a count followed by its children. There
/// is no separate parse pass building an intermediate tree.
///
/// ```text
/// 'D' 'V' 'F' 'B'  version:u8  reserved:u8  reserved:u16   -- 8-byte header
/// tag:u8  payload...                                        -- one root value
/// ```
///
/// Every read is bounds-checked against the buffer it was given. A decoder
/// that trusts a length it was handed is the standard way a codec turns
/// hostile input into a crash or a disclosure, and one that ignores trailing
/// bytes lets two different buffers decode alike -- which is how a signature
/// over the bytes stops meaning anything.
library dartvel_core.flat_buffer;

import 'dart:convert';
import 'dart:typed_data';

/// The magic and version prefix every buffer starts with.
const int dvFlatHeaderLength = 8;

const List<int> _magic = <int>[0x44, 0x56, 0x46, 0x42]; // 'DVFB'
const int _version = 1;

// Type tags. Small ints are their own tag so the common case is two bytes.
const int _tagNull = 0x01;
const int _tagFalse = 0x02;
const int _tagTrue = 0x03;
const int _tagInt = 0x04;
const int _tagDouble = 0x05;
const int _tagString = 0x06;
const int _tagBytes = 0x07;
const int _tagList = 0x08;
const int _tagMap = 0x09;

/// The MIME parameter that names this encoding in a request header, so a
/// reader knows what it has before it starts decoding.
const String dvFlatContentType = 'application/vnd.dartvel.flat.v1';

/// Encodes [value] into a self-describing binary buffer.
///
/// Accepts null, bool, int, double, String, `List<int>` as bytes, List and
/// `Map<String, Object?>`. Anything else is an [ArgumentError]: guessing at a
/// type here would put the guess on the wire.
Uint8List dvFlatEncode(Object? value) {
  final _Writer writer = _Writer()
    ..bytes(_magic)
    ..u8(_version)
    ..u8(0)
    ..u16(0);
  _writeValue(writer, value);
  return writer.take();
}

/// Decodes a buffer produced by [dvFlatEncode].
///
/// Throws [FormatException] for anything that is not exactly one well-formed
/// buffer, including a truncation, an out-of-range length, an unknown tag, and
/// trailing bytes after the root value.
Object? dvFlatDecode(Uint8List buffer) {
  if (buffer.length < dvFlatHeaderLength) {
    throw const FormatException('Not a Dartvel flat buffer: too short.');
  }
  for (int i = 0; i < _magic.length; i += 1) {
    if (buffer[i] != _magic[i]) {
      throw const FormatException('Not a Dartvel flat buffer: bad magic.');
    }
  }
  if (buffer[4] != _version) {
    throw FormatException(
      'Unsupported Dartvel flat buffer version ${buffer[4]}.',
    );
  }

  final _Reader reader = _Reader(buffer, dvFlatHeaderLength);
  final Object? value = _readValue(reader);
  if (!reader.atEnd) {
    // Ignoring these would let two different buffers decode alike.
    throw FormatException(
      '${reader.remaining} trailing byte(s) after the value.',
    );
  }
  return value;
}

void _writeValue(_Writer out, Object? value) {
  if (value == null) {
    out.u8(_tagNull);
    return;
  }
  if (value is bool) {
    out.u8(value ? _tagTrue : _tagFalse);
    return;
  }
  if (value is int) {
    out
      ..u8(_tagInt)
      ..i64(value);
    return;
  }
  if (value is double) {
    // The bit pattern, not a decimal rendering: NaN, the infinities and the
    // sign of negative zero do not survive a string round trip.
    out
      ..u8(_tagDouble)
      ..f64(value);
    return;
  }
  if (value is String) {
    final List<int> encoded = utf8.encode(value);
    out
      ..u8(_tagString)
      ..u32(encoded.length)
      ..bytes(encoded);
    return;
  }
  if (value is Uint8List) {
    out
      ..u8(_tagBytes)
      ..u32(value.length)
      ..bytes(value);
    return;
  }
  if (value is Map) {
    out
      ..u8(_tagMap)
      ..u32(value.length);
    // Written in iteration order, so encoding the same map twice produces the
    // same bytes and a signature over them is stable.
    value.forEach((Object? key, Object? child) {
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'map keys must be strings');
      }
      final List<int> encoded = utf8.encode(key);
      out
        ..u32(encoded.length)
        ..bytes(encoded);
      _writeValue(out, child);
    });
    return;
  }
  if (value is List) {
    out
      ..u8(_tagList)
      ..u32(value.length);
    for (final Object? child in value) {
      _writeValue(out, child);
    }
    return;
  }
  throw ArgumentError.value(
    value,
    'value',
    'a Dartvel flat buffer holds null, bool, int, double, String, Uint8List, '
        'List or Map<String, Object?>',
  );
}

Object? _readValue(_Reader input) {
  final int tag = input.u8();
  switch (tag) {
    case _tagNull:
      return null;
    case _tagFalse:
      return false;
    case _tagTrue:
      return true;
    case _tagInt:
      return input.i64();
    case _tagDouble:
      return input.f64();
    case _tagString:
      return utf8.decode(input.take(input.u32()));
    case _tagBytes:
      return Uint8List.fromList(input.take(input.u32()));
    case _tagList:
      final int count = input.u32();
      final List<Object?> items = <Object?>[];
      for (int i = 0; i < count; i += 1) {
        items.add(_readValue(input));
      }
      return items;
    case _tagMap:
      final int count = input.u32();
      final Map<String, Object?> entries = <String, Object?>{};
      for (int i = 0; i < count; i += 1) {
        final String key = utf8.decode(input.take(input.u32()));
        entries[key] = _readValue(input);
      }
      return entries;
    default:
      throw FormatException(
        'Unknown Dartvel flat buffer tag 0x${tag.toRadixString(16)}.',
      );
  }
}

class _Writer {
  // copy: false means the builder keeps a reference to what it is handed, so
  // every word below is freshly allocated. A shared scratch buffer would be
  // rewritten under bytes already queued, and the corruption would only appear
  // once a field was written twice.
  final BytesBuilder _out = BytesBuilder(copy: false);

  void u8(int value) => _out.addByte(value & 0xFF);

  void u16(int value) {
    final ByteData word = ByteData(2)..setUint16(0, value, Endian.big);
    _out.add(word.buffer.asUint8List());
  }

  void u32(int value) {
    final ByteData word = ByteData(4)..setUint32(0, value, Endian.big);
    _out.add(word.buffer.asUint8List());
  }

  void i64(int value) {
    final ByteData word = ByteData(8)..setInt64(0, value, Endian.big);
    _out.add(word.buffer.asUint8List());
  }

  void f64(double value) {
    final ByteData word = ByteData(8)..setFloat64(0, value, Endian.big);
    _out.add(word.buffer.asUint8List());
  }

  void bytes(List<int> value) => _out.add(value);

  Uint8List take() => _out.toBytes();
}

class _Reader {
  _Reader(this.buffer, this.offset)
      : _view = ByteData.sublistView(buffer);

  final Uint8List buffer;
  final ByteData _view;
  int offset;

  bool get atEnd => offset == buffer.length;
  int get remaining => buffer.length - offset;

  /// Every read goes through here, so no length taken off the wire can move
  /// the cursor past the end of what was actually received.
  void _need(int count) {
    if (count < 0 || offset + count > buffer.length) {
      throw FormatException(
        'Truncated Dartvel flat buffer: wanted $count byte(s) at $offset, '
        '$remaining left.',
      );
    }
  }

  int u8() {
    _need(1);
    return buffer[offset++];
  }

  int u32() {
    _need(4);
    final int value = _view.getUint32(offset, Endian.big);
    offset += 4;
    return value;
  }

  int i64() {
    _need(8);
    final int value = _view.getInt64(offset, Endian.big);
    offset += 8;
    return value;
  }

  double f64() {
    _need(8);
    final double value = _view.getFloat64(offset, Endian.big);
    offset += 8;
    return value;
  }

  Uint8List take(int count) {
    _need(count);
    final Uint8List slice = Uint8List.sublistView(
      buffer,
      offset,
      offset + count,
    );
    offset += count;
    return slice;
  }
}

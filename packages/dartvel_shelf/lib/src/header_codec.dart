import 'dart:typed_data';

Map<String, List<String>> decodeHeaders(Uint8List flat) {
  final out = <String, List<String>>{};
  var i = 0;
  while (i < flat.length) {
    final ke = flat.indexOf(0, i);
    if (ke < 0) break;
    final key = String.fromCharCodes(flat.sublist(i, ke)).toLowerCase();
    i = ke + 1;
    final ve = flat.indexOf(0, i);
    if (ve < 0) break;
    final val = String.fromCharCodes(flat.sublist(i, ve));
    i = ve + 1;
    (out[key] ??= <String>[]).add(val);
  }
  return out;
}

Uint8List encodeHeaders(Map<String, List<String>> headers) {
  final b = BytesBuilder();
  headers.forEach((k, vs) {
    for (final v in vs) {
      b.add(k.codeUnits);
      b.addByte(0);
      b.add(v.codeUnits);
      b.addByte(0);
    }
  });
  return b.toBytes();
}

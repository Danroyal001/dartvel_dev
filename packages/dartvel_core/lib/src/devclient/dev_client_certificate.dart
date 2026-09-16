/// The TLS certificate a dev server presents: self-signed, for the key its
/// pairing link carries.
///
/// A device pins the connection to that key rather than to any authority, so
/// the certificate needs no name, no chain and no extensions -- only the key,
/// signed by itself so a TLS stack will load it. What makes a connection
/// trusted is that the certificate's public key is the link's key, and the
/// handshake proves the server holds its private half.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../notifications/web_push_vapid.dart' show dvWebPushSignEs256;

/// A dev server's certificate and private key.
class DVDevClientCertificate {
  const DVDevClientCertificate({
    required this.der,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  /// The certificate, DER.
  final Uint8List der;

  /// The certificate, PEM, for `SecurityContext.useCertificateChainBytes`.
  final String certificatePem;

  /// The private key, PKCS#8 PEM, for `SecurityContext.usePrivateKeyBytes`.
  final String privateKeyPem;
}

// OIDs, DER-encoded without their tag and length.
const List<int> _ecPublicKey = <int>[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];
const List<int> _prime256v1 = <int>[
  0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //
];
const List<int> _ecdsaWithSha256 = <int>[
  0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02, //
];
const List<int> _commonName = <int>[0x55, 0x04, 0x03];

List<int> _length(int n) {
  if (n < 0x80) return <int>[n];
  final List<int> bytes = <int>[];
  for (int v = n; v > 0; v >>= 8) {
    bytes.insert(0, v & 0xff);
  }
  return <int>[0x80 | bytes.length, ...bytes];
}

List<int> _tlv(int tag, List<int> value) => <int>[
  tag,
  ..._length(value.length),
  ...value,
];

List<int> _sequence(List<List<int>> items) =>
    _tlv(0x30, <int>[for (final List<int> item in items) ...item]);

List<int> _oid(List<int> encoded) => _tlv(0x06, encoded);

/// A non-negative INTEGER from unsigned big-endian [bytes].
List<int> _unsigned(List<int> bytes) {
  int start = 0;
  while (start < bytes.length - 1 && bytes[start] == 0) {
    start++;
  }
  final List<int> trimmed = bytes.sublist(start);
  return _tlv(0x02, <int>[if (trimmed.first & 0x80 != 0) 0, ...trimmed]);
}

List<int> _utcTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final DateTime u = t.toUtc();
  return _tlv(
    0x17,
    ascii.encode(
      '${two(u.year % 100)}${two(u.month)}${two(u.day)}'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z',
    ),
  );
}

String _pem(String label, List<int> der) {
  final String body = base64.encode(der);
  final StringBuffer out = StringBuffer('-----BEGIN $label-----\n');
  for (int i = 0; i < body.length; i += 64) {
    out.writeln(body.substring(i, min(i + 64, body.length)));
  }
  out.write('-----END $label-----\n');
  return out.toString();
}

/// A self-signed P-256 certificate for [publicKey], signed with
/// [privateKey], valid from a day before [now] for thirty days.
DVDevClientCertificate dvDevClientCertificate({
  required Uint8List publicKey,
  required Uint8List privateKey,
  DateTime? now,
  Random? random,
}) {
  final DateTime at = now ?? DateTime.now();
  final Random source = random ?? Random.secure();
  final List<int> serial = <int>[
    for (int i = 0; i < 16; i++) source.nextInt(256),
  ]..[0] &= 0x7f;
  serial[0] |= 0x01;
  final List<int> name = _sequence(<List<int>>[
    _tlv(
      0x31,
      _sequence(<List<int>>[
        _oid(_commonName),
        _tlv(0x0c, utf8.encode('dartvel dev')),
      ]),
    ),
  ]);
  final List<int> algorithm = _sequence(<List<int>>[_oid(_ecdsaWithSha256)]);
  final List<int> spki = _sequence(<List<int>>[
    _sequence(<List<int>>[_oid(_ecPublicKey), _oid(_prime256v1)]),
    _tlv(0x03, <int>[0, ...publicKey]),
  ]);
  final List<int> tbs = _sequence(<List<int>>[
    _tlv(0xa0, _tlv(0x02, <int>[2])),
    _tlv(0x02, serial),
    algorithm,
    name,
    _sequence(<List<int>>[
      _utcTime(at.subtract(const Duration(days: 1))),
      _utcTime(at.add(const Duration(days: 30))),
    ]),
    name,
    spki,
  ]);
  final Uint8List raw = dvWebPushSignEs256(tbs, privateKey);
  final List<int> signature = _sequence(<List<int>>[
    _unsigned(raw.sublist(0, 32)),
    _unsigned(raw.sublist(32, 64)),
  ]);
  final Uint8List der = Uint8List.fromList(
    _sequence(<List<int>>[
      tbs,
      algorithm,
      _tlv(0x03, <int>[0, ...signature]),
    ]),
  );
  final List<int> pkcs8 = _sequence(<List<int>>[
    _tlv(0x02, <int>[0]),
    _sequence(<List<int>>[_oid(_ecPublicKey), _oid(_prime256v1)]),
    _tlv(
      0x04,
      _sequence(<List<int>>[
        _tlv(0x02, <int>[1]),
        _tlv(0x04, privateKey),
        _tlv(0xa1, _tlv(0x03, <int>[0, ...publicKey])),
      ]),
    ),
  ]);
  return DVDevClientCertificate(
    der: der,
    certificatePem: _pem('CERTIFICATE', der),
    privateKeyPem: _pem('PRIVATE KEY', pkcs8),
  );
}

/// A DER element: its tag, and where its value starts and ends in the input.
class _Element {
  const _Element(this.tag, this.start, this.end);
  final int tag;
  final int start;
  final int end;
}

_Element _read(List<int> der, int at, int limit) {
  if (at + 2 > limit) throw const FormatException('truncated');
  final int tag = der[at];
  int length = der[at + 1];
  int start = at + 2;
  if (length & 0x80 != 0) {
    final int count = length & 0x7f;
    if (count == 0 || count > 4 || start + count > limit) {
      throw const FormatException('bad length');
    }
    length = 0;
    for (int i = 0; i < count; i++) {
      length = (length << 8) | der[start + i];
    }
    start += count;
  }
  if (start + length > limit) throw const FormatException('truncated');
  return _Element(tag, start, start + length);
}

bool _equals(List<int> a, int start, int end, List<int> b) {
  if (end - start != b.length) return false;
  for (int i = 0; i < b.length; i++) {
    if (a[start + i] != b[i]) return false;
  }
  return true;
}

/// The uncompressed P-256 point a certificate's subject public key info
/// carries, or null when [der] is not a certificate with a P-256 key.
///
/// Read by structure -- certificate, to-be-signed certificate, the seventh
/// field of it -- never by searching the bytes: a certificate for another key
/// can carry the pairing key anywhere else it likes.
Uint8List? dvCertificateP256PublicKey(List<int> der) {
  try {
    final _Element certificate = _read(der, 0, der.length);
    if (certificate.tag != 0x30) return null;
    final _Element tbs = _read(der, certificate.start, certificate.end);
    if (tbs.tag != 0x30) return null;
    int at = tbs.start;
    _Element field = _read(der, at, tbs.end);
    // version is optional, as [0].
    if (field.tag == 0xa0) {
      at = field.end;
      field = _read(der, at, tbs.end);
    }
    // serialNumber, signature, issuer, validity, subject.
    for (int i = 0; i < 5; i++) {
      at = field.end;
      field = _read(der, at, tbs.end);
    }
    if (field.tag != 0x30) return null;
    final _Element algorithm = _read(der, field.start, field.end);
    if (algorithm.tag != 0x30) return null;
    final _Element keyType = _read(der, algorithm.start, algorithm.end);
    if (keyType.tag != 0x06 ||
        !_equals(der, keyType.start, keyType.end, _ecPublicKey)) {
      return null;
    }
    final _Element curve = _read(der, keyType.end, algorithm.end);
    if (curve.tag != 0x06 ||
        !_equals(der, curve.start, curve.end, _prime256v1)) {
      return null;
    }
    final _Element bits = _read(der, algorithm.end, field.end);
    if (bits.tag != 0x03 || bits.end - bits.start != 66) return null;
    if (der[bits.start] != 0 || der[bits.start + 1] != 0x04) return null;
    return Uint8List.fromList(der.sublist(bits.start + 1, bits.end));
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

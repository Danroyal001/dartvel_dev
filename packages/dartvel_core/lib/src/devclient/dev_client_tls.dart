/// Connections to a dev server, trusted only for the key the pairing link
/// carries.
library;

import 'dart:io';

import 'dev_client.dart' show DVDevClientPairing;
import 'dev_client_certificate.dart';

/// Whether [certificate] is the one a server paired by [pairing] presents:
/// its public key is the link's key.
bool dvDevClientCertificateTrusted(
  DVDevClientPairing pairing,
  X509Certificate certificate,
) {
  final List<int>? key = dvCertificateP256PublicKey(certificate.der);
  if (key == null || key.length != pairing.publicKey.length) return false;
  int difference = 0;
  for (int i = 0; i < key.length; i++) {
    difference |= key[i] ^ pairing.publicKey[i];
  }
  return difference == 0;
}

/// A security context that trusts nothing by itself, so every certificate
/// reaches the pin check: one that also trusted the system's roots would
/// accept a publicly issued certificate without asking.
SecurityContext _untrusting() => SecurityContext(withTrustedRoots: false);

/// An [HttpClient] that talks only to the dev server [pairing] names.
HttpClient dvDevClientHttpClient(DVDevClientPairing pairing) =>
    HttpClient(context: _untrusting())
      ..badCertificateCallback = (X509Certificate certificate, _, _) =>
          dvDevClientCertificateTrusted(pairing, certificate);

/// A TLS connection to the dev server [pairing] names, refused before
/// anything is sent when its certificate is not for the link's key.
Future<SecureSocket> dvDevClientSecureConnect(
  DVDevClientPairing pairing, {
  Duration timeout = const Duration(seconds: 10),
}) => SecureSocket.connect(
  pairing.server.host,
  pairing.server.port,
  context: _untrusting(),
  onBadCertificate: (X509Certificate certificate) =>
      dvDevClientCertificateTrusted(pairing, certificate),
  timeout: timeout,
);

/// The security context a dev server serves [certificate] with.
SecurityContext dvDevClientServerContext(DVDevClientCertificate certificate) =>
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(certificate.certificatePem.codeUnits)
      ..usePrivateKeyBytes(certificate.privateKeyPem.codeUnits);

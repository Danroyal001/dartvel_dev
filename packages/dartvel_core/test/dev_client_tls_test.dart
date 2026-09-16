// Pairing over TLS, pinned to the key in the pairing link.
//
// Over plain http the key stopped another machine pushing code to a device,
// but the token went across the network in the clear, and anything that saw
// it could read every page the dev server serves. Now a dev server presents a
// self-signed certificate for the very key the link carries, and a device
// trusts a connection only when the certificate's key is that key -- no CA,
// no hostname, nothing a LAN can offer instead. The failures that stay silent:
//
//  * a client that accepts any certificate, which is TLS that stops nobody;
//  * a client that trusts the system's roots first and never reaches the pin,
//    so a publicly trusted certificate for the address is accepted;
//  * a key found anywhere in a certificate rather than in its public key
//    info, which a crafted certificate can carry without holding the key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final DVDevClientSigner signer = DVDevClientSigner.generate();
  final DVDevClientSigner other = DVDevClientSigner.generate();
  final String token = DVDevClientPairing.newToken();

  DVDevClientPairing pairing(int port, {DVDevClientSigner? key}) =>
      DVDevClientPairing(
        server: Uri.parse('https://127.0.0.1:$port'),
        branch: 'main',
        publicKey: (key ?? signer).publicKey,
        token: token,
      );

  group('the link', () {
    test('names an https dev server; an http one is refused', () {
      final DVDevClientPairing secure = pairing(8787);
      expect(DVDevClientPairing.parse(secure.link).server.scheme, 'https');

      final Uri plain = secure.link.replace(
        queryParameters: <String, String>{
          ...secure.link.queryParameters,
          'server': 'http://127.0.0.1:8787',
        },
      );
      expect(() => DVDevClientPairing.parse(plain), throwsFormatException);
    });
  });

  group('the certificate', () {
    test('carries the pairing key as its public key', () {
      final DVDevClientCertificate certificate = signer.certificate();
      expect(dvCertificateP256PublicKey(certificate.der), signer.publicKey);
      expect(
        dvCertificateP256PublicKey(other.certificate().der),
        isNot(signer.publicKey),
      );
    });

    test('is PEM a TLS server loads', () {
      final DVDevClientCertificate certificate = signer.certificate();
      expect(
        certificate.certificatePem,
        startsWith('-----BEGIN CERTIFICATE-----'),
      );
      expect(
        certificate.privateKeyPem,
        startsWith('-----BEGIN PRIVATE KEY-----'),
      );
      expect(
        () => SecurityContext(withTrustedRoots: false)
          ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
          ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem)),
        returnsNormally,
      );
    });

    test('a key that appears elsewhere in a certificate is not its key', () {
      final Uint8List der = other.certificate().der;
      // The pairing key pasted over bytes that are not the public key info:
      // the certificate's own signature at the end.
      final Uint8List forged = Uint8List.fromList(der)
        ..setRange(der.length - 65, der.length, signer.publicKey);
      expect(dvCertificateP256PublicKey(forged), isNot(signer.publicKey));
    });
  });

  group('over the network', () {
    late HttpServer server;
    late List<String> received;

    Future<void> serve(DVDevClientSigner key) async {
      final DVDevClientCertificate certificate = key.certificate();
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext(withTrustedRoots: false)
          ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
          ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem)),
      );
      received = <String>[];
      server.listen((HttpRequest request) async {
        received.add(request.headers.value('authorization') ?? '');
        request.response.write('pages');
        await request.response.close();
      });
    }

    tearDown(() => server.close(force: true));

    test('a device reaches the server holding the pairing key', () async {
      await serve(signer);
      final HttpClient client = dvDevClientHttpClient(pairing(server.port));
      try {
        final HttpClientRequest request = await client.getUrl(
          pairing(server.port).bundleUri('android'),
        );
        request.headers.set('authorization', 'Bearer $token');
        final HttpClientResponse response = await request.close();
        expect(await utf8.decodeStream(response), 'pages');
        expect(received, <String>['Bearer $token']);
      } finally {
        client.close(force: true);
      }
    });

    test('a server holding another key never receives the token', () async {
      await serve(other);
      final HttpClient client = dvDevClientHttpClient(pairing(server.port));
      try {
        await expectLater(() async {
          final HttpClientRequest request = await client.getUrl(
            pairing(server.port).bundleUri('android'),
          );
          request.headers.set('authorization', 'Bearer $token');
          await (await request.close()).drain<void>();
        }(), throwsA(isA<Exception>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(received, hasLength(0));
      } finally {
        client.close(force: true);
      }
    });

    test('a raw socket pinned the same way reaches the key and refuses '
        'another', () async {
      await serve(signer);
      final SecureSocket ok = await dvDevClientSecureConnect(
        pairing(server.port),
      );
      ok.destroy();

      await expectLater(
        dvDevClientSecureConnect(pairing(server.port, key: other)),
        throwsA(isA<Exception>()),
      );
    });
  });
}

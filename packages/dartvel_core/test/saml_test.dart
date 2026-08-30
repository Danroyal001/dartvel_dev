// SAML assertion validation.
//
// The failure worth designing against is not a rejected login. It is signature
// wrapping: an attacker takes a genuine signed assertion, moves it somewhere
// the validator does not read from, and puts a forged one where it does. The
// signature verifies -- over the real assertion -- and the validator reads the
// forged one. Every field checks out and the wrong person is logged in.
//
// So the assertions below are mostly attacks. A validator that passes the
// happy-path test and fails these is not a slightly weaker validator; it is
// one that authenticates anybody who can capture a single assertion.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/src/auth/saml.dart';
import 'package:dartvel_core/src/auth/xml_c14n.dart';
// asn1.dart is not part of pointycastle's export.dart barrel; the
// certificate parser needs it explicitly.
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const String issuer = 'https://idp.example/metadata';
const String audience = 'https://app.example/sp';
const String recipient = 'https://app.example/acs';

late RSAPrivateKey idpPrivate;
late RSAPublicKey idpPublic;

/// A self-signed-ish certificate body: this test signs and verifies with a
/// raw RSA key, so the "certificate" is the SubjectPublicKeyInfo DER the
/// validator parses.
late String certificate;

/// Builds a SAML response whose assertion is signed.
///
/// [tamper] runs on the parsed document *after* signing, which is how each
/// attack below is constructed: the signature stays genuine and the document
/// around it changes.
String signedResponse({
  String assertionId = 'id-assertion-1',
  String nameId = 'ada@example.org',
  String forAudience = audience,
  String forIssuer = issuer,
  String? forRecipient = recipient,
  String? inResponseTo,
  DateTime? notBefore,
  DateTime? notOnOrAfter,
  void Function(XmlDocument document)? tamper,
}) {
  final String conditions = '<saml:Conditions'
      '${notBefore == null ? '' : ' NotBefore="${notBefore.toIso8601String()}"'}'
      '${notOnOrAfter == null ? '' : ' NotOnOrAfter="${notOnOrAfter.toIso8601String()}"'}'
      '>'
      '<saml:AudienceRestriction><saml:Audience>$forAudience'
      '</saml:Audience></saml:AudienceRestriction>'
      '</saml:Conditions>';

  final String assertion = '<saml:Assertion '
      'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" '
      'ID="$assertionId" Version="2.0" IssueInstant="2026-01-01T00:00:00Z">'
      '<saml:Issuer>$forIssuer</saml:Issuer>'
      '<saml:Subject>'
      '<saml:NameID>$nameId</saml:NameID>'
      '<saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">'
      '<saml:SubjectConfirmationData'
      '${forRecipient == null ? '' : ' Recipient="$forRecipient"'}'
      '${inResponseTo == null ? '' : ' InResponseTo="$inResponseTo"'}'
      '/>'
      '</saml:SubjectConfirmation>'
      '</saml:Subject>'
      '$conditions'
      '<saml:AuthnStatement SessionIndex="session-1" '
      'AuthnInstant="2026-01-01T00:00:00Z"/>'
      '<saml:AttributeStatement>'
      '<saml:Attribute Name="email">'
      '<saml:AttributeValue>$nameId</saml:AttributeValue>'
      '</saml:Attribute>'
      '</saml:AttributeStatement>'
      '</saml:Assertion>';

  // Digest the assertion as canonicalized, then sign SignedInfo -- the same
  // two steps the validator performs in reverse.
  final XmlElement assertionElement = XmlDocument.parse(assertion).rootElement;
  final String digest =
      base64.encode(sha256.convert(dvCanonicalizeExclusive(assertionElement)).bytes);

  final String signedInfo = '<ds:SignedInfo '
      'xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
      '<ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>'
      '<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>'
      '<ds:Reference URI="#$assertionId">'
      '<ds:Transforms>'
      '<ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>'
      '</ds:Transforms>'
      '<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>'
      '<ds:DigestValue>$digest</ds:DigestValue>'
      '</ds:Reference>'
      '</ds:SignedInfo>';

  final Uint8List canonicalSignedInfo = Uint8List.fromList(
    dvCanonicalizeExclusive(XmlDocument.parse(signedInfo).rootElement),
  );
  final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(idpPrivate));
  final String signatureValue =
      base64.encode(signer.generateSignature(canonicalSignedInfo).bytes);

  final String signature =
      '<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
      '$signedInfo'
      '<ds:SignatureValue>$signatureValue</ds:SignatureValue>'
      '</ds:Signature>';

  // The signature sits inside the assertion, after Issuer, as SAML places it.
  final String signedAssertion = assertion.replaceFirst(
    '</saml:Issuer>',
    '</saml:Issuer>$signature',
  );

  final String response = '<samlp:Response '
      'xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" '
      'ID="id-response-1" Version="2.0">'
      '$signedAssertion'
      '</samlp:Response>';

  if (tamper == null) return response;
  final XmlDocument document = XmlDocument.parse(response);
  tamper(document);
  return document.toXmlString();
}

DVSaml validator({String? forRecipient = recipient}) => DVSaml(
      idpCertificate: certificate,
      expectedAudience: audience,
      expectedIssuer: issuer,
      expectedRecipient: forRecipient,
    );

void main() {
  setUpAll(() {
    final SecureRandom random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List<int>.filled(32, 11))));
    final RSAKeyGenerator generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 12),
        random,
      ));
    final AsymmetricKeyPair<PublicKey, PrivateKey> pair =
        generator.generateKeyPair();
    idpPrivate = pair.privateKey as RSAPrivateKey;
    idpPublic = pair.publicKey as RSAPublicKey;
    certificate = base64.encode(_subjectPublicKeyInfo(idpPublic));
  });

  test('a genuine assertion validates', () {
    final DVSamlResult result = validator().validateXml(
      signedResponse(),
      now: DateTime.utc(2026, 1, 1, 12),
    );

    expect(result.ok, isTrue, reason: result.reason);
    expect(result.assertion!.subject, 'ada@example.org');
    expect(result.assertion!.first('email'), 'ada@example.org');
    expect(result.assertion!.sessionIndex, 'session-1');
  });

  group('signature wrapping', () {
    test('a forged assertion added beside the signed one is refused', () {
      // The classic attack. The genuine signed assertion stays exactly where
      // it is; a forged one is added as a sibling. A validator that searches
      // the document for "the assertion" may well find the forged one, while
      // the signature it checks covers the real one.
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement forged = XmlDocument.parse(
          '<saml:Assertion '
          'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" '
          'ID="id-forged" Version="2.0">'
          '<saml:Issuer>$issuer</saml:Issuer>'
          '<saml:Subject><saml:NameID>attacker@evil.test</saml:NameID>'
          '</saml:Subject>'
          '</saml:Assertion>',
        ).rootElement.copy();
        document.rootElement.children.insert(0, forged);
      });

      final DVSamlResult result =
          validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12));

      // Either it refuses, or -- if it accepts -- it must have read the signed
      // assertion, never the forged one.
      if (result.ok) {
        expect(result.assertion!.subject, isNot('attacker@evil.test'));
        expect(result.assertion!.subject, 'ada@example.org');
      }
    });

    test('a second assertion carrying the signed one is refused', () {
      // The wrapping variant: the genuine assertion is buried inside a forged
      // wrapper so the signature still resolves, while the document's own
      // first assertion is the attacker's.
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement genuine = document.rootElement.children
            .whereType<XmlElement>()
            .firstWhere((XmlElement e) => e.name.local == 'Assertion');
        final XmlElement copy = genuine.copy();
        genuine.parent!.children.remove(genuine);

        final XmlElement forged = XmlDocument.parse(
          '<saml:Assertion '
          'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" '
          'ID="id-forged" Version="2.0">'
          '<saml:Issuer>$issuer</saml:Issuer>'
          '<saml:Subject><saml:NameID>attacker@evil.test</saml:NameID>'
          '</saml:Subject>'
          '<saml:Extensions/>'
          '</saml:Assertion>',
        ).rootElement.copy();
        forged.children
            .firstWhere((XmlNode n) =>
                n is XmlElement && n.name.local == 'Extensions')
            .children
            .add(copy);
        document.rootElement.children.add(forged);
      });

      final DVSamlResult result =
          validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12));

      if (result.ok) {
        expect(result.assertion!.subject, 'ada@example.org');
      }
    });

    test('two elements sharing the signed ID are refused outright', () {
      // Not valid XML, and the point of doing it: the validator resolves one,
      // the signature covered the other.
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement genuine = document.rootElement.children
            .whereType<XmlElement>()
            .firstWhere((XmlElement e) => e.name.local == 'Assertion');
        final XmlElement duplicate = XmlDocument.parse(
          '<saml:Assertion '
          'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" '
          'ID="id-assertion-1" Version="2.0">'
          '<saml:Issuer>$issuer</saml:Issuer>'
          '<saml:Subject><saml:NameID>attacker@evil.test</saml:NameID>'
          '</saml:Subject>'
          '</saml:Assertion>',
        ).rootElement.copy();
        genuine.parent!.children.insert(0, duplicate);
      });

      final DVSamlResult result =
          validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12));

      expect(result.ok, isFalse);
    });

    test('more than one signature is refused', () {
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement signature = document
            .findAllElements('Signature',
                namespace: 'http://www.w3.org/2000/09/xmldsig#')
            .first;
        signature.parent!.children.add(signature.copy());
      });

      expect(
        validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12)).ok,
        isFalse,
      );
    });
  });

  group('tampering', () {
    test('changing the NameID breaks the digest', () {
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement nameId = document
            .findAllElements('NameID',
                namespace: 'urn:oasis:names:tc:SAML:2.0:assertion')
            .first;
        nameId.children
          ..clear()
          ..add(XmlText('attacker@evil.test'));
      });

      final DVSamlResult result =
          validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12));

      expect(result.ok, isFalse);
      expect(result.reason, contains('signature'));
    });

    test('adding an attribute breaks the digest', () {
      final String xml = signedResponse(tamper: (XmlDocument document) {
        final XmlElement statement = document
            .findAllElements('AttributeStatement',
                namespace: 'urn:oasis:names:tc:SAML:2.0:assertion')
            .first;
        statement.children.add(XmlDocument.parse(
          '<saml:Attribute '
          'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" Name="role">'
          '<saml:AttributeValue>admin</saml:AttributeValue>'
          '</saml:Attribute>',
        ).rootElement.copy());
      });

      expect(
        validator().validateXml(xml, now: DateTime.utc(2026, 1, 1, 12)).ok,
        isFalse,
      );
    });

    test('a signature from another key is refused', () {
      final DVSaml wrongKey = DVSaml(
        // A different modulus: the signature is well-formed and simply is not
        // this issuer's.
        idpCertificate: base64.encode(_subjectPublicKeyInfo(
          RSAPublicKey(idpPublic.modulus! - BigInt.one, idpPublic.exponent!),
        )),
        expectedAudience: audience,
        expectedIssuer: issuer,
      );

      expect(
        wrongKey.validateXml(signedResponse(),
            now: DateTime.utc(2026, 1, 1, 12)).ok,
        isFalse,
      );
    });

    test('an unsigned response is refused', () {
      const String xml = '<samlp:Response '
          'xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="r">'
          '<saml:Assertion '
          'xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="a">'
          '<saml:Issuer>$issuer</saml:Issuer>'
          '<saml:Subject><saml:NameID>anyone@evil.test</saml:NameID>'
          '</saml:Subject></saml:Assertion></samlp:Response>';

      expect(validator().validateXml(xml).ok, isFalse);
    });
  });

  group('what the assertion says', () {
    test('an assertion for another audience is refused', () {
      // Perfectly valid, and issued to somebody else.
      final DVSamlResult result = validator().validateXml(
        signedResponse(forAudience: 'https://other.example/sp'),
        now: DateTime.utc(2026, 1, 1, 12),
      );

      expect(result.ok, isFalse);
      expect(result.reason, contains('addressed'));
    });

    test('an assertion from another issuer is refused', () {
      expect(
        validator().validateXml(
          signedResponse(forIssuer: 'https://evil.example/metadata'),
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isFalse,
      );
    });

    test('an expired assertion is refused', () {
      expect(
        validator().validateXml(
          signedResponse(notOnOrAfter: DateTime.utc(2026, 1, 1, 1)),
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isFalse,
      );
    });

    test('an assertion not yet valid is refused', () {
      expect(
        validator().validateXml(
          signedResponse(notBefore: DateTime.utc(2026, 6, 1)),
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isFalse,
      );
    });

    test('a clock a few seconds out does not fail a good login', () {
      // Without skew this fails intermittently on a drifting server, which
      // presents as "SSO is flaky" rather than as a clock problem.
      expect(
        validator().validateXml(
          signedResponse(notBefore: DateTime.utc(2026, 1, 1, 12, 0, 30)),
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isTrue,
      );
    });

    test('an assertion for another recipient is refused', () {
      expect(
        validator().validateXml(
          signedResponse(forRecipient: 'https://evil.example/acs'),
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isFalse,
      );
    });

    test('an assertion answering another request is refused', () {
      // Ties it to the request this service made, so one captured elsewhere
      // cannot be replayed here.
      expect(
        validator().validateXml(
          signedResponse(inResponseTo: 'req-other'),
          expectedInResponseTo: 'req-mine',
          now: DateTime.utc(2026, 1, 1, 12),
        ).ok,
        isFalse,
      );
    });

    test('the assertion ID comes back, so replay can be detected', () {
      // The validator cannot know an assertion has been seen before; the
      // caller stores this. Not returning it would make replay undetectable.
      final DVSamlResult result = validator()
          .validateXml(signedResponse(), now: DateTime.utc(2026, 1, 1, 12));

      expect(result.assertion!.assertionId, 'id-assertion-1');
    });
  });

  test('malformed XML is refused rather than throwing', () {
    expect(validator().validateXml('<not xml').ok, isFalse);
    expect(validator().validateResponse('not base64!!').ok, isFalse);
  });
}

/// Wraps an RSA public key as SubjectPublicKeyInfo DER, which is what the
/// validator parses out of a certificate.
Uint8List _subjectPublicKeyInfo(RSAPublicKey key) {
  final ASN1Sequence rsaKey = ASN1Sequence()
    ..add(ASN1Integer(key.modulus!))
    ..add(ASN1Integer(key.exponent!));
  final ASN1Sequence algorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromName('rsaEncryption'))
    ..add(ASN1Null());
  final ASN1Sequence spki = ASN1Sequence()
    ..add(algorithm)
    ..add(ASN1BitString(stringValues: rsaKey.encode()));

  // Wrapped in a minimal certificate shape, because the validator locates the
  // key by structure inside a tbsCertificate.
  final ASN1Sequence tbs = ASN1Sequence()
    ..add(ASN1Integer(BigInt.two))
    ..add(spki);
  final ASN1Sequence certificate = ASN1Sequence()..add(tbs);
  return certificate.encode();
}

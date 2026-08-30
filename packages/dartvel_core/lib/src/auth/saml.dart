/// SAML 2.0 sign-in: validating an assertion from an identity provider.
///
/// The dangerous failure here is not a rejected login. It is **signature
/// wrapping**: an attacker takes a genuine signed assertion, puts it somewhere
/// the validator does not read from, and adds a forged assertion where it
/// does. The signature still verifies -- over the real assertion -- and the
/// validator reads the forged one. Every field checks out and the wrong person
/// is logged in.
///
/// The defence is structural rather than a check bolted on: this resolves the
/// signature's Reference URI to a specific element, and then reads every claim
/// out of *that element object*. Nothing is looked up by searching the
/// document a second time, because a second search is what an attacker aims
/// at.
library dartvel_core.auth.saml;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
// asn1.dart is not part of pointycastle's export.dart barrel; the
// certificate parser needs it explicitly.
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xml/xml.dart';

import 'xml_c14n.dart';

const String _samlNs = 'urn:oasis:names:tc:SAML:2.0:assertion';
const String _dsNs = 'http://www.w3.org/2000/09/xmldsig#';

/// What a validated assertion says about the user.
class DVSamlAssertion {
  const DVSamlAssertion({
    required this.subject,
    required this.issuer,
    required this.assertionId,
    required this.attributes,
    required this.notOnOrAfter,
    this.sessionIndex,
  });

  /// The NameID.
  final String subject;
  final String issuer;

  /// Unique per assertion. Store it: an assertion replayed inside its validity
  /// window is otherwise a second valid login.
  final String assertionId;

  final Map<String, List<String>> attributes;
  final DateTime? notOnOrAfter;
  final String? sessionIndex;

  String? first(String name) {
    final List<String>? values = attributes[name];
    return values == null || values.isEmpty ? null : values.first;
  }
}

/// The outcome of validating a SAML response.
class DVSamlResult {
  const DVSamlResult._(this.ok, this.reason, this.assertion);

  const DVSamlResult.failed(String reason) : this._(false, reason, null);

  const DVSamlResult.passed(DVSamlAssertion assertion)
      : this._(true, null, assertion);

  final bool ok;
  final String? reason;
  final DVSamlAssertion? assertion;
}

/// Validates SAML responses from an identity provider.
class DVSaml {
  const DVSaml({
    required this.idpCertificate,
    required this.expectedAudience,
    required this.expectedIssuer,
    this.expectedRecipient,
    this.clockSkew = const Duration(minutes: 2),
  });

  /// The IdP's signing certificate, base64 DER as it appears in metadata.
  final String idpCertificate;

  /// This service provider's entity ID. An assertion for a different audience
  /// is a valid assertion issued to somebody else.
  final String expectedAudience;

  final String expectedIssuer;

  /// The ACS URL the assertion must name, where the IdP sends one.
  final String? expectedRecipient;

  /// Tolerance for clocks that disagree. Without it, a correct login fails
  /// intermittently on a server whose clock drifts by seconds.
  final Duration clockSkew;

  /// Validates a base64-encoded SAMLResponse.
  DVSamlResult validateResponse(
    String base64Response, {
    String? expectedInResponseTo,
    DateTime? now,
  }) {
    String xml;
    try {
      xml = utf8.decode(base64.decode(base64Response.replaceAll('\n', '')));
    } on Object {
      return const DVSamlResult.failed('The response was not base64 XML.');
    }
    return validateXml(
      xml,
      expectedInResponseTo: expectedInResponseTo,
      now: now,
    );
  }

  /// Validates the response XML directly.
  DVSamlResult validateXml(
    String xml, {
    String? expectedInResponseTo,
    DateTime? now,
  }) {
    XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException catch (error) {
      return DVSamlResult.failed('The response was not XML: ${error.message}');
    }

    // --- the signature decides which element we may read -------------------
    final List<XmlElement> signatures = document
        .findAllElements('Signature', namespace: _dsNs)
        .toList();
    if (signatures.isEmpty) {
      return const DVSamlResult.failed('The response carried no signature.');
    }
    // More than one signature means more than one candidate for "the signed
    // assertion", which is the shape a wrapping attack takes. Refused rather
    // than resolved by preference.
    if (signatures.length > 1) {
      return DVSamlResult.failed(
        'The response carried ${signatures.length} signatures; exactly one is '
        'expected.',
      );
    }

    final XmlElement signature = signatures.single;
    final _SignedElement? signed = _verifySignature(document, signature);
    if (signed == null) {
      return const DVSamlResult.failed(
        'The signature did not verify against the configured certificate.',
      );
    }

    // The signed element must be an Assertion, or a Response containing
    // exactly one. Anything else and there is no single element whose claims
    // the signature actually covers.
    XmlElement? assertion;
    if (signed.element.name.local == 'Assertion') {
      assertion = signed.element;
    } else if (signed.element.name.local == 'Response') {
      final List<XmlElement> inner = signed.element.children
          .whereType<XmlElement>()
          .where((XmlElement e) =>
              e.name.local == 'Assertion' && e.name.namespaceUri == _samlNs)
          .toList();
      if (inner.length != 1) {
        return DVSamlResult.failed(
          'The signed response contained ${inner.length} assertions; exactly '
          'one is expected.',
        );
      }
      assertion = inner.single;
    } else {
      return DVSamlResult.failed(
        'The signature covered a <${signed.element.name.local}>, which is '
        'neither an Assertion nor a Response.',
      );
    }

    // From here on, every value is read out of `assertion` -- the element the
    // signature covered. Searching the document again is precisely what a
    // wrapping attack is aiming for.
    return _readAssertion(
      assertion,
      expectedInResponseTo: expectedInResponseTo,
      now: now ?? DateTime.now().toUtc(),
    );
  }

  DVSamlResult _readAssertion(
    XmlElement assertion, {
    required DateTime now,
    String? expectedInResponseTo,
  }) {
    final String? assertionId = assertion.getAttribute('ID');
    if (assertionId == null || assertionId.isEmpty) {
      return const DVSamlResult.failed('The assertion had no ID.');
    }

    final String? issuer =
        _childText(assertion, 'Issuer') ?? _childText(assertion, 'issuer');
    if (issuer != expectedIssuer) {
      return DVSamlResult.failed(
        'The assertion was issued by "$issuer", not $expectedIssuer.',
      );
    }

    // --- conditions --------------------------------------------------------
    final XmlElement? conditions = _child(assertion, 'Conditions');
    DateTime? notOnOrAfter;
    if (conditions != null) {
      final DateTime? notBefore =
          DateTime.tryParse(conditions.getAttribute('NotBefore') ?? '');
      notOnOrAfter =
          DateTime.tryParse(conditions.getAttribute('NotOnOrAfter') ?? '');

      if (notBefore != null && now.isBefore(notBefore.subtract(clockSkew))) {
        return const DVSamlResult.failed('The assertion is not yet valid.');
      }
      if (notOnOrAfter != null && !now.isBefore(notOnOrAfter.add(clockSkew))) {
        return const DVSamlResult.failed('The assertion has expired.');
      }

      // An assertion is issued *to* somebody. One for a different audience is
      // perfectly valid and simply not addressed to this service.
      final Iterable<XmlElement> restrictions =
          conditions.findElements('AudienceRestriction', namespace: _samlNs);
      if (restrictions.isNotEmpty) {
        final Set<String> audiences = <String>{
          for (final XmlElement restriction in restrictions)
            for (final XmlElement audience
                in restriction.findElements('Audience', namespace: _samlNs))
              audience.innerText.trim(),
        };
        if (!audiences.contains(expectedAudience)) {
          return DVSamlResult.failed(
            'The assertion is addressed to $audiences, not $expectedAudience.',
          );
        }
      }
    }

    // --- subject -----------------------------------------------------------
    final XmlElement? subject = _child(assertion, 'Subject');
    if (subject == null) {
      return const DVSamlResult.failed('The assertion had no Subject.');
    }
    final String? nameId = _childText(subject, 'NameID');
    if (nameId == null || nameId.isEmpty) {
      return const DVSamlResult.failed('The assertion had no NameID.');
    }

    for (final XmlElement confirmation
        in subject.findElements('SubjectConfirmation', namespace: _samlNs)) {
      final XmlElement? data = _child(confirmation, 'SubjectConfirmationData');
      if (data == null) continue;

      final DateTime? confirmationExpiry =
          DateTime.tryParse(data.getAttribute('NotOnOrAfter') ?? '');
      if (confirmationExpiry != null &&
          !now.isBefore(confirmationExpiry.add(clockSkew))) {
        return const DVSamlResult.failed(
          'The subject confirmation has expired.',
        );
      }

      final String? recipient = data.getAttribute('Recipient');
      if (expectedRecipient != null &&
          recipient != null &&
          recipient != expectedRecipient) {
        return DVSamlResult.failed(
          'The assertion names recipient "$recipient", not $expectedRecipient.',
        );
      }

      // Ties the assertion to the request this service actually made, which
      // is what stops one captured at another service being replayed here.
      final String? inResponseTo = data.getAttribute('InResponseTo');
      if (expectedInResponseTo != null && inResponseTo != expectedInResponseTo) {
        return DVSamlResult.failed(
          'The assertion answers request "$inResponseTo", not '
          '$expectedInResponseTo.',
        );
      }
    }

    // --- attributes and session -------------------------------------------
    final Map<String, List<String>> attributes = <String, List<String>>{};
    for (final XmlElement statement
        in assertion.findElements('AttributeStatement', namespace: _samlNs)) {
      for (final XmlElement attribute
          in statement.findElements('Attribute', namespace: _samlNs)) {
        final String? name = attribute.getAttribute('Name');
        if (name == null) continue;
        attributes[name] = <String>[
          for (final XmlElement value
              in attribute.findElements('AttributeValue', namespace: _samlNs))
            value.innerText.trim(),
        ];
      }
    }

    String? sessionIndex;
    for (final XmlElement statement
        in assertion.findElements('AuthnStatement', namespace: _samlNs)) {
      sessionIndex = statement.getAttribute('SessionIndex');
    }

    return DVSamlResult.passed(DVSamlAssertion(
      subject: nameId,
      issuer: issuer!,
      assertionId: assertionId,
      attributes: Map<String, List<String>>.unmodifiable(attributes),
      notOnOrAfter: notOnOrAfter,
      sessionIndex: sessionIndex,
    ));
  }

  /// Verifies the signature and returns the element it actually covers.
  _SignedElement? _verifySignature(
    XmlDocument document,
    XmlElement signature,
  ) {
    try {
      final XmlElement? signedInfo = _child(signature, 'SignedInfo', _dsNs);
      final XmlElement? reference =
          signedInfo == null ? null : _child(signedInfo, 'Reference', _dsNs);
      if (signedInfo == null || reference == null) return null;

      // The Reference names the element this signature is over. Everything
      // downstream reads from that element and no other.
      final String uri = reference.getAttribute('URI') ?? '';
      if (!uri.startsWith('#') || uri.length < 2) return null;
      final String id = uri.substring(1);

      final List<XmlElement> targets = document
          .findAllElements('*')
          .where((XmlElement e) => e.getAttribute('ID') == id)
          .toList();
      // Two elements sharing an ID is not valid XML and is the other shape a
      // wrapping attack takes: the validator resolves one, the signature
      // covered the other.
      if (targets.length != 1) return null;
      final XmlElement target = targets.single;

      // The digest is taken over the target with its own signature removed,
      // because the signature cannot cover itself. The document is copied
      // first: mutating the caller's tree to compute a hash would leave the
      // assertion altered for everything that reads it afterwards.
      final XmlElement isolated = target.copy();
      for (final XmlElement nested
          in isolated.findAllElements('Signature', namespace: _dsNs).toList()) {
        nested.parent?.children.remove(nested);
      }

      final List<int> digest =
          sha256.convert(dvCanonicalizeExclusive(isolated)).bytes;
      final String expectedDigest =
          _childText(reference, 'DigestValue', _dsNs)?.trim() ?? '';
      if (base64.encode(digest) != expectedDigest) return null;

      // Then the signature over SignedInfo itself. Checking the digest alone
      // would let anyone rewrite SignedInfo to point at their own content.
      final List<int> canonicalSignedInfo =
          dvCanonicalizeExclusive(signedInfo.copy());
      final String signatureValue =
          (_childText(signature, 'SignatureValue', _dsNs) ?? '')
              .replaceAll(RegExp(r'\s'), '');
      if (signatureValue.isEmpty) return null;

      final bool valid = _verifyRsaSha256(
        certificate: idpCertificate,
        payload: Uint8List.fromList(canonicalSignedInfo),
        signature: base64.decode(signatureValue),
      );
      if (!valid) return null;

      return _SignedElement(target);
    } on Object {
      // Malformed input is a refusal. This runs on whatever an identity
      // provider -- or someone pretending to be one -- posted.
      return null;
    }
  }

  static bool _verifyRsaSha256({
    required String certificate,
    required Uint8List payload,
    required Uint8List signature,
  }) {
    final RSAPublicKey key = dvPublicKeyFromCertificate(certificate);
    final RSASigner signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(key));
    return signer.verifySignature(payload, RSASignature(signature));
  }
}

/// The element a signature was found to cover.
class _SignedElement {
  const _SignedElement(this.element);
  final XmlElement element;
}

/// Extracts the RSA public key from a base64 DER X.509 certificate.
RSAPublicKey dvPublicKeyFromCertificate(String base64Der) {
  final Uint8List der =
      base64.decode(base64Der.replaceAll(RegExp(r'\s|-----[^-]+-----'), ''));
  final ASN1Parser parser = ASN1Parser(der);
  final ASN1Sequence certificate = parser.nextObject() as ASN1Sequence;
  final ASN1Sequence tbs = certificate.elements!.first as ASN1Sequence;

  // SubjectPublicKeyInfo is the first element that is itself a sequence
  // containing an algorithm identifier and a bit string. Located by shape
  // rather than by index, because the optional version field shifts every
  // index after it.
  for (final ASN1Object element in tbs.elements!) {
    if (element is! ASN1Sequence) continue;
    final List<ASN1Object>? parts = element.elements;
    if (parts == null || parts.length != 2) continue;
    if (parts[0] is! ASN1Sequence || parts[1] is! ASN1BitString) continue;

    final ASN1BitString bits = parts[1] as ASN1BitString;
    final Uint8List keyBytes = Uint8List.fromList(bits.stringValues!);
    final ASN1Sequence key =
        ASN1Parser(keyBytes).nextObject() as ASN1Sequence;
    return RSAPublicKey(
      (key.elements![0] as ASN1Integer).integer!,
      (key.elements![1] as ASN1Integer).integer!,
    );
  }
  throw const FormatException(
    'No SubjectPublicKeyInfo found in the certificate.',
  );
}

XmlElement? _child(XmlElement parent, String name, [String namespace = _samlNs]) {
  for (final XmlElement child in parent.children.whereType<XmlElement>()) {
    if (child.name.local == name) return child;
  }
  return null;
}

String? _childText(XmlElement parent, String name,
        [String namespace = _samlNs]) =>
    _child(parent, name, namespace)?.innerText;

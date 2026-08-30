/// Exclusive XML canonicalization (C14N 1.0), as XML signatures require.
///
/// A signature is over bytes, and XML has many byte representations of the
/// same document: attribute order, namespace prefixes, quoting and whitespace
/// all vary without changing meaning. Canonicalization picks one. Get it
/// wrong and a valid assertion fails to verify -- or, far worse, the bytes you
/// hash stop being the bytes you read, and a forged element verifies against a
/// signature made over something else.
///
/// Exclusive (rather than inclusive) canonicalization is what SAML uses: it
/// renders only the namespace declarations an element actually uses, so an
/// assertion keeps verifying when it is lifted out of one envelope and placed
/// in another -- which is exactly what a SAML response does to it.
library dartvel_core.auth.xml_c14n;

import 'dart:convert';

import 'package:xml/xml.dart';

/// Canonicalizes [element] and returns the bytes a signature covers.
List<int> dvCanonicalizeExclusive(
  XmlElement element, {
  Set<String> inclusivePrefixes = const <String>{},
}) {
  final StringBuffer out = StringBuffer();
  _writeElement(element, out, <String, String>{}, inclusivePrefixes);
  return utf8.encode(out.toString());
}

void _writeElement(
  XmlElement element,
  StringBuffer out,
  Map<String, String> renderedAncestors,
  Set<String> inclusivePrefixes,
) {
  final String prefix = element.name.prefix ?? '';
  final String qualified = element.name.qualified;

  // Exclusive canonicalization renders a namespace declaration only where the
  // element or one of its attributes visibly uses that prefix. Rendering them
  // all would make an assertion's canonical form depend on declarations its
  // envelope happened to carry, so lifting it into a different envelope would
  // break the signature.
  final Set<String> used = <String>{prefix, ...inclusivePrefixes};
  for (final XmlAttribute attribute in element.attributes) {
    if (attribute.name.prefix == 'xmlns' || attribute.name.qualified == 'xmlns') {
      continue;
    }
    if (attribute.name.prefix != null) used.add(attribute.name.prefix!);
  }

  final Map<String, String> rendered = Map<String, String>.of(renderedAncestors);
  final List<MapEntry<String, String>> declarations = <MapEntry<String, String>>[];

  for (final String candidate in used) {
    final String? uri = _lookupNamespace(element, candidate);
    if (uri == null) continue;
    // Re-declared only when it differs from what an ancestor already rendered.
    if (rendered[candidate] == uri) continue;
    rendered[candidate] = uri;
    declarations.add(MapEntry<String, String>(candidate, uri));
  }

  // Namespace declarations sort by prefix, with the default namespace first.
  declarations.sort((MapEntry<String, String> a, MapEntry<String, String> b) {
    if (a.key.isEmpty) return -1;
    if (b.key.isEmpty) return 1;
    return a.key.compareTo(b.key);
  });

  // Attributes sort by namespace URI then local name -- not by the prefix,
  // which is arbitrary and may differ between two equivalent documents.
  final List<XmlAttribute> attributes = element.attributes
      .where((XmlAttribute a) =>
          a.name.prefix != 'xmlns' && a.name.qualified != 'xmlns')
      .toList()
    ..sort((XmlAttribute a, XmlAttribute b) {
      final String aUri = a.name.prefix == null
          ? ''
          : (_lookupNamespace(element, a.name.prefix!) ?? '');
      final String bUri = b.name.prefix == null
          ? ''
          : (_lookupNamespace(element, b.name.prefix!) ?? '');
      final int byUri = aUri.compareTo(bUri);
      return byUri != 0 ? byUri : a.name.local.compareTo(b.name.local);
    });

  out.write('<$qualified');
  for (final MapEntry<String, String> declaration in declarations) {
    out.write(declaration.key.isEmpty
        ? ' xmlns="${_escapeAttribute(declaration.value)}"'
        : ' xmlns:${declaration.key}="${_escapeAttribute(declaration.value)}"');
  }
  for (final XmlAttribute attribute in attributes) {
    out.write(
      ' ${attribute.name.qualified}="${_escapeAttribute(attribute.value)}"',
    );
  }
  out.write('>');

  for (final XmlNode child in element.children) {
    if (child is XmlElement) {
      _writeElement(child, out, rendered, inclusivePrefixes);
    } else if (child is XmlText) {
      out.write(_escapeText(child.value));
    } else if (child is XmlCDATA) {
      // CDATA is text once canonicalized; leaving it as CDATA would hash
      // differently from the same content written plainly.
      out.write(_escapeText(child.value));
    }
    // Comments and processing instructions are dropped: this is the
    // #WithComments-free form, which is what SAML signatures use.
  }

  // Always a closing tag. `<a/>` and `<a></a>` are the same element and must
  // hash the same.
  out.write('</$qualified>');
}

/// Resolves [prefix] against [element] and its ancestors.
String? _lookupNamespace(XmlElement element, String prefix) {
  XmlElement? current = element;
  while (current != null) {
    for (final XmlAttribute attribute in current.attributes) {
      if (prefix.isEmpty && attribute.name.qualified == 'xmlns') {
        return attribute.value;
      }
      if (prefix.isNotEmpty &&
          attribute.name.prefix == 'xmlns' &&
          attribute.name.local == prefix) {
        return attribute.value;
      }
    }
    final XmlNode? parent = current.parent;
    current = parent is XmlElement ? parent : null;
  }
  return null;
}

/// Text escaping. `>` is escaped too, which plain XML does not require but
/// canonical XML does -- a document that escapes it and one that does not
/// would otherwise hash differently.
String _escapeText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r', '&#xD;');

/// Attribute escaping. Tab, newline and carriage return become character
/// references because an XML parser would otherwise normalise them to spaces,
/// and the signature would cover something the reader never sees.
String _escapeAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\t', '&#x9;')
    .replaceAll('\n', '&#xA;')
    .replaceAll('\r', '&#xD;');

import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('structured data', () {
    test('derives a schema.org WebPage from what the page declares', () {
      const props = SeoProps(
        title: 'Pricing',
        description: 'Our plans',
        canonicalUrl: 'https://example.com/pricing',
        siteName: 'Example',
      );

      final doc =
          jsonDecode(props.structuredDataJson()!) as Map<String, Object?>;
      expect(doc['@context'], 'https://schema.org');
      expect(doc['@type'], 'WebPage');
      expect(doc['name'], 'Pricing');
      expect(doc['url'], 'https://example.com/pricing');
      expect((doc['isPartOf']! as Map)['name'], 'Example');
    });

    test('explicit structured data wins and gets @context filled in', () {
      const props = SeoProps(
        title: 'Ignored for JSON-LD',
        structuredData: <String, Object?>{
          '@type': 'Product',
          'name': 'Widget',
          'offers': <String, Object?>{'@type': 'Offer', 'price': '9.99'},
        },
      );

      final doc =
          jsonDecode(props.structuredDataJson()!) as Map<String, Object?>;
      expect(doc['@type'], 'Product');
      expect(doc['@context'], 'https://schema.org');
      expect((doc['offers']! as Map)['price'], '9.99');
    });

    test('a page with nothing to say emits nothing', () {
      expect(const SeoProps().structuredDataJson(), isNull);
      // Rather than an empty WebPage that tells crawlers nothing.
    });

    test('merge carries structured data like every other property', () {
      const base = SeoProps(structuredData: <String, Object?>{'@type': 'A'});
      const page = SeoProps(structuredData: <String, Object?>{'@type': 'B'});

      expect(
        (jsonDecode(base.merge(page).structuredDataJson()!) as Map)['@type'],
        'B',
      );
      expect(
        (jsonDecode(base.merge(const SeoProps()).structuredDataJson()!)
            as Map)['@type'],
        'A',
      );
    });
  });

  group('OTA version gates', () {
    const updates = DVUpdates();

    tearDown(() {
      updates.unlockVersion();
      updates.skipImmediateNextVersion('');
    });

    DVUpdateInfo info(String version, {bool required = false}) => DVUpdateInfo(
          available: true,
          version: version,
          required: required,
        );

    test('a locked version declines every other update', () {
      updates.lockVersion('2.1.0');

      expect(updates.shouldApply(info('2.2.0')), isFalse);
      expect(updates.shouldApply(info('2.1.0')), isTrue);

      updates.unlockVersion();
      expect(updates.shouldApply(info('2.2.0')), isTrue);
    });

    test('skipping declines exactly that version and no other', () {
      updates.skipImmediateNextVersion('2.2.0');

      expect(updates.shouldApply(info('2.2.0')), isFalse);
      expect(updates.shouldApply(info('2.3.0')), isTrue);
    });

    test('a required update overrides a skip — a skip is a preference', () {
      updates.skipImmediateNextVersion('2.2.0');

      expect(updates.shouldApply(info('2.2.0', required: true)), isTrue);
    });

    test('an unavailable update is never applied', () {
      expect(
        updates.shouldApply(const DVUpdateInfo(available: false)),
        isFalse,
      );
    });
  });
}

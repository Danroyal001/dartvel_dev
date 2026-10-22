import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_documents/dartvel_documents.dart';
import 'package:dartvel_documents/src/pdfium_release.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtures = 'test/fixtures';

/// How many sampled pixels of [image] are dark: text on a white page.
Future<int> darkPixels(ui.Image image) async {
  final ByteData? rgba = await image.toByteData();
  int dark = 0;
  for (int i = 0; i < rgba!.lengthInBytes; i += 4 * 7) {
    if (rgba.getUint8(i) < 100 && rgba.getUint8(i + 1) < 100 && rgba.getUint8(i + 2) < 100) dark++;
  }
  return dark;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a PDF, through the bundled PDFium', () {
    test('opens, counts its pages and knows their size', () async {
      final DVDocument document = await DVDocuments.open('$fixtures/two_pages.pdf');
      addTearDown(document.close);
      expect(document.pageCount, 2);
      final ui.Size a4 = await document.pageSize(0);
      expect(a4.width, closeTo(595, 2), reason: 'A4 is 595 x 842 points');
      expect(a4.height, closeTo(842, 2));
    });

    testWidgets('draws a page at the width asked, its words dark on white', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final DVDocument document = await DVDocuments.open('$fixtures/two_pages.pdf');
        final ui.Image page = await document.renderPage(0, width: 600);
        expect(page.width, 600);
        expect(page.height, closeTo(849, 2));
        expect(await darkPixels(page), greaterThan(20), reason: 'the heading and its line are drawn');
        final ui.Image second = await document.renderPage(1, width: 600);
        expect(second.width, 600);
        expect(await darkPixels(second), greaterThan(5));
        await document.close();
      });
    });

    test('a page that is not there is a range error', () async {
      final DVDocument document = await DVDocuments.open('$fixtures/two_pages.pdf');
      addTearDown(document.close);
      expect(() => document.pageSize(2), throwsRangeError);
    });

    test('a damaged file says so', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dv_docs_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File bad = File('${dir.path}/bad.pdf')..writeAsStringSync('%PDF-1.7 this is not a pdf');
      await expectLater(
        DVDocuments.open(bad.path),
        throwsA(isA<DVDocumentUnavailable>().having((DVDocumentUnavailable e) => e.reason, 'reason', contains('damaged'))),
      );
    });

    test('a file that is not there says so', () async {
      await expectLater(
        DVDocuments.open('$fixtures/nothing.pdf'),
        throwsA(isA<DVDocumentUnavailable>().having((DVDocumentUnavailable e) => e.reason, 'reason', 'There is no file there.')),
      );
    });
  });

  group('a presentation or office document', () {
    final bool hasLibreOffice = DVDocuments.dvFindLibreOffice() != null;

    test('is converted with LibreOffice and opened like a PDF', () async {
      final DVDocument document = await DVDocuments.open('$fixtures/two_pages.odt');
      addTearDown(document.close);
      expect(document.path, '$fixtures/two_pages.odt', reason: 'the document is the file opened, not its copy');
      expect(document.pageCount, 2);
    }, skip: hasLibreOffice ? false : 'LibreOffice is not installed here', timeout: const Timeout(Duration(minutes: 4)));
  });

  group('the pinned PDFium', () {
    test('has a build for every desktop and mobile target Dartvel builds', () {
      for (final (String os, String arch) in <(String, String)>[
        ('linux', 'x64'), ('linux', 'arm64'), ('windows', 'x64'), ('windows', 'arm64'), //
        ('macos', 'x64'), ('macos', 'arm64'), ('android', 'arm64'), ('android', 'x64'), ('ios', 'arm64'),
      ]) {
        expect(dvPdfiumArchiveFor(os, arch), isNotNull, reason: '$os-$arch');
      }
      expect(dvPdfiumArchiveFor('ios', 'arm64', simulator: true)!.name, 'pdfium-ios-simulator-arm64.tgz');
      expect(dvPdfiumArchiveFor('fuchsia', 'x64'), isNull, reason: 'no build: documents answer with the reason');
    });

    test('every pin is a sha256', () {
      for (final DVPdfiumArchive archive in dvPdfiumArchives.values) {
        expect(archive.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: archive.name);
      }
    });
  });
}

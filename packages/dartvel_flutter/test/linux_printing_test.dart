// Printing on Linux, against a real GTK under Xvfb.
//
// A page is a picture; printing draws the pictures onto pages. GTK's print
// operation has an export action that runs without a dialog and without a
// printer, writing a PDF -- so the same code that drives the print dialog is
// exercised here to the byte: the PDF exists, is a PDF, and has as many
// pages as were sent. What is not tested is the dialog itself; there is no
// one at the desk to press Print.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A coloured page with a line of text, as PNG bytes.
Future<Uint8List> page(Color colour, String text) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 800), Paint()..color = colour);
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
    ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)))
    ..addText(text);
  final ui.Paragraph paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 560));
  canvas.drawParagraph(paragraph, const Offset(20, 20));
  final ui.Image image = await recorder.endRecording().toImage(600, 800);
  final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with no binding, printing fails naming what is missing', () async {
    DVNativeBridge.unregister('printing.toFile');
    await expectLater(
      const DVPrinting().toFile('/tmp/never.pdf', pages: <Uint8List>[Uint8List(0)]),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('printing.toFile'))),
    );
  });

  test('nothing to print is refused before any binding is asked', () async {
    await expectLater(
      const DVPrinting().toFile('/tmp/never.pdf', pages: const <Uint8List>[]),
      throwsArgumentError,
    );
  });

  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux printing (skipped: no X display)', () {}, skip: 'Run under an X server (xvfb-run works).');
    return;
  }

  group('under GTK', () {
    late Directory dir;
    setUpAll(() {
      expect(DVLinuxBindings.register(), isTrue);
      dir = Directory.systemTemp.createTempSync('dv_print_');
    });
    tearDownAll(() {
      DVLinuxBindings.unregister();
      dir.deleteSync(recursive: true);
    });

    test('printing is among what the Linux bindings implement', () {
      expect(DVLinuxBindings.implemented, containsAll(<String>['printing.toFile', 'printing.print']));
    });

    test('two pictures become a two-page PDF', () async {
      final String path = '${dir.path}/out.pdf';
      final DVPrintResult result = await DV.Platform.Printing.toFile(
        path,
        pages: <Uint8List>[await page(const Color(0xFFFFEEDD), 'Page one'), await page(const Color(0xFFDDEEFF), 'Page two')],
      );

      expect(result.pages, 2);
      expect(result.path, path);
      final File pdf = File(path);
      expect(pdf.existsSync(), isTrue);
      final String head = String.fromCharCodes(pdf.readAsBytesSync().take(8));
      expect(head, startsWith('%PDF-1.'));
      // cairo 1.18 writes the page tree inside a compressed object stream,
      // so the count is read back with poppler rather than grepped for.
      final ProcessResult info = await Process.run('pdfinfo', <String>[path]);
      expect(info.exitCode, 0, reason: 'pdfinfo (poppler-utils) is needed to read the page count: ${info.stderr}');
      expect('${info.stdout}', matches(RegExp(r'Pages:\s+2\b')));
    });

    test('a page that is not a picture is refused, and no file is written', () async {
      final String path = '${dir.path}/bad.pdf';
      await expectLater(
        DV.Platform.Printing.toFile(path, pages: <Uint8List>[Uint8List.fromList(<int>[1, 2, 3])]),
        throwsA(isA<StateError>()),
      );
      expect(File(path).existsSync(), isFalse);
    });
  });
}

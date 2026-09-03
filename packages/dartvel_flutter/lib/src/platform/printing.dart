// Printing: pictures onto pages.
//
// A page is a picture -- PNG bytes, typically a widget captured with a
// RepaintBoundary -- and printing draws each onto a page, scaled to fit.
// `toFile` writes a PDF without a dialog or a printer; `print` shows the
// platform's dialog. Both go through the `printing.*` bindings and fail
// naming the binding where there is none, as every desktop API does.
import 'dart:typed_data';

import '../../dartvel_flutter.dart' show DVNativeBridge;

class DVPrintResult {
  /// Where the PDF was written, for [DVPrinting.toFile]; null for a dialog.
  final String? path;
  final int pages;

  const DVPrintResult({required this.pages, this.path});
}

class DVPrinting {
  const DVPrinting();

  static void _check(List<Uint8List> pages) {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'Nothing to print.');
    }
  }

  /// Writes [pages] to a PDF at [path], one picture per page.
  Future<DVPrintResult> toFile(String path, {required List<Uint8List> pages}) async {
    _check(pages);
    final Object? result = await DVNativeBridge.require<Object?>(
      'printing.toFile',
      <String, Object?>{'path': path, 'pages': pages},
    );
    return DVPrintResult(path: path, pages: _pages(result, pages.length));
  }

  /// Shows the platform's print dialog for [pages]. Resolves when the dialog
  /// closes; [DVPrintResult.pages] is 0 if it was cancelled.
  Future<DVPrintResult> print({required List<Uint8List> pages, String? title}) async {
    _check(pages);
    final Object? result = await DVNativeBridge.require<Object?>(
      'printing.print',
      <String, Object?>{'pages': pages, if (title != null) 'title': title},
    );
    return DVPrintResult(pages: _pages(result, pages.length));
  }

  static int _pages(Object? result, int sent) {
    if (result is Map && result['pages'] is int) return result['pages']! as int;
    return sent;
  }
}

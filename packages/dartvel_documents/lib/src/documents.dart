import 'dart:ui' as ui;

import 'documents_backend_web.dart' if (dart.library.ffi) 'documents_backend_ffi.dart' as backend;

/// A document cannot be opened here, and why: a file that is not there, a
/// damaged PDF, a presentation with no converter on this machine, a target
/// PDFium has no build for, the web.
final class DVDocumentUnavailable implements Exception {
  const DVDocumentUnavailable(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'DVDocumentUnavailable: $path: $reason';
}

/// Presentations and documents opened by converting them to PDF first.
const Set<String> dvConvertedExtensions = <String>{
  'pptx', 'ppt', 'pps', 'ppsx', 'odp', 'key', 'docx', 'doc', 'odt', 'rtf',
};

/// Opening and rendering documents: PDF through PDFium, bundled with the
/// app; presentations through LibreOffice where it is installed. Compiles on
/// every target; where it cannot open a document it says why.
///
/// ```dart
/// final DVDocument deck = await DVDocuments.open('/church/sunday.pptx');
/// final ui.Image slide = await deck.renderPage(0, width: 1920);
/// ```
final class DVDocuments {
  const DVDocuments._();

  /// Opens [path]: a PDF directly, a presentation or office document by
  /// converting it to PDF with LibreOffice. Throws [DVDocumentUnavailable]
  /// with the reason when it cannot.
  static Future<DVDocument> open(String path) => backend.dvOpenDocument(path);

  /// LibreOffice's command, from PATH or where its installers put it; null
  /// where there is none (and always on the web).
  static String? dvFindLibreOffice() => backend.dvFindLibreOffice();
}

/// An open document. Close it when done; its pages render on demand.
abstract interface class DVDocument {
  /// The file opened (the presentation, not its converted copy).
  String get path;

  int get pageCount;

  /// Page [index]'s size in points (1/72 inch).
  Future<ui.Size> pageSize(int index);

  /// Page [index] drawn [width] pixels wide (its height follows the page),
  /// on white, annotations included.
  Future<ui.Image> renderPage(int index, {required int width});

  /// Releases the document.
  Future<void> close();
}

/// Documents in a Dartvel app: PDFs rendered by PDFium, which the build
/// bundles for each target, and presentations converted with LibreOffice
/// where it is installed. See the README for what each target can open.
library;

export 'src/document_page.dart';
export 'src/documents.dart' show DVDocument, DVDocumentUnavailable, DVDocuments, dvConvertedExtensions;
export 'src/pdfium_release.dart' show dvPdfiumRelease;

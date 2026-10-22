import 'documents.dart';

/// The web has no PDFium yet: opening answers with the reason.
Future<DVDocument> dvOpenDocument(String path) async => throw DVDocumentUnavailable(
    path, 'Documents open in the desktop and mobile apps; this browser build has no PDF engine yet.');

/// The web cannot run LibreOffice.
String? dvFindLibreOffice() => null;

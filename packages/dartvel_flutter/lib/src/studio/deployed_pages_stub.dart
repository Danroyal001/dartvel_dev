/// A web app reads deployed pages from the server that served it, through
/// Studio's browser transport, never from here.
library;

import 'page_document.dart' show DVPageDocument;

Future<List<DVPageDocument>> dvDeployedPagesFromBackend() =>
    throw UnsupportedError('A web app reads deployed pages from its server.');

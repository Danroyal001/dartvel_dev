/// Reading the documentation payload off the web.
///
/// There is no document to fetch from: the payload is a file the build wrote
/// beside a browser bundle, and a native process has no way to ask a web server
/// for it without becoming one. An application that wants the documentation on
/// a device passes its own `DVDocsSource` -- the same one a test does.
library dartvel_flutter.docs.source.stub;

Future<String> dvDocsReadPayload(String url) => throw UnsupportedError(
  'The documentation payload is a file served beside the web bundle. Pass '
  'DVDocsApp a document, or a DVDocsSource of your own, to read it here.',
);

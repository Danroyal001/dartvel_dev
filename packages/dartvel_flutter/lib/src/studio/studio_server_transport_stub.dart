/// Studio's transport off the web: there is no page it was served from, so
/// there is no mount to send relative requests to. A native Studio passes its
/// own [DVStudioTransport].
library;

import 'studio_server.dart' show DVStudioReply;

Future<DVStudioReply> dvStudioSend(
  String method,
  String path, {
  Object? body,
  required String csrf,
}) =>
    throw UnsupportedError(
      'The browser transport runs only in the Studio a web-server binary '
      'serves. Give DVStudioClient a transport of your own elsewhere.',
    );

/// In a browser: same-origin fetch, as the page's own scripts make.
library;

import 'studio_server.dart' show DVStudioReply;
import 'studio_server_transport_web.dart' show dvStudioSend;

Future<DVStudioReply> dvSiteSend(String method, String path, {Object? body}) =>
    dvStudioSend(method, path, body: body, csrf: '');

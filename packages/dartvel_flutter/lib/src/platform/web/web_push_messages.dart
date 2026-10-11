/// What the generated service worker posts to a page, and the queue entry the
/// page turns it into.
///
/// Apart from `web_push_js.dart` because that file imports `dart:js_interop`
/// and cannot load under the Dart VM, and the shape of this message is the
/// contract between two programs written in two languages: the worker (in
/// `pwa_service_worker.dart`, JavaScript) and the page (Dart). It is the
/// part that breaks silently, so it is the part with a test.
library dartvel_flutter.platform.web.push_messages;

/// A queue entry for [message], or null when it is not one of the worker's.
///
/// Two message types exist. `dartvel-push` carries `payload`
/// (`{title, body, data}`, what the server encrypted) and arrives while a
/// window is open. `dartvel-push-open` is a click on a notification and
/// carries `title`, `body`, `data` and `url` at the top level.
Map<String, Object?>? dvWebPushEntryFrom(
  Object? message, {
  required DateTime now,
  required int sequence,
}) {
  if (message is! Map) return null;
  final Object? type = message['type'];
  final bool opened = type == 'dartvel-push-open';
  if (type != 'dartvel-push' && !opened) return null;
  final Object? payload = opened ? message : message['payload'];
  if (payload is! Map) return null;
  final Object? data = payload['data'];
  return <String, Object?>{
    'id': 'web-${now.millisecondsSinceEpoch}-$sequence',
    'title': payload['title'] is String ? payload['title'] : null,
    'body': payload['body'] is String ? payload['body'] : null,
    'data': <String, Object?>{
      if (data is Map)
        for (final MapEntry<Object?, Object?> entry in data.entries)
          '${entry.key}': '${entry.value}',
      if (opened && message['url'] is String) 'url': message['url'],
    },
    'receivedAt': now.millisecondsSinceEpoch,
    'opened': opened,
  };
}

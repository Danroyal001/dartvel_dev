import 'dart:async';
import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final app = DartvelShelf()
    ..http10(true).http11(true).http2(true).http3(true)
    ..use('logRequests()')
    ..use('gzip()')
    ..static('/assets', dir: 'www')
    ..get('/hello', (req) => Response.text('hi!\n'))
    ..sse('/events', (sse) async {
      for (var i = 0; i < 3; i++) {
        await sse.event(event: 'tick', data: {'i': i});
        await Future.delayed(Duration(milliseconds: 200));
      }
      await sse.close();
    })
    ..websocket('/ws', (ws) async {
      await for (final msg in ws.stream) {
        if (msg is String) ws.sendText('echo: $msg');
      }
      await ws.close();
    });
  await app.listen(port: 8080, h3Port: 8443);
  print('dartvel_shelf full server started.');
}

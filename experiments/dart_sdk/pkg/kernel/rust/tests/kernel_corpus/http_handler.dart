import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'path': request.uri.path, 'method': request.method}))
      ..close();
  });
  final client = HttpClient();
  final request = await client.get('127.0.0.1', server.port, '/hello');
  final response = await request.close();
  print(await response.transform(utf8.decoder).join());
  client.close();
  await server.close();
}

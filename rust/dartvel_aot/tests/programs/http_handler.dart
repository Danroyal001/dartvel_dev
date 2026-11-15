import 'dart:convert';

class Request {
  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  Request(this.method, this.path, this.headers, this.body);
}

class Response {
  final int status;
  final String contentType;
  final String body;

  Response(this.status, this.contentType, this.body);

  String reason() {
    if (status == 200) return 'OK';
    if (status == 201) return 'Created';
    if (status == 400) return 'Bad Request';
    if (status == 404) return 'Not Found';
    return 'Method Not Allowed';
  }

  String serialize() {
    final out = StringBuffer();
    out.write('HTTP/1.1 $status ${reason()}\r\n');
    out.write('content-type: $contentType\r\n');
    out.write('content-length: ${body.length}\r\n');
    out.write('\r\n');
    out.write(body);
    return out.toString();
  }
}

Request parseRequest(String raw) {
  final split = raw.indexOf('\r\n\r\n');
  final head = split < 0 ? raw : raw.substring(0, split);
  final body = split < 0 ? '' : raw.substring(split + 4);
  final lines = head.split('\r\n');
  final parts = lines[0].split(' ');
  final headers = <String, String>{};
  for (var i = 1; i < lines.length; i++) {
    final colon = lines[i].indexOf(':');
    if (colon > 0) {
      headers[lines[i].substring(0, colon).trim().toLowerCase()] =
          lines[i].substring(colon + 1).trim();
    }
  }
  return Request(parts[0], parts[1], headers, body);
}

final todos = <Map<String, Object?>>[];

Response handle(Request request) {
  if (request.path == '/health') {
    return Response(200, 'text/plain', 'ok');
  }
  if (request.path == '/todos') {
    if (request.method == 'GET') {
      return Response(200, 'application/json', jsonEncode(todos));
    }
    if (request.method == 'POST') {
      if (request.headers['content-type'] != 'application/json') {
        return Response(400, 'text/plain', 'expected json');
      }
      final input = jsonDecode(request.body) as Map<String, dynamic>;
      final todo = <String, Object?>{
        'id': todos.length + 1,
        'title': input['title'],
        'done': false,
      };
      todos.add(todo);
      return Response(201, 'application/json', jsonEncode(todo));
    }
    return Response(405, 'text/plain', 'method not allowed');
  }
  return Response(404, 'text/plain', 'no route for ${request.path}');
}

void main() {
  final requests = [
    'GET /health HTTP/1.1\r\nHost: example.test\r\n\r\n',
    'POST /todos HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{"title":"buy milk"}',
    'POST /todos HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{"title":"call \\"mum\\""}',
    'POST /todos HTTP/1.1\r\nContent-Type: text/plain\r\n\r\nhello',
    'GET /todos HTTP/1.1\r\n\r\n',
    'DELETE /todos HTTP/1.1\r\n\r\n',
    'GET /missing HTTP/1.1\r\n\r\n',
  ];
  for (final raw in requests) {
    print(handle(parseRequest(raw)).serialize());
    print('---');
  }
}

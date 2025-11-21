import 'dart:async';
import 'body.dart';
import 'headers.dart';

class Request {
  final String method;
  final Uri url;
  final Headers headers;
  final Body body;
  final Map<String, String> params;
  Request({
    required this.method,
    required this.url,
    required this.headers,
    required Stream<List<int>> bodyStream,
    this.params = const {},
  }) : body = Body(bodyStream);
}

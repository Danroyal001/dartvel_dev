/// Reading a request the way the edge defences need it, whichever shape it
/// arrives in: a WinterCG request, a `Uri`, or the map tests and adapters use.
///
/// Not exported: these are shared by the edge libraries, not API.
library dartvel_core.edge.request_parts;

import '../http/wintercg.dart' as dv;

String dvEdgeMethod(Object? request) {
  if (request is dv.Request) return request.method.toUpperCase();
  if (request is Map) {
    final method = request['method'];
    if (method is String && method.trim().isNotEmpty) {
      return method.trim().toUpperCase();
    }
  }
  return 'GET';
}

/// The request path as sent, still percent-encoded where it was.
String dvEdgePath(Object? request) {
  if (request is dv.Request) return request.url.path;
  if (request is Uri) return request.path;
  if (request is Map) {
    final path = request['path'];
    if (path is String && path.trim().isNotEmpty) return path.trim();
    final url = request['url'];
    if (url is Uri) return url.path;
    if (url is String) return Uri.tryParse(url)?.path ?? url;
  }
  return '/';
}

String? dvEdgeHeader(Object? request, String name) {
  final lower = name.toLowerCase();
  if (request is dv.Request) return request.headers.get(lower);
  if (request is Map) {
    final headers = request['headers'];
    if (headers is Map) {
      for (final entry in headers.entries) {
        if ('${entry.key}'.toLowerCase() == lower && entry.value != null) {
          return '${entry.value}';
        }
      }
    }
  }
  return null;
}

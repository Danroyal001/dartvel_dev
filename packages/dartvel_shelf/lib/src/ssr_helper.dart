import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'wintercg.dart';

// Helper to handle SSR fallback
Future<Response> handleSsrFallback(Request req, String spaRoot) async {
  final indexFile = File(p.join(spaRoot, 'index.html'));
  if (!await indexFile.exists()) {
    return Response.text('SPA index.html not found', status: 404);
  }

  var html = await indexFile.readAsString();

  // Check for prerendered metadata
  final route = req.url.path;
  final cleanRoute =
      route == '/' || route.isEmpty ? 'index' : route.substring(1);
  final metaFile = File(p.join(spaRoot, 'prerender', cleanRoute, 'meta.json'));

  if (await metaFile.exists()) {
    try {
      final metaJson = await metaFile.readAsString();
      final meta = jsonDecode(metaJson) as Map<String, dynamic>;

      final title = meta['title'] as String?;
      final content = meta['content'] as String?;

      if (title != null) {
        html = html.replaceFirst(
            RegExp(r'<title>.*?</title>'), '<title>$title</title>');
      }

      if (content != null) {
        // Inject semantic prerendered content before the Flutter bootstrap.
        final injection =
            '<div id="semantic-content" style="position:absolute;left:-9999px;top:auto;width:1px;height:1px;overflow:hidden;">$content</div>';
        html = html.replaceFirst('</body>', '$injection</body>');
      }

      // Inject defer to main.dart.js if not present (optional, usually build handles it)
      // html = html.replaceFirst('src="main.dart.js"', 'src="main.dart.js" defer');
    } catch (_) {
      // Keep serving the original HTML if optional SSR content injection fails.
    }
  }

  final headers = Headers()..set('content-type', 'text/html');
  return Response(200, headers: headers, body: Stream.value(html.codeUnits));
}

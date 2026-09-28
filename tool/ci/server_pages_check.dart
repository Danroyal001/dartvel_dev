// Every page a running web-server binary serves says something to a crawler,
// and Studio refuses a stranger.
//
// dartvel.dev is served by `dartvel build web-server`, which renders each page
// on request rather than from a prerendered file. crawler_text_check.dart
// reads the static bundle; this asks the server, so a binary that answered
// every path with the bare shell -- a title and no text -- fails here even
// when the static build is fine.
//
// For each page in the server's own sitemap.xml: a 200, a <title>, a meta
// description, and at least [min-words] words in the crawler block. Then:
// /__studio/ answers an anonymous request exactly as an unknown path does (a
// 404), and the image endpoint resizes one of the site's images.
//
// Usage: dart tool/ci/server_pages_check.dart <base-url> [min-words]
import 'dart:convert';
import 'dart:io';

final HttpClient _client = HttpClient()..autoUncompress = true;

Future<(int, String, ContentType?)> _get(Uri uri) async {
  final HttpClientRequest request = await _client.getUrl(uri);
  request.followRedirects = false;
  final HttpClientResponse response = await request.close();
  final List<int> bytes = await response
      .fold<List<int>>(<int>[], (List<int> all, List<int> part) => all..addAll(part));
  return (response.statusCode, utf8.decode(bytes, allowMalformed: true), response.headers.contentType);
}

String _crawlerText(String html) {
  final RegExpMatch? found = RegExp(
    r'<div class="dv-fallback"[^>]*>([\s\S]*?)</div>\s*<!-- /dartvel:text -->',
  ).firstMatch(html);
  if (found == null) return '';
  return found
      .group(1)!
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _words(String text) =>
    text.isEmpty ? 0 : text.split(' ').where((String w) => w.isNotEmpty).length;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: server_pages_check.dart <base-url> [min-words]');
    exit(2);
  }
  final Uri base = Uri.parse(args.first);
  final int minimum = args.length == 2 ? int.parse(args[1]) : 25;
  final List<String> problems = <String>[];

  final (int sitemapStatus, String sitemap, _) = await _get(base.resolve('/sitemap.xml'));
  if (sitemapStatus != 200) {
    stderr.writeln('::error::sitemap.xml answered $sitemapStatus');
    exit(1);
  }
  final List<String> paths = <String>[
    for (final RegExpMatch m in RegExp(r'<loc>([^<]+)</loc>').allMatches(sitemap))
      Uri.parse(m.group(1)!.trim()).path,
  ];
  if (paths.isEmpty) {
    stderr.writeln('::error::sitemap.xml lists no pages');
    exit(1);
  }

  for (final String path in paths) {
    final String route = path.isEmpty ? '/' : path;
    final (int status, String html, _) = await _get(base.resolve(route));
    if (status != 200) {
      problems.add('$route answered $status');
      continue;
    }
    if (!RegExp(r'<title>[^<]+</title>').hasMatch(html)) {
      problems.add('$route has no <title>');
    }
    if (!RegExp(r'<meta name="description" content="[^"]+"').hasMatch(html)) {
      problems.add('$route has no meta description');
    }
    final int count = _words(_crawlerText(html));
    if (count < minimum) problems.add('$route says $count words to a crawler');
  }

  // HEAD answers as GET does: a monitor or a crawler that asks HEAD first
  // must not be told the home page is not there.
  final HttpClientRequest head = await _client.openUrl('HEAD', base.resolve('/'));
  final HttpClientResponse headResponse = await head.close();
  await headResponse.drain<void>();
  if (headResponse.statusCode != 200) {
    problems.add('HEAD / answered ${headResponse.statusCode}');
  }

  // A stranger gets what a path nobody serves gets, so the answer does not
  // say whether Studio is there. On this site an unknown path is the app's
  // shell, which draws the not-found page, so the two are compared after
  // taking out the path each was asked for.
  for (final String studioPath in <String>['/__studio', '/__studio/api/grants']) {
    final String unknownPath =
        studioPath.replaceFirst('/__studio', '/zz-no-such-page');
    final (int s, String studio, _) = await _get(base.resolve(studioPath));
    final (int u, String unknown, _) = await _get(base.resolve(unknownPath));
    String strip(String body, String path) => body
        .replaceAll(path, '')
        .replaceAll(path.substring(1), '')
        .replaceAll('/__studio', '')
        .replaceAll('zz-no-such-page', '')
        .replaceAll(RegExp(r'/"'), '"');
    if (s != u || strip(studio, studioPath) != strip(unknown, unknownPath)) {
      problems.add(' answered an anonymous request () '
          'differently from a path nobody serves ()');
    }
  }

  // The image endpoint: one of the site's own images, at a width it serves.
  final (int image, _, ContentType? type) = await _get(base.resolve(
      '/_dartvel/image?src=${Uri.encodeQueryComponent('assets/assets/studio_shots/page-builder.png')}&w=640&q=75'));
  if (image != 200 || type?.primaryType != 'image') {
    problems.add('/_dartvel/image answered $image ($type)');
  }

  _client.close(force: true);
  if (problems.isEmpty) {
    stdout.writeln('${paths.length} pages rendered on the server, each with a '
        'title, a description and at least $minimum words; Studio refuses a '
        'stranger; the image endpoint resizes.');
    return;
  }
  stderr.writeln('::error::${problems.length} problems: ${problems.join('; ')}');
  exit(1);
}

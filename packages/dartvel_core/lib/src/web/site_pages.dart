/// The pages this server serves, as data a backend can read.
///
/// A site search, an llms.txt or a list of related pages all need the same
/// thing: each page's title and text. A web-server build already has it, in
/// the route manifest it renders every page from, and a backend function had
/// no way to reach it. Copying the text somewhere else would be a second
/// source that drifts from the first, so this reads the one the server uses.
library dartvel_core.web.site_pages;

import 'dart:convert';

import 'site_pages_read_stub.dart'
    if (dart.library.io) 'site_pages_read_io.dart';

/// One part of a page: a heading and what it says.
class DVSitePageSection {
  const DVSitePageSection({required this.heading, required this.text});

  /// The page's own heading for the first section, then each subheading.
  final String heading;
  final String text;
}

/// A page a reader can be sent to.
class DVSitePage {
  const DVSitePage({
    required this.path,
    required this.title,
    this.description = '',
    this.sections = const <DVSitePageSection>[],
  });

  final String path;
  final String title;
  final String description;
  final List<DVSitePageSection> sections;
}

class DVSitePages {
  DVSitePages._();

  /// The built site this process serves, set by the generated backend when
  /// it serves one. Null in a process with no site, which has no pages.
  static String? webRoot;

  /// This server's pages, read from the manifest it renders them from.
  static Future<List<DVSitePage>> load() async {
    final String? root = webRoot;
    if (root == null) return const <DVSitePage>[];
    final String? text = await dvReadSiteManifest(root);
    return text == null ? const <DVSitePage>[] : parse(text);
  }

  /// The pages in a route manifest.
  ///
  /// A route is a page when it has a title and no parameters: `/post/:id` is
  /// a shape, an untitled route is an error or offline page, and a route
  /// with a location is another site's. What every page repeats -- the
  /// header, the navigation, the footer -- is chrome rather than content,
  /// and is left out, so a page is found for what it says and not for the
  /// links it shares with every other page.
  static List<DVSitePage> parse(String manifest) {
    final Object? decoded;
    try {
      decoded = jsonDecode(manifest);
    } on FormatException {
      return const <DVSitePage>[];
    }
    final Object? routes = decoded is Map ? decoded['routes'] : null;
    if (routes is! Map) return const <DVSitePage>[];

    final List<({String path, String title, String description, List<String> lines})>
        found = <({String path, String title, String description, List<String> lines})>[];
    for (final MapEntry<Object?, Object?> entry in routes.entries) {
      final Object? path = entry.key;
      final Object? route = entry.value;
      if (path is! String || route is! Map) continue;
      if (path.contains(':') || path.contains('*')) continue;
      if (route['location'] != null) continue;
      final Object? title = route['title'];
      if (title is! String || title.trim().isEmpty) continue;
      final Object? page = route['page'];
      final Object? html = page is Map ? page['html'] : null;
      final Object? description = page is Map ? page['description'] : null;
      found.add((
        path: path,
        title: title.trim(),
        description: description is String ? description.trim() : '',
        lines: html is String
            ? html
                .split('\n')
                .map((String l) => l.trim())
                .where((String l) => l.isNotEmpty)
                .toList()
            : const <String>[],
      ));
    }

    // A line on more than half the pages is the site's, not the page's.
    final Map<String, int> seenOn = <String, int>{};
    for (final ({String path, String title, String description, List<String> lines}) p
        in found) {
      for (final String line in p.lines.toSet()) {
        seenOn[line] = (seenOn[line] ?? 0) + 1;
      }
    }
    final bool shared = found.length >= 2;
    bool chrome(String line) => shared && seenOn[line]! * 2 > found.length;

    return <DVSitePage>[
      for (final ({String path, String title, String description, List<String> lines}) p
          in found)
        DVSitePage(
          path: p.path,
          title: p.title,
          description: p.description,
          sections: _sections(<String>[
            for (final String line in p.lines)
              if (!chrome(line)) line,
          ]),
        ),
    ];
  }

  static final RegExp _heading = RegExp(r'^<h([12])\b[^>]*>(.*?)</h\1>$', dotAll: true);

  static List<DVSitePageSection> _sections(List<String> lines) {
    final List<DVSitePageSection> out = <DVSitePageSection>[];
    String heading = '';
    final List<String> body = <String>[];
    void close() {
      final String text = body.join(' ').trim();
      if (heading.isNotEmpty || text.isNotEmpty) {
        out.add(DVSitePageSection(heading: heading, text: text));
      }
      body.clear();
    }

    for (final String line in lines) {
      final RegExpMatch? match = _heading.firstMatch(line);
      if (match != null) {
        close();
        heading = _text(match.group(2)!);
        continue;
      }
      final String text = _text(line);
      if (text.isNotEmpty) body.add(text);
    }
    close();
    return out;
  }

  static String _text(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

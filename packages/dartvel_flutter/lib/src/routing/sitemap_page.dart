/// The human `/sitemap` page every Dartvel site gets (owner, asked 14 and 15
/// Oct 2026; queue 6d10).
///
/// It reads the site's own `/sitemap.xml` and lays it out the way the XSL view
/// of that file does: an "XML SITEMAP" label, the site's name and description,
/// the number of pages, then a table of every page and when it last changed.
/// One source, so this page and the file crawlers read never disagree. It is a
/// route of the application like `/404` and `/offline`: rendered on the server
/// for a web-server build, prerendered for a web build, in the app's theme,
/// with real links, selectable text and a heading a screen reader announces.
/// An application that defines its own `/sitemap` page keeps it.
library;

import 'package:dartvel_core/dartvel.dart' show DVSitemapLink, dvReadSitemap;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../dartvel_flutter.dart' show DVBox, DVNavLink, DVRouteTarget;

/// The sitemap page. [load] returns the sitemap's XML; by default it is fetched
/// from `/sitemap.xml` on the site the page is served from.
class DVSitemapPage extends StatefulWidget {
  const DVSitemapPage({super.key, this.siteName, this.description, this.siteUrl, this.load});

  final String? siteName;
  final String? description;

  /// The site's own address (`dartvel.seo.siteUrl`): links to it show as
  /// paths, links elsewhere as full addresses.
  final String? siteUrl;
  final Future<String> Function()? load;

  @override
  State<DVSitemapPage> createState() => _DVSitemapPageState();
}

Future<String> _fetchSitemap() async {
  final Uri base = Uri.base;
  if (base.scheme != 'http' && base.scheme != 'https') return '';
  try {
    final http.Response response = await http.get(base.resolve('/sitemap.xml'));
    return response.statusCode == 200 ? response.body : '';
  } on Object {
    return '';
  }
}

const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `12 Nov 2026`: unambiguous in every locale, unlike 11/12/2026.
String dvSitemapDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

class _DVSitemapPageState extends State<DVSitemapPage> {
  List<DVSitemapLink>? _links;

  @override
  void initState() {
    super.initState();
    (widget.load ?? _fetchSitemap)().then((String xml) {
      if (mounted) setState(() => _links = dvReadSitemap(xml, siteUrl: widget.siteUrl));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colours = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final List<DVSitemapLink>? links = _links;
    final String name = (widget.siteName ?? '').trim().isEmpty ? 'Site map' : widget.siteName!.trim();
    final String description = (widget.description ?? '').trim();

    final Widget header = Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colours.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text('XML SITEMAP', style: text.labelMedium?.copyWith(color: colours.primary, letterSpacing: 1.6, fontWeight: .w700)),
              const SizedBox(height: 10),
              Semantics(container: true, header: true, headingLevel: 1, child: Text(name, style: text.headlineMedium?.copyWith(fontWeight: .w700))),
              if (description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(description, style: text.bodyLarge?.copyWith(color: colours.onSurfaceVariant)),
              ],
              if (links != null && links.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(links.length == 1 ? '1 page' : '${links.length} pages', style: text.titleSmall),
              ],
            ],
          ),
        ),
      ),
    );

    Widget framed(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
          ),
        );

    Widget row(DVSitemapLink link) {
      final Widget label = Text(link.path, style: text.bodyMedium?.copyWith(color: colours.primary));
      return framed(Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colours.outlineVariant))),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: link.external
                    ? DVNavLink.external(link.url, padding: .zero, child: label)
                    : DVNavLink(to: DVRouteTarget(link.path), padding: .zero, child: label),
              ),
            ),
            const SizedBox(width: 16),
            Text(link.lastModified == null ? '' : dvSitemapDate(link.lastModified!), style: text.bodyMedium?.copyWith(color: colours.onSurfaceVariant)),
          ],
        ),
      ));
    }

    final List<Widget> body = <Widget>[header, const SizedBox(height: 24)];
    if (links == null) {
      body.add(framed(const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))));
    } else if (links.isEmpty) {
      body.add(framed(Text('This site has no pages listed in its sitemap yet.', style: text.bodyLarge)));
    } else {
      body.add(framed(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: <Widget>[
          Expanded(child: Text('URL', style: text.labelLarge)),
          Text('Last modified', style: text.labelLarge),
        ]),
      )));
      body.addAll(links.map(row));
      body.add(const SizedBox(height: 48));
    }
    return Material(child: DVBox.scrollableList(body, spacing: 0));
  }
}

/// The head tags a built web application ships with.
///
/// `dartvel build web` produced an `index.html` whose title was the package
/// name and which carried no Open Graph tags at all, above a body that stays
/// empty until JavaScript runs. A crawler, a link preview in a chat client and
/// a share on social all read exactly that, and none of them execute the app.
///
/// The failure is quiet in the worst way: the page is perfect in a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvViewportApply;
import 'package:path/path.dart' as p;

export 'package:dartvel_core/dartvel.dart' show dvSeoHead, dvSeoApply, dvAbsoluteAsset, dvViewportMeta, dvViewportApply;

/// Put a viewport into the project's own `web/index.html`.
///
/// Fixing only the built output leaves `dartvel run web` serving the source
/// template, which is the mode a developer is actually looking at when they
/// check a layout on a phone -- so the one place it matters most during
/// development would still be laying out at 980px.
///
/// Returns whether the file was changed, so a build can say it did something
/// to a file the developer owns rather than editing it silently. A project
/// with no `web/` at all is not an error: mobile-only and server-only projects
/// are ordinary.
bool dvEnsureProjectViewport(String root) {
  final File index = File(p.join(root, 'web', 'index.html'));
  if (!index.existsSync()) return false;

  final String before = index.readAsStringSync();
  final String after = dvViewportApply(before);
  if (after == before) return false;

  index.writeAsStringSync(after);
  return true;
}

/// The title for a project, from whichever key it uses.
///
/// The scaffold writes `defaultTitle` and this reads `title`; for a while it
/// read only the latter, so the configuration a new project shipped with was
/// ignored and the page kept the package name. Both are read, the explicit one
/// wins, and [fallback] is used before the package name ever is.
String dvSeoTitle(Map<Object?, Object?> seo, String fallback) {
  final title = seo['title'] ?? seo['defaultTitle'];
  final text = title == null ? '' : '$title'.trim();
  return text.isEmpty ? fallback : text;
}

/// The description for a project, from whichever key it uses.
String? dvSeoDescription(Map<Object?, Object?> seo) {
  final value = seo['description'] ?? seo['defaultDescription'];
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? null : text;
}

/// Strip what `flutter build web` leaves behind for the developer, and fill
/// in what it leaves blank.
///
/// The file Flutter writes is a template and it ships as one. Two long
/// comments address the developer directly — one explaining `--base-href`,
/// one explaining how to customise `flutter_bootstrap.js` — and both reach
/// production on every page of every Dartvel site. The
/// `apple-mobile-web-app-title` carries the Dart package name, which is what
/// iOS shows under the icon when someone saves the page, and `<html>` declares
/// no language at all.
///
/// The comments are instructions *about* the tags, so only the comments go:
/// removing `<base href>` or the bootstrap script with them would be a far
/// worse bug than shipping them.
String dvCleanShell(
  String shell, {
  required String siteName,
  String locale = 'en',
}) {
  var html = shell;

  // Only comments Flutter wrote. An application's own comment in its
  // index.html is not this function's business.
  for (final RegExp template in <RegExp>[
    RegExp(r'\s*<!--\s*\n?\s*If you are serving your web app.*?-->',
        dotAll: true),
    RegExp(r'\s*<!--\s*\n?\s*You can customize the "flutter_bootstrap\.js".*?-->',
        dotAll: true),
  ]) {
    html = html.replaceAll(template, '');
  }

  // A page with no lang is read in the reader's default voice.
  html = html.replaceFirstMapped(
    RegExp(r'<html(?![^>]*\blang=)([^>]*)>'),
    (Match m) => '<html lang="$locale"${m.group(1)}>',
  );

  final String escaped = const HtmlEscape(HtmlEscapeMode.attribute)
      .convert(siteName);
  html = html.replaceFirstMapped(
    RegExp(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")'),
    (Match m) => '${m.group(1)}$escaped${m.group(2)}',
  );

  return html;
}


/// One URL per locale for [route]: the default locale unprefixed, every
/// other under its own path prefix, on [siteUrl].
///
/// A route that already carries a locale prefix -- the prerender walks
/// /fr/pricing as well as /pricing -- gets the same set as its unprefixed
/// form, so the prefix is never doubled. A single locale yields nothing, so
/// no lone hreflang is written.
Map<String, String> dvSeoAlternatesFor({
  required String siteUrl,
  required String route,
  required List<String> locales,
  required String defaultLocale,
}) {
  if (locales.length < 2) return const <String, String>{};
  final String base = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;

  // Strip a leading locale segment, whichever locale it is.
  List<String> segments = route.split('/').where((String s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty &&
      locales.any((String l) => l.toLowerCase() == segments.first.toLowerCase())) {
    segments = segments.sublist(1);
  }
  final String bare = segments.isEmpty ? '/' : '/${segments.join('/')}';

  return <String, String>{
    for (final String locale in locales)
      locale: locale == defaultLocale
          ? '$base$bare'
          : '$base/${locale.toLowerCase()}$bare',
  };
}

/// The locales a site is built for, from `dartvel.i18n`.
///
/// `locales` lists them and `defaultLocale` names the unprefixed one. No
/// section means one implicit locale, which writes no hreflang at all: a
/// single-language site declaring itself as one alternate of itself reads as
/// a misconfiguration.
class DVI18nLocales {
  const DVI18nLocales({required this.locales, required this.defaultLocale, required this.problems});

  final List<String> locales;
  final String defaultLocale;
  final List<String> problems;

  /// Whether there is anything to write hreflang about.
  bool get multilingual => locales.length > 1;

  static DVI18nLocales parse(Object? dartvelSection) {
    final Object? section = dartvelSection is Map ? dartvelSection['i18n'] : null;
    final List<String> problems = <String>[];
    if (section == null) {
      return const DVI18nLocales(locales: <String>['en'], defaultLocale: 'en', problems: <String>[]);
    }
    if (section is! Map) {
      problems.add('dartvel.i18n must be a map.');
      return DVI18nLocales(locales: const <String>['en'], defaultLocale: 'en', problems: problems);
    }
    final Object? raw = section['locales'];
    final List<String> locales = <String>[
      if (raw is List)
        for (final Object? l in raw)
          if (l is String && l.trim().isNotEmpty) l.trim(),
    ];
    if (raw != null && raw is! List) {
      problems.add('dartvel.i18n.locales must be a list of locale tags.');
    }
    if (locales.isEmpty) locales.add('en');
    final Object? configured = section['defaultLocale'];
    String defaultLocale = locales.first;
    if (configured is String && configured.trim().isNotEmpty) {
      if (locales.contains(configured.trim())) {
        defaultLocale = configured.trim();
      } else {
        // A default the site does not have sends x-default to a 404.
        problems.add('dartvel.i18n.defaultLocale is "${configured.trim()}", which is not '
            'one of the locales (${locales.join(', ')}).');
      }
    }
    return DVI18nLocales(locales: locales, defaultLocale: defaultLocale, problems: problems);
  }
}

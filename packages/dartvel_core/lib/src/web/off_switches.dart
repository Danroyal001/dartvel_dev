/// Runtime off switches: a framework feature turned off by the server's
/// environment and a restart, without a rebuild.
///
/// A production hotfix on sigmadev.digital needed a 25-minute rebuild to turn
/// off one framework feature (the page scroll button, whose tap area covered
/// the page). With this the web-server binary reads `DARTVEL_OFF` when it
/// starts:
///
/// ```sh
/// DARTVEL_OFF=page-scroll-button,ssr-first   # comma or space separated
/// ```
///
/// The value is resolved like any other setting the server reads: the
/// process environment (a systemd `Environment=` or `EnvironmentFile=`), then
/// a systemd credential, then the project's `.env`. The server logs which
/// switches are on when it starts, and every name it does not know.
///
/// What a switch does on the client the server tells the client: every HTML
/// document it serves carries `<meta name="dartvel-off" content="...">` with
/// the switches the client acts on, and the app reads it once when it starts
/// ([DVOffSwitches.current]). With nothing off, or only server switches off,
/// no tag is written and every byte is what it always was. A client that is
/// not in a browser has no server document and nothing is off there.
library;

import 'dart:convert' show HtmlEscape, HtmlEscapeMode;

import '../modules/module_outcome.dart' show DVModuleEnvironment;
import '../secrets/secrets.dart' show DVSecrets;
import 'off_switches_page_none.dart' if (dart.library.js_interop) 'off_switches_page_web.dart' as page;
import 'ssr_first.dart' show dvWithoutSsrFirst;

/// The environment variable the server reads its off switches from.
const String dvOffVariable = 'DARTVEL_OFF';

/// The name of the meta tag that tells the client what is off.
const String dvOffMetaName = 'dartvel-off';

/// The framework features turned off for this process.
final class DVOffSwitches {
  const DVOffSwitches._(this.names, this.unknown);

  /// Nothing off.
  static const DVOffSwitches none = DVOffSwitches._(<String>{}, <String>[]);

  /// The page's "To the bottom / Back to top" button (`pageScrollToTop`).
  /// Client side: no button and no tap target is built; the page scrolls as
  /// it always does.
  static const String pageScrollButton = 'page-scroll-button';

  /// SSR-first documents (`dartvel.web.ssrFirst`). Server side: every page
  /// is served as a build with `ssrFirst: false` serves it.
  static const String ssrFirst = 'ssr-first';

  /// Every mounted module that declares itself analytics (the Meta Pixel and
  /// Google Analytics modules): no third-party script is loaded in the
  /// browser and the server forwards nothing to the vendor.
  static const String analytics = 'analytics';

  /// Filling the rendered-page cache with the site's static pages after the
  /// server starts.
  static const String cacheWarm = 'cache-warm';

  /// `module:<id>`: one mounted module, by the id it is mounted under in
  /// `dartvel.modules`.
  static const String modulePrefix = 'module:';

  /// Every switch name there is, besides `module:<id>`.
  static const Set<String> known = <String>{pageScrollButton, ssrFirst, analytics, cacheWarm};

  /// The switches the client acts on, and so the ones the document carries.
  static const Set<String> _client = <String>{pageScrollButton, analytics};

  /// The names that are off, as written for a module id and in lower case
  /// for the rest.
  final Set<String> names;

  /// What was asked for and is not a switch, in the order it was written:
  /// reported when the server starts rather than silently ignored.
  final List<String> unknown;

  /// Whether nothing is off.
  bool get isEmpty => names.isEmpty;

  /// [raw] as the server reads `DARTVEL_OFF`: names separated by commas
  /// and/or white space, in any case.
  factory DVOffSwitches.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return none;
    final Set<String> names = <String>{};
    final List<String> unknown = <String>[];
    for (final String word in raw.split(RegExp(r'[\s,]+'))) {
      if (word.isEmpty) continue;
      final String lower = word.toLowerCase();
      if (known.contains(lower)) {
        names.add(lower);
      } else if (lower.startsWith(modulePrefix) && RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(word.substring(modulePrefix.length))) {
        names.add('$modulePrefix${word.substring(modulePrefix.length)}');
      } else {
        unknown.add(word);
      }
    }
    if (names.isEmpty && unknown.isEmpty) return none;
    return DVOffSwitches._(Set<String>.unmodifiable(names), List<String>.unmodifiable(unknown));
  }

  /// The switches a document served by the server says are off.
  factory DVOffSwitches.fromPage(String html) {
    final Match? tag = _metaPattern.firstMatch(html);
    if (tag == null) return none;
    return DVOffSwitches.parse(_unescape(tag.group(1)!));
  }

  /// Whether [name] is off.
  bool isOff(String name) => names.contains(name);

  /// Whether the module mounted as [id] is off: by `module:<id>`, or by one
  /// of the [groups] it says it belongs to (an analytics module passes
  /// `analytics`).
  bool moduleOff(String id, {Iterable<String> groups = const <String>[]}) {
    final String lower = id.toLowerCase();
    for (final String name in names) {
      if (name.startsWith(modulePrefix) && name.substring(modulePrefix.length).toLowerCase() == lower) return true;
    }
    return groups.any(isOff);
  }

  /// The switches that are off, sorted, for a log line.
  String describe() => isEmpty ? 'none' : (names.toList()..sort()).join(', ');

  /// [html] as it is served with these switches off: without SSR-first when
  /// `ssr-first` is off, and with the meta tag telling the client which of
  /// its switches are off. Nothing off returns [html] itself.
  String document(String html) {
    if (isEmpty) return html;
    String out = isOff(ssrFirst) ? dvWithoutSsrFirst(html) : html;
    final List<String> client = <String>[
      for (final String name in names)
        if (_client.contains(name) || name.startsWith(modulePrefix)) name,
    ]..sort();
    if (client.isEmpty) return out;
    out = out.replaceAll(_metaPattern, '');
    final int head = out.indexOf('</head>');
    if (head < 0) return out;
    final String content = const HtmlEscape(HtmlEscapeMode.attribute).convert(client.join(' '));
    return '${out.substring(0, head)}<meta name="$dvOffMetaName" content="$content">${out.substring(head)}';
  }

  static DVOffSwitches? _current;

  /// The switches for this process, read once: from `DARTVEL_OFF` on the
  /// server, from the document's meta tag in a browser, and none in a
  /// client that is not in a browser.
  static DVOffSwitches get current => _current ??= resolve();

  /// Replaces [current]: for a test, or a host that reads its settings from
  /// somewhere of its own.
  static set current(DVOffSwitches value) => _current = value;

  /// Reads the switches afresh, as [current] does the first time.
  static DVOffSwitches resolve() => switch (DVModuleEnvironment.current) {
    DVModuleEnvironment.backend => DVOffSwitches.parse(const DVSecrets().maybeGet(dvOffVariable)),
    DVModuleEnvironment.web => DVOffSwitches.parse(page.dvOffSwitchesFromPage()),
    DVModuleEnvironment.native => none,
  };

  static final RegExp _metaPattern = RegExp('<meta name="$dvOffMetaName" content="([^"]*)">');

  static String _unescape(String value) => value.replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
}

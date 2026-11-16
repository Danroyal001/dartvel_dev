/// `dartvel.platforms`: the settings that belong to one platform, grouped
/// under that platform's name.
///
/// ```yaml
/// dartvel:
///   platforms:
///     web:
///       document:
///         head:
///           - html: <meta name="theme-color" content="#0b0b0b">
///           - file: html/analytics.html
///         bodyStart:
///           - file: html/tag-manager-noscript.html
///         bodyEnd:
///           - html: <script src="https://cdn.example.com/chat.js" async></script>
/// ```
///
/// The same object in a Dart config class is [DVPlatformSettings], and
/// [DVPlatformSettings.toPubspec] writes exactly the map above. Studio's
/// Platforms screen reads and writes this same object, so a change made in
/// either place is a diff in the other.
///
/// Settings that predate the grouping are still read where they were:
/// `dartvel.web` and `dartvel.android` are the same objects as
/// `dartvel.platforms.web` and `dartvel.platforms.android` (see
/// [dvWithPlatforms]), and where both name the same key the one under
/// `platforms:` wins.
library;

import '../web/document_slots.dart' show DVDocumentSlot, dvHtmlSnippetProblems;

/// A file of the project under `html/`, as a value rather than a path.
///
/// `dartvel routes` writes a `DVWebFile` enum with one value per HTML file
/// under `html/` (`html/head.html` is `DVWebFile.head`), so a renamed or
/// deleted file is a compile error in a Dart config class rather than a
/// snippet that silently disappears.
abstract interface class DVWebFileRef {
  /// The path relative to the project, `html/head.html`.
  String get path;
}

/// A file named by its path, as the YAML spelling names it.
final class _DVWebFilePath implements DVWebFileRef {
  const _DVWebFilePath(this.path);

  @override
  final String path;
}

/// Raw HTML placed in the page as it is written: either [html] itself, or the
/// contents of a [file] under `html/`.
///
/// Nothing escapes or rewrites it, and the minifier copies it untouched, so
/// a script runs exactly as its vendor wrote it. That also means it runs with
/// the page's full authority: only paste HTML from a source you trust.
final class DVHtmlSnippet {
  /// Inline HTML.
  const DVHtmlSnippet.html(String this.html) : file = null;

  /// The contents of a file under `html/`, read at build time.
  const DVHtmlSnippet.file(DVWebFileRef this.file) : html = null;

  final String? html;
  final DVWebFileRef? file;

  /// `{html: ...}` or `{file: html/...}`.
  Map<String, Object?> toPubspec() =>
      html != null ? <String, Object?>{'html': html} : <String, Object?>{'file': file!.path};

  @override
  bool operator ==(Object other) => other is DVHtmlSnippet && other.html == html && other.file?.path == file?.path;

  @override
  int get hashCode => Object.hash(html, file?.path);

  @override
  String toString() => html != null ? 'DVHtmlSnippet.html(${html!.length} chars)' : 'DVHtmlSnippet.file(${file!.path})';
}

/// The three edges of every web page a project can put its own HTML at.
final class DVWebDocumentSlots {
  const DVWebDocumentSlots({
    this.head = const <DVHtmlSnippet>[],
    this.bodyStart = const <DVHtmlSnippet>[],
    this.bodyEnd = const <DVHtmlSnippet>[],
  });

  /// Inside `<head>`, after the tags the shell carries.
  final List<DVHtmlSnippet> head;

  /// Right after `<body>` opens, before anything else in the body.
  final List<DVHtmlSnippet> bodyStart;

  /// Right before `</body>` closes, after the page's own document.
  final List<DVHtmlSnippet> bodyEnd;

  /// The snippets of [slot].
  List<DVHtmlSnippet> of(DVDocumentSlot slot) => switch (slot) {
    DVDocumentSlot.head => head,
    DVDocumentSlot.bodyStart => bodyStart,
    DVDocumentSlot.bodyEnd => bodyEnd,
  };

  bool get isEmpty => head.isEmpty && bodyStart.isEmpty && bodyEnd.isEmpty;

  Map<String, Object?> toPubspec() => <String, Object?>{
    for (final DVDocumentSlot slot in DVDocumentSlot.values)
      if (of(slot).isNotEmpty) slot.key: <Object?>[for (final DVHtmlSnippet snippet in of(slot)) snippet.toPubspec()],
  };

  @override
  bool operator ==(Object other) =>
      other is DVWebDocumentSlots &&
      _sameList(other.head, head) &&
      _sameList(other.bodyStart, bodyStart) &&
      _sameList(other.bodyEnd, bodyEnd);

  @override
  int get hashCode => Object.hash(Object.hashAll(head), Object.hashAll(bodyStart), Object.hashAll(bodyEnd));
}

/// `dartvel.platforms.web`.
final class DVWebSettings {
  const DVWebSettings({this.document = const DVWebDocumentSlots()});

  /// `dartvel.platforms.web.document`: HTML at the edges of every page.
  final DVWebDocumentSlots document;

  bool get isEmpty => document.isEmpty;

  Map<String, Object?> toPubspec() => <String, Object?>{if (!document.isEmpty) 'document': document.toPubspec()};

  @override
  bool operator ==(Object other) => other is DVWebSettings && other.document == document;

  @override
  int get hashCode => document.hashCode;
}

/// `dartvel.platforms`: each platform's own settings.
final class DVPlatformSettings {
  const DVPlatformSettings({this.web = const DVWebSettings()});

  /// `dartvel.platforms.web`.
  final DVWebSettings web;

  bool get isEmpty => web.isEmpty;

  Map<String, Object?> toPubspec() => <String, Object?>{if (!web.isEmpty) 'web': web.toPubspec()};

  /// Reads the `dartvel.platforms` value, as YAML or as the map a Dart config
  /// class wrote. Validation is here and only here, so both spellings are
  /// refused for the same reasons in the same words.
  static DVPlatformSettingsRead fromPubspec(Object? value) {
    final List<String> problems = <String>[];
    // The older shape: a list of the targets the project builds for, with no
    // settings in it.
    if (value == null || value is List) return const DVPlatformSettingsRead(DVPlatformSettings(), <String>[]);
    if (value is! Map) {
      return const DVPlatformSettingsRead(DVPlatformSettings(), <String>[
        'dartvel.platforms must be a map of platforms, such as web, or a list of the platforms the project builds for.',
      ]);
    }
    final Object? web = value['web'];
    if (web != null && web is! Map) problems.add('dartvel.platforms.web must be a map.');
    final Object? document = web is Map ? web['document'] : null;
    final DVWebDocumentSlots slots = _readDocument(document, problems);
    return DVPlatformSettingsRead(DVPlatformSettings(web: DVWebSettings(document: slots)), problems);
  }

  @override
  bool operator ==(Object other) => other is DVPlatformSettings && other.web == web;

  @override
  int get hashCode => web.hashCode;

  @override
  String toString() => 'DVPlatformSettings(${toPubspec()})';
}

/// What reading `dartvel.platforms` found.
final class DVPlatformSettingsRead {
  const DVPlatformSettingsRead(this.settings, this.problems);

  final DVPlatformSettings settings;

  /// Why an entry was left out. Reported rather than thrown so the build can
  /// print every one at once; the build refuses to continue while any stand.
  final List<String> problems;
}

const String _where = 'dartvel.platforms.web.document';

DVWebDocumentSlots _readDocument(Object? document, List<String> problems) {
  if (document == null) return const DVWebDocumentSlots();
  if (document is! Map) {
    problems.add('$_where must be a map with head, bodyStart and bodyEnd.');
    return const DVWebDocumentSlots();
  }
  for (final Object? key in document.keys) {
    if (!DVDocumentSlot.values.any((DVDocumentSlot slot) => slot.key == key)) {
      problems.add('$_where has an unknown slot "$key"; the slots are head, bodyStart and bodyEnd.');
    }
  }
  List<DVHtmlSnippet> slot(DVDocumentSlot which) {
    final Object? raw = document[which.key];
    if (raw == null) return const <DVHtmlSnippet>[];
    if (raw is! List) {
      problems.add('$_where.${which.key} must be a list of snippets.');
      return const <DVHtmlSnippet>[];
    }
    final List<DVHtmlSnippet> out = <DVHtmlSnippet>[];
    for (int index = 0; index < raw.length; index++) {
      final String at = '$_where.${which.key}[$index]';
      final Object? entry = raw[index];
      if (entry is! Map) {
        problems.add('$at must be a map with either html or file.');
        continue;
      }
      for (final Object? key in entry.keys) {
        if (key != 'html' && key != 'file') problems.add('$at has an unknown key "$key"; the keys are html and file.');
      }
      final Object? html = entry['html'];
      final Object? file = entry['file'];
      if ((html == null) == (file == null)) {
        problems.add('$at must have either html or file, not ${html == null ? 'neither' : 'both'}.');
        continue;
      }
      if (html != null) {
        final String text = '$html';
        final List<String> wrong = dvHtmlSnippetProblems(text, slot: which);
        if (wrong.isNotEmpty) {
          problems.addAll(<String>[for (final String problem in wrong) '$at: $problem']);
          continue;
        }
        out.add(DVHtmlSnippet.html(text));
        continue;
      }
      final String path = '$file'.trim().replaceAll(r'\', '/');
      final String? refused = dvWebFileProblem(path);
      if (refused != null) {
        problems.add('$at: $refused');
        continue;
      }
      out.add(DVHtmlSnippet.file(_DVWebFilePath(path)));
    }
    return out;
  }

  return DVWebDocumentSlots(
    head: slot(DVDocumentSlot.head),
    bodyStart: slot(DVDocumentSlot.bodyStart),
    bodyEnd: slot(DVDocumentSlot.bodyEnd),
  );
}

/// The folder snippet files are kept in.
///
/// Not `web/`: that folder is generated by the build and ignored by git in a
/// Dartvel project (native folders are build output), so a file kept there
/// would never be committed, and its presence would stop the build from
/// generating the rest of the folder.
const String dvHtmlSnippetDirectory = 'html';

/// Why [path] cannot name a snippet file, or null when it can.
String? dvWebFileProblem(String path) {
  final List<String> parts = path.split('/');
  if (parts.length < 2 ||
      parts.first != dvHtmlSnippetDirectory ||
      parts.any((String part) => part == '..' || part == '.' || part.isEmpty)) {
    return '"$path" must be a file under html/, such as html/head.html'
        '${parts.first == 'web' ? ' (web/ is generated by the build and not kept in git)' : ''}.';
  }
  return null;
}

bool _sameList(List<DVHtmlSnippet> a, List<DVHtmlSnippet> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The platforms whose settings used to sit straight under `dartvel:`.
const List<String> dvPlatformNames = <String>['web', 'android', 'ios', 'macos', 'windows', 'linux'];

/// [section], the `dartvel:` object, with each platform's settings readable
/// at both homes: `platforms.<name>` and the older `<name>`.
///
/// The two are merged key by key, the newer home winning where both set the
/// same key, so a project that moved one setting and not the others keeps
/// every one. Readers can then use either spelling and see the same values.
Map<Object?, Object?> dvWithPlatforms(Map<Object?, Object?> section) {
  final Object? declared = section['platforms'];
  // A list of targets with no settings anywhere is left as it is written.
  if (declared is List && dvLegacyPlatformKeys(section).isEmpty) return section;
  // A list of targets is the map with nothing set for each.
  final Map<Object?, Object?> grouped = declared is Map
      ? declared.cast<Object?, Object?>()
      : declared is List
          ? <Object?, Object?>{for (final Object? name in declared) '$name': <Object?, Object?>{}}
          : const <Object?, Object?>{};
  final Map<Object?, Object?> merged = <Object?, Object?>{};
  for (final String name in dvPlatformNames) {
    final Object? old = section[name];
    final Object? fresh = grouped[name];
    if (old is! Map && fresh is! Map) continue;
    merged[name] = _deepMerge(
      old is Map ? old : const <Object?, Object?>{},
      fresh is Map ? fresh : const <Object?, Object?>{},
    );
  }
  if (merged.isEmpty) return section;
  return <Object?, Object?>{
    ...section,
    ...merged,
    'platforms': <Object?, Object?>{...grouped, ...merged},
  };
}

/// The older top-level platform keys [section] still uses, for a note that
/// they have moved under `platforms:`.
List<String> dvLegacyPlatformKeys(Map<Object?, Object?> section) => <String>[
  for (final String name in dvPlatformNames)
    if (section[name] is Map) name,
];

Map<Object?, Object?> _deepMerge(Map<Object?, Object?> base, Map<Object?, Object?> over) {
  final Map<Object?, Object?> out = <Object?, Object?>{...base};
  over.forEach((Object? key, Object? value) {
    final Object? existing = out[key];
    out[key] = existing is Map && value is Map
        ? _deepMerge(existing.cast<Object?, Object?>(), value.cast<Object?, Object?>())
        : value;
  });
  return out;
}

/// The platforms a project says it builds for, from either shape of
/// `dartvel.platforms`: the older list (`[web, android]`) or the map, whose
/// keys are the platforms.
List<String> dvPlatformTargets(Object? platforms) => switch (platforms) {
      List<Object?>() => <String>[for (final Object? name in platforms) '$name'],
      Map<Object?, Object?>() => <String>[for (final Object? name in platforms.keys) '$name'],
      _ => const <String>[],
    };

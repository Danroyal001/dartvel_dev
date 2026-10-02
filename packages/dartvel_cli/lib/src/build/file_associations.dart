/// File associations on every target: one declaration, `dartvel.fileAssociations`,
/// registered the way each platform expects.
///
/// | Target | How the OS learns the types |
/// |---|---|
/// | Android | intent filters on the main activity (open with, share to) |
/// | iOS, macOS | document types and declared content types in Info.plist |
/// | Web (installed PWA) | `file_handlers` in the web app manifest |
/// | Linux desktop, Sony eLinux | `.desktop` MimeType and shared-mime-info |
/// | Windows | a per-user registry script beside the binary |
/// | Tizen | app controls for the view operation in tizen-manifest.xml |
/// | webOS, browser extensions, terminal | no OS registration: the app's picker fallback |
///
/// Every edit to a file the developer owns -- the Android manifest, an
/// Info.plist, tizen-manifest.xml -- is a marked block the build replaces on
/// every run and removes when the declaration goes away. Entries the
/// developer wrote outside the markers are never touched, and nothing here
/// asks anybody to hand-edit a native folder.
library;

import 'package:dartvel_core/config.dart' show DVFileAssociation, DVFileAssociationRole, DVFileAssociationsParse;

export 'package:dartvel_core/config.dart' show DVFileAssociation, DVFileAssociationRole;

/// What a project declares, read from its `dartvel:` object.
class DVProjectFileAssociations {
  const DVProjectFileAssociations(this.associations, {this.problems = const <String>[], this.warnings = const <String>[]});

  final List<DVFileAssociation> associations;
  final List<String> problems;
  final List<String> warnings;

  bool get isEmpty => associations.isEmpty;

  /// `dartvel.fileAssociations`, plus the older `dartvel.desktop.fileAssociations`,
  /// which still works and says once that it has moved.
  static DVProjectFileAssociations of(Map<Object?, Object?> section) {
    final List<DVFileAssociation> associations = <DVFileAssociation>[];
    final List<String> problems = <String>[];
    final List<String> warnings = <String>[];
    final DVFileAssociationsParse current = DVFileAssociation.fromPubspec(section['fileAssociations']);
    associations.addAll(current.associations);
    problems.addAll(current.problems);
    final Object? desktop = section['desktop'];
    final Object? legacy = desktop is Map ? desktop['fileAssociations'] : null;
    if (legacy != null) {
      warnings.add('dartvel.desktop.fileAssociations has moved to dartvel.fileAssociations, which every '
          'target reads, not only desktops. It still works for now; move it to keep it working.');
      final DVFileAssociationsParse older = DVFileAssociation.fromPubspec(legacy, key: 'dartvel.desktop.fileAssociations');
      problems.addAll(older.problems);
      for (final DVFileAssociation association in older.associations) {
        if (!associations.any((DVFileAssociation existing) => existing.mimeType == association.mimeType)) {
          associations.add(association);
        }
      }
    }
    return DVProjectFileAssociations(associations, problems: problems, warnings: warnings);
  }
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// [source] without the block between [start] and [end], and the block's
/// leading newline, so a re-run or a removed declaration leaves no residue.
String _withoutBlock(String source, String start, String end) => source.replaceAll(
    RegExp('\n?[ \t]*${RegExp.escape(start.trim())}.*?${RegExp.escape(end.trim())}', dotAll: true), '');

// -- Android ------------------------------------------------------------------

const String _androidStart = '            <!-- dartvel.fileAssociations: begin -->';
const String _androidEnd = '            <!-- dartvel.fileAssociations: end -->';

/// The intent filters for [associations]: VIEW so the app is offered to open
/// the type, SEND and SEND_MULTIPLE so it is offered as a share target. A
/// type the app introduces is also matched by extension, because a content
/// provider often reports such a file as application/octet-stream.
String dvAndroidIntentFilters(List<DVFileAssociation> associations) {
  final StringBuffer out = StringBuffer()..writeln(_androidStart);
  for (final DVFileAssociation association in associations) {
    final String mime = _xml(association.mimeType);
    out
      ..writeln('            <intent-filter android:label="${_xml(association.description ?? association.mimeType)}">')
      ..writeln('                <action android:name="android.intent.action.VIEW"/>')
      ..writeln('                <category android:name="android.intent.category.DEFAULT"/>')
      ..writeln('                <category android:name="android.intent.category.BROWSABLE"/>')
      ..writeln('                <data android:scheme="content"/>')
      ..writeln('                <data android:scheme="file"/>')
      ..writeln('                <data android:mimeType="$mime"/>')
      ..writeln('            </intent-filter>')
      ..writeln('            <intent-filter>')
      ..writeln('                <action android:name="android.intent.action.SEND"/>')
      ..writeln('                <action android:name="android.intent.action.SEND_MULTIPLE"/>')
      ..writeln('                <category android:name="android.intent.category.DEFAULT"/>')
      ..writeln('                <data android:mimeType="$mime"/>')
      ..writeln('            </intent-filter>');
    if (association.extensions.isNotEmpty) {
      out
        ..writeln('            <intent-filter>')
        ..writeln('                <action android:name="android.intent.action.VIEW"/>')
        ..writeln('                <category android:name="android.intent.category.DEFAULT"/>')
        ..writeln('                <category android:name="android.intent.category.BROWSABLE"/>')
        ..writeln('                <data android:scheme="content"/>')
        ..writeln('                <data android:scheme="file"/>')
        ..writeln('                <data android:host="*"/>')
        ..writeln('                <data android:mimeType="*/*"/>');
      for (final String extension in association.extensions) {
        // pathPattern has no "ends with", and matches the first dot it can:
        // one pattern per depth is the documented way to match a.b.order.
        for (final String prefix in const <String>['.*\\\\.', '.*\\\\..*\\\\.', '.*\\\\..*\\\\..*\\\\.']) {
          out.writeln('                <data android:pathPattern="$prefix${_xml(extension)}"/>');
        }
      }
      out.writeln('            </intent-filter>');
    }
  }
  out.write(_androidEnd);
  return out.toString();
}

/// [manifest] with the declared intent filters inside the launcher activity,
/// or without them when nothing is declared.
///
/// The activity is the one carrying the MAIN/LAUNCHER filter, so a renamed
/// MainActivity is still found; a manifest with none is left as it was.
String dvAndroidFileAssociationsManifest(String manifest, List<DVFileAssociation> associations) {
  final String stripped = _withoutBlock(manifest, _androidStart, _androidEnd);
  if (associations.isEmpty) return stripped;
  final int launcher = stripped.indexOf('android.intent.category.LAUNCHER');
  if (launcher < 0) return stripped;
  final int activityStart = stripped.lastIndexOf('<activity', launcher);
  final int activityEnd = stripped.indexOf('</activity>', launcher);
  if (activityStart < 0 || activityEnd < 0) return stripped;
  final int lineStart = stripped.lastIndexOf('\n', activityEnd) + 1;
  return '${stripped.substring(0, lineStart)}${dvAndroidIntentFilters(associations)}\n${stripped.substring(lineStart)}';
}

// -- Apple (iOS and macOS) ---------------------------------------------------

const String _appleStart = '\t<!-- dartvel.fileAssociations: begin -->';
const String _appleEnd = '\t<!-- dartvel.fileAssociations: end -->';

/// Uniform type identifiers for the MIME types Apple already declares, so a
/// document type for image/png names public.png instead of inventing a type
/// the system would not connect to the files it has.
const Map<String, String> _knownUtis = <String, String>{
  'application/pdf': 'com.adobe.pdf',
  'application/json': 'public.json',
  'application/zip': 'public.zip-archive',
  'text/plain': 'public.plain-text',
  'text/csv': 'public.comma-separated-values-text',
  'text/html': 'public.html',
  'text/markdown': 'net.daringfireball.markdown',
  'image/png': 'public.png',
  'image/jpeg': 'public.jpeg',
  'image/gif': 'com.compuserve.gif',
  'image/heic': 'public.heic',
  'image/svg+xml': 'public.svg-image',
  'image/webp': 'org.webmproject.webp',
  'audio/mpeg': 'public.mp3',
  'video/mp4': 'public.mpeg-4',
  'video/quicktime': 'com.apple.quicktime-movie',
};

/// The type identifier the plist uses for [association].
String dvAppleUti(String app, DVFileAssociation association) {
  final String? known = _knownUtis[association.mimeType];
  if (known != null) return known;
  final String sanitized = association.mimeType.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '-');
  return 'dev.dartvel.${app.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '-')}.$sanitized';
}

String _plistStrings(List<String> values) =>
    values.map((String value) => '\t\t\t\t<string>${_xml(value)}</string>').join('\n');

/// The plist entries for [associations]: document types naming each type by
/// its identifier, and a declaration for every type Apple does not already
/// know -- exported for one this app introduces (it has extensions), imported
/// for one it only opens. [ios] adds LSSupportsOpeningDocumentsInPlace, which
/// iOS requires for an app that opens documents from Files.
String dvAppleDocumentTypes(String app, List<DVFileAssociation> associations, {required bool ios}) {
  final StringBuffer out = StringBuffer()..writeln(_appleStart);
  out
    ..writeln('\t<key>CFBundleDocumentTypes</key>')
    ..writeln('\t<array>');
  for (final DVFileAssociation association in associations) {
    out
      ..writeln('\t\t<dict>')
      ..writeln('\t\t\t<key>CFBundleTypeName</key>')
      ..writeln('\t\t\t<string>${_xml(association.description ?? association.mimeType)}</string>')
      ..writeln('\t\t\t<key>CFBundleTypeRole</key>')
      ..writeln('\t\t\t<string>${association.role == DVFileAssociationRole.viewer ? 'Viewer' : 'Editor'}</string>')
      ..writeln('\t\t\t<key>LSHandlerRank</key>')
      ..writeln('\t\t\t<string>${association.isNew ? 'Owner' : 'Alternate'}</string>')
      ..writeln('\t\t\t<key>LSItemContentTypes</key>')
      ..writeln('\t\t\t<array>')
      ..writeln(_plistStrings(<String>[dvAppleUti(app, association)]))
      ..writeln('\t\t\t</array>')
      ..writeln('\t\t</dict>');
  }
  out.writeln('\t</array>');
  final List<DVFileAssociation> exported = <DVFileAssociation>[
    for (final DVFileAssociation association in associations)
      if (association.isNew && !_knownUtis.containsKey(association.mimeType)) association,
  ];
  final List<DVFileAssociation> imported = <DVFileAssociation>[
    for (final DVFileAssociation association in associations)
      if (!association.isNew && !_knownUtis.containsKey(association.mimeType)) association,
  ];
  for (final (String key, List<DVFileAssociation> group) in <(String, List<DVFileAssociation>)>[
    ('UTExportedTypeDeclarations', exported),
    ('UTImportedTypeDeclarations', imported),
  ]) {
    if (group.isEmpty) continue;
    out
      ..writeln('\t<key>$key</key>')
      ..writeln('\t<array>');
    for (final DVFileAssociation association in group) {
      out
        ..writeln('\t\t<dict>')
        ..writeln('\t\t\t<key>UTTypeIdentifier</key>')
        ..writeln('\t\t\t<string>${_xml(dvAppleUti(app, association))}</string>')
        ..writeln('\t\t\t<key>UTTypeDescription</key>')
        ..writeln('\t\t\t<string>${_xml(association.description ?? association.mimeType)}</string>')
        ..writeln('\t\t\t<key>UTTypeConformsTo</key>')
        ..writeln('\t\t\t<array>')
        ..writeln(_plistStrings(const <String>['public.data']))
        ..writeln('\t\t\t</array>')
        ..writeln('\t\t\t<key>UTTypeTagSpecification</key>')
        ..writeln('\t\t\t<dict>')
        ..writeln('\t\t\t\t<key>public.mime-type</key>')
        ..writeln('\t\t\t\t<array>')
        ..writeln(_plistStrings(<String>[association.mimeType]).replaceAll('\t\t\t\t<string>', '\t\t\t\t\t<string>'))
        ..writeln('\t\t\t\t</array>');
      if (association.extensions.isNotEmpty) {
        out
          ..writeln('\t\t\t\t<key>public.filename-extension</key>')
          ..writeln('\t\t\t\t<array>')
          ..writeln(_plistStrings(association.extensions).replaceAll('\t\t\t\t<string>', '\t\t\t\t\t<string>'))
          ..writeln('\t\t\t\t</array>');
      }
      out
        ..writeln('\t\t\t</dict>')
        ..writeln('\t\t</dict>');
    }
    out.writeln('\t</array>');
  }
  if (ios) {
    out
      ..writeln('\t<key>LSSupportsOpeningDocumentsInPlace</key>')
      ..writeln('\t<true/>');
  }
  out.write(_appleEnd);
  return out.toString();
}

/// [plist] with the declared document types in its top dictionary, or
/// without them when nothing is declared. A plist that already declares
/// CFBundleDocumentTypes outside the markers is the developer's, and is left
/// alone rather than given a second key the system would ignore.
String dvAppleFileAssociationsPlist(String plist, String app, List<DVFileAssociation> associations, {required bool ios}) {
  final String stripped = _withoutBlock(plist, _appleStart, _appleEnd);
  if (associations.isEmpty) return stripped;
  if (stripped.contains('<key>CFBundleDocumentTypes</key>')) return stripped;
  final int close = stripped.lastIndexOf('</dict>');
  if (close < 0) return stripped;
  return '${stripped.substring(0, close)}${dvAppleDocumentTypes(app, associations, ios: ios)}\n${stripped.substring(close)}';
}

/// Whether [plist] has document types the developer declared by hand, which
/// the build leaves in charge.
bool dvAppleHasOwnDocumentTypes(String plist) =>
    _withoutBlock(plist, _appleStart, _appleEnd).contains('<key>CFBundleDocumentTypes</key>');

// -- Web ----------------------------------------------------------------------

/// The manifest's `file_handlers`: an installed PWA is offered to open these
/// types, and the files arrive through `launchQueue`. Chromium matches by
/// extension, so a type with none is accepted by MIME type alone.
List<Map<String, Object?>> dvWebFileHandlers(List<DVFileAssociation> associations) => <Map<String, Object?>>[
      if (associations.isNotEmpty)
        <String, Object?>{
          'action': './',
          'accept': <String, Object?>{
            for (final DVFileAssociation association in associations)
              association.mimeType: <String>[for (final String extension in association.extensions) '.$extension'],
          },
        },
    ];

// -- Tizen ----------------------------------------------------------------------

const String _tizenStart = '    <!-- dartvel.fileAssociations: begin -->';
const String _tizenEnd = '    <!-- dartvel.fileAssociations: end -->';

/// [manifest] with an app control per type, so Tizen offers the app for
/// opening files of that type, or without them when nothing is declared.
String dvTizenFileAssociationsManifest(String manifest, List<DVFileAssociation> associations) {
  final String stripped = _withoutBlock(manifest, _tizenStart, _tizenEnd);
  if (associations.isEmpty) return stripped;
  final int close = stripped.indexOf('</ui-application>');
  if (close < 0) return stripped;
  final StringBuffer out = StringBuffer()..writeln(_tizenStart);
  for (final DVFileAssociation association in associations) {
    out
      ..writeln('    <app-control>')
      ..writeln('      <operation name="http://tizen.org/appcontrol/operation/view"/>')
      ..writeln('      <mime name="${_xml(association.mimeType)}"/>')
      ..writeln('    </app-control>');
  }
  out.write(_tizenEnd);
  final int lineStart = stripped.lastIndexOf('\n', close) + 1;
  return '${stripped.substring(0, lineStart)}$out\n${stripped.substring(lineStart)}';
}

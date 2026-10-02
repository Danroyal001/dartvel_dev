/// File associations and app links on Linux: the desktop entry and the MIME
/// database entry a build writes next to the binary.
///
/// A Linux desktop learns what an application opens from a .desktop file's
/// MimeType line and, for a type it has never heard of, from a
/// shared-mime-info XML naming the extension. Both are written from the
/// `dartvel.desktop` section of pubspec.yaml, so an association is declared
/// once, next to the app, and never hand-edited into a system directory.
/// The runtime half -- the file or link arriving as an argument and opening
/// as a route -- is DVAppLaunch's.
library;

import 'dart:io';

import '../config/dartvel_section.dart';
import 'file_associations.dart';

export 'file_associations.dart' show DVFileAssociation, DVFileAssociationRole;

class DVDesktopSettings {
  final String app;
  final String name;
  final String? comment;
  final String? icon;
  final String exec;
  final List<String> categories;
  final List<DVFileAssociation> associations;
  final List<String> schemes;
  final List<String> problems;

  const DVDesktopSettings({
    required this.app,
    required this.name,
    required this.exec,
    this.comment,
    this.icon,
    this.categories = const <String>[],
    this.associations = const <DVFileAssociation>[],
    this.schemes = const <String>[],
    this.problems = const <String>[],
  });

  /// Reads `dartvel.desktop` alone, with its file types where they used to
  /// live. Kept for callers that hold just that section; a build reads the
  /// whole `dartvel:` object through [fromDartvel].
  static DVDesktopSettings parse(Object? section, {required String app, required String appName}) =>
      fromDartvel(<Object?, Object?>{'desktop': section}, app: app, appName: appName);

  /// Reads the `dartvel:` object: the window identity from `desktop`, the
  /// file types from `fileAssociations` (or the older `desktop.fileAssociations`).
  /// Never throws: a build reports what is wrong alongside the rest of its findings.
  static DVDesktopSettings fromDartvel(Map<Object?, Object?> dartvel, {required String app, required String appName}) {
    final Object? desktopSection = dartvel['desktop'];
    final Map<Object?, Object?> d = desktopSection is Map ? desktopSection : const <Object?, Object?>{};
    final DVProjectFileAssociations declared = DVProjectFileAssociations.of(dartvel);
    final List<String> problems = <String>[...declared.problems];
    final List<DVFileAssociation> associations = declared.associations;
    final List<String> schemes = <String>[];
    for (final Object? raw in _list(d['schemes'])) {
      final String s = '$raw';
      if (!RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(s)) {
        problems.add('dartvel.desktop.schemes: "$s" is not a scheme; write the name alone, such as "shop", not "shop://".');
        continue;
      }
      schemes.add(s);
    }
    return DVDesktopSettings(
      app: app,
      name: d['name'] is String ? d['name']! as String : appName,
      comment: d['comment'] is String ? d['comment']! as String : null,
      icon: d['icon'] is String ? d['icon']! as String : null,
      exec: d['exec'] is String ? d['exec']! as String : app,
      categories: <String>[for (final Object? c in _list(d['categories'])) '$c'],
      associations: associations,
      schemes: schemes,
      problems: problems,
    );
  }

  static List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];
}

/// One line's value: a newline would start a second key.
String _line(String value) => value.replaceAll(RegExp(r'[\r\n]+'), ' ');

/// The `.desktop` file. `%U` is how files and links reach main as arguments.
String dvDesktopEntry(DVDesktopSettings s) {
  final List<String> mime = <String>[
    for (final DVFileAssociation a in s.associations) a.mimeType,
    for (final String scheme in s.schemes) 'x-scheme-handler/$scheme',
  ];
  final StringBuffer out = StringBuffer()
    ..writeln('[Desktop Entry]')
    ..writeln('Type=Application')
    ..writeln('Name=${_line(s.name)}');
  if (s.comment != null) out.writeln('Comment=${_line(s.comment!)}');
  if (s.icon != null) out.writeln('Icon=${_line(s.icon!)}');
  out.writeln('Exec=${_line(s.exec)} %U');
  out.writeln('Terminal=false');
  if (s.categories.isNotEmpty) out.writeln('Categories=${s.categories.map(_line).join(';')};');
  if (mime.isNotEmpty) out.writeln('MimeType=${mime.join(';')};');
  return out.toString();
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The shared-mime-info XML for the types this app introduces, or null when
/// it introduces none.
String? dvMimeInfo(DVDesktopSettings s) {
  final List<DVFileAssociation> fresh = <DVFileAssociation>[for (final DVFileAssociation a in s.associations) if (a.isNew) a];
  if (fresh.isEmpty) return null;
  final StringBuffer out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">');
  for (final DVFileAssociation a in fresh) {
    out.writeln('  <mime-type type="${_xml(a.mimeType)}">');
    if (a.description != null) out.writeln('    <comment>${_xml(a.description!)}</comment>');
    for (final String ext in a.extensions) {
      out.writeln('    <glob pattern="*.${_xml(ext)}"/>');
    }
    out.writeln('  </mime-type>');
  }
  out.writeln('</mime-info>');
  return out.toString();
}

/// Every file the Linux build writes under the bundle, by relative path.
Map<String, String> dvDesktopFiles(DVDesktopSettings s) {
  final String? mime = dvMimeInfo(s);
  return <String, String>{
    '${s.app}.desktop': dvDesktopEntry(s),
    if (mime != null) 'share/mime/packages/${s.app}.xml': mime,
  };
}

/// What [dvWriteLinuxDesktopFiles] did.
class DVDesktopWrite {
  final List<String> written;
  final List<String> problems;

  const DVDesktopWrite({required this.written, required this.problems});
}

/// Reads `dartvel.desktop` from the pubspec at [root] and writes the desktop
/// entry and MIME info under [bundle]. Problems are returned, not thrown:
/// the entry is still written without the parts that were wrong.
DVDesktopWrite dvWriteLinuxDesktopFiles(String root, String bundle) {
  final DVDesktopSettings settings = _settingsFor(root);
  final List<String> written = <String>[];
  for (final MapEntry<String, String> e in dvDesktopFiles(settings).entries) {
    final File file = File('$bundle/${e.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(e.value);
    written.add(e.key);
  }
  return DVDesktopWrite(written: written, problems: settings.problems);
}

// -- macOS ------------------------------------------------------------------

const String _plistMarkStart = '\t<!-- dartvel.desktop: begin -->';
const String _plistMarkEnd = '\t<!-- dartvel.desktop: end -->';

/// [plist] with the declaration's URL types and document types in its top
/// dictionary. The block is marked, so a later build replaces it rather
/// than adding a second; a declaration with nothing to open leaves the
/// plist as it was.
String dvMacosInfoPlist(String plist, DVDesktopSettings settings) {
  final RegExp block = RegExp('\n${RegExp.escape(_plistMarkStart)}.*?${RegExp.escape(_plistMarkEnd)}', dotAll: true);
  final String stripped = plist.replaceAll(block, '');
  if (settings.associations.isEmpty && settings.schemes.isEmpty) return stripped;

  // Document types and type declarations are the same block iOS gets, from
  // file_associations.dart, so the two Apple targets cannot drift apart.
  final String withTypes = dvAppleFileAssociationsPlist(stripped, settings.app, settings.associations, ios: false);
  if (settings.schemes.isEmpty) return withTypes;

  final StringBuffer out = StringBuffer()..writeln(_plistMarkStart);
  {
    out
      ..writeln('\t<key>CFBundleURLTypes</key>')
      ..writeln('\t<array>')
      ..writeln('\t\t<dict>')
      ..writeln('\t\t\t<key>CFBundleURLName</key>')
      ..writeln('\t\t\t<string>${_xml(settings.app)}</string>')
      ..writeln('\t\t\t<key>CFBundleURLSchemes</key>')
      ..writeln('\t\t\t<array>');
    for (final String scheme in settings.schemes) {
      out.writeln('\t\t\t\t<string>${_xml(scheme)}</string>');
    }
    out
      ..writeln('\t\t\t</array>')
      ..writeln('\t\t</dict>')
      ..writeln('\t</array>');
  }
  out.write(_plistMarkEnd);

  // Before the top dictionary closes: the last </dict> is the top one.
  final int close = withTypes.lastIndexOf('</dict>');
  if (close < 0) return withTypes;
  return '${withTypes.substring(0, close)}$out\n${withTypes.substring(close)}';
}

/// Rewrites `macos/Runner/Info.plist` under [root] with the declaration's
/// types, before Xcode packages it. A project without a macOS runner is
/// told so rather than given a plist nothing will read.
DVDesktopWrite dvWriteMacosDesktopEntries(String root) {
  final DVDesktopSettings settings = _settingsFor(root);
  final File plist = File('$root/macos/Runner/Info.plist');
  if (!plist.existsSync()) {
    return DVDesktopWrite(written: const <String>[], problems: <String>[
      ...settings.problems,
      'macos/Runner/Info.plist is not there; run flutter create . to add the macOS runner before declaring dartvel.desktop for it.',
    ]);
  }
  final String before = plist.readAsStringSync();
  final String after = dvMacosInfoPlist(before, settings);
  if (after == before) return DVDesktopWrite(written: const <String>[], problems: settings.problems);
  plist.writeAsStringSync(after);
  return DVDesktopWrite(written: const <String>['macos/Runner/Info.plist'], problems: settings.problems);
}

// -- Windows ------------------------------------------------------------------

String _reg(String text) => text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// A registry script that associates each extension and scheme with
/// [executable], under the current user. Null when there is nothing to
/// open. Windows lets only an installer or the person write these keys,
/// so the build writes the script an installer runs, beside the binary.
String? dvWindowsAssociationsScript(DVDesktopSettings settings, {required String executable}) {
  if (settings.associations.isEmpty && settings.schemes.isEmpty) return null;
  const String classes = r'HKEY_CURRENT_USER\Software\Classes';
  final String command = '"$executable" "%1"';
  final StringBuffer out = StringBuffer()
    ..writeln('Windows Registry Editor Version 5.00')
    ..writeln()
    ..writeln('; ${settings.app}: file associations and app links, from dartvel.fileAssociations and dartvel.desktop in pubspec.yaml.')
    ..writeln();
  for (final DVFileAssociation a in settings.associations) {
    for (final String ext in a.extensions) {
      final String progId = '${settings.app}.$ext';
      out
        ..writeln('[$classes\\.$ext]')
        ..writeln('@="$progId"')
        ..writeln('"Content Type"="${_reg(a.mimeType)}"')
        ..writeln()
        ..writeln('[$classes\\$progId]')
        ..writeln('@="${_reg(a.description ?? a.mimeType)}"')
        ..writeln()
        ..writeln('[$classes\\$progId\\shell\\open\\command]')
        ..writeln('@="${_reg(command)}"')
        ..writeln();
      // An editor is also offered for Edit, which Explorer shows beside Open.
      if (a.role == DVFileAssociationRole.editor) {
        out
          ..writeln('[$classes\\$progId\\shell\\edit\\command]')
          ..writeln('@="${_reg(command)}"')
          ..writeln();
      }
    }
  }
  for (final String scheme in settings.schemes) {
    out
      ..writeln('[$classes\\$scheme]')
      ..writeln('@="URL:${_reg(settings.name)}"')
      ..writeln('"URL Protocol"=""')
      ..writeln()
      ..writeln('[$classes\\$scheme\\shell\\open\\command]')
      ..writeln('@="${_reg(command)}"')
      ..writeln();
  }
  return out.toString();
}

/// Writes the registry script beside the binary under [bundle].
DVDesktopWrite dvWriteWindowsDesktopFiles(String root, String bundle) {
  final DVDesktopSettings settings = _settingsFor(root);
  final String? script = dvWindowsAssociationsScript(settings, executable: '$bundle\\${settings.app}.exe');
  if (script == null) return DVDesktopWrite(written: const <String>[], problems: settings.problems);
  final String name = '${settings.app}-associations.reg';
  File('$bundle/$name').writeAsStringSync(script);
  return DVDesktopWrite(written: <String>[name], problems: settings.problems);
}

DVDesktopSettings _settingsFor(String root) {
  final DVDartvelSection section = dvDartvelSection(root);
  final String app = dvPackageName(root) ?? 'dartvel_app';
  final DVDesktopSettings settings = DVDesktopSettings.fromDartvel(section.values, app: app, appName: app);
  if (section.problems.isEmpty) return settings;
  return DVDesktopSettings(
    app: settings.app,
    name: settings.name,
    exec: settings.exec,
    comment: settings.comment,
    icon: settings.icon,
    categories: settings.categories,
    associations: settings.associations,
    schemes: settings.schemes,
    problems: <String>[...section.problems, ...settings.problems],
  );
}

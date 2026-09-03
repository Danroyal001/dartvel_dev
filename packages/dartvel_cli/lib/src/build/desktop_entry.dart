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

import 'package:yaml/yaml.dart';

class DVFileAssociation {
  final String mimeType;
  final List<String> extensions;
  final String? description;

  const DVFileAssociation({required this.mimeType, this.extensions = const <String>[], this.description});

  /// A type the desktop already knows needs no MIME info of its own; one
  /// this app introduces is named by its extensions.
  bool get isNew => extensions.isNotEmpty;
}

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

  /// Reads `dartvel.desktop`. Never throws: a build reports what is wrong
  /// with the declaration alongside the rest of its findings.
  static DVDesktopSettings parse(Object? section, {required String app, required String appName}) {
    final Map<Object?, Object?> d = section is Map ? section : const <Object?, Object?>{};
    final List<String> problems = <String>[];
    final List<DVFileAssociation> associations = <DVFileAssociation>[];
    for (final Object? raw in _list(d['fileAssociations'])) {
      if (raw is! Map) {
        problems.add('dartvel.desktop.fileAssociations has an entry that is not a map.');
        continue;
      }
      final Object? mime = raw['mimeType'];
      if (mime is! String || !mime.contains('/')) {
        problems.add('dartvel.desktop.fileAssociations: every association needs a mimeType such as application/x-shop-order.');
        continue;
      }
      associations.add(DVFileAssociation(
        mimeType: mime,
        extensions: <String>[for (final Object? e in _list(raw['extensions'])) '$e'.replaceFirst(RegExp(r'^\.'), '')],
        description: raw['description'] is String ? raw['description']! as String : null,
      ));
    }
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
  final File pubspec = File('$root/pubspec.yaml');
  Object? doc;
  if (pubspec.existsSync()) {
    try {
      doc = loadYaml(pubspec.readAsStringSync());
    } on Object {
      doc = null;
    }
  }
  final Map<Object?, Object?> top = doc is Map ? doc : const <Object?, Object?>{};
  final String app = top['name'] is String ? top['name']! as String : 'dartvel_app';
  final Object? dartvel = top['dartvel'];
  final Object? desktop = dartvel is Map ? dartvel['desktop'] : null;
  final DVDesktopSettings settings = DVDesktopSettings.parse(desktop, app: app, appName: app);
  final List<String> written = <String>[];
  for (final MapEntry<String, String> e in dvDesktopFiles(settings).entries) {
    final File file = File('$bundle/${e.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(e.value);
    written.add(e.key);
  }
  return DVDesktopWrite(written: written, problems: settings.problems);
}

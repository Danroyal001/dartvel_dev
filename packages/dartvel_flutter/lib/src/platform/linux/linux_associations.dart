/// File associations on Linux: the user's own share of the desktop.
///
/// A Linux desktop learns what an application opens from a `.desktop` file's
/// `MimeType=` line, and learns that a new extension is a type at all from a
/// shared-mime-info XML naming the glob. The build writes both beside the
/// binary; putting them where the desktop reads them is the packager's job,
/// and an application installed by being copied has no packager.
///
/// So this writes them into the user's own directories -- the ones every
/// desktop reads before the system ones -- and refreshes the two caches when
/// the tools to do it are installed. No X11, no GTK: these are files, so the
/// binding works on a kiosk with no desktop session at all, which is exactly
/// where an application is most likely to have been copied into place.
library;

import 'dart:io';

/// What each desktop reads first: `$XDG_DATA_HOME`, or its default.
String _dataHome() {
  final String? test = DVLinuxAssociations.debugXdgRoot;
  if (test != null) return '$test/share';
  final String? declared = Platform.environment['XDG_DATA_HOME'];
  if (declared != null && declared.isNotEmpty) return declared;
  return '${_home()}/.local/share';
}

String _configHome() {
  final String? test = DVLinuxAssociations.debugXdgRoot;
  if (test != null) return '$test/config';
  final String? declared = Platform.environment['XDG_CONFIG_HOME'];
  if (declared != null && declared.isNotEmpty) return declared;
  return '${_home()}/.config';
}

String _home() => Platform.environment['HOME'] ?? '/root';

class DVLinuxAssociations {
  const DVLinuxAssociations._();

  static const Set<String> implemented = <String>{
    'associations.register',
    'associations.unregister',
    'associations.handlerFor',
  };

  /// Test-only: the directories the user's own share lives in, as
  /// `<root>/share` and `<root>/config`.
  ///
  /// A test cannot change this process's environment, and a test that wrote
  /// into the real XDG directories would change what opens files on the
  /// machine running the suite.
  static String? debugXdgRoot;

  /// The desktop entry this application is known by.
  ///
  /// Named for the executable, because that is the one thing an application
  /// installed by being copied is sure to have: two copies under different
  /// names are two applications to the desktop, which is what a person
  /// running two builds side by side means.
  static String get desktopFileName =>
      '${_executableName()}.desktop';

  static String _executableName() {
    final String path = Platform.resolvedExecutable;
    final String base = path.substring(path.lastIndexOf('/') + 1);
    return base.isEmpty ? 'dartvel-app' : base;
  }

  static void register(void Function(String, Object? Function(Object?)) bind) {
    bind('associations.register', (Object? arguments) => _apply(arguments, add: true));
    bind('associations.unregister', (Object? arguments) => _apply(arguments, add: false));
    bind('associations.handlerFor', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return handlerFor('${map['extension'] ?? ''}');
    });
  }

  static bool _apply(Object? arguments, {required bool add}) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final List<Object?> rawTypes =
        map['types'] is List ? map['types']! as List<Object?> : const <Object?>[];
    final List<String> schemes = <String>[
      for (final Object? scheme in
          map['schemes'] is List ? map['schemes']! as List<Object?> : const <Object?>[])
        '$scheme',
    ];
    final List<Map<Object?, Object?>> types = <Map<Object?, Object?>>[
      for (final Object? raw in rawTypes)
        if (raw is Map) raw,
    ];

    final File entry =
        File('${_dataHome()}/applications/$desktopFileName');
    final File mime =
        File('${_dataHome()}/mime/packages/${_executableName()}.xml');

    if (!add) {
      if (entry.existsSync()) entry.deleteSync();
      if (mime.existsSync()) mime.deleteSync();
      _forget(types, schemes);
      _refresh();
      return true;
    }

    entry.parent.createSync(recursive: true);
    entry.writeAsStringSync(_desktopEntry(types, schemes));

    // Only the types this application is introducing. A glob for a type the
    // desktop already knows -- text/plain, image/png -- would be a second
    // definition of somebody else's type.
    final List<Map<Object?, Object?>> fresh = <Map<Object?, Object?>>[
      for (final Map<Object?, Object?> type in types)
        if (!_wellKnown('${type['mimeType']}')) type,
    ];
    if (fresh.isNotEmpty) {
      mime.parent.createSync(recursive: true);
      mime.writeAsStringSync(_mimeInfo(fresh));
    }

    _claim(types, schemes);
    _refresh();
    return true;
  }

  /// A type the shared MIME database already defines.
  ///
  /// Anything under a registered top-level tree that is not a private
  /// extension: `application/x-...` and `application/vnd....` are what an
  /// application introduces, and everything else it should be reusing.
  static bool _wellKnown(String mimeType) {
    final int slash = mimeType.indexOf('/');
    if (slash < 0) return true;
    final String subtype = mimeType.substring(slash + 1);
    return !subtype.startsWith('x-') && !subtype.startsWith('vnd.');
  }

  static String _desktopEntry(
    List<Map<Object?, Object?>> types,
    List<String> schemes,
  ) {
    final List<String> mimes = <String>[
      for (final Map<Object?, Object?> type in types) '${type['mimeType']}',
      for (final String scheme in schemes) 'x-scheme-handler/$scheme',
    ];
    return '''
[Desktop Entry]
Type=Application
Name=${_executableName()}
Exec=${Platform.resolvedExecutable} %f
NoDisplay=false
Terminal=false
MimeType=${mimes.join(';')};
''';
  }

  static String _mimeInfo(List<Map<Object?, Object?>> types) {
    final StringBuffer out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">');
    for (final Map<Object?, Object?> type in types) {
      out.writeln('  <mime-type type="${type['mimeType']}">');
      final Object? description = type['description'];
      if (description != null) {
        out.writeln('    <comment>$description</comment>');
      }
      final List<Object?> extensions =
          type['extensions'] is List ? type['extensions']! as List<Object?> : const <Object?>[];
      for (final Object? extension in extensions) {
        out.writeln('    <glob pattern="*.$extension"/>');
      }
      out.writeln('  </mime-type>');
    }
    out.writeln('</mime-info>');
    return out.toString();
  }

  /// Writes this application into the user's default-applications list.
  ///
  /// The desktop entry says what the application *can* open; mimeapps.list
  /// says what opens a type. Without the second, registering puts the
  /// application in the "Open with" menu and changes nothing about
  /// double-clicking.
  static void _claim(List<Map<Object?, Object?>> types, List<String> schemes) {
    final Map<String, String> defaults = <String, String>{
      for (final Map<Object?, Object?> type in types)
        '${type['mimeType']}': desktopFileName,
      for (final String scheme in schemes)
        'x-scheme-handler/$scheme': desktopFileName,
    };
    _editMimeApps((Map<String, String> current) => current..addAll(defaults));
  }

  static void _forget(List<Map<Object?, Object?>> types, List<String> schemes) {
    _editMimeApps((Map<String, String> current) {
      for (final Map<Object?, Object?> type in types) {
        // Only if it is still ours: another application may have taken the
        // type since, and dropping its line would break it while
        // uninstalling us.
        if (current['${type['mimeType']}'] == desktopFileName) {
          current.remove('${type['mimeType']}');
        }
      }
      for (final String scheme in schemes) {
        if (current['x-scheme-handler/$scheme'] == desktopFileName) {
          current.remove('x-scheme-handler/$scheme');
        }
      }
      return current;
    });
  }

  /// Which desktop entry opens [extension] now, or null when nothing does.
  static String? handlerFor(String extension) {
    if (extension.isEmpty) return null;
    final String? mimeType = _mimeTypeOf(extension);
    if (mimeType == null) return null;
    final String? handler = _mimeApps()[mimeType];
    return handler == null || handler.isEmpty ? null : handler;
  }

  /// The type the shared MIME database gives an extension.
  ///
  /// Read from the `globs` files the database compiles, the user's before
  /// the system's, which is the order a desktop reads them in.
  static String? _mimeTypeOf(String extension) {
    final String suffix = '*.${extension.toLowerCase()}';
    for (final String directory in <String>[
      '${_dataHome()}/mime',
      '/usr/local/share/mime',
      '/usr/share/mime',
    ]) {
      final File globs = File('$directory/globs');
      if (!globs.existsSync()) continue;
      for (final String line in globs.readAsLinesSync()) {
        if (line.startsWith('#')) continue;
        final int colon = line.indexOf(':');
        if (colon < 0) continue;
        if (line.substring(colon + 1).toLowerCase() == suffix) {
          return line.substring(0, colon);
        }
      }
    }
    // Not in a compiled database: the packages directory this application
    // writes into is read as well, because update-mime-database may not have
    // run -- it is not installed everywhere, and a registration that only
    // works where it is would be a registration that works on the developer's
    // machine.
    final Directory packages = Directory('${_dataHome()}/mime/packages');
    if (!packages.existsSync()) return null;
    final RegExp declaration = RegExp(
        r'<mime-type\s+type="([^"]+)"(.*?)</mime-type>',
        dotAll: true);
    for (final FileSystemEntity entity in packages.listSync()) {
      if (entity is! File || !entity.path.endsWith('.xml')) continue;
      for (final RegExpMatch match
          in declaration.allMatches(entity.readAsStringSync())) {
        if ((match.group(2) ?? '').contains('pattern="$suffix"')) {
          return match.group(1);
        }
      }
    }
    return null;
  }

  static File get _mimeAppsFile => File('${_configHome()}/mimeapps.list');

  /// The `[Default Applications]` section, as a map.
  static Map<String, String> _mimeApps() {
    final File file = _mimeAppsFile;
    if (!file.existsSync()) return <String, String>{};
    final Map<String, String> defaults = <String, String>{};
    bool inSection = false;
    for (final String line in file.readAsLinesSync()) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        inSection = trimmed == '[Default Applications]';
        continue;
      }
      if (!inSection || trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final int equals = trimmed.indexOf('=');
      if (equals < 0) continue;
      defaults[trimmed.substring(0, equals).trim()] =
          trimmed.substring(equals + 1).trim();
    }
    return defaults;
  }

  /// Rewrites the `[Default Applications]` section, leaving every other
  /// section as it was.
  ///
  /// mimeapps.list belongs to the user and holds their choices for every
  /// application on the machine. Rewriting the whole file would throw those
  /// away, which is a thing an application does exactly once before somebody
  /// stops trusting it.
  static void _editMimeApps(
    Map<String, String> Function(Map<String, String>) edit,
  ) {
    final File file = _mimeAppsFile;
    final Map<String, String> defaults = edit(_mimeApps());
    final List<String> kept = <String>[];
    bool inSection = false;
    if (file.existsSync()) {
      for (final String line in file.readAsLinesSync()) {
        final String trimmed = line.trim();
        if (trimmed.startsWith('[')) {
          inSection = trimmed == '[Default Applications]';
          if (inSection) continue;
        }
        if (!inSection) kept.add(line);
      }
    }
    final StringBuffer out = StringBuffer()
      ..writeln('[Default Applications]');
    final List<String> names = defaults.keys.toList()..sort();
    for (final String name in names) {
      out.writeln('$name=${defaults[name]}');
    }
    for (final String line in kept) {
      out.writeln(line);
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(out.toString());
  }

  /// Refreshes the two caches, where the tools exist.
  ///
  /// Best effort by design: neither tool is installed everywhere, and a
  /// registration that only worked where they are would be one that worked
  /// on the developer's machine. The files are read directly when the caches
  /// are stale.
  static void _refresh() {
    for (final (String tool, List<String> arguments) in <(String, List<String>)>[
      ('update-desktop-database', <String>['${_dataHome()}/applications']),
      ('update-mime-database', <String>['${_dataHome()}/mime']),
    ]) {
      try {
        Process.runSync(tool, arguments);
      } on ProcessException {
        // Not installed. Said nowhere, because there is nothing for the
        // caller to do about it and the registration still stands.
      }
    }
  }
}

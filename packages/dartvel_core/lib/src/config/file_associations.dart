/// The file types an application opens, declared once and registered with
/// every platform the build targets.
///
/// One declaration, `dartvel.fileAssociations` in `pubspec.yaml` or the same
/// field on a Dart config class. Both go through [DVFileAssociation.fromPubspec]
/// and [DVFileAssociation.toPubspec], so the two spellings are the same object:
/// a key, a default or a validation message cannot exist in one and not the
/// other.
library;

/// What the application does with a file of this type.
///
/// Platforms that rank handlers use it (macOS `CFBundleTypeRole`, the
/// Windows verb); the rest ignore it rather than refuse it.
enum DVFileAssociationRole {
  /// Opens and changes the file. The default: an application that declares
  /// a type usually made it.
  editor,

  /// Opens the file to show it.
  viewer;

  static DVFileAssociationRole? parse(Object? value) {
    for (final DVFileAssociationRole role in DVFileAssociationRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

/// One file type the application opens.
class DVFileAssociation {
  const DVFileAssociation({
    required this.mimeType,
    this.extensions = const <String>[],
    this.description,
    this.icon,
    this.role = DVFileAssociationRole.editor,
  });

  /// The type, `application/x-shop-order` or `image/png`.
  final String mimeType;

  /// The extensions that are this type, without their dots. Empty for a type
  /// the platform already knows (`image/png`); a type the application
  /// introduces needs at least one, because files are recognised by them.
  final List<String> extensions;

  /// What a file manager calls the type.
  final String? description;

  /// An icon for files of this type, as a path in the project.
  final String? icon;

  final DVFileAssociationRole role;

  /// A type this application introduces, rather than one the platform
  /// already has a name for.
  bool get isNew => extensions.isNotEmpty;

  /// The pubspec object, with defaults left out so a round trip is exact.
  Map<String, Object?> toPubspec() => <String, Object?>{
        'mimeType': mimeType,
        if (extensions.isNotEmpty) 'extensions': List<String>.of(extensions),
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (role != DVFileAssociationRole.editor) 'role': role.name,
      };

  /// Every association in [raw], the value of `fileAssociations`, and what
  /// is wrong with the ones that could not be read. Never throws: a build
  /// reports these with the rest of its findings, and the entries that are
  /// right still register.
  static DVFileAssociationsParse fromPubspec(Object? raw, {String key = 'dartvel.fileAssociations'}) {
    final List<DVFileAssociation> associations = <DVFileAssociation>[];
    final List<String> problems = <String>[];
    if (raw == null) return DVFileAssociationsParse(associations, problems);
    if (raw is! List) {
      problems.add('$key must be a list of file types.');
      return DVFileAssociationsParse(associations, problems);
    }
    for (final Object? entry in raw) {
      if (entry is! Map) {
        problems.add('$key has an entry that is not a map.');
        continue;
      }
      final Object? mimeType = entry['mimeType'];
      if (mimeType is! String || !RegExp(r'^[a-z0-9.+-]+/[A-Za-z0-9.+*-]+$').hasMatch(mimeType)) {
        problems.add('$key: every file type needs a mimeType such as application/x-shop-order.');
        continue;
      }
      final Object? rawExtensions = entry['extensions'];
      final List<String> extensions = <String>[];
      if (rawExtensions != null && rawExtensions is! List) {
        problems.add('$key: extensions of $mimeType must be a list, such as [order].');
        continue;
      }
      bool extensionsValid = true;
      for (final Object? extension in (rawExtensions as List?) ?? const <Object?>[]) {
        final String bare = '$extension'.replaceFirst(RegExp(r'^\.'), '');
        if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_+-]*$').hasMatch(bare)) {
          problems.add('$key: "$extension" is not an extension; write it alone, such as order.');
          extensionsValid = false;
          break;
        }
        extensions.add(bare);
      }
      if (!extensionsValid) continue;
      final Object? role = entry['role'];
      final DVFileAssociationRole? parsedRole = role == null ? DVFileAssociationRole.editor : DVFileAssociationRole.parse(role);
      if (parsedRole == null) {
        problems.add('$key: role of $mimeType must be editor or viewer.');
        continue;
      }
      final Object? description = entry['description'];
      final Object? icon = entry['icon'];
      if (description != null && description is! String) {
        problems.add('$key: description of $mimeType must be text.');
        continue;
      }
      if (icon != null && icon is! String) {
        problems.add('$key: icon of $mimeType must be a path.');
        continue;
      }
      final Set<String> known = <String>{'mimeType', 'extensions', 'description', 'icon', 'role'};
      final Iterable<Object?> unknown = entry.keys.where((Object? name) => !known.contains(name));
      if (unknown.isNotEmpty) {
        problems.add('$key: $mimeType has ${unknown.map((Object? name) => '"$name"').join(', ')}, '
            'which a file type does not take; the keys are ${known.join(', ')}.');
        continue;
      }
      associations.add(DVFileAssociation(
        mimeType: mimeType,
        extensions: extensions,
        description: description as String?,
        icon: icon as String?,
        role: parsedRole,
      ));
    }
    return DVFileAssociationsParse(associations, problems);
  }

  @override
  bool operator ==(Object other) =>
      other is DVFileAssociation &&
      other.mimeType == mimeType &&
      other.description == description &&
      other.icon == icon &&
      other.role == role &&
      other.extensions.length == extensions.length &&
      Iterable<int>.generate(extensions.length).every((int index) => other.extensions[index] == extensions[index]);

  @override
  int get hashCode => Object.hash(mimeType, description, icon, role, Object.hashAll(extensions));

  @override
  String toString() => 'DVFileAssociation(${toPubspec()})';
}

/// What reading `fileAssociations` found.
class DVFileAssociationsParse {
  const DVFileAssociationsParse(this.associations, this.problems);
  final List<DVFileAssociation> associations;
  final List<String> problems;
}

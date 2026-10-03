/// `dartvel.fileStorage`: what `DV.Platform.fileStorage` may reach on a
/// device, beyond the application's own directory.
///
/// One declaration, read by the build to write each platform's permissions
/// the way that platform wants them (AndroidManifest permissions per API
/// level, Info.plist keys on iOS and macOS, sandbox entitlements on macOS) and
/// by the runtime to know what to ask for. The same object is what a Dart
/// config file builds: [DVFileStorageConfig.toDeclaration] gives back exactly
/// the map [DVFileStorageConfig.parse] reads, so the two forms cannot drift.
library;

/// A kind of file outside the application's own directory.
enum DVDeviceFileAccess {
  /// The person's pictures.
  photos,

  /// Pictures, video and audio.
  media,

  /// Documents the person picks, one at a time or a folder at a time.
  documents,

  /// Every file on shared storage. Rarely the right answer: app stores
  /// restrict it and most platforms do not have it at all.
  allFiles;

  /// The name used in pubspec.yaml.
  String get key => name;

  static DVDeviceFileAccess? fromKey(String key) {
    for (final DVDeviceFileAccess access in values) {
      if (access.key == key) return access;
    }
    return null;
  }
}

/// The parsed `dartvel.fileStorage` section.
class DVFileStorageConfig {
  const DVFileStorageConfig({
    this.access = const <DVDeviceFileAccess>[],
    this.reason,
    this.shareAppFiles = false,
    this.problems = const <String>[],
  });

  /// What is needed beyond the application's own directory, which needs no
  /// permission anywhere and is therefore not listed.
  final List<DVDeviceFileAccess> access;

  /// Why, in the words iOS and macOS show the person when they ask.
  final String? reason;

  /// Whether the application's own documents show in the Files app (iOS) and
  /// can be opened in place by other apps.
  final bool shareAppFiles;

  /// What was wrong with the declaration, one sentence each.
  final List<String> problems;

  bool get isEmpty => access.isEmpty && reason == null && !shareAppFiles;

  /// Whether [kind] was asked for.
  bool allows(DVDeviceFileAccess kind) => access.contains(kind);

  /// The Dartvel permission names a runtime request uses for this access.
  List<String> get permissionNames => <String>[
        for (final DVDeviceFileAccess kind in access)
          if (kind != DVDeviceFileAccess.documents) kind.key,
      ];

  /// Reads `dartvel.fileStorage`. A missing section is the default: the
  /// application's own directory and nothing else.
  static DVFileStorageConfig parse(Object? raw) {
    if (raw == null) return const DVFileStorageConfig();
    if (raw is! Map) {
      return const DVFileStorageConfig(problems: <String>[
        'dartvel.fileStorage must be a map with access, reason and shareAppFiles.',
      ]);
    }
    final List<String> problems = <String>[];
    for (final Object? key in raw.keys) {
      if (!const <String>{'access', 'reason', 'shareAppFiles'}.contains('$key')) {
        problems.add('dartvel.fileStorage.$key is not a setting; the settings are access, reason and shareAppFiles.');
      }
    }
    final List<DVDeviceFileAccess> access = <DVDeviceFileAccess>[];
    final Object? listed = raw['access'];
    if (listed != null && listed is! List) {
      problems.add('dartvel.fileStorage.access must be a list, for example [photos, documents].');
    }
    for (final Object? entry in listed is List ? listed : const <Object?>[]) {
      final DVDeviceFileAccess? kind = DVDeviceFileAccess.fromKey('$entry'.trim());
      if (kind == null) {
        problems.add('dartvel.fileStorage.access has "$entry"; the kinds are '
            '${DVDeviceFileAccess.values.map((DVDeviceFileAccess value) => value.key).join(', ')}.');
      } else if (!access.contains(kind)) {
        access.add(kind);
      }
    }
    final Object? reason = raw['reason'];
    if (reason != null && (reason is! String || reason.trim().isEmpty)) {
      problems.add('dartvel.fileStorage.reason must be a sentence saying why the app needs these files.');
    }
    final bool needsReason = access.any((DVDeviceFileAccess kind) =>
        kind == DVDeviceFileAccess.photos || kind == DVDeviceFileAccess.media);
    if (needsReason && (reason is! String || reason.trim().isEmpty)) {
      problems.add('dartvel.fileStorage.reason is required with photos or media: iOS and macOS show it when they ask, and refuse the request without it.');
    }
    final Object? share = raw['shareAppFiles'];
    if (share != null && share is! bool) {
      problems.add('dartvel.fileStorage.shareAppFiles must be true or false.');
    }
    return DVFileStorageConfig(
      access: List<DVDeviceFileAccess>.unmodifiable(access),
      reason: reason is String && reason.trim().isNotEmpty ? reason.trim() : null,
      shareAppFiles: share == true,
      problems: List<String>.unmodifiable(problems),
    );
  }

  /// The pubspec map this configuration is. Only what differs from the
  /// default is written, so a default configuration is an empty map.
  Map<String, Object?> toDeclaration() => <String, Object?>{
        if (access.isNotEmpty)
          'access': <String>[for (final DVDeviceFileAccess kind in access) kind.key],
        if (reason != null) 'reason': reason,
        if (shareAppFiles) 'shareAppFiles': true,
      };

  @override
  bool operator ==(Object other) =>
      other is DVFileStorageConfig &&
      other.reason == reason &&
      other.shareAppFiles == shareAppFiles &&
      other.access.length == access.length &&
      <int>[for (int index = 0; index < access.length; index++) index]
          .every((int index) => other.access[index] == access[index]);

  @override
  int get hashCode => Object.hash(Object.hashAll(access), reason, shareAppFiles);
}

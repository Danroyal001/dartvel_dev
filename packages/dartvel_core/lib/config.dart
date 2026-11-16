/// The Dart form of the `dartvel:` section of `pubspec.yaml`.
///
/// A project can write `dartvel: dartvel_config.dart` and declare its
/// configuration as a class instead:
///
/// ```dart
/// import 'package:dartvel_core/config.dart';
///
/// class const AppConfig() extends DartvelConfig {
///
///   @override
///   List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[
///         DVFileAssociation(mimeType: 'application/x-shop-order', extensions: <String>['order']),
///       ];
/// }
/// ```
///
/// The build turns the class into the same object the YAML would have been
/// with [DartvelConfig.toPubspec], so the two are one configuration: every
/// field has the same name, default and validation in both.
///
/// A separate library rather than part of `dartvel.dart`, because the
/// generated client barrel already has a `DartvelConfig` (its constants), and
/// a page importing both would not compile.
library;

import 'src/config/file_associations.dart';
import 'src/config/platforms.dart';

export 'src/config/file_associations.dart';
export 'src/config/platforms.dart';
export 'src/web/document_slots.dart';

/// A project's configuration, written in Dart.
abstract class DartvelConfig {
  const DartvelConfig();

  /// `dartvel.fileAssociations`: the file types the application opens.
  List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[];

  /// `dartvel.platforms`: each platform's own settings, such as the HTML at
  /// the edges of every web page (`platforms.web.document`).
  DVPlatformSettings get platforms => const DVPlatformSettings();

  /// The `dartvel:` object this configuration is, as the YAML would have
  /// written it. Fields at their defaults are left out.
  Map<String, Object?> toPubspec() => <String, Object?>{
        if (fileAssociations.isNotEmpty)
          'fileAssociations': <Object?>[
            for (final DVFileAssociation association in fileAssociations) association.toPubspec(),
          ],
        if (!platforms.isEmpty) 'platforms': platforms.toPubspec(),
      };
}

/// The configuration a `dartvel:` object describes, as a [DartvelConfig].
///
/// What the YAML spelling becomes on its way into the same typed shape, and
/// the other half of the round trip the parity tests hold.
class DartvelPubspecConfig extends DartvelConfig {
  DartvelPubspecConfig._(this.fileAssociations, this.platforms, this.problems);

  /// Reads [section], the `dartvel:` object. Problems are collected, not
  /// thrown, in the same words the build prints.
  factory DartvelPubspecConfig.fromPubspec(Map<Object?, Object?> section) {
    final DVFileAssociationsParse associations = DVFileAssociation.fromPubspec(section['fileAssociations']);
    // The older homes (dartvel.web, dartvel.android) read as platforms too.
    final DVPlatformSettingsRead platforms = DVPlatformSettings.fromPubspec(dvWithPlatforms(section)['platforms']);
    return DartvelPubspecConfig._(
      associations.associations,
      platforms.settings,
      <String>[...associations.problems, ...platforms.problems],
    );
  }

  @override
  final List<DVFileAssociation> fileAssociations;

  @override
  final DVPlatformSettings platforms;

  final List<String> problems;
}

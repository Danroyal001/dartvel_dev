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
import 'src/observability/open_telemetry_config.dart';

export 'src/config/file_associations.dart';
export 'src/observability/logging.dart' show DVLogLevel;
export 'src/observability/open_telemetry_config.dart';

/// A project's configuration, written in Dart.
abstract class DartvelConfig {
  const DartvelConfig();

  /// `dartvel.fileAssociations`: the file types the application opens.
  List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[];

  /// `dartvel.openTelemetry`: where traces, metrics and logs are exported.
  /// Null leaves the section out, which is export off unless the deployment
  /// names an endpoint.
  DVOpenTelemetryConfig? get openTelemetry => null;

  /// The `dartvel:` object this configuration is, as the YAML would have
  /// written it. Fields at their defaults are left out.
  Map<String, Object?> toPubspec() => <String, Object?>{
        if (fileAssociations.isNotEmpty)
          'fileAssociations': <Object?>[
            for (final DVFileAssociation association in fileAssociations) association.toPubspec(),
          ],
        if (openTelemetry != null) 'openTelemetry': openTelemetry!.toDeclaration(),
      };
}

/// The configuration a `dartvel:` object describes, as a [DartvelConfig].
///
/// What the YAML spelling becomes on its way into the same typed shape, and
/// the other half of the round trip the parity tests hold.
class DartvelPubspecConfig extends DartvelConfig {
  DartvelPubspecConfig._(this.fileAssociations, this.problems, {this.openTelemetry});

  /// Reads [section], the `dartvel:` object. Problems are collected, not
  /// thrown, in the same words the build prints.
  factory DartvelPubspecConfig.fromPubspec(Map<Object?, Object?> section) {
    final DVFileAssociationsParse associations = DVFileAssociation.fromPubspec(section['fileAssociations']);
    final List<String> problems = <String>[...associations.problems];
    DVOpenTelemetryConfig? openTelemetry;
    if (section['openTelemetry'] != null) {
      try {
        openTelemetry = DVOpenTelemetryConfig.parse(section['openTelemetry']);
      } on ArgumentError catch (error) {
        problems.add('${error.name}: ${error.message}');
      }
    }
    return DartvelPubspecConfig._(associations.associations, problems, openTelemetry: openTelemetry);
  }

  @override
  final List<DVFileAssociation> fileAssociations;

  @override
  final DVOpenTelemetryConfig? openTelemetry;


  final List<String> problems;
}

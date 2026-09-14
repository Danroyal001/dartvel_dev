import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVAnalyticsConfigurationError, DVAnalyticsSettings, DVConsentDeclaration;
import 'package:path/path.dart' as p;

/// `dartvel.analytics` read at generation, and the Dart the running
/// application starts `DV.Analytics` and `DV.Privacy` from.
///
/// Two files, both importing only dartvel_core, because the generated server
/// imports them as well as the client runtime and a Flutter import would
/// compile Flutter into a process with no dart:ui.
class AnalyticsGenerator {
  const AnalyticsGenerator._();

  /// Reads and checks `dartvel.analytics` from [dv], or returns null when
  /// the project declares none.
  ///
  /// Throws [StateError] naming the key for anything it does not understand.
  /// Called before anything is generated, because a build that is going to
  /// fail must not leave half a client behind it -- and a value that was
  /// skipped instead would be a setting the application believes it made.
  static DVAnalyticsSettings? read(Map<Object?, Object?> dv) {
    final Object? analytics = dv['analytics'];
    if (analytics == null) return null;
    if (analytics is! Map) {
      throw StateError('dartvel.analytics must be a map with a consent policy, '
          'not "$analytics"');
    }
    final DVAnalyticsSettings settings;
    try {
      settings = DVAnalyticsSettings.fromConfig(analytics);
    } on DVAnalyticsConfigurationError catch (error) {
      throw StateError(error.message);
    }
    for (final DVConsentDeclaration d in settings.consent.categories) {
      final String name = d.category.name;
      if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(name) ||
          _reserved.contains(name)) {
        throw StateError(
          'dartvel.analytics.consent.categories: "$name" cannot be generated '
          'as ConsentCategories.$name. Category names are lowerCamelCase Dart '
          'names that are not keywords, such as productUsage.',
        );
      }
    }
    return settings;
  }

  /// Writes `analytics.g.dart` and `privacy.g.dart` under
  /// `lib/dartvel_client`, whether or not analytics is declared: the client
  /// runtime and the generated server call both unconditionally.
  static void generate({
    required String root,
    required DVAnalyticsSettings? settings,
  }) {
    final Directory out = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(p.join(out.path, 'analytics.g.dart'))
        .writeAsStringSync(_analyticsSource(settings));
    File(p.join(out.path, 'privacy.g.dart')).writeAsStringSync(_privacySource());
  }

  static String _literal(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

  static String _analyticsSource(DVAnalyticsSettings? settings) {
    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln();

    if (settings == null) {
      sb
        ..writeln('/// `dartvel.analytics` from pubspec.yaml. This project declares none,')
        ..writeln('/// so there is no policy and `DV.Analytics` throws when used.')
        ..writeln('const DVAnalyticsSettings? dartvelAnalyticsSettings = null;')
        ..writeln()
        ..writeln('/// Starts nothing: this project declares no `dartvel.analytics`.')
        ..writeln('void configureDartvelAnalytics({')
        ..writeln('  required FutureOr<DVDatabaseAdapter> Function() database,')
        ..writeln('}) {}');
      return sb.toString();
    }

    sb
      ..writeln('/// The consent categories `dartvel.analytics.consent` declares.')
      ..writeln('///')
      ..writeln('/// An event names its category through one of these rather than a')
      ..writeln('/// string, so a misspelt category is a compile error instead of a')
      ..writeln('/// second category that is denied for ever.')
      ..writeln('abstract final class ConsentCategories {');
    for (final DVConsentDeclaration d in settings.consent.categories) {
      final String name = d.category.name;
      sb.writeln('  static const DVConsentCategory $name = '
          'DVConsentCategory(${_literal(name)});');
    }
    sb
      ..writeln('}')
      ..writeln()
      ..writeln('/// `dartvel.analytics` from pubspec.yaml, as read and checked when')
      ..writeln('/// this file was generated.')
      ..writeln('final DVAnalyticsSettings? dartvelAnalyticsSettings = DVAnalyticsSettings(')
      ..writeln('  consent: DVConsentPolicy(')
      ..writeln('    version: ${_literal(settings.consent.version)},')
      ..writeln('    categories: const <DVConsentDeclaration>[');
    for (final DVConsentDeclaration d in settings.consent.categories) {
      final List<String> args = <String>[
        'ConsentCategories.${d.category.name}',
        if (d.required) 'required: true',
        if (!d.required) 'defaultGranted: ${d.defaultGranted}',
        if (d.tracking) 'tracking: true',
      ];
      sb.writeln('      DVConsentDeclaration(${args.join(', ')}),');
    }
    sb
      ..writeln('    ],')
      ..writeln('  ),');
    if (settings.flagExposureCategory != null) {
      sb.writeln('  flagExposureCategory: '
          'ConsentCategories.${settings.flagExposureCategory!.name},');
    }
    sb
      ..writeln('  sessionCap: ${settings.sessionCap},')
      ..writeln(');')
      ..writeln()
      ..writeln('/// Starts `DV.Analytics` over the database [database] opens.')
      ..writeln('///')
      ..writeln('/// Called by the generated client runtime, over the device\'s own')
      ..writeln('/// database, and by the generated server over the application\'s.')
      ..writeln('/// Returns at once; an event tracked before the stored consent has')
      ..writeln('/// been read waits for it rather than being judged against the')
      ..writeln('/// declared defaults.')
      ..writeln('void configureDartvelAnalytics({')
      ..writeln('  required FutureOr<DVDatabaseAdapter> Function() database,')
      ..writeln('}) {')
      ..writeln('  DVAnalyticsRuntime.start(')
      ..writeln('    settings: dartvelAnalyticsSettings!,')
      ..writeln('    database: database,')
      ..writeln('  );')
      ..writeln('}');
    return sb.toString();
  }

  static String _privacySource() => '''
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:dartvel_core/dartvel.dart';

/// Every declared model as the privacy walk sees it, over [database].
List<DVPrivacyModel> dartvelPrivacyModels(DVDatabaseAdapter database) =>
    <DVPrivacyModel>[];

/// Configures `DV.Privacy` over [database] from `${'DARTVEL_PRIVACY_KEY'}` in
/// [environment], and returns whether it did.
///
/// Called by the generated server. With the key unset nothing is configured
/// and `DV.Privacy` throws naming it; with the key set and no database the
/// server does not start, because an erasure with nothing to walk would
/// report success.
bool configureDartvelBackendPrivacy({
  required DVDatabaseAdapter? database,
  required Map<String, String> environment,
}) =>
    DVPrivacyRuntime.configureFromEnvironment(
      environment: environment,
      database: database,
      models: database == null
          ? const <DVPrivacyModel>[]
          : dartvelPrivacyModels(database),
    );
''';

  static const Set<String> _reserved = <String>{
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type',
    'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
  };
}

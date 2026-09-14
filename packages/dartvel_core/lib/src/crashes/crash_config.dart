/// `dartvel.crashes`: what a pubspec says about crash reporting.
library;

import '../analytics/consent.dart';

/// The build a setting applies to.
enum DVCrashBuildMode { debug, profile, release }

/// Where reports are sent.
enum DVCrashSinkChoice {
  /// Nowhere: reports are captured and kept, and release health is computed
  /// locally, with nowhere to send the detail.
  none,

  /// The deployment's own backend, which serves the crash endpoint when this
  /// is declared.
  dartvel,
}

/// Crash reporting as a project declares it.
///
/// Read strictly. Every setting has a default, which is what makes a loose
/// reading dangerous: a misspelt key, a string where a boolean belongs, or a
/// sample rate of 25 meaning a quarter would each be replaced by the default
/// and look exactly like a setting that was honoured. So each is refused,
/// naming the key.
final class DVCrashConfig {
  const DVCrashConfig({
    this.disabledIn = const <DVCrashBuildMode>{},
    this.sink = DVCrashSinkChoice.none,
    this.nonFatalSampleRate = 1,
    this.breadcrumbs = 64,
    this.fullReportsPerRelease = 5,
    this.identityConsent,
    this.ingestPerInstallPerHour = 30,
    this.ingestMaxBytes = 262144,
  });

  /// The builds crash reporting is off in. Off is a declaration the build
  /// reports (`DV-CRASH-009`).
  final Set<DVCrashBuildMode> disabledIn;

  final DVCrashSinkChoice sink;

  /// The share of non-fatal errors kept, from 0 to 1. Crashes are never
  /// sampled.
  final double nonFatalSampleRate;

  /// How many breadcrumbs a report carries.
  final int breadcrumbs;

  /// Full reports per device per release; past it crashes are counted.
  final int fullReportsPerRelease;

  /// The consent category a report may carry a user id under, or null when
  /// no report is ever tied to an account.
  final DVConsentCategory? identityConsent;

  /// With `sink: dartvel`, the reports the backend stores per install per
  /// hour; past it they are counted.
  final int ingestPerInstallPerHour;

  /// With `sink: dartvel`, the largest report body the backend accepts.
  final int ingestMaxBytes;

  bool enabledIn(DVCrashBuildMode mode) => !disabledIn.contains(mode);

  /// The settings `dartvel.crashes` accepts.
  static const List<String> settings = <String>[
    'enabled',
    'disabledIn',
    'sink',
    'nonFatalSampleRate',
    'breadcrumbs',
    'fullReportsPerRelease',
    'identity',
    'ingest',
  ];

  static const String _section = 'dartvel.crashes';

  /// Reads the `dartvel.crashes` section, or the defaults when there is none.
  ///
  /// Throws [ArgumentError] naming the key for anything it cannot honour.
  factory DVCrashConfig.parse(Object? section) {
    if (section == null) return const DVCrashConfig();
    if (section is! Map) {
      throw ArgumentError.value(
          section, _section, 'must be a map of crash reporting settings');
    }
    for (final Object? key in section.keys) {
      if (!settings.contains('$key')) {
        throw ArgumentError.value(section[key], '$_section.$key',
            'is not a crash reporting setting; the settings are '
            '${settings.join(', ')}');
      }
    }

    final Object? enabled = section['enabled'];
    if (enabled != null && enabled is! bool) {
      throw ArgumentError.value(
          enabled, '$_section.enabled', 'must be true or false');
    }

    final Set<DVCrashBuildMode> disabledIn = <DVCrashBuildMode>{};
    final Object? modes = section['disabledIn'];
    if (modes != null) {
      if (modes is! List) {
        throw ArgumentError.value(modes, '$_section.disabledIn',
            'must be a list of build modes: debug, profile, release');
      }
      for (final Object? mode in modes) {
        final DVCrashBuildMode? known = DVCrashBuildMode.values
            .where((DVCrashBuildMode m) => m.name == mode)
            .firstOrNull;
        if (known == null) {
          throw ArgumentError.value(mode, '$_section.disabledIn',
              'names a build mode that does not exist; the modes are debug, '
              'profile and release');
        }
        disabledIn.add(known);
      }
    }
    if (enabled == false) disabledIn.addAll(DVCrashBuildMode.values);

    final Object? rawSink = section['sink'];
    DVCrashSinkChoice sink = DVCrashSinkChoice.none;
    if (rawSink != null) {
      final DVCrashSinkChoice? known = DVCrashSinkChoice.values
          .where((DVCrashSinkChoice s) => s.name == rawSink)
          .firstOrNull;
      if (known == null) {
        throw ArgumentError.value(rawSink, '$_section.sink',
            'is not a crash sink this build has; the sinks are '
            '${DVCrashSinkChoice.values.map((DVCrashSinkChoice s) => s.name).join(', ')}');
      }
      sink = known;
    }

    final Object? rate = section['nonFatalSampleRate'];
    if (rate != null && (rate is! num || rate < 0 || rate > 1)) {
      throw ArgumentError.value(rate, '$_section.nonFatalSampleRate',
          'must be a number from 0 to 1 -- 0.25 keeps a quarter');
    }

    final Object? breadcrumbs = section['breadcrumbs'];
    if (breadcrumbs != null && (breadcrumbs is! int || breadcrumbs < 0)) {
      throw ArgumentError.value(breadcrumbs, '$_section.breadcrumbs',
          'must be a whole number of breadcrumbs, 0 or more');
    }

    final Object? full = section['fullReportsPerRelease'];
    if (full != null && (full is! int || full < 1)) {
      throw ArgumentError.value(full, '$_section.fullReportsPerRelease',
          'must be a whole number, 1 or more');
    }

    DVConsentCategory? identityConsent;
    final Object? identity = section['identity'];
    if (identity != null) {
      if (identity is! Map) {
        throw ArgumentError.value(identity, '$_section.identity',
            'must be a map naming the consent category: identity: '
            '{consent: <category>}');
      }
      for (final Object? key in identity.keys) {
        if (key != 'consent') {
          throw ArgumentError.value(identity[key], '$_section.identity.$key',
              'is not an identity setting; the one setting is consent');
        }
      }
      final Object? category = identity['consent'];
      if (category is! String || category.trim().isEmpty) {
        throw ArgumentError.value(category, '$_section.identity.consent',
            'must name the consent category a report may carry a user id '
            'under');
      }
      identityConsent = DVConsentCategory(category.trim());
    }

    int perInstallPerHour = 30;
    int maxBytes = 262144;
    final Object? ingest = section['ingest'];
    if (ingest != null) {
      if (ingest is! Map) {
        throw ArgumentError.value(ingest, '$_section.ingest',
            'must be a map of what the backend accepts: perInstallPerHour, '
            'maxBytes');
      }
      for (final Object? key in ingest.keys) {
        if (key != 'perInstallPerHour' && key != 'maxBytes') {
          throw ArgumentError.value(ingest[key], '$_section.ingest.$key',
              'is not an ingest setting; the settings are perInstallPerHour '
              'and maxBytes');
        }
      }
      final Object? perInstall = ingest['perInstallPerHour'];
      if (perInstall != null) {
        if (perInstall is! int || perInstall < 1) {
          throw ArgumentError.value(
              perInstall,
              '$_section.ingest.perInstallPerHour',
              'must be a whole number of reports, 1 or more');
        }
        perInstallPerHour = perInstall;
      }
      final Object? bytes = ingest['maxBytes'];
      if (bytes != null) {
        if (bytes is! int || bytes < 1024) {
          throw ArgumentError.value(bytes, '$_section.ingest.maxBytes',
              'must be a whole number of bytes, 1024 or more');
        }
        maxBytes = bytes;
      }
    }

    return DVCrashConfig(
      disabledIn: disabledIn,
      sink: sink,
      nonFatalSampleRate: rate == null ? 1 : (rate as num).toDouble(),
      breadcrumbs: breadcrumbs == null ? 64 : breadcrumbs as int,
      fullReportsPerRelease: full == null ? 5 : full as int,
      identityConsent: identityConsent,
      ingestPerInstallPerHour: perInstallPerHour,
      ingestMaxBytes: maxBytes,
    );
  }

  /// The declaration this configuration reads back from: what the generator
  /// writes into the runtime, so the running application parses the same
  /// rules the build checked.
  Map<String, Object?> toDeclaration() => <String, Object?>{
        if (disabledIn.isNotEmpty)
          'disabledIn': <Object?>[
            for (final DVCrashBuildMode mode in DVCrashBuildMode.values)
              if (disabledIn.contains(mode)) mode.name,
          ],
        'sink': sink.name,
        'nonFatalSampleRate': nonFatalSampleRate,
        'breadcrumbs': breadcrumbs,
        'fullReportsPerRelease': fullReportsPerRelease,
        if (identityConsent != null)
          'identity': <String, Object?>{'consent': identityConsent!.name},
        'ingest': <String, Object?>{
          'perInstallPerHour': ingestPerInstallPerHour,
          'maxBytes': ingestMaxBytes,
        },
      };
}

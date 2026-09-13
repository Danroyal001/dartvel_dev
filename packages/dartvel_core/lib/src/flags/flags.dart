/// Feature flags: declared, typed, dated, and answered by one pure function of
/// a rule set and an evaluation context.
///
/// The generated `Flags.<name>` accessors read through here. So does a backend
/// function, with the request's own context, which is what makes the promise
/// "a client and the backend reach the same answer from the same two inputs"
/// a property of this file rather than of discipline.
library dartvel.flags;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../diagnostics/diagnostics.dart';
import '../observability/logging.dart';
import '../tenancy/tenants.dart';

/// Whether this is a release build. Overrides are only ever read when it is
/// not, so a release binary has no path that consults one.
const bool _dvReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// Who a percentage rollout is bucketed by.
enum DVFlagSubject { user, tenant, device }

/// When a changed rule reaches a flag that is already being read.
enum DVFlagSettle {
  /// As soon as the rule syncs. The default, because a kill switch that waits
  /// for a relaunch has not switched anything off.
  immediately,

  /// The first answer in a process is kept for the rest of it, for a flag whose
  /// mid-session flip would strand somebody halfway through a flow.
  onNextLaunch,
}

/// Where an answer came from.
enum DVFlagSource { override, rules, defaults }

/// A declared flag: its key, type, compiled default, owner and expiry.
///
/// Generated from `@DVFlags()` declarations rather than written by hand, so a
/// misspelt flag is a compile error instead of a lookup that silently misses.
class DVFeatureFlag<T> {
  const DVFeatureFlag({
    required this.key,
    required this.defaultValue,
    required this.owner,
    required this.expires,
    this.settle = DVFlagSettle.immediately,
    this.values,
  });

  /// The key the rule set names this flag by.
  final String key;

  /// The answer compiled into the build: what the flag says before anything
  /// syncs, and what every fallback falls back to.
  final T defaultValue;

  /// Who to ask about it, and who prunes it.
  final String owner;

  /// When it becomes debt. Past it the build warns, and `dartvel flags prune`
  /// lists it.
  final DateTime expires;

  final DVFlagSettle settle;

  /// The declared values of an enum flag, so a rule's value can be read back
  /// by name. Null for `bool`, `String`, `int` and `double` flags.
  final List<T>? values;

  /// The current answer for the ambient context.
  T get value => DVFlags.resolve(this).value;

  bool isExpired(DateTime now) => expires.isBefore(now);

  @override
  String toString() => 'DVFeatureFlag<$T>($key)';
}

/// Everything an answer may depend on.
///
/// Identity, tenant, organization role, app version, platform, locale, and any
/// attributes the application declares. Nothing ambient is read during
/// evaluation: the same context and the same rules give the same answer on a
/// phone and in a backend function.
class DVFlagContext {
  const DVFlagContext({
    this.userId,
    this.tenantId,
    this.deviceId,
    this.organizationRole,
    this.appVersion,
    this.platform,
    this.locale,
    this.attributes = const <String, Object?>{},
  });

  final String? userId;
  final String? tenantId;
  final String? deviceId;
  final String? organizationRole;
  final String? appVersion;
  final String? platform;
  final String? locale;
  final Map<String, Object?> attributes;

  /// The identifier a rollout by [subject] buckets on, or null when this
  /// context has none.
  String? subjectFor(DVFlagSubject subject) => switch (subject) {
        DVFlagSubject.user => userId,
        DVFlagSubject.tenant => tenantId,
        DVFlagSubject.device => deviceId,
      };

  /// A stable string for "the same evaluation context", used to record an
  /// exposure once per context rather than once per read.
  String get fingerprint => jsonEncode(<Object?>[
        userId,
        tenantId,
        deviceId,
        organizationRole,
        appVersion,
        platform,
        locale,
        <String, Object?>{
          for (final String k in attributes.keys.toList()..sort())
            k: '${attributes[k]}',
        },
      ]);
}

/// A percentage of a population, chosen by hashing rather than by chance.
class DVFlagRollout {
  const DVFlagRollout._(this.basisPoints, this.by);

  /// [percent] of subjects identified by [by], from 0 to 100.
  factory DVFlagRollout.percentage(num percent, {required DVFlagSubject by}) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(percent, 'percent', 'must be 0 to 100');
    }
    return DVFlagRollout._((percent * 100).round(), by);
  }

  /// The threshold, out of 10,000.
  final int basisPoints;
  final DVFlagSubject by;

  /// A subject's bucket for a flag: the first eight bytes of
  /// `SHA-256("$flagKey:$subjectId")`, big-endian, modulo 10,000.
  ///
  /// Nothing is stored, so the same person gets the same answer on every
  /// device and after every reinstall. The flag key is inside the hash, so two
  /// flags at ten percent do not pick the same tenth. And a subject is in when
  /// its bucket is below the threshold, so raising the percentage only ever
  /// adds people. Arithmetic on a `BigInt`, because a web build's integers are
  /// doubles and eight bytes do not fit in one.
  static int bucket(String flagKey, String subjectId) {
    final List<int> digest =
        sha256.convert(utf8.encode('$flagKey:$subjectId')).bytes;
    BigInt value = BigInt.zero;
    for (int i = 0; i < 8; i++) {
      value = (value << 8) | BigInt.from(digest[i]);
    }
    return (value % BigInt.from(10000)).toInt();
  }

  bool includes(String flagKey, String subjectId) =>
      bucket(flagKey, subjectId) < basisPoints;

  Map<String, Object?> toJson() => <String, Object?>{
        'percentage':
            basisPoints % 100 == 0 ? basisPoints ~/ 100 : basisPoints / 100,
        'by': by.name,
      };

  static DVFlagRollout? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? percentage = json['percentage'];
    final Object? by = json['by'];
    if (percentage is! num || percentage < 0 || percentage > 100) return null;
    final DVFlagSubject? subject = DVFlagSubject.values
        .where((DVFlagSubject s) => s.name == by)
        .firstOrNull;
    if (subject == null) return null;
    return DVFlagRollout.percentage(percentage, by: subject);
  }
}

/// Who a rule applies to. Every stated condition must hold; an absent one does
/// not restrict.
class DVFlagTarget {
  const DVFlagTarget({
    this.platforms,
    this.tenants,
    this.organizationRoles,
    this.locales,
    this.minAppVersion,
    this.maxAppVersion,
    this.attributes = const <String, Object?>{},
  });

  final List<String>? platforms;
  final List<String>? tenants;
  final List<String>? organizationRoles;
  final List<String>? locales;

  /// Inclusive.
  final String? minAppVersion;

  /// Exclusive.
  final String? maxAppVersion;
  final Map<String, Object?> attributes;

  bool matches(DVFlagContext context) {
    if (!_inList(platforms, context.platform)) return false;
    if (!_inList(tenants, context.tenantId)) return false;
    if (!_inList(organizationRoles, context.organizationRole)) return false;
    if (!_inList(locales, context.locale)) return false;
    if (minAppVersion != null || maxAppVersion != null) {
      final String? version = context.appVersion;
      if (version == null) return false;
      if (minAppVersion != null &&
          _compareVersions(version, minAppVersion!) < 0) {
        return false;
      }
      if (maxAppVersion != null &&
          _compareVersions(version, maxAppVersion!) >= 0) {
        return false;
      }
    }
    for (final MapEntry<String, Object?> wanted in attributes.entries) {
      if (context.attributes[wanted.key] != wanted.value) return false;
    }
    return true;
  }

  static bool _inList(List<String>? allowed, String? value) =>
      allowed == null || (value != null && allowed.contains(value));

  Map<String, Object?> toJson() => <String, Object?>{
        if (platforms != null) 'platforms': platforms,
        if (tenants != null) 'tenants': tenants,
        if (organizationRoles != null) 'organizationRoles': organizationRoles,
        if (locales != null) 'locales': locales,
        if (minAppVersion != null || maxAppVersion != null)
          'appVersion': <String, Object?>{
            if (minAppVersion != null) 'min': minAppVersion,
            if (maxAppVersion != null) 'max': maxAppVersion,
          },
        if (attributes.isNotEmpty) 'attributes': attributes,
      };

  static DVFlagTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String>? strings(Object? v) =>
        v is List ? <String>[for (final Object? e in v) '$e'] : null;
    final Object? version = json['appVersion'];
    final Object? attributes = json['attributes'];
    return DVFlagTarget(
      platforms: strings(json['platforms']),
      tenants: strings(json['tenants']),
      organizationRoles: strings(json['organizationRoles']),
      locales: strings(json['locales']),
      minAppVersion: version is Map ? version['min'] as String? : null,
      maxAppVersion: version is Map ? version['max'] as String? : null,
      attributes: attributes is Map
          ? <String, Object?>{
              for (final MapEntry<Object?, Object?> e in attributes.entries)
                '${e.key}': e.value,
            }
          : const <String, Object?>{},
    );
  }
}

/// Dotted numeric comparison: `2.10.0` is after `2.3.0`, which a string
/// comparison gets backwards. A pre-release or build suffix is ignored.
int _compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp('[-+]'))
      .first
      .split('.')
      .map((String p) => int.tryParse(p) ?? 0)
      .toList();
  final List<int> x = parts(a);
  final List<int> y = parts(b);
  for (int i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final int xi = i < x.length ? x[i] : 0;
    final int yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

/// One rule: a value, for whoever the target and rollout admit.
class DVFlagRule {
  const DVFlagRule({required this.value, this.target, this.rollout});

  final Object? value;
  final DVFlagTarget? target;
  final DVFlagRollout? rollout;

  Map<String, Object?> toJson() => <String, Object?>{
        'value': value,
        if (target != null) 'target': target!.toJson(),
        if (rollout != null) 'rollout': rollout!.toJson(),
      };
}

/// The rules one environment publishes: every flag the deployment knows, in
/// order, and the version that identifies this set.
class DVFlagRules {
  const DVFlagRules({required this.rulesVersion, required this.flags});

  /// The newest document format this build reads.
  static const int supportedFormat = 1;

  final int rulesVersion;
  final Map<String, List<DVFlagRule>> flags;

  /// Reads a published rule set.
  ///
  /// A rule this build cannot read — a newer format's rollout subject, a
  /// malformed target — is skipped rather than guessed at, and
  /// `DV-FLAGS-003` says so through [report]. The rest of the set is still
  /// used: one unreadable rule is not a reason to abandon the kill switches
  /// beside it.
  factory DVFlagRules.fromJson(
    Map<String, Object?> json, {
    void Function(String code, String message)? report,
  }) {
    final Object? format = json['format'];
    bool skipped = format is int && format > supportedFormat;
    final Map<String, List<DVFlagRule>> flags = <String, List<DVFlagRule>>{};
    final Object? rawFlags = json['flags'];
    if (rawFlags is Map) {
      for (final MapEntry<Object?, Object?> entry in rawFlags.entries) {
        final List<DVFlagRule> rules = <DVFlagRule>[];
        final Object? rawRules = entry.value;
        if (rawRules is List) {
          for (final Object? rawRule in rawRules) {
            final DVFlagRule? rule = _readRule(rawRule);
            if (rule == null) {
              skipped = true;
            } else {
              rules.add(rule);
            }
          }
        } else {
          skipped = true;
        }
        flags['${entry.key}'] = rules;
      }
    }
    if (skipped) {
      report?.call(
        'DV-FLAGS-003',
        'the rule set is newer than this build understands; unreadable rules '
            'were skipped',
      );
    }
    final Object? version = json['rulesVersion'];
    return DVFlagRules(
      rulesVersion: version is int ? version : 0,
      flags: flags,
    );
  }

  static DVFlagRule? _readRule(Object? json) {
    if (json is! Map || !json.containsKey('value')) return null;
    DVFlagTarget? target;
    if (json.containsKey('target')) {
      target = DVFlagTarget.fromJson(json['target']);
      if (target == null) return null;
    }
    DVFlagRollout? rollout;
    if (json.containsKey('rollout')) {
      rollout = DVFlagRollout.fromJson(json['rollout']);
      if (rollout == null) return null;
    }
    return DVFlagRule(value: json['value'], target: target, rollout: rollout);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'format': supportedFormat,
        'rulesVersion': rulesVersion,
        'flags': <String, Object?>{
          for (final MapEntry<String, List<DVFlagRule>> e in flags.entries)
            e.key: <Object?>[for (final DVFlagRule r in e.value) r.toJson()],
        },
      };
}

/// An answer, where it came from, and what was worth reporting about it.
class DVFlagResolution<T> {
  const DVFlagResolution({
    required this.value,
    required this.source,
    this.rulesVersion,
    this.codes = const <String>[],
  });

  final T value;
  final DVFlagSource source;

  /// The rule set that served [value], when one did.
  final int? rulesVersion;

  /// Diagnostic codes this evaluation produced.
  final List<String> codes;
}

/// The first time a flag was resolved for an evaluation context in a session.
class DVFlagExposure {
  const DVFlagExposure({
    required this.key,
    required this.value,
    required this.rulesVersion,
  });

  final String key;
  final Object? value;
  final int? rulesVersion;

  /// As the Product Analytics event it is recorded as.
  Map<String, Object?> toEvent() => <String, Object?>{
        'event': 'dartvel.flag_exposed',
        'flag': key,
        'value': value,
        'rulesVersion': rulesVersion,
      };
}

/// The flag runtime: the synced rules, the evaluation context, and resolution.
final class DVFlags {
  /// `@DVFlags()` marks the private class a build generates `Flags` from. The
  /// same name as the runtime on purpose: the declaration and the thing that
  /// answers for it are one concept.
  const DVFlags();

  static const Symbol _zoneOverrides = #dartvelFlagOverrides;

  static DVFlagRules? _rules;
  static DateTime? _receivedAt;
  static final Map<String, DVFeatureFlag<Object?>> _declared =
      <String, DVFeatureFlag<Object?>>{};
  static final Map<String, Object?> _pins = <String, Object?>{};
  static final Set<String> _exposed = <String>{};
  static final Set<String> _reportedOnce = <String>{};
  static StreamController<void> _changes = StreamController<void>.broadcast();
  static final DVLogger _logger = DVLogger();

  /// Past this age a synced rule set is reported on every resolve — and still
  /// used. Stale rules are not discarded: a kill switch that expires back to
  /// "on" for the devices hardest to reach is worse than one a day old.
  static Duration? maxAge;

  /// The evaluation context for reads that do not pass one.
  static DVFlagContext Function() context = _defaultContext;

  /// Where diagnostics go. Logged at the registry's level by default.
  static void Function(String code, String message) onDiagnostic =
      _logDiagnostic;

  /// Receives each exposure, once per flag per context per session.
  static void Function(DVFlagExposure exposure)? onExposure;

  /// Whether exposure may be recorded. When it answers false nothing is
  /// recorded and `DV-FLAGS-007` says the experiment is missing people.
  static bool Function()? exposureConsent;

  /// The rule set in force, or null before the first sync.
  static DVFlagRules? get rules => _rules;

  /// When [rules] arrived.
  static DateTime? get rulesReceivedAt => _receivedAt;

  /// Fires when the rule set changes, so a signal over a flag can rebuild.
  static Stream<void> get changes => _changes.stream;

  static DVFlagContext _defaultContext() =>
      DVFlagContext(tenantId: const DVTenants().currentTenant);

  static void _logDiagnostic(String code, String message) {
    final String level = DVDiagnostics.all
            .where((DVDiagnostic d) => d.code == code)
            .firstOrNull
            ?.level ??
        'warning';
    _logger.log(
      '$code: $message',
      level: switch (level) {
        'debug' => DVLogLevel.debug,
        'info' => DVLogLevel.info,
        'error' => DVLogLevel.error,
        _ => DVLogLevel.warn,
      },
      context: <String, Object?>{'code': code},
    );
  }

  /// Registers the flags this build declares. The generated accessors call
  /// it, which is how a rule set naming an unknown flag gets noticed and how
  /// `dartvel flags prune` knows what is due.
  static void declare(Iterable<DVFeatureFlag<Object?>> flags) {
    for (final DVFeatureFlag<Object?> flag in flags) {
      _declared[flag.key] = flag;
    }
  }

  /// Every declared flag.
  static List<DVFeatureFlag<Object?>> get declared =>
      List<DVFeatureFlag<Object?>>.unmodifiable(_declared.values);

  /// Declared flags past their expiry at [now], in declaration order.
  static List<DVFeatureFlag<Object?>> expired(DateTime now) => <DVFeatureFlag<Object?>>[
        for (final DVFeatureFlag<Object?> flag in _declared.values)
          if (flag.isExpired(now)) flag,
      ];

  /// Installs a synced rule set.
  static void setRules(DVFlagRules? rules, {DateTime? receivedAt}) {
    _rules = rules;
    _receivedAt = rules == null ? null : (receivedAt ?? DateTime.now().toUtc());
    if (rules != null && _declared.isNotEmpty) {
      for (final String key in rules.flags.keys) {
        if (!_declared.containsKey(key)) {
          onDiagnostic(
            'DV-FLAGS-002',
            'the synced rule set names "$key", which this build does not '
                'declare',
          );
        }
      }
    }
    _changes.add(null);
  }

  /// Runs [body] with [overrides] in force for it and for nothing else.
  ///
  /// Zone-scoped, so an override follows the callback across awaits and a
  /// test's flags never leak into the next test. Ignored in a release build.
  static Future<R> withOverrides<R>(
    Map<String, Object?> overrides,
    Future<R> Function() body,
  ) {
    final Map<String, Object?> merged = <String, Object?>{
      ..._currentOverrides(),
      ...overrides,
    };
    return runZoned(body, zoneValues: <Object?, Object?>{
      _zoneOverrides: merged,
    });
  }

  static Map<String, Object?> _currentOverrides() =>
      (Zone.current[_zoneOverrides] as Map<String, Object?>?) ??
      const <String, Object?>{};

  /// The answer for [flag], reported, pinned and exposed as the spec says.
  static DVFlagResolution<T> resolve<T>(
    DVFeatureFlag<T> flag, {
    DVFlagContext? context,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now().toUtc();
    final DVFlagContext ctx = context ?? DVFlags.context();

    if (flag.isExpired(at) && _reportedOnce.add('004:${flag.key}')) {
      onDiagnostic(
        'DV-FLAGS-004',
        '"${flag.key}" is past its declared expiry '
            '(${flag.expires.toIso8601String()}), owner ${flag.owner}',
      );
    }

    if (flag.settle == DVFlagSettle.onNextLaunch &&
        _pins.containsKey(flag.key)) {
      return _pins[flag.key]! as DVFlagResolution<T>;
    }

    final DVFlagResolution<T> resolution = evaluate(
      flag,
      _rules,
      ctx,
      overrides: _currentOverrides(),
      allowOverrides: !_dvReleaseBuild,
    );

    for (final String code in resolution.codes) {
      switch (code) {
        case 'DV-FLAGS-001':
          if (_reportedOnce.add('001')) {
            onDiagnostic(code,
                'no rule set has synced; flags answered with the defaults '
                'compiled into the build');
          }
        case 'DV-FLAGS-005':
          onDiagnostic(code,
              '"${flag.key}" has a percentage rollout and the context has no '
              'subject for it; the flag held its default');
        case 'DV-FLAGS-006':
          onDiagnostic(code,
              "a rule's value for \"${flag.key}\" is not a $T; the flag held "
              'its default');
        case 'DV-FLAGS-008':
          onDiagnostic(code,
              'a local override is in force for "${flag.key}"; this build is '
              'not answering from the rules');
      }
    }

    final Duration? limit = maxAge;
    final DateTime? received = _receivedAt;
    if (_rules != null &&
        limit != null &&
        received != null &&
        at.difference(received) > limit) {
      onDiagnostic(
        'DV-FLAGS-009',
        'the rule set is older than flags.maxAge (${at.difference(received)}) '
            'and is still in use',
      );
    }

    if (flag.settle == DVFlagSettle.onNextLaunch) {
      _pins[flag.key] = resolution;
    }

    _expose(flag, resolution, ctx);
    return resolution;
  }

  static void _expose<T>(
    DVFeatureFlag<T> flag,
    DVFlagResolution<T> resolution,
    DVFlagContext ctx,
  ) {
    final void Function(DVFlagExposure)? sink = onExposure;
    if (sink == null) return;
    final String seen = '${flag.key}|${ctx.fingerprint}';
    if (!_exposed.add(seen)) return;
    final bool Function()? consent = exposureConsent;
    if (consent != null && !consent()) {
      onDiagnostic(
        'DV-FLAGS-007',
        'exposure of "${flag.key}" not recorded: consent was withheld for the '
            'declared analytics category',
      );
      return;
    }
    sink(DVFlagExposure(
      key: flag.key,
      value: resolution.value,
      rulesVersion: resolution.rulesVersion,
    ));
  }

  /// The pure evaluation: an override if allowed, then the first rule that
  /// admits [context], then the compiled default.
  ///
  /// No clock, no storage, no randomness — which is what lets a client and a
  /// backend function agree.
  static DVFlagResolution<T> evaluate<T>(
    DVFeatureFlag<T> flag,
    DVFlagRules? rules,
    DVFlagContext context, {
    Map<String, Object?> overrides = const <String, Object?>{},
    bool allowOverrides = true,
  }) {
    DVFlagResolution<T> fallback(List<String> codes) => DVFlagResolution<T>(
          value: flag.defaultValue,
          source: DVFlagSource.defaults,
          codes: codes,
        );

    if (allowOverrides && overrides.containsKey(flag.key)) {
      final (bool, T?) read = _read(flag, overrides[flag.key]);
      if (read.$1) {
        return DVFlagResolution<T>(
          value: read.$2 as T,
          source: DVFlagSource.override,
          codes: const <String>['DV-FLAGS-008'],
        );
      }
    }

    if (rules == null) return fallback(const <String>['DV-FLAGS-001']);

    final List<DVFlagRule>? entry = rules.flags[flag.key];
    if (entry == null) return fallback(const <String>[]);

    for (final DVFlagRule rule in entry) {
      final DVFlagTarget? target = rule.target;
      if (target != null && !target.matches(context)) continue;
      final DVFlagRollout? rollout = rule.rollout;
      if (rollout != null) {
        final String? subject = context.subjectFor(rollout.by);
        // Held, not rolled: a flag that flickers between two frames is a bug
        // report nobody can reproduce.
        if (subject == null) return fallback(const <String>['DV-FLAGS-005']);
        if (!rollout.includes(flag.key, subject)) continue;
      }
      final (bool, T?) read = _read(flag, rule.value);
      if (!read.$1) return fallback(const <String>['DV-FLAGS-006']);
      return DVFlagResolution<T>(
        value: read.$2 as T,
        source: DVFlagSource.rules,
        rulesVersion: rules.rulesVersion,
      );
    }
    return fallback(const <String>[]);
  }

  /// Reads [raw] as the flag's declared type, without coercion: `"true"` is
  /// not a bool and `2.5` is not an int. An `int` is accepted for a `double`
  /// flag, because JSON does not distinguish `1` from `1.0`.
  static (bool, T?) _read<T>(DVFeatureFlag<T> flag, Object? raw) {
    final List<T>? values = flag.values;
    if (values != null) {
      if (raw is! String) return (false, null);
      for (final T v in values) {
        if (v is Enum && v.name == raw) return (true, v);
      }
      return (false, null);
    }
    final T defaultValue = flag.defaultValue;
    if (defaultValue is double) {
      return raw is num ? (true, raw.toDouble() as T) : (false, null);
    }
    if (defaultValue is int) {
      return raw is int ? (true, raw as T) : (false, null);
    }
    if (defaultValue is bool) {
      return raw is bool ? (true, raw as T) : (false, null);
    }
    if (defaultValue is String) {
      return raw is String ? (true, raw as T) : (false, null);
    }
    return raw is T ? (true, raw) : (false, null);
  }

  /// Clears every piece of process state, for tests.
  static void resetForTest() {
    _rules = null;
    _receivedAt = null;
    _declared.clear();
    _pins.clear();
    _exposed.clear();
    _reportedOnce.clear();
    maxAge = null;
    context = _defaultContext;
    onDiagnostic = _logDiagnostic;
    onExposure = null;
    exposureConsent = null;
    unawaited(_changes.close());
    _changes = StreamController<void>.broadcast();
  }
}

/// Marks one flag inside a `@DVFlags()` class.
///
/// ```dart
/// @DVFlags()
/// abstract class _Flags {
///   @DVFlag(owner: 'payments', expires: '2026-12-01')
///   static const bool newCheckout = false;
/// }
/// ```
///
/// The field's initializer is the default compiled into the build. [expires]
/// is required: a flag is debt with an owner and a date on it.
class DVFlag {
  const DVFlag({
    required this.owner,
    required this.expires,
    this.settle = DVFlagSettle.immediately,
  });

  final String owner;

  /// `YYYY-MM-DD`.
  final String expires;
  final DVFlagSettle settle;
}

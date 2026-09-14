/// Consent for measurement: declared categories, the choices people make
/// about them, and the record each choice leaves.
///
/// Every failure this guards against is silent. A category nobody can be
/// asked about on some platform is denied for ever there and nobody knows
/// why. A choice made under last year's categories quietly stands for this
/// year's. A grant the database never stored is honoured anyway, and the
/// evidence that consent existed is missing exactly when somebody asks for it.
library dartvel_core.analytics.consent;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/adapter.dart';
import '../diagnostics/diagnostics.dart';
import '../observability/logging.dart';

/// A purpose somebody can consent to, by name.
///
/// A constant rather than a string at each call, so a misspelt category is a
/// compile error instead of a second category that is denied for ever.
final class DVConsentCategory {
  const DVConsentCategory(this.name);

  /// What the application needs to function. Declared `required`, never
  /// asked, always granted.
  static const DVConsentCategory essential = DVConsentCategory('essential');

  final String name;

  @override
  bool operator ==(Object other) =>
      other is DVConsentCategory && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'DVConsentCategory($name)';
}

/// One category as the policy declares it.
final class DVConsentDeclaration {
  const DVConsentDeclaration(
    this.category, {
    this.required = false,
    bool? defaultGranted,
    this.tracking = false,
  }) : _defaultGranted = defaultGranted;

  final DVConsentCategory category;

  /// Needed for the application to work: always granted and never asked.
  final bool required;

  final bool? _defaultGranted;

  /// The state before anybody answers. Denied unless declared otherwise, and
  /// always granted for a required category.
  bool get defaultGranted => _defaultGranted ?? required;

  /// Whether the category implies tracking across other companies' apps and
  /// sites, which on iOS and tvOS means the App Tracking Transparency prompt.
  final bool tracking;
}

/// How a platform asks.
enum DVConsentPrompt { banner, appTrackingTransparency, settingsScreen }

/// A build target and the ways it has of asking.
final class DVConsentTarget {
  const DVConsentTarget(
    this.name, {
    required this.prompts,
    this.tracksWithAppTrackingTransparency = false,
  });

  static const DVConsentTarget web = DVConsentTarget(
    'web',
    prompts: <DVConsentPrompt>{
      DVConsentPrompt.banner,
      DVConsentPrompt.settingsScreen,
    },
  );
  static const DVConsentTarget ios = DVConsentTarget(
    'ios',
    prompts: <DVConsentPrompt>{
      DVConsentPrompt.settingsScreen,
      DVConsentPrompt.appTrackingTransparency,
    },
    tracksWithAppTrackingTransparency: true,
  );
  static const DVConsentTarget tvos = DVConsentTarget(
    'tvos',
    prompts: <DVConsentPrompt>{
      DVConsentPrompt.settingsScreen,
      DVConsentPrompt.appTrackingTransparency,
    },
    tracksWithAppTrackingTransparency: true,
  );
  static const DVConsentTarget android = DVConsentTarget(
    'android',
    prompts: <DVConsentPrompt>{DVConsentPrompt.settingsScreen},
  );
  static const DVConsentTarget macos = DVConsentTarget(
    'macos',
    prompts: <DVConsentPrompt>{DVConsentPrompt.settingsScreen},
  );
  static const DVConsentTarget windows = DVConsentTarget(
    'windows',
    prompts: <DVConsentPrompt>{DVConsentPrompt.settingsScreen},
  );
  static const DVConsentTarget linux = DVConsentTarget(
    'linux',
    prompts: <DVConsentPrompt>{DVConsentPrompt.settingsScreen},
  );

  final String name;
  final Set<DVConsentPrompt> prompts;

  /// Whether a tracking category needs the App Tracking Transparency prompt
  /// here rather than any prompt at all.
  final bool tracksWithAppTrackingTransparency;
}

/// A problem with the declarations, found before anything runs.
final class DVAnalyticsFinding {
  const DVAnalyticsFinding({
    required this.code,
    required this.category,
    required this.target,
    required this.message,
  });

  final String code;
  final String category;
  final String? target;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// The declared categories, and the version somebody set for them.
final class DVConsentPolicy {
  DVConsentPolicy({
    required this.version,
    required List<DVConsentDeclaration> categories,
  }) : categories = List<DVConsentDeclaration>.unmodifiable(categories) {
    if (version.trim().isEmpty) {
      throw ArgumentError.value(version, 'version', 'must be set');
    }
    final Set<String> names = <String>{};
    for (final DVConsentDeclaration d in categories) {
      if (!names.add(d.category.name)) {
        throw ArgumentError.value(
            d.category.name, 'category', 'is declared twice');
      }
      if (d.required && !d.defaultGranted) {
        throw ArgumentError.value(d.category.name, 'category',
            'is required and cannot default to denied');
      }
    }
  }

  /// Reads `dartvel.analytics.consent` from `pubspec.yaml`.
  ///
  /// The version is required. Without one a changed set of categories could
  /// never ask again, and every earlier answer would stand for purposes
  /// nobody was asked about.
  ///
  /// Read strictly. A key it does not know is refused rather than skipped:
  /// `tracknig: true` skipped is a tracking category that never shows the App
  /// Tracking Transparency prompt, and `required: "yes"` read as false is a
  /// category the application needs defaulting to denied. Neither throws
  /// anywhere later, so the configuration is the only place to catch them.
  factory DVConsentPolicy.fromConfig(Map<String, Object?> consent) {
    for (final String key in consent.keys) {
      if (!_consentKeys.contains(key)) {
        throw ArgumentError.value(key, 'consent',
            'is not a consent setting; accepted: ${_consentKeys.join(', ')}');
      }
    }
    final Object? version = consent['version'];
    if (version == null || '$version'.trim().isEmpty) {
      throw ArgumentError.value(consent, 'consent',
          'declares no version; a changed policy could never ask again');
    }
    final Object? raw = consent['categories'];
    if (raw is! Map) {
      throw ArgumentError.value(raw, 'categories', 'must be a map');
    }
    final List<DVConsentDeclaration> declarations = <DVConsentDeclaration>[];
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      final Object? body = entry.value;
      if (body != null && body is! Map) {
        throw ArgumentError.value(body, '${entry.key}',
            'must be a map of ${_categoryKeys.join(', ')}, such as '
                '{ default: denied }');
      }
      final Map<Object?, Object?> fields =
          body is Map ? body : const <Object?, Object?>{};
      for (final Object? key in fields.keys) {
        if (!_categoryKeys.contains(key)) {
          throw ArgumentError.value(key, '${entry.key}',
              'is not a category setting; accepted: ${_categoryKeys.join(', ')}');
        }
      }
      bool flag(String key) {
        final Object? value = fields[key];
        if (value == null) return false;
        if (value is bool) return value;
        throw ArgumentError.value(
            value, '${entry.key}.$key', 'must be true or false');
      }

      final bool required = flag('required');
      final bool tracking = flag('tracking');
      final Object? def = fields['default'];
      final bool? granted = switch (def) {
        null => null,
        'denied' => false,
        'granted' => true,
        _ => throw ArgumentError.value(def, '${entry.key}.default',
            'must be granted or denied'),
      };
      declarations.add(DVConsentDeclaration(
        DVConsentCategory('${entry.key}'),
        required: required,
        defaultGranted: granted,
        tracking: tracking,
      ));
    }
    return DVConsentPolicy(version: '$version', categories: declarations);
  }

  static const List<String> _consentKeys = <String>['version', 'categories'];
  static const List<String> _categoryKeys = <String>[
    'required',
    'default',
    'tracking',
  ];

  final String version;
  final List<DVConsentDeclaration> categories;

  DVConsentDeclaration? declaration(DVConsentCategory category) {
    for (final DVConsentDeclaration d in categories) {
      if (d.category == category) return d;
    }
    return null;
  }

  /// The categories somebody can be asked about.
  Iterable<DVConsentDeclaration> get askable =>
      categories.where((DVConsentDeclaration d) => !d.required);

  /// `DV-ANALYTICS-002` for every declared category with no way to ask on a
  /// target the application builds for.
  List<DVAnalyticsFinding> check({required List<DVConsentTarget> targets}) =>
      <DVAnalyticsFinding>[
        for (final DVConsentTarget target in targets)
          for (final DVConsentDeclaration d in askable)
            if (target.prompts.isEmpty ||
                (d.tracking &&
                    target.tracksWithAppTrackingTransparency &&
                    !target.prompts
                        .contains(DVConsentPrompt.appTrackingTransparency)))
              DVAnalyticsFinding(
                code: 'DV-ANALYTICS-002',
                category: d.category.name,
                target: target.name,
                message: target.prompts.isEmpty
                    ? '"${d.category.name}" cannot be asked about on '
                        '${target.name}, so it would be denied there for ever'
                    : '"${d.category.name}" implies tracking and '
                        '${target.name} has no App Tracking Transparency '
                        'prompt',
              ),
      ];
}

/// One choice, as it was recorded.
final class DVConsentRecord {
  const DVConsentRecord({
    required this.id,
    required this.seq,
    required this.installId,
    required this.userId,
    required this.policyVersion,
    required this.asked,
    required this.answers,
    required this.prompt,
    required this.recordedAt,
  });

  final String id;
  final int seq;
  final String installId;
  final String? userId;
  final String policyVersion;
  final Set<String> asked;
  final Map<String, bool> answers;
  final DVConsentPrompt prompt;
  final DateTime recordedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'seq': seq,
        'installId': installId,
        'userId': userId,
        'policyVersion': policyVersion,
        'asked': (asked.toList()..sort()),
        'answers': answers,
        'prompt': prompt.name,
        'recordedAt': recordedAt.toIso8601String(),
      };

  static DVConsentRecord fromRow(Map<String, Object?> row) {
    final Object? answers = jsonDecode('${row['answers']}');
    return DVConsentRecord(
      id: '${row['id']}',
      seq: row['seq'] is int ? row['seq']! as int : int.parse('${row['seq']}'),
      installId: '${row['install_id']}',
      userId: row['user_id'] as String?,
      policyVersion: '${row['policy_version']}',
      asked: <String>{
        for (final Object? a in jsonDecode('${row['asked']}') as List) '$a',
      },
      answers: <String, bool>{
        for (final MapEntry<Object?, Object?> e in (answers as Map).entries)
          '${e.key}': e.value == true,
      },
      prompt: DVConsentPrompt.values.byName('${row['prompt']}'),
      recordedAt: DateTime.parse('${row['recorded_at']}'),
    );
  }
}

/// Which categories a change granted and which it withdrew.
final class DVConsentChange {
  const DVConsentChange({required this.granted, required this.withdrawn});

  final Set<DVConsentCategory> granted;
  final Set<DVConsentCategory> withdrawn;
}

/// The consent state of one install, read from its records.
class DVConsent {
  DVConsent({
    required this.policy,
    required this.database,
    required this.installId,
    DateTime Function()? clock,
    void Function(String code, String message)? onDiagnostic,
  })  : _clock = clock ?? DateTime.now,
        _diagnose = onDiagnostic ?? dvLogAnalyticsDiagnostic;

  static const String table = 'dv_consent_records';

  final DVConsentPolicy policy;
  final DVDatabaseAdapter database;

  /// The install the prompt was shown on. Consent is asked on a device before
  /// anybody signs in, so it belongs to the install, with the user recorded
  /// beside it when one is known.
  final String installId;

  final DateTime Function() _clock;
  final void Function(String code, String message) _diagnose;

  /// Answers recorded under the current policy version, or null when there
  /// are none.
  Map<String, bool>? _answers;

  /// Withdrawals that could not be written: collection stops anyway, since
  /// stopping loses nothing, but they are not evidence of anything.
  final Set<String> _unrecordedWithdrawals = <String>{};

  final List<void Function(DVConsentChange change)> _listeners =
      <void Function(DVConsentChange change)>[];

  Future<void> ensureSchema() => database.execute(
        'CREATE TABLE IF NOT EXISTS $table (id, seq, install_id, user_id, '
        'policy_version, asked, answers, prompt, recorded_at)',
      );

  /// Reads the latest choice for this install. A choice made under another
  /// version of the categories is not consent to this one, so it leaves every
  /// category at its default and [needsPrompt] true.
  ///
  /// Listeners are not told: loading is reading what was already so.
  Future<void> load() async {
    final List<DVConsentRecord> mine = await records();
    _answers = null;
    if (mine.isEmpty) return;
    final DVConsentRecord latest = mine.last;
    if (latest.policyVersion == policy.version) {
      _answers = Map<String, bool>.of(latest.answers);
    }
  }

  /// Whether nobody has answered under the current version.
  bool get needsPrompt => _answers == null;

  DVConsentDeclaration _declared(DVConsentCategory category) {
    final DVConsentDeclaration? d = policy.declaration(category);
    if (d == null) {
      throw ArgumentError.value(category.name, 'category',
          'is not declared in the consent policy ${policy.version}');
    }
    return d;
  }

  bool isGranted(DVConsentCategory category) {
    final DVConsentDeclaration d = _declared(category);
    if (d.required) return true;
    if (_unrecordedWithdrawals.contains(category.name)) return false;
    return _answers?[category.name] ?? d.defaultGranted;
  }

  /// [userId] when [category] is granted, and null otherwise: an identity
  /// bound to a purpose goes where the purpose goes and nowhere else.
  String? boundIdentity(DVConsentCategory category, {required String? userId}) =>
      isGranted(category) ? userId : null;

  void addListener(void Function(DVConsentChange change) listener) =>
      _listeners.add(listener);

  void removeListener(void Function(DVConsentChange change) listener) =>
      _listeners.remove(listener);

  /// Records a choice, and returns whether it was written.
  ///
  /// A grant that cannot be written is not treated as consent
  /// (`DV-ANALYTICS-006`). A withdrawal that cannot be written still stops
  /// collection, because stopping loses nothing, and is reported the same
  /// way. A category that was [asked] and not answered is denied.
  Future<bool> record(
    Map<DVConsentCategory, bool> answers, {
    Set<DVConsentCategory>? asked,
    DVConsentPrompt prompt = DVConsentPrompt.settingsScreen,
    String? userId,
  }) async {
    final Set<DVConsentCategory> presented = <DVConsentCategory>{
      ...?asked,
      ...answers.keys,
    };
    for (final DVConsentCategory c in presented) {
      _declared(c);
    }
    final Map<String, bool> resolved = <String, bool>{
      for (final DVConsentCategory c in presented)
        if (!_declared(c).required) c.name: answers[c] ?? false,
    };
    final Map<DVConsentCategory, bool> before = _snapshot();

    final DateTime at = _clock().toUtc();
    try {
      final List<DVConsentRecord> mine = await records();
      final int seq = mine.isEmpty ? 1 : mine.last.seq + 1;
      await database.execute(
        'INSERT INTO $table (id, seq, install_id, user_id, policy_version, '
        'asked, answers, prompt, recorded_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          _randomId(),
          seq,
          installId,
          userId,
          policy.version,
          jsonEncode(resolved.keys.toList()..sort()),
          jsonEncode(resolved),
          prompt.name,
          at.toIso8601String(),
        ],
      );
    } on Object catch (error) {
      _diagnose(
        'DV-ANALYTICS-006',
        'a consent choice could not be recorded ($error); it is not treated '
            'as consent',
      );
      for (final MapEntry<String, bool> e in resolved.entries) {
        if (!e.value) _unrecordedWithdrawals.add(e.key);
      }
      _notify(before);
      return false;
    }

    _answers = <String, bool>{
      // A partial choice under the same version keeps the earlier answers
      // for the categories it did not present.
      ...?_answers,
      ...resolved,
    };
    _unrecordedWithdrawals.removeAll(resolved.keys);
    _notify(before);
    return true;
  }

  Map<DVConsentCategory, bool> _snapshot() => <DVConsentCategory, bool>{
        for (final DVConsentDeclaration d in policy.categories)
          d.category: isGranted(d.category),
      };

  void _notify(Map<DVConsentCategory, bool> before) {
    final Map<DVConsentCategory, bool> after = _snapshot();
    final DVConsentChange change = DVConsentChange(
      granted: <DVConsentCategory>{
        for (final DVConsentCategory c in after.keys)
          if (after[c]! && !before[c]!) c,
      },
      withdrawn: <DVConsentCategory>{
        for (final DVConsentCategory c in after.keys)
          if (!after[c]! && before[c]!) c,
      },
    );
    if (change.granted.isEmpty && change.withdrawn.isEmpty) return;
    for (final void Function(DVConsentChange) listener
        in List<void Function(DVConsentChange)>.of(_listeners)) {
      listener(change);
    }
  }

  /// Records for this install, oldest first; or, given [subject], every
  /// record whose install or user is [subject].
  Future<List<DVConsentRecord>> records({String? subject}) async {
    final List<Map<String, Object?>> rows = subject == null
        ? await database.query(
            'SELECT * FROM $table WHERE install_id = ?', <Object?>[installId])
        : await database.query('SELECT * FROM $table');
    return <DVConsentRecord>[
      for (final Map<String, Object?> row in rows)
        if (subject == null ||
            '${row['install_id']}' == subject ||
            (row['user_id'] != null && '${row['user_id']}' == subject))
          DVConsentRecord.fromRow(row),
    ]..sort((DVConsentRecord a, DVConsentRecord b) {
        final int bySeq = a.seq.compareTo(b.seq);
        return bySeq != 0 ? bySeq : a.recordedAt.compareTo(b.recordedAt);
      });
  }

  /// Replaces [subject] on every record naming it with [pseudonym], keeping
  /// what was asked, what was answered, when, and under which version.
  ///
  /// The install id goes too: it ties the record to a device, which is
  /// personal data as much as the account is. Returns how many records were
  /// kept this way.
  Future<int> pseudonymize(String subject, String pseudonym) async {
    final List<DVConsentRecord> named = await records(subject: subject);
    for (final DVConsentRecord r in named) {
      await database.execute(
        'UPDATE $table SET install_id = ?, user_id = ? WHERE id = ?',
        <Object?>[pseudonym, r.userId == null ? null : pseudonym, r.id],
      );
    }
    return named.length;
  }
}

final Random _random = Random.secure();

/// A random identifier with no structure anybody could read anything from.
String dvAnalyticsRandomId() => <String>[
      for (int i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();

String _randomId() => dvAnalyticsRandomId();

final DVLogger _analyticsLogger = DVLogger();

/// Logs an analytics diagnostic at the level the registry gives its code.
void dvLogAnalyticsDiagnostic(String code, String message) {
  final String level = DVDiagnostics.all
          .where((DVDiagnostic d) => d.code == code)
          .firstOrNull
          ?.level ??
      'warning';
  _analyticsLogger.log(
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

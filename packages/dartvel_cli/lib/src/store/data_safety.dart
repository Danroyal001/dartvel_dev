/// Google Play Data Safety answers, derived from what a project declares.
///
/// "Collected" in the Data Safety form means sent off the device. A
/// permission is access and a dependency is code, and neither shows that
/// anything leaves, so neither becomes an answer here: each becomes a
/// question. What is derived is limited to features whose data flow Dartvel
/// itself defines (crash reports to the backend, analytics events, purchase
/// receipts, account ids), and every derived answer carries the declaration
/// it came from. Docs: docs/data-safety.md.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show
        DVCrashBuildMode,
        DVCrashConfig,
        DVCrashSinkChoice,
        DVFileStorageConfig,
        dvAndroidPermissionsFor;

import '../build/android_capture_bridge.dart' show dvAndroidRequestedPermissions;
import '../build/file_storage_permissions.dart'
    show dvFileStorageAndroidPermissionNames;

/// A data type in the form, with the identifiers the import format uses.
///
/// [verifiedCategoryId] and [verifiedResponseId] are the ones Google's help
/// page for the Data safety form names. The `recalled` pair is what the
/// Console's template is believed to use, and is not confirmed by anything
/// Google publishes; it is only used when asked for.
enum DVDataSafetyType {
  name('Personal info', 'Name',
      verifiedCategoryId: 'PSL_DATA_TYPES_PERSONAL',
      verifiedResponseId: 'PSL_NAME'),
  approximateLocation('Location', 'Approximate location',
      verifiedCategoryId: 'PSL_DATA_TYPES_LOCATION',
      verifiedResponseId: 'PSL_APPROX_LOCATION'),
  userIds('Personal info', 'User IDs',
      recalledCategoryId: 'PSL_DATA_TYPES_PERSONAL',
      recalledResponseId: 'PSL_USER_ACCOUNT'),
  purchaseHistory('Financial info', 'Purchase history',
      recalledCategoryId: 'PSL_DATA_TYPES_FINANCIAL',
      recalledResponseId: 'PSL_PURCHASE_HISTORY'),
  appInteractions('App activity', 'App interactions',
      recalledCategoryId: 'PSL_DATA_TYPES_APP_ACTIVITY',
      recalledResponseId: 'PSL_USER_INTERACTION'),
  crashLogs('App info and performance', 'Crash logs',
      recalledCategoryId: 'PSL_DATA_TYPES_APP_PERFORMANCE',
      recalledResponseId: 'PSL_CRASH_LOGS');

  const DVDataSafetyType(
    this.category,
    this.label, {
    this.verifiedCategoryId,
    this.verifiedResponseId,
    this.recalledCategoryId,
    this.recalledResponseId,
  });

  final String category;
  final String label;
  final String? verifiedCategoryId;
  final String? verifiedResponseId;
  final String? recalledCategoryId;
  final String? recalledResponseId;

  /// How the Console's template labels the row: `Category > Type`.
  String get fullLabel => '$category > $label';
}

/// Why data is collected, with the response id Google's page names.
enum DVDataSafetyPurpose {
  appFunctionality('PSL_APP_FUNCTIONALITY', 'App functionality'),
  analytics('PSL_ANALYTICS', 'Analytics'),
  developerCommunications(
      'PSL_DEVELOPER_COMMUNICATIONS', 'Developer communications'),
  fraudPreventionSecurity(
      'PSL_FRAUD_PREVENTION_SECURITY', 'Fraud prevention, security, and compliance'),
  advertising('PSL_ADVERTISING', 'Advertising or marketing'),
  personalization('PSL_PERSONALIZATION', 'Personalization'),
  accountManagement('PSL_ACCOUNT_MANAGEMENT', 'Account management');

  const DVDataSafetyPurpose(this.responseId, this.label);
  final String responseId;
  final String label;
}

enum DVDataSafetyUserChoice {
  /// The user can turn collection off.
  optional('PSL_DATA_USAGE_USER_CONTROL_OPTIONAL'),

  /// Collection is part of using the app.
  required('PSL_DATA_USAGE_USER_CONTROL_REQUIRED');

  const DVDataSafetyUserChoice(this.responseId);
  final String responseId;
}

/// One data type the project collects, and the declaration that says so.
final class DVDataSafetyAnswer {
  const DVDataSafetyAnswer({
    required this.type,
    required this.purposes,
    required this.shared,
    required this.userChoice,
    required this.basis,
  });

  final DVDataSafetyType type;
  final Set<DVDataSafetyPurpose> purposes;

  /// Whether it is shared with a third party, not only collected.
  final bool shared;
  final DVDataSafetyUserChoice userChoice;

  /// The pubspec declaration this was derived from.
  final String basis;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        'label': type.fullLabel,
        'purposes': <String>[for (final DVDataSafetyPurpose p in purposes) p.name],
        'shared': shared,
        'userChoice': userChoice.name,
        'basis': basis,
      };
}

/// A question the project's declarations cannot answer.
final class DVDataSafetyQuestion {
  const DVDataSafetyQuestion(this.id, this.text, {required this.basis});

  final String id;
  final String text;

  /// What made this a question.
  final String basis;

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'text': text, 'basis': basis};
}

/// What the derivation reads, as plain values.
final class DVDataSafetyInputs {
  const DVDataSafetyInputs({
    this.androidPermissions = const <String>[],
    this.crashes = const DVCrashConfig(),
    this.crashesDeclared = false,
    this.analyticsDeclared = false,
    this.analyticsHasConsent = false,
    this.authDeclared = false,
    this.purchasesDeclared = false,
    this.cleartextHosts = const <String>[],
    this.dependencies = const <String>{},
  });

  /// Reads a parsed `pubspec.yaml`.
  factory DVDataSafetyInputs.fromPubspec(Map<Object?, Object?> pubspec) {
    final Object? section = pubspec['dartvel'];
    final Map<Object?, Object?> dartvel =
        section is Map ? section : const <Object?, Object?>{};
    final Object? deps = pubspec['dependencies'];
    final Object? crashes = dartvel['crashes'];
    final Object? analytics = dartvel['analytics'];
    final Object? android = dartvel['android'];
    final Object? hosts = android is Map ? android['cleartextHosts'] : null;
    final Object? fileStorage = dartvel['fileStorage'];
    return DVDataSafetyInputs(
      androidPermissions: <String>[
        ...dvAndroidRequestedPermissions(dartvel),
        // dartvel.fileStorage asks for permissions of its own.
        if (fileStorage != null)
          ...dvFileStorageAndroidPermissionNames(
              DVFileStorageConfig.parse(_plain(fileStorage))),
      ],
      crashesDeclared: crashes != null,
      crashes: crashes == null
          ? const DVCrashConfig()
          : DVCrashConfig.parse(_plain(crashes)),
      analyticsDeclared: analytics != null,
      analyticsHasConsent: analytics is Map && analytics['consent'] is Map,
      authDeclared: dartvel['auth'] != null,
      purchasesDeclared:
          dartvel['purchases'] is Map || dartvel['purchases'] == true,
      cleartextHosts: hosts is List
          ? <String>[for (final Object? host in hosts) '$host']
          : const <String>[],
      dependencies: deps is Map
          ? <String>{for (final Object? key in deps.keys) '$key'}
          : const <String>{},
    );
  }

  final List<String> androidPermissions;
  final DVCrashConfig crashes;
  final bool crashesDeclared;
  final bool analyticsDeclared;
  final bool analyticsHasConsent;
  final bool authDeclared;
  final bool purchasesDeclared;
  final List<String> cleartextHosts;
  final Set<String> dependencies;

  static Object? _plain(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': _plain(e.value),
      };
    }
    if (value is List) return <Object?>[for (final Object? v in value) _plain(v)];
    return value;
  }
}

/// Dependencies whose own disclosure decides what the form says.
const Map<String, String> _knownSdks = <String, String>{
  'firebase_messaging': 'Firebase Cloud Messaging (a device token goes to Google)',
  'firebase_analytics': 'Firebase Analytics',
  'firebase_crashlytics': 'Firebase Crashlytics',
  'firebase_core': 'Firebase',
  'google_mobile_ads': 'Google Mobile Ads (advertising id)',
  'sentry_flutter': 'Sentry',
  'google_sign_in': 'Google Sign-In',
  'facebook_app_events': 'Meta App Events',
  'flutter_facebook_auth': 'Meta Login',
  'onesignal_flutter': 'OneSignal',
  'mixpanel_flutter': 'Mixpanel',
  'amplitude_flutter': 'Amplitude',
  'appsflyer_sdk': 'AppsFlyer',
  'adjust_sdk': 'Adjust',
  'geolocator': 'Location',
  'in_app_purchase': 'in_app_purchase',
};

/// The answers a project's declarations support, and the questions they do
/// not.
final class DVDataSafetyReport {
  const DVDataSafetyReport({
    required this.collected,
    required this.questions,
    required this.encryptedInTransit,
  });

  final List<DVDataSafetyAnswer> collected;
  final List<DVDataSafetyQuestion> questions;

  /// Whether the Android release refuses cleartext traffic everywhere.
  final bool encryptedInTransit;

  /// Answers with no identifier from Google's published page.
  List<DVDataSafetyAnswer> get unplaced => unplacedWith(null);

  /// Answers [csvTemplate] (the Console's exported CSV) does not place,
  /// counting the published identifiers as placed.
  List<DVDataSafetyAnswer> unplacedWith(String? csvTemplate,
      {bool unverifiedIds = false}) {
    final Map<String, _TemplateRow> rows = _readTemplate(csvTemplate);
    return <DVDataSafetyAnswer>[
      for (final DVDataSafetyAnswer a in collected)
        if (_placement(a.type, rows, unverifiedIds) == null) a,
    ];
  }

  /// The Console's import CSV for every answer that has an identifier to
  /// be written under; the rest are in [unplacedWith] and the worksheet.
  String toCsv({String? template, bool unverifiedIds = false}) {
    final Map<String, _TemplateRow> rows = _readTemplate(template);
    final List<DVDataSafetyAnswer> placed = <DVDataSafetyAnswer>[
      for (final DVDataSafetyAnswer a in collected)
        if (_placement(a.type, rows, unverifiedIds) != null) a,
    ];
    return dvDataSafetyCsv(placed, template: template, unverifiedIds: unverifiedIds);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'collected': <Object?>[for (final DVDataSafetyAnswer a in collected) a.toJson()],
        'questions': <Object?>[for (final DVDataSafetyQuestion q in questions) q.toJson()],
        'encryptedInTransit': encryptedInTransit,
      };

  /// A page for the person filling in the form: what was derived and why,
  /// and every question left to them.
  String toWorksheet({String? template, bool unverifiedIds = false}) {
    final StringBuffer out = StringBuffer()
      ..writeln('# Play Data Safety worksheet')
      ..writeln()
      ..writeln('Generated by `dartvel store data-safety` from pubspec.yaml. '
          'Nothing here was guessed: a row is derived only from a declaration '
          'that fixes where the data goes, and everything else is a TODO.')
      ..writeln()
      ..writeln('## Derived');
    final List<DVDataSafetyAnswer> unplaced =
        unplacedWith(template, unverifiedIds: unverifiedIds);
    if (collected.isEmpty) {
      out.writeln('\nNo data type is derived as collected.');
    }
    for (final DVDataSafetyAnswer a in collected) {
      out
        ..writeln()
        ..writeln('### ${a.type.fullLabel}')
        ..writeln('- Collected${a.shared ? ' and shared' : ', not shared'}.')
        ..writeln('- Purposes: ${a.purposes.map((DVDataSafetyPurpose p) => p.label).join(', ')}.')
        ..writeln('- User choice: ${a.userChoice == DVDataSafetyUserChoice.optional ? 'optional' : 'required'}.')
        ..writeln('- Because: ${a.basis}.')
        ..writeln(unplaced.contains(a)
            ? '- TODO: not in the CSV, because no identifier is known for it. '
                'Enter it in the Console form, or pass the Console\'s exported '
                'template with --template.'
            : '- In the CSV.');
    }
    out
      ..writeln()
      ..writeln('## Encryption in transit')
      ..writeln()
      ..writeln(encryptedInTransit
          ? 'Derived yes: the Android release refuses cleartext traffic '
              '(dartvel.android.cleartextHosts is empty). This covers what '
              'Dartvel sends; see the `app-code-network-calls` question.'
          : 'Not derived: dartvel.android.cleartextHosts allows cleartext to '
              'some host.')
      ..writeln()
      ..writeln('## TODO: questions only you can answer');
    for (final DVDataSafetyQuestion q in questions) {
      out
        ..writeln()
        ..writeln('- TODO `${q.id}`: ${q.text} (${q.basis})');
    }
    return out.toString();
  }
}

/// Derives the report.
DVDataSafetyReport dvDataSafetyFor(DVDataSafetyInputs inputs) {
  final List<DVDataSafetyAnswer> collected = <DVDataSafetyAnswer>[];
  final List<DVDataSafetyQuestion> questions = <DVDataSafetyQuestion>[];

  final bool crashSent = inputs.crashesDeclared &&
      inputs.crashes.sink == DVCrashSinkChoice.dartvel &&
      !inputs.crashes.disabledIn.contains(DVCrashBuildMode.release);
  if (crashSent) {
    collected.add(const DVDataSafetyAnswer(
      type: DVDataSafetyType.crashLogs,
      purposes: <DVDataSafetyPurpose>{DVDataSafetyPurpose.analytics},
      shared: false,
      userChoice: DVDataSafetyUserChoice.required,
      basis: 'dartvel.crashes.sink is dartvel, so release builds send crash '
          'reports to your backend',
    ));
  }

  if (inputs.analyticsDeclared) {
    collected.add(DVDataSafetyAnswer(
      type: DVDataSafetyType.appInteractions,
      purposes: const <DVDataSafetyPurpose>{DVDataSafetyPurpose.analytics},
      shared: false,
      userChoice: inputs.analyticsHasConsent
          ? DVDataSafetyUserChoice.optional
          : DVDataSafetyUserChoice.required,
      basis: 'dartvel.analytics is declared'
          '${inputs.analyticsHasConsent ? ' with a consent policy, so events are only recorded for a category the user accepted' : ''}',
    ));
  }

  if (inputs.purchasesDeclared) {
    collected.add(const DVDataSafetyAnswer(
      type: DVDataSafetyType.purchaseHistory,
      purposes: <DVDataSafetyPurpose>{DVDataSafetyPurpose.appFunctionality},
      shared: false,
      userChoice: DVDataSafetyUserChoice.required,
      basis: 'dartvel.purchases is declared, so receipts are sent to your '
          'backend to be verified',
    ));
  }

  if (inputs.authDeclared) {
    collected.add(const DVDataSafetyAnswer(
      type: DVDataSafetyType.userIds,
      purposes: <DVDataSafetyPurpose>{
        DVDataSafetyPurpose.accountManagement,
        DVDataSafetyPurpose.appFunctionality,
      },
      shared: false,
      userChoice: DVDataSafetyUserChoice.required,
      basis: 'dartvel.auth is declared, so accounts have ids on your backend',
    ));
    questions
      ..add(const DVDataSafetyQuestion('auth-identifiers',
          'What does sign-up ask for: email address, name, phone number? Each is its own data type (Personal info) and is collected.',
          basis: 'dartvel.auth is declared and the fields are your own'))
      ..add(const DVDataSafetyQuestion('account-creation-methods',
          'Which account creation methods does the app offer: username and password, username and other authentication, OAuth, other?',
          basis: 'dartvel.auth is declared'))
      ..add(const DVDataSafetyQuestion('account-deletion',
          'What is the URL where a user can ask for their account and data to be deleted? Play requires one when the app lets people create an account.',
          basis: 'dartvel.auth is declared'));
  }

  for (final String permission in inputs.androidPermissions) {
    final List<String>? manifest = dvAndroidPermissionsFor(permission);
    if (manifest == null) {
      questions.add(DVDataSafetyQuestion('permission-unknown-$permission',
          'pubspec.yaml lists "$permission", which Dartvel has no Android permission for, so nothing was declared for it. Fix the name before answering for it.',
          basis: 'dartvel.android.permissions'));
      continue;
    }
    if (manifest.isEmpty) continue;
    final String names = manifest.join(', ');
    questions.add(DVDataSafetyQuestion('permission-$permission',
        'The app can read data behind $names. Does any of it leave the device (to your backend or anyone else)? If yes, declare the data type it is; if it stays on the device, nothing is declared.',
        basis: 'dartvel.android.permissions lists $permission'));
  }

  final List<String> sdks = inputs.dependencies
      .where(_knownSdks.containsKey)
      .toList()
    ..sort();
  for (final String sdk in sdks) {
    questions.add(DVDataSafetyQuestion('sdk-$sdk',
        '${_knownSdks[sdk]} is a dependency. Its data collection is declared by you, from the SDK\'s own Data safety guidance; Dartvel does not know what it sends.',
        basis: 'pubspec.yaml dependencies: $sdk'));
  }

  final bool encrypted = inputs.cleartextHosts.isEmpty;
  if (!encrypted) {
    questions.add(DVDataSafetyQuestion('encryption-in-transit',
        'Cleartext traffic is allowed to ${inputs.cleartextHosts.join(', ')}. Is all user data still encrypted in transit? Answer for the data sent to those hosts.',
        basis: 'dartvel.android.cleartextHosts'));
  }

  questions.addAll(const <DVDataSafetyQuestion>[
    DVDataSafetyQuestion('collects-or-shares-any-data',
        'Does the app collect or share any of the required user data types? Static analysis of a pubspec cannot show that nothing leaves the app.',
        basis: 'always asked'),
    DVDataSafetyQuestion('data-deletion',
        'Can users request that their data be deleted? Where, and does it cover all of it?',
        basis: 'always asked'),
    DVDataSafetyQuestion('ephemeral-processing',
        'Is any collected data processed ephemerally (held in memory, never stored)? Dartvel does not track that.',
        basis: 'always asked'),
    DVDataSafetyQuestion('sharing-with-third-parties',
        'Is any collected data transferred to a third party (an analytics vendor, a payment gateway, a support tool)? Dartvel\'s own backend is not a third party; a vendor you added is.',
        basis: 'always asked'),
    DVDataSafetyQuestion('app-code-network-calls',
        'Does your own code send anything else off the device (DV.Http calls, uploads, forms)? Each is a data type to declare.',
        basis: 'always asked'),
  ]);

  return DVDataSafetyReport(
    collected: collected,
    questions: questions,
    encryptedInTransit: encrypted,
  );
}

// -- CSV -----------------------------------------------------------------------

const String _header = 'Question ID (machine readable),Response (machine readable),'
    'Response value,Answer requirement,Human-friendly question label';

typedef _TemplateRow = ({String questionId, String responseId});

({String question, String response})? _placement(
  DVDataSafetyType type,
  Map<String, _TemplateRow> template,
  bool unverifiedIds,
) {
  final _TemplateRow? fromTemplate = template[type.fullLabel.toLowerCase()];
  if (fromTemplate != null) {
    return (question: fromTemplate.questionId, response: fromTemplate.responseId);
  }
  if (type.verifiedCategoryId != null && type.verifiedResponseId != null) {
    return (
      question: type.verifiedCategoryId!,
      response: type.verifiedResponseId!
    );
  }
  if (unverifiedIds &&
      type.recalledCategoryId != null &&
      type.recalledResponseId != null) {
    return (
      question: type.recalledCategoryId!,
      response: type.recalledResponseId!
    );
  }
  return null;
}

/// Writes [answers] as the Console's import format. An answer with no
/// identifier is skipped; [DVDataSafetyReport.toCsv] decides which.
String dvDataSafetyCsv(
  List<DVDataSafetyAnswer> answers, {
  String? template,
  bool unverifiedIds = false,
}) {
  final Map<String, _TemplateRow> rows = _readTemplate(template);
  final StringBuffer out = StringBuffer()..writeln(_header);
  void row(String question, String response, String requirement, String label) {
    out.writeln(<String>[
      _field(question),
      _field(response),
      'TRUE',
      requirement,
      _field(label),
    ].join(','));
  }

  for (final DVDataSafetyAnswer a in answers) {
    final ({String question, String response})? at =
        _placement(a.type, rows, unverifiedIds);
    if (at == null) continue;
    final String usage = 'PSL_DATA_USAGE_RESPONSES:${at.response}';
    row(at.question, at.response, 'MULTIPLE_CHOICE', a.type.fullLabel);
    row(
        '$usage:PSL_DATA_USAGE_COLLECTION_AND_SHARING',
        a.shared ? 'PSL_DATA_USAGE_ONLY_SHARED' : 'PSL_DATA_USAGE_ONLY_COLLECTED',
        'MULTIPLE_CHOICE',
        'Is this data collected, shared, or both? > ${a.type.label}');
    row(
        '$usage:DATA_USAGE_USER_CONTROL',
        a.userChoice.responseId,
        'SINGLE_CHOICE',
        'Can users choose whether this data is collected? > ${a.type.label}');
    for (final DVDataSafetyPurpose purpose in a.purposes) {
      row(
          '$usage:${a.shared ? 'DATA_USAGE_SHARING_PURPOSE' : 'DATA_USAGE_COLLECTION_PURPOSE'}',
          purpose.responseId,
          'MULTIPLE_CHOICE',
          'Why is this user data ${a.shared ? 'shared' : 'collected'}? > ${purpose.label}');
    }
  }
  return out.toString();
}

String _field(String text) => text.contains(RegExp(r'[",\n]'))
    ? '"${text.replaceAll('"', '""')}"'
    : text;

/// The Console's exported CSV as `label -> (question id, response id)`.
Map<String, _TemplateRow> _readTemplate(String? csv) {
  final Map<String, _TemplateRow> out = <String, _TemplateRow>{};
  if (csv == null) return out;
  for (final List<String> cells in _parseCsv(csv).skip(1)) {
    if (cells.length < 5 || cells[0].isEmpty || cells[1].isEmpty) continue;
    final String label = cells[4].trim().toLowerCase();
    out.putIfAbsent(
        label, () => (questionId: cells[0].trim(), responseId: cells[1].trim()));
  }
  return out;
}

List<List<String>> _parseCsv(String text) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer cell = StringBuffer();
  bool quoted = false;
  final String input = const LineSplitter().convert(text).join('\n');
  for (int i = 0; i < input.length; i++) {
    final String c = input[i];
    if (quoted) {
      if (c == '"' && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      if (row.any((String s) => s.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((String s) => s.isNotEmpty)) rows.add(row);
  return rows;
}

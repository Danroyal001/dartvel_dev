/// The words and edits behind Studio's Flags section: a flag's type, a rule in
/// a sentence, a rule being edited, and what an edit changes.
///
/// Nothing here decides an answer. Whether a value is one a flag can carry is
/// asked of `DVFlags.evaluate`, the function every read goes through, so a
/// value this file accepts is one the runtime reads rather than one it holds
/// the default over.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.flag_rules;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show
        DVFeatureFlag,
        DVFlagContext,
        DVFlagRollout,
        DVFlagRule,
        DVFlagRules,
        DVFlagSource,
        DVFlagSubject,
        DVFlagTarget,
        DVFlags;

/// The value types a flag carries.
enum StudioFlagKind { boolean, integer, decimal, text, enumeration }

/// [flag]'s value type, read from its type argument before its default: on
/// the web an `int` and a `double` are one number, so `20 is double` cannot
/// tell a page size from a sample rate there, and `DVFeatureFlag<int>` can.
StudioFlagKind studioFlagKind(DVFeatureFlag<Object?> flag) {
  if (flag.values != null) return StudioFlagKind.enumeration;
  if (flag is DVFeatureFlag<bool>) return StudioFlagKind.boolean;
  if (flag is DVFeatureFlag<int>) return StudioFlagKind.integer;
  if (flag is DVFeatureFlag<double>) return StudioFlagKind.decimal;
  if (flag is DVFeatureFlag<String>) return StudioFlagKind.text;
  final Object? value = flag.defaultValue;
  if (value is bool) return StudioFlagKind.boolean;
  if (value is String) return StudioFlagKind.text;
  if (value is int) return StudioFlagKind.integer;
  return StudioFlagKind.decimal;
}

/// The type as it is declared: `bool`, `int`, `double`, `String`, `enum`.
String studioFlagTypeLabel(DVFeatureFlag<Object?> flag) =>
    switch (studioFlagKind(flag)) {
      StudioFlagKind.boolean => 'bool',
      StudioFlagKind.integer => 'int',
      StudioFlagKind.decimal => 'double',
      StudioFlagKind.text => 'String',
      StudioFlagKind.enumeration => 'enum',
    };

/// The values a `bool` or enum flag can be set to, as they are written in a
/// rule. Empty for the others, which take typed text.
List<String> studioFlagOptions(DVFeatureFlag<Object?> flag) =>
    switch (studioFlagKind(flag)) {
      StudioFlagKind.boolean => const <String>['true', 'false'],
      StudioFlagKind.enumeration => <String>[
          for (final Object? value in flag.values!)
            value is Enum ? value.name : '$value',
        ],
      _ => const <String>[],
    };

/// A flag value — resolved, or as a rule carries it — as the screen shows it:
/// an enum by name, a string in quotes so `"true"` is not mistaken for `true`.
String studioFlagValueText(DVFeatureFlag<Object?> flag, Object? value) {
  if (value is Enum) return value.name;
  if (value is String && studioFlagKind(flag) == StudioFlagKind.enumeration) {
    return value;
  }
  if (value is String) return jsonEncode(value);
  return '$value';
}

/// [value] as a rule would carry it: an enum by name, anything else as is.
Object? studioFlagRaw(Object? value) => value is Enum ? value.name : value;

/// Whether the runtime reads [raw] as a value of [flag].
///
/// Asked of `DVFlags.evaluate` with one unconditional rule, which answers from
/// that rule only when its value is one the flag can carry and otherwise
/// holds the default with `DV-FLAGS-006`.
bool studioFlagAccepts(DVFeatureFlag<Object?> flag, Object? raw) =>
    DVFlags.evaluate<Object?>(
      flag,
      DVFlagRules(
        rulesVersion: 0,
        flags: <String, List<DVFlagRule>>{
          flag.key: <DVFlagRule>[DVFlagRule(value: raw)],
        },
      ),
      const DVFlagContext(),
      allowOverrides: false,
    ).source ==
    DVFlagSource.rules;

/// The text an editor starts from for [raw]: blank for a `bool` or enum
/// value the flag cannot read, so nothing looks chosen that is not, and the
/// raw JSON otherwise, so a wrong-typed value shows as the refusal it is
/// rather than as something tidied into the right type.
String? studioFlagDraftText(DVFeatureFlag<Object?> flag, Object? raw) {
  switch (studioFlagKind(flag)) {
    case StudioFlagKind.boolean:
      return raw is bool ? '$raw' : null;
    case StudioFlagKind.enumeration:
      return raw is String && studioFlagOptions(flag).contains(raw)
          ? raw
          : null;
    case StudioFlagKind.integer:
      return raw is int ? '$raw' : (raw == null ? '' : jsonEncode(raw));
    case StudioFlagKind.decimal:
      return raw is num ? '$raw' : (raw == null ? '' : jsonEncode(raw));
    case StudioFlagKind.text:
      return raw is String ? raw : (raw == null ? '' : jsonEncode(raw));
  }
}

final RegExp _wholeNumber = RegExp(r'^-?\d+$');
final RegExp _number = RegExp(r'^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$');
final RegExp _version = RegExp(r'^\d+(\.\d+)*([-+][0-9A-Za-z.-]+)?$');

/// Reads what somebody typed as a value of [flag], or says why it is not one.
///
/// No coercion, as the runtime does none: `2.5` is not an int, `"30"` is not
/// a number, `yes` is not a bool. Whatever passes is then put to the runtime
/// itself, which has the last word.
(Object?, String?) studioParseFlagValue(
  DVFeatureFlag<Object?> flag,
  String? text,
) {
  final String typed = (text ?? '').trim();
  final Object? raw;
  switch (studioFlagKind(flag)) {
    case StudioFlagKind.boolean:
      if (typed != 'true' && typed != 'false') {
        return (null, 'Choose true or false.');
      }
      raw = typed == 'true';
    case StudioFlagKind.enumeration:
      final List<String> options = studioFlagOptions(flag);
      if (!options.contains(typed)) {
        return (null, 'Choose one of ${options.join(', ')}.');
      }
      raw = typed;
    case StudioFlagKind.integer:
      if (!_wholeNumber.hasMatch(typed)) {
        return (
          null,
          typed.isEmpty
              ? 'Enter a whole number: this flag is an int.'
              : '$typed is not a whole number, and this flag is an int.',
        );
      }
      raw = int.parse(typed);
    case StudioFlagKind.decimal:
      if (!_number.hasMatch(typed)) {
        return (
          null,
          typed.isEmpty
              ? 'Enter a number: this flag is a double.'
              : '$typed is not a number, and this flag is a double.',
        );
      }
      raw = num.parse(typed);
    case StudioFlagKind.text:
      raw = text ?? '';
  }
  if (!studioFlagAccepts(flag, raw)) {
    return (
      null,
      'The runtime does not read $typed as a ${studioFlagTypeLabel(flag)} '
          '(DV-FLAGS-006).',
    );
  }
  return (raw, null);
}

// --- attributes -------------------------------------------------------------

/// One attribute value as it is typed: `true`, `3`, `2.5`, `"quoted text"`,
/// or bare text. The evaluator and the rule editor both read with this, so an
/// attribute typed the same way in each is the same value in each.
(Object?, String?) studioParseAttributeValue(String text) {
  final String typed = text.trim();
  if (typed.startsWith('"')) {
    try {
      final Object? decoded = jsonDecode(typed);
      if (decoded is String) return (decoded, null);
    } on FormatException {
      // Falls through to the refusal below.
    }
    return (null, 'Close the quotes around $typed.');
  }
  if (typed == 'true') return (true, null);
  if (typed == 'false') return (false, null);
  if (_wholeNumber.hasMatch(typed)) return (int.parse(typed), null);
  if (_number.hasMatch(typed)) return (double.parse(typed), null);
  return (typed, null);
}

/// `key=value` pairs separated by commas, where a comma inside quotes is part
/// of the value.
(Map<String, Object?>, String?) studioParseAttributes(String text) {
  final List<String> parts = <String>[];
  final StringBuffer part = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if (c == '"' && (i == 0 || text[i - 1] != r'\')) quoted = !quoted;
    if (c == ',' && !quoted) {
      parts.add(part.toString());
      part.clear();
    } else {
      part.write(c);
    }
  }
  parts.add(part.toString());

  final Map<String, Object?> attributes = <String, Object?>{};
  for (final String raw in parts) {
    if (raw.trim().isEmpty) continue;
    final int eq = raw.indexOf('=');
    if (eq <= 0 || raw.substring(0, eq).trim().isEmpty) {
      return (
        const <String, Object?>{},
        'Write attributes as key=value, separated by commas.',
      );
    }
    final (Object? value, String? error) =
        studioParseAttributeValue(raw.substring(eq + 1));
    if (error != null) return (const <String, Object?>{}, error);
    attributes[raw.substring(0, eq).trim()] = value;
  }
  return (attributes, null);
}

/// [attributes] written back the way [studioParseAttributes] reads them, so
/// editing a rule and changing nothing changes nothing — a string that would
/// read back as something else is quoted.
String studioAttributesText(Map<String, Object?> attributes) => <String>[
      for (final MapEntry<String, Object?> e in attributes.entries)
        '${e.key}=${_attributeText(e.value)}',
    ].join(', ');

String _attributeText(Object? value) {
  if (value is! String) return '$value';
  final bool plain = value.isNotEmpty &&
      value.trim() == value &&
      !value.contains(',') &&
      !value.contains('"') &&
      studioParseAttributeValue(value).$1 == value;
  return plain ? value : jsonEncode(value);
}

/// An attribute value as a rule shows it: `beta = true`, `plan = "pro"`.
String studioAttributeDisplay(Object? value) =>
    value is String ? jsonEncode(value) : '$value';

// --- a rule in words --------------------------------------------------------

/// A rollout's percentage without a trailing `.0`.
String studioPercentText(DVFlagRollout rollout) =>
    rollout.basisPoints % 100 == 0
        ? '${rollout.basisPoints ~/ 100}'
        : '${rollout.basisPoints / 100}';

String studioSubjectPlural(DVFlagSubject subject) => switch (subject) {
      DVFlagSubject.user => 'users',
      DVFlagSubject.tenant => 'tenants',
      DVFlagSubject.device => 'devices',
    };

String studioSubjectSingular(DVFlagSubject subject) => switch (subject) {
      DVFlagSubject.user => 'user',
      DVFlagSubject.tenant => 'tenant',
      DVFlagSubject.device => 'device',
    };

/// `25% of users`.
String studioRolloutText(DVFlagRollout rollout) =>
    '${studioPercentText(rollout)}% of ${studioSubjectPlural(rollout.by)}';

/// Each condition of [target] in words, with the field it restricts:
/// `('platform', 'platform is ios or android')`.
List<(String, String)> studioTargetClauses(DVFlagTarget? target) {
  if (target == null) return const <(String, String)>[];
  String? list(String label, List<String>? values) {
    if (values == null) return null;
    if (values.isEmpty) return '$label is nothing, so no one matches';
    if (values.length == 1) return '$label is ${values.single}';
    return '$label is ${values.sublist(0, values.length - 1).join(', ')} '
        'or ${values.last}';
  }

  final String? min = target.minAppVersion;
  final String? max = target.maxAppVersion;
  return <(String, String)>[
    if (list('platform', target.platforms) case final String s)
      ('platform', s),
    if (list('tenant', target.tenants) case final String s) ('tenant', s),
    if (list('role', target.organizationRoles) case final String s)
      ('role', s),
    if (list('locale', target.locales) case final String s) ('locale', s),
    if (min != null && max != null)
      ('version', 'app version $min or later, before $max')
    else if (min != null)
      ('version', 'app version $min or later')
    else if (max != null)
      ('version', 'app version before $max'),
    for (final MapEntry<String, Object?> e in target.attributes.entries)
      ('attribute', '${e.key} = ${studioAttributeDisplay(e.value)}'),
  ];
}

/// The whole rule in one sentence, for a diff:
/// `Serve true to 25% of users when tenant is acme`.
String studioRuleText(DVFeatureFlag<Object?> flag, DVFlagRule rule) {
  final DVFlagRollout? rollout = rule.rollout;
  final List<(String, String)> clauses = studioTargetClauses(rule.target);
  return 'Serve ${studioFlagValueText(flag, rule.value)} to '
      '${rollout == null ? 'everyone' : studioRolloutText(rollout)}'
      '${clauses.isEmpty ? '' : ' when ${clauses.map(((String, String) c) => c.$2).join(' and ')}'}';
}

// --- a rule being edited ----------------------------------------------------

/// One rule as its editor holds it: text for every field, read into a
/// [DVFlagRule] only by [build], which refuses what the runtime would not
/// read.
class StudioRuleDraft {
  StudioRuleDraft._({
    required this.original,
    required this.value,
    this.platforms = '',
    this.tenants = '',
    this.roles = '',
    this.locales = '',
    this.minVersion = '',
    this.maxVersion = '',
    this.attributes = '',
    this.rollout = false,
    this.percent = '10',
    this.by = DVFlagSubject.user,
  });

  /// A rule as it stands.
  factory StudioRuleDraft.fromRule(
    DVFeatureFlag<Object?> flag,
    DVFlagRule rule,
  ) {
    final DVFlagTarget? target = rule.target;
    final DVFlagRollout? rollout = rule.rollout;
    String join(List<String>? values) => values?.join(', ') ?? '';
    return StudioRuleDraft._(
      original: rule,
      value: studioFlagDraftText(flag, rule.value),
      platforms: join(target?.platforms),
      tenants: join(target?.tenants),
      roles: join(target?.organizationRoles),
      locales: join(target?.locales),
      minVersion: target?.minAppVersion ?? '',
      maxVersion: target?.maxAppVersion ?? '',
      attributes: studioAttributesText(
        target?.attributes ?? const <String, Object?>{},
      ),
      rollout: rollout != null,
      percent: rollout == null ? '10' : studioPercentText(rollout),
      by: rollout?.by ?? DVFlagSubject.user,
    );
  }

  /// A new rule serving the compiled default to everyone, which is valid as
  /// it stands and changes no answer until it is edited.
  factory StudioRuleDraft.blank(DVFeatureFlag<Object?> flag) =>
      StudioRuleDraft._(
        original: null,
        value: studioFlagDraftText(flag, studioFlagRaw(flag.defaultValue)),
      );

  /// The rule this draft was opened from; null for a new one.
  final DVFlagRule? original;

  String? value;
  String platforms;
  String tenants;
  String roles;
  String locales;
  String minVersion;
  String maxVersion;
  String attributes;
  bool rollout;
  String percent;
  DVFlagSubject by;

  /// The rule, or why there is none.
  (DVFlagRule?, String?) build(DVFeatureFlag<Object?> flag) {
    final (Object? value, String? valueError) =
        studioParseFlagValue(flag, this.value);
    if (valueError != null) return (null, valueError);

    final DVFlagTarget? was = original?.target;
    List<String>? list(String text, List<String>? before) {
      final List<String> items = <String>[
        for (final String item in text.split(','))
          if (item.trim().isNotEmpty) item.trim(),
      ];
      if (items.isNotEmpty) return items;
      // An empty list matches no one and an absent one matches everyone, so
      // a rule opened with an empty list keeps it rather than being widened.
      return before != null && before.isEmpty ? const <String>[] : null;
    }

    for (final (String label, String version) in <(String, String)>[
      ('minimum', minVersion.trim()),
      ('maximum', maxVersion.trim()),
    ]) {
      if (version.isNotEmpty && !_version.hasMatch(version)) {
        return (
          null,
          'The $label app version $version is not a version like 2.0.0.',
        );
      }
    }
    final (Map<String, Object?> attrs, String? attrError) =
        studioParseAttributes(attributes);
    if (attrError != null) return (null, attrError);

    final List<String>? platformList = list(platforms, was?.platforms);
    final List<String>? tenantList = list(tenants, was?.tenants);
    final List<String>? roleList = list(roles, was?.organizationRoles);
    final List<String>? localeList = list(locales, was?.locales);
    final bool unrestricted = platformList == null &&
        tenantList == null &&
        roleList == null &&
        localeList == null &&
        minVersion.trim().isEmpty &&
        maxVersion.trim().isEmpty &&
        attrs.isEmpty;
    final DVFlagTarget? target = unrestricted
        ? (was != null && was.toJson().isEmpty ? const DVFlagTarget() : null)
        : DVFlagTarget(
            platforms: platformList,
            tenants: tenantList,
            organizationRoles: roleList,
            locales: localeList,
            minAppVersion: minVersion.trim().isEmpty ? null : minVersion.trim(),
            maxAppVersion: maxVersion.trim().isEmpty ? null : maxVersion.trim(),
            attributes: attrs,
          );

    DVFlagRollout? roll;
    if (rollout) {
      final num? p = num.tryParse(percent.trim());
      if (p == null || p < 0 || p > 100) {
        return (null, 'A rollout is a percentage from 0 to 100.');
      }
      roll = DVFlagRollout.percentage(p, by: by);
    }
    return (DVFlagRule(value: value, target: target, rollout: roll), null);
  }
}

/// [current] with [key]'s rules replaced by [rules], under a new
/// `rulesVersion` so an exposure recorded against the edit is not mistaken
/// for one recorded against the synced set.
DVFlagRules studioRulesWith(
  DVFlagRules? current,
  String key,
  List<DVFlagRule> rules,
) {
  final Map<String, List<DVFlagRule>> flags = <String, List<DVFlagRule>>{
    ...?current?.flags,
  };
  if (rules.isEmpty && !flags.containsKey(key)) {
    flags.remove(key);
  } else {
    flags[key] = rules;
  }
  return DVFlagRules(
    rulesVersion: (current?.rulesVersion ?? 0) + 1,
    flags: flags,
  );
}

/// Whether two rule lists say the same thing.
bool studioSameRules(List<DVFlagRule> a, List<DVFlagRule> b) =>
    jsonEncode(<Object?>[for (final DVFlagRule r in a) r.toJson()]) ==
    jsonEncode(<Object?>[for (final DVFlagRule r in b) r.toJson()]);

// --- what an edit changes ---------------------------------------------------

enum StudioRuleChangeKind { added, removed, changed, moved }

/// One line of a rule diff. [from] and [to] are indexes into the rules before
/// and after.
class StudioRuleChange {
  const StudioRuleChange({
    required this.kind,
    this.from,
    this.to,
    this.before,
    this.after,
  });

  final StudioRuleChangeKind kind;
  final int? from;
  final int? to;
  final String? before;
  final String? after;
}

/// What replacing [before] with [after] changes, rule by rule.
///
/// A rule that is the same in both is unchanged, unless the edit put it out of
/// order with the other unchanged rules — then it moved, which matters,
/// because the first rule that admits a context answers. A rule at the same
/// place in both that differs changed; anything else was added or removed.
List<StudioRuleChange> studioRuleDiff(
  DVFeatureFlag<Object?> flag,
  List<DVFlagRule> before,
  List<DVFlagRule> after,
) {
  final List<String> b = <String>[
    for (final DVFlagRule r in before) jsonEncode(r.toJson()),
  ];
  final List<String> a = <String>[
    for (final DVFlagRule r in after) jsonEncode(r.toJson()),
  ];
  final List<int?> matchOfAfter = List<int?>.filled(a.length, null);
  final List<bool> usedBefore = List<bool>.filled(b.length, false);
  for (int ai = 0; ai < a.length; ai++) {
    for (int bi = 0; bi < b.length; bi++) {
      if (!usedBefore[bi] && b[bi] == a[ai]) {
        usedBefore[bi] = true;
        matchOfAfter[ai] = bi;
        break;
      }
    }
  }

  // The longest run of matched rules still in their old relative order stays
  // put; every other matched rule moved.
  final List<int> matched = <int>[
    for (int ai = 0; ai < a.length; ai++)
      if (matchOfAfter[ai] != null) ai,
  ];
  final List<int> length = List<int>.filled(matched.length, 1);
  final List<int> previous = List<int>.filled(matched.length, -1);
  for (int i = 0; i < matched.length; i++) {
    for (int j = 0; j < i; j++) {
      if (matchOfAfter[matched[j]]! < matchOfAfter[matched[i]]! &&
          length[j] + 1 > length[i]) {
        length[i] = length[j] + 1;
        previous[i] = j;
      }
    }
  }
  final Set<int> stayed = <int>{};
  if (matched.isNotEmpty) {
    int best = 0;
    for (int i = 1; i < matched.length; i++) {
      if (length[i] > length[best]) best = i;
    }
    for (int i = best; i >= 0; i = previous[i]) {
      stayed.add(matched[i]);
    }
  }

  final List<StudioRuleChange> changes = <StudioRuleChange>[];
  final Set<int> pairedBefore = <int>{};
  for (int ai = 0; ai < a.length; ai++) {
    final int? bi = matchOfAfter[ai];
    if (bi != null) {
      if (!stayed.contains(ai)) {
        changes.add(StudioRuleChange(
          kind: StudioRuleChangeKind.moved,
          from: bi,
          to: ai,
          after: studioRuleText(flag, after[ai]),
        ));
      }
      continue;
    }
    if (ai < b.length && !usedBefore[ai]) {
      pairedBefore.add(ai);
      changes.add(StudioRuleChange(
        kind: StudioRuleChangeKind.changed,
        from: ai,
        to: ai,
        before: studioRuleText(flag, before[ai]),
        after: studioRuleText(flag, after[ai]),
      ));
    } else {
      changes.add(StudioRuleChange(
        kind: StudioRuleChangeKind.added,
        to: ai,
        after: studioRuleText(flag, after[ai]),
      ));
    }
  }
  for (int bi = 0; bi < b.length; bi++) {
    if (usedBefore[bi] || pairedBefore.contains(bi)) continue;
    changes.add(StudioRuleChange(
      kind: StudioRuleChangeKind.removed,
      from: bi,
      before: studioRuleText(flag, before[bi]),
    ));
  }
  changes.sort((StudioRuleChange x, StudioRuleChange y) =>
      (x.to ?? x.from!).compareTo(y.to ?? y.from!));
  return changes;
}

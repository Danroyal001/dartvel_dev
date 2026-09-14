/// Studio's Flags section: every declared flag, its rules in words, who gets
/// what, rule edits applied to this running app, and a debug-build override.
///
/// Every answer on this screen comes from `DVFlags.evaluate` with the rule set
/// and overrides `DVFlags.resolve` would hand it, so it cannot disagree with
/// what the application reads. The evaluator does not call `resolve` itself:
/// that records an exposure and pins a settle-on-next-launch flag, and a
/// what-if typed into Studio is neither.
///
/// Rules are applied through `DVFlags.setRules`, which is all the runtime has:
/// nothing publishes a rule set per environment yet, so an applied edit lives
/// in this process until the next sync or relaunch, and the screen says so
/// wherever it can be applied.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.flags;

import 'dart:async';

// Not re-exported by the dartvel_flutter barrel, whose core exports are a
// `show` list.
import 'package:dartvel_core/dartvel.dart'
    show
        DVFeatureFlag,
        DVFlagContext,
        DVFlagResolution,
        DVFlagRollout,
        DVFlagRule,
        DVFlagRules,
        DVFlagSettle,
        DVFlagSource,
        DVFlagSubject,
        DVFlags;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import 'studio_flag_rules.dart';
import 'studio_review.dart' show studioActionControl, studioBanner;

/// The Flags section of [DVStudioScreen].
class StudioFlagsSection extends StatefulWidget {
  const StudioFlagsSection({
    super.key,
    required this.flags,
    this.releaseBuild = kReleaseMode,
    this.now,
  });

  /// The flag runtime this section reads and edits.
  final DVFlags flags;

  /// Whether this is a release build, where the runtime reads no override and
  /// the section therefore offers none. Only a test says otherwise.
  final bool releaseBuild;

  /// The clock expiry is judged by.
  final DateTime Function()? now;

  @override
  State<StudioFlagsSection> createState() => _StudioFlagsSectionState();
}

const List<String> _evalFields = <String>[
  'user',
  'tenant',
  'device',
  'role',
  'platform',
  'locale',
  'version',
];

const Map<String, String> _evalLabels = <String, String>{
  'user': 'User ID',
  'tenant': 'Tenant',
  'device': 'Device ID',
  'role': 'Role',
  'platform': 'Platform',
  'locale': 'Locale',
  'version': 'App version',
};

const Map<String, String> _evalHints = <String, String>{
  'user': 'user-42',
  'tenant': 'acme',
  'device': 'device-1',
  'role': 'admin',
  'platform': 'ios',
  'locale': 'en-GB',
  'version': '2.4.0',
};

class _StudioFlagsSectionState extends State<StudioFlagsSection> {
  StreamSubscription<void>? _changes;
  String? _selected;

  bool _editing = false;
  bool _confirming = false;
  List<StudioRuleDraft> _drafts = <StudioRuleDraft>[];

  /// The flag's rules when editing began, to notice them changing underneath.
  List<DVFlagRule> _editBase = const <DVFlagRule>[];

  String? _applied;
  String? _error;
  final Set<String> _localEdits = <String>{};

  final Map<String, String> _eval = <String, String>{};
  final Map<String, String?> _overrideText = <String, String?>{};
  final Map<String, String?> _overrideError = <String, String?>{};

  @override
  void initState() {
    super.initState();
    // A sync, an override set elsewhere, or this screen's own apply: every
    // answer shown has to be the one in force now.
    _changes = DVFlags.changes.listen((void _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  DateTime get _now => widget.now?.call() ?? DateTime.now().toUtc();

  List<DVFlagRule> _rulesOf(DVFeatureFlag<Object?> flag) =>
      DVFlags.rules?.flags[flag.key] ?? const <DVFlagRule>[];

  /// The answer for [context] against [rules], exactly as a read gets it.
  DVFlagResolution<Object?> _evaluate(
    DVFeatureFlag<Object?> flag,
    DVFlagContext context, {
    DVFlagRules? rules,
    bool useCurrent = true,
  }) =>
      DVFlags.evaluate<Object?>(
        flag,
        useCurrent ? DVFlags.rules : rules,
        context,
        overrides: DVFlags.overridesInForce,
        allowOverrides: DVFlags.overridesAllowed,
      );

  DVFlagContext _appContext() {
    try {
      return DVFlags.context();
    } on Object {
      return const DVFlagContext();
    }
  }

  void _select(String key) {
    setState(() {
      _selected = key;
      _editing = false;
      _confirming = false;
      _applied = null;
      _error = null;
    });
  }

  // --- editing --------------------------------------------------------------

  void _startEdit(DVFeatureFlag<Object?> flag) {
    final List<DVFlagRule> rules = _rulesOf(flag);
    setState(() {
      _editBase = rules;
      _drafts = <StudioRuleDraft>[
        for (final DVFlagRule rule in rules)
          StudioRuleDraft.fromRule(flag, rule),
      ];
      _editing = true;
      _confirming = false;
      _applied = null;
      _error = null;
    });
  }

  void _discard() => setState(() {
        _editing = false;
        _confirming = false;
        _drafts = <StudioRuleDraft>[];
      });

  void _edit(void Function() change) => setState(change);

  /// The drafts as rules, or the first reason they cannot be.
  (List<DVFlagRule>?, int?, String?) _built(DVFeatureFlag<Object?> flag) {
    final List<DVFlagRule> rules = <DVFlagRule>[];
    for (int i = 0; i < _drafts.length; i++) {
      final (DVFlagRule? rule, String? error) = _drafts[i].build(flag);
      if (error != null) return (null, i, error);
      rules.add(rule!);
    }
    return (rules, null, null);
  }

  void _apply(DVFeatureFlag<Object?> flag) {
    final (List<DVFlagRule>? rules, _, _) = _built(flag);
    if (rules == null) return;
    final DVFlagRules next = studioRulesWith(DVFlags.rules, flag.key, rules);
    try {
      // The received time is kept: a local edit does not make a rule set
      // that is past flags.maxAge look freshly synced.
      DVFlags.setRules(next, receivedAt: DVFlags.rulesReceivedAt);
    } on Object catch (error) {
      setState(() {
        _confirming = false;
        _error = '$error';
      });
      return;
    }
    setState(() {
      _editing = false;
      _confirming = false;
      _drafts = <StudioRuleDraft>[];
      _localEdits.add(flag.key);
      _applied = 'Rules v${next.rulesVersion} are in force in this process '
          'only. Nothing was published: the next synced rule set, or a '
          'relaunch, replaces them.';
    });
  }

  // --- override -------------------------------------------------------------

  String? _overrideTextFor(DVFeatureFlag<Object?> flag) {
    if (_overrideText.containsKey(flag.key)) return _overrideText[flag.key];
    final Map<String, Object?> overrides = DVFlags.debugOverrides;
    return studioFlagDraftText(
      flag,
      overrides.containsKey(flag.key)
          ? overrides[flag.key]
          : studioFlagRaw(flag.defaultValue),
    );
  }

  Object? _typed(DVFeatureFlag<Object?> flag, Object? raw) {
    final List<Object?>? values = flag.values;
    if (values == null) return raw;
    return values.firstWhere(
      (Object? v) => v is Enum && v.name == raw,
      orElse: () => raw,
    );
  }

  /// Sets the override from the typed value, reporting a refusal where the
  /// value was typed.
  void _setOverride(DVFeatureFlag<Object?> flag) {
    final (Object? raw, String? error) =
        studioParseFlagValue(flag, _overrideTextFor(flag));
    if (error != null) {
      setState(() => _overrideError[flag.key] = error);
      return;
    }
    try {
      DVFlags.setDebugOverride<Object?>(flag, _typed(flag, raw));
      setState(() => _overrideError[flag.key] = null);
    } on ArgumentError catch (refused) {
      setState(() => _overrideError[flag.key] = '${refused.message}');
    }
  }

  void _overrideChanged(DVFeatureFlag<Object?> flag, String text) {
    final (_, String? error) = studioParseFlagValue(flag, text);
    setState(() {
      _overrideText[flag.key] = text;
      _overrideError[flag.key] = error;
    });
    if (error == null && DVFlags.debugOverrides.containsKey(flag.key)) {
      _setOverride(flag);
    }
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<DVFeatureFlag<Object?>> flags = DVFlags.declared;
    if (flags.isEmpty) {
      return Container(
        color: DVStudioStyle.canvas,
        child: DVStudioStyle.emptyState(
          icon: DVStudioIcons.flags,
          title: 'No flags declared',
          message: 'Declare flags as static const fields of a private '
              '@DVFlags() class. dartvel routes generates Flags, and '
              'registerDartvelFlags() declares them to the runtime.',
        ),
      );
    }
    final DVFeatureFlag<Object?> selected = flags.firstWhere(
      (DVFeatureFlag<Object?> f) => f.key == _selected,
      orElse: () => flags.first,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DVStudioStyle.panes(
              listWidth: box.maxWidth < 1000 ? 240 : 300,
              list: _list(flags, selected),
              detail: _detail(selected),
            ),
            if (_confirming) _confirmSheet(selected, box),
          ],
        );
      },
    );
  }

  // --- the list -------------------------------------------------------------

  Widget _list(
    List<DVFeatureFlag<Object?>> flags,
    DVFeatureFlag<Object?> selected,
  ) {
    final DateTime now = _now;
    final int expired =
        flags.where((DVFeatureFlag<Object?> f) => f.isExpired(now)).length;
    final DVFlagRules? rules = DVFlags.rules;
    final DateTime? received = DVFlags.rulesReceivedAt;
    final DVFlagContext here = _appContext();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 48,
          padding:
              const EdgeInsets.symmetric(horizontal: DVStudioStyle.space4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _text('Flags', size: 14, weight: FontWeight.w600),
              ),
              if (expired > 0)
                KeyedSubtree(
                  key: const ValueKey<String>('dv-studio-flags-expired-count'),
                  child: DVStudioStyle.badge('$expired expired',
                      tone: DVStudioStyle.danger),
                ),
            ],
          ),
        ),
        Container(
          key: rules == null
              ? const ValueKey<String>('dv-studio-flags-no-rules')
              : null,
          padding: const EdgeInsets.symmetric(
            horizontal: DVStudioStyle.space4,
            vertical: 10,
          ),
          decoration: const BoxDecoration(
            color: DVStudioStyle.canvas,
            border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              DVStudioStyle.dot(
                rules == null ? DVStudioStyle.warning : DVStudioStyle.success,
              ),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: _text(
                  rules == null
                      ? 'No rule set synced · defaults answer'
                      : 'Rules v${rules.rulesVersion}'
                          '${received == null ? '' : ' · ${_dateTime(received)}'}',
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: <Widget>[
              for (final DVFeatureFlag<Object?> flag in flags)
                _StudioFlagRow(
                  key: ValueKey<String>('dv-studio-flag-${flag.key}'),
                  flag: flag,
                  selected: flag.key == selected.key,
                  expired: flag.isExpired(now),
                  ruleCount: rules?.flags[flag.key]?.length ?? 0,
                  overridden: DVFlags.debugOverrides.containsKey(flag.key),
                  localEdit: _localEdits.contains(flag.key),
                  answer: studioFlagValueText(
                    flag,
                    _evaluate(flag, here).value,
                  ),
                  onTap: () => _select(flag.key),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- the detail -----------------------------------------------------------

  Widget _detail(DVFeatureFlag<Object?> flag) {
    final DateTime now = _now;
    final bool expired = flag.isExpired(now);
    final Map<String, Object?> overrides = DVFlags.debugOverrides;
    final bool overridden = overrides.containsKey(flag.key);
    final bool rulesMoved = _editing &&
        !studioSameRules(_editBase, _rulesOf(flag));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _detailHeader(flag),
        if (expired)
          studioBanner(
            key: const ValueKey<String>('dv-studio-flag-expired-banner'),
            tone: DVStudioStyle.danger,
            icon: Icons.event_busy_outlined,
            title: 'Expired ${_date(flag.expires)} · due for removal',
            detail: 'Past its declared expiry, so every read reports it '
                '(DV-FLAGS-004). Run dartvel flags prune to list the code '
                'that still reads it; a running app cannot count those reads. '
                'Owner: ${flag.owner}.',
          ),
        if (overridden && !widget.releaseBuild)
          studioBanner(
            key: const ValueKey<String>('dv-studio-flag-override-banner'),
            tone: DVStudioStyle.warning,
            icon: Icons.bug_report_outlined,
            title: 'Debug override in force',
            detail: 'Every read of ${flag.key} in this process answers '
                '${studioFlagValueText(flag, overrides[flag.key])}, whatever '
                'the rules say (DV-FLAGS-008).',
          ),
        if (rulesMoved)
          studioBanner(
            key: const ValueKey<String>('dv-studio-flag-rules-moved'),
            tone: DVStudioStyle.warning,
            icon: Icons.sync_problem_outlined,
            title: 'The rules changed while you were editing',
            detail: 'A new rule set arrived. Review shows the change against '
                'the rules in force now, and applying replaces them.',
          ),
        if (_applied != null)
          studioBanner(
            key: const ValueKey<String>('dv-studio-flag-applied'),
            tone: DVStudioStyle.success,
            icon: Icons.check_circle_outline,
            title: 'Applied to this running app',
            detail: _applied!,
            onDismiss: () => setState(() => _applied = null),
          ),
        if (_error != null)
          studioBanner(
            key: const ValueKey<String>('dv-studio-flag-error'),
            tone: DVStudioStyle.danger,
            icon: Icons.error_outline,
            title: 'The rules were not applied',
            detail: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final bool wide = box.maxWidth >= 1040;
              final double pad =
                  box.maxWidth < 600 ? DVStudioStyle.space4 : DVStudioStyle.space6;
              final DVFlagResolution<Object?>? evaluated = _evaluated(flag);
              final List<Widget> main = <Widget>[
                _facts(flag),
                const SizedBox(height: DVStudioStyle.space4),
                if (_editing) _editor(flag) else _rules(flag, evaluated),
              ];
              final List<Widget> side = <Widget>[
                _evaluator(flag, evaluated),
                const SizedBox(height: DVStudioStyle.space4),
                if (widget.releaseBuild)
                  _overrideUnavailable()
                else
                  _override(flag),
              ];
              return SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: main,
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space5),
                          SizedBox(
                            width: 360,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: side,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ...main,
                          const SizedBox(height: DVStudioStyle.space4),
                          ...side,
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _detailHeader(DVFeatureFlag<Object?> flag) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space5),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: DVStudioStyle.accentSoft,
              borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            ),
            child: const Icon(DVStudioIcons.flags,
                size: 16, color: DVStudioStyle.accent),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _text(flag.key, size: 15, weight: FontWeight.w700),
                const SizedBox(height: 2),
                _text(
                  '${studioFlagTypeLabel(flag)} · owned by ${flag.owner}',
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ],
            ),
          ),
          if (!_editing) ...<Widget>[
            const SizedBox(width: DVStudioStyle.space2),
            Flexible(
              child: studioActionControl(
                'dv-studio-flag-edit',
                'Edit rules',
                () => _startEdit(flag),
                icon: Icons.tune,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _facts(DVFeatureFlag<Object?> flag) {
    final DVFlagResolution<Object?> here = _evaluate(flag, _appContext());
    final bool expired = flag.isExpired(_now);
    return DVStudioStyle.card(
      child: Wrap(
        spacing: DVStudioStyle.space6,
        runSpacing: DVStudioStyle.space3,
        children: <Widget>[
          _fact('Default', studioFlagValueText(flag, flag.defaultValue)),
          _fact(
            'Answers here',
            studioFlagValueText(flag, here.value),
            detail: _sourceLabel(here),
          ),
          _fact('Owner', flag.owner),
          _fact(
            'Expires',
            _date(flag.expires),
            tone: expired ? DVStudioStyle.danger : DVStudioStyle.ink,
            detail: expired ? 'Expired' : null,
          ),
          _fact(
            'Settles',
            flag.settle == DVFlagSettle.onNextLaunch
                ? 'On next launch'
                : 'Immediately',
          ),
        ],
      ),
    );
  }

  Widget _fact(
    String label,
    String value, {
    Color tone = DVStudioStyle.ink,
    String? detail,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _text(label.toUpperCase(),
              size: 10.5, color: DVStudioStyle.muted, weight: FontWeight.w600),
          const SizedBox(height: 4),
          _text(value, size: 14, color: tone, weight: FontWeight.w600),
          if (detail != null) ...<Widget>[
            const SizedBox(height: 2),
            _text(detail, size: 11.5, color: DVStudioStyle.faint),
          ],
        ],
      ),
    );
  }

  // --- rules, read ----------------------------------------------------------

  Widget _rules(
    DVFeatureFlag<Object?> flag,
    DVFlagResolution<Object?>? evaluated,
  ) {
    final DVFlagRules? set = DVFlags.rules;
    final List<DVFlagRule> rules = _rulesOf(flag);
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _cardHeader(
            'Rules',
            'Top to bottom. The first rule that admits a context answers.',
            trailing: set == null
                ? null
                : DVStudioStyle.badge('v${set.rulesVersion}',
                    tone: DVStudioStyle.muted),
          ),
          if (set == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _note(
                key: const ValueKey<String>('dv-studio-flag-no-rule-set'),
                tone: DVStudioStyle.warning,
                icon: Icons.cloud_off_outlined,
                title: 'No rule set has synced',
                body: 'Every read answers the default compiled into the build '
                    '(DV-FLAGS-001).',
              ),
            ),
          for (int i = 0; i < rules.length; i++)
            _ruleView(flag, rules[i], i, evaluated),
          Container(
            key: const ValueKey<String>('dv-studio-flag-fallthrough'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: evaluated != null &&
                      evaluated.rule == null &&
                      evaluated.source == DVFlagSource.defaults
                  ? DVStudioStyle.accent.withValues(alpha: 0.05)
                  : null,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(DVStudioStyle.radiusLarge),
              ),
            ),
            child: Row(
              children: <Widget>[
                _index('–'),
                const SizedBox(width: DVStudioStyle.space3),
                Flexible(
                  child: _text(
                    rules.isEmpty ? 'Everyone gets' : 'Otherwise, serve',
                    size: 13,
                    color: DVStudioStyle.muted,
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: _valuePill(
                      studioFlagValueText(flag, flag.defaultValue)),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: _text('the compiled default',
                      size: 12, color: DVStudioStyle.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleView(
    DVFeatureFlag<Object?> flag,
    DVFlagRule rule,
    int index,
    DVFlagResolution<Object?>? evaluated,
  ) {
    final bool decided = evaluated?.rule == index;
    final bool held = decided && evaluated!.source == DVFlagSource.defaults;
    final List<(String, String)> clauses = studioTargetClauses(rule.target);
    final DVFlagRollout? rollout = rule.rollout;
    final bool readable = studioFlagAccepts(flag, rule.value);
    return Container(
      key: ValueKey<String>('dv-studio-flag-rule-$index'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: decided ? DVStudioStyle.accent.withValues(alpha: 0.05) : null,
        border: const Border(top: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _index('${index + 1}', active: decided),
          const SizedBox(width: DVStudioStyle.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _text('Serve', size: 13, color: DVStudioStyle.muted),
                    _valuePill(studioFlagValueText(flag, rule.value),
                        tone: readable
                            ? DVStudioStyle.accent
                            : DVStudioStyle.danger),
                    if (decided)
                      DVStudioStyle.badge(
                        held ? 'Held the default here' : 'Answers this context',
                        tone: held
                            ? DVStudioStyle.warning
                            : DVStudioStyle.accent,
                      ),
                  ],
                ),
                const SizedBox(height: DVStudioStyle.space2),
                if (clauses.isEmpty && rollout == null)
                  _clause(Icons.public, 'everyone'),
                for (final (String field, String text) in clauses)
                  _clause(_clauseIcon(field), text),
                if (rollout != null) _rolloutBar(rollout),
                if (!readable)
                  Padding(
                    padding: const EdgeInsets.only(top: DVStudioStyle.space2),
                    child: _note(
                      key: ValueKey<String>(
                          'dv-studio-flag-rule-$index-wrong-type'),
                      tone: DVStudioStyle.danger,
                      icon: Icons.error_outline,
                      title: 'Not a ${studioFlagTypeLabel(flag)}',
                      body: 'A context this rule admits holds the default '
                          'instead (DV-FLAGS-006). Edit the rule to serve a '
                          '${studioFlagTypeLabel(flag)}.',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _clauseIcon(String field) => switch (field) {
        'platform' => Icons.devices_outlined,
        'tenant' => Icons.apartment_outlined,
        'role' => Icons.badge_outlined,
        'locale' => Icons.translate,
        'version' => Icons.numbers,
        _ => Icons.label_outline,
      };

  Widget _clause(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: DVStudioStyle.faint),
          ),
          const SizedBox(width: 6),
          Expanded(child: _text(text, size: 12.5, maxLines: 3)),
        ],
      ),
    );
  }

  Widget _rolloutBar(DVFlagRollout rollout) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: <Widget>[
          const Icon(Icons.donut_large, size: 14, color: DVStudioStyle.faint),
          const SizedBox(width: 6),
          Flexible(
            flex: 3,
            child: _text(studioRolloutText(rollout),
                size: 12.5, weight: FontWeight.w600),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Container(
                height: 6,
                color: DVStudioStyle.canvas,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: rollout.basisPoints / 10000,
                  child: Container(color: DVStudioStyle.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- rules, edited --------------------------------------------------------

  Widget _editor(DVFeatureFlag<Object?> flag) {
    final (List<DVFlagRule>? built, int? badRule, String? problem) =
        _built(flag);
    final bool dirty =
        built != null && !studioSameRules(built, _rulesOf(flag));
    final String? reason = problem != null
        ? 'Rule ${badRule! + 1}: $problem'
        : !dirty
            ? 'Nothing has changed yet.'
            : null;
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _cardHeader(
            'Edit rules',
            'Drafts only, until you review the change and apply it.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _note(
              tone: DVStudioStyle.warning,
              icon: Icons.phone_iphone,
              title: 'Local to this running app',
              body: 'Applying calls DVFlags.setRules in this process. No '
                  'environment is published to, because Dartvel has no rule '
                  'publisher yet: the next synced rule set, or a relaunch, '
                  'replaces this edit.',
            ),
          ),
          for (int i = 0; i < _drafts.length; i++)
            KeyedSubtree(
              key: ObjectKey(_drafts[i]),
              child: _ruleEditor(flag, i),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              key: const ValueKey<String>('dv-studio-flag-add-rule'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(
                () => _drafts = <StudioRuleDraft>[
                  ..._drafts,
                  StudioRuleDraft.blank(flag),
                ],
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: DVStudioStyle.lineStrong),
                    borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                    color: DVStudioStyle.canvas,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(DVStudioIcons.add,
                          size: 15, color: DVStudioStyle.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: _text('Add rule',
                            size: 13,
                            color: DVStudioStyle.muted,
                            weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: DVStudioStyle.space4),
            padding: const EdgeInsets.all(DVStudioStyle.space4),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: DVStudioStyle.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Wrap(
                  spacing: DVStudioStyle.space2,
                  runSpacing: DVStudioStyle.space2,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    studioActionControl(
                      'dv-studio-flag-discard',
                      'Discard',
                      _discard,
                    ),
                    studioActionControl(
                      'dv-studio-flag-review',
                      'Review changes',
                      reason == null
                          ? () => setState(() => _confirming = true)
                          : null,
                      primary: true,
                      reason: reason,
                    ),
                  ],
                ),
                if (reason != null) ...<Widget>[
                  const SizedBox(height: DVStudioStyle.space1),
                  _text(reason,
                      size: 12, color: DVStudioStyle.faint, maxLines: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleEditor(DVFeatureFlag<Object?> flag, int i) {
    final StudioRuleDraft draft = _drafts[i];
    final (DVFlagRule? rule, String? error) = draft.build(flag);
    final String prefix = 'dv-studio-flag-rule-$i';
    void move(int by) => _edit(() {
          final List<StudioRuleDraft> next = <StudioRuleDraft>[..._drafts];
          next.insert(i + by, next.removeAt(i));
          _drafts = next;
        });
    return Container(
      key: ValueKey<String>(prefix),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border.all(
          color: error == null
              ? DVStudioStyle.line
              : DVStudioStyle.danger.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _index('${i + 1}', active: true),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: _text(
                  rule == null ? 'Rule ${i + 1}' : studioRuleText(flag, rule),
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ),
              DVStudioIconButton(
                key: ValueKey<String>('$prefix-up'),
                icon: Icons.arrow_upward,
                tooltip: 'Move up',
                size: 28,
                onTap: i == 0 ? null : () => move(-1),
              ),
              DVStudioIconButton(
                key: ValueKey<String>('$prefix-down'),
                icon: Icons.arrow_downward,
                tooltip: 'Move down',
                size: 28,
                onTap: i == _drafts.length - 1 ? null : () => move(1),
              ),
              DVStudioIconButton(
                key: ValueKey<String>('$prefix-remove'),
                icon: DVStudioIcons.delete,
                tooltip: 'Remove rule',
                size: 28,
                onTap: () => _edit(() {
                  _drafts = <StudioRuleDraft>[..._drafts]..removeAt(i);
                }),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space3),
          _label('Serve'),
          _valueEditor(
            flag,
            draft.value,
            (String v) => _edit(() => draft.value = v),
            '$prefix-value',
          ),
          const SizedBox(height: DVStudioStyle.space3),
          _label('Who'),
          _grid(<Widget>[
            _field('Platforms', 'ios, android', draft.platforms,
                (String v) => _edit(() => draft.platforms = v),
                '$prefix-platforms'),
            _field('Tenants', 'acme', draft.tenants,
                (String v) => _edit(() => draft.tenants = v),
                '$prefix-tenants'),
            _field('Roles', 'admin', draft.roles,
                (String v) => _edit(() => draft.roles = v), '$prefix-roles'),
            _field('Locales', 'en-GB', draft.locales,
                (String v) => _edit(() => draft.locales = v),
                '$prefix-locales'),
            _field('From version', '2.0.0', draft.minVersion,
                (String v) => _edit(() => draft.minVersion = v),
                '$prefix-min-version'),
            _field('Before version', '3.0.0', draft.maxVersion,
                (String v) => _edit(() => draft.maxVersion = v),
                '$prefix-max-version'),
          ]),
          const SizedBox(height: DVStudioStyle.space2),
          _field('Attributes', 'plan=pro, beta=true', draft.attributes,
              (String v) => _edit(() => draft.attributes = v),
              '$prefix-attributes'),
          const SizedBox(height: DVStudioStyle.space3),
          _label('Rollout'),
          Wrap(
            spacing: DVStudioStyle.space2,
            runSpacing: DVStudioStyle.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _choices(
                const <String>['Everyone', 'Percentage'],
                draft.rollout ? 'Percentage' : 'Everyone',
                (String v) => _edit(() => draft.rollout = v == 'Percentage'),
                key: '$prefix-rollout',
              ),
              if (draft.rollout) ...<Widget>[
                SizedBox(
                  width: 96,
                  child: KeyedSubtree(
                    key: ValueKey<String>('$prefix-percent'),
                    child: DVStudioTextInput(
                      value: draft.percent,
                      suffix: '%',
                      onChanged: (String v) => _edit(() => draft.percent = v),
                    ),
                  ),
                ),
                _choices(
                  <String>[
                    for (final DVFlagSubject s in DVFlagSubject.values)
                      studioSubjectPlural(s),
                  ],
                  studioSubjectPlural(draft.by),
                  (String v) => _edit(() => draft.by = DVFlagSubject.values
                      .firstWhere(
                          (DVFlagSubject s) => studioSubjectPlural(s) == v)),
                  key: '$prefix-by',
                ),
              ],
            ],
          ),
          if (error != null)
            Padding(
              key: ValueKey<String>('$prefix-error'),
              padding: const EdgeInsets.only(top: DVStudioStyle.space3),
              child: _errorLine(error),
            ),
        ],
      ),
    );
  }

  // --- confirm --------------------------------------------------------------

  Widget _confirmSheet(DVFeatureFlag<Object?> flag, BoxConstraints box) {
    final (List<DVFlagRule>? built, _, _) = _built(flag);
    final List<StudioRuleChange> changes = built == null
        ? const <StudioRuleChange>[]
        : studioRuleDiff(flag, _rulesOf(flag), built);
    final int nextVersion = (DVFlags.rules?.rulesVersion ?? 0) + 1;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _confirming = false),
            child: Container(color: const Color(0x5916161D)),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(DVStudioStyle.space4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: box.maxHeight - DVStudioStyle.space8,
              ),
              child: Container(
                key: const ValueKey<String>('dv-studio-flag-confirm'),
                decoration: BoxDecoration(
                  color: DVStudioStyle.surface,
                  border: Border.all(color: DVStudioStyle.line),
                  borderRadius:
                      BorderRadius.circular(DVStudioStyle.radiusLarge),
                  boxShadow: DVStudioStyle.shadowLarge,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: DVStudioStyle.warning
                                  .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(DVStudioStyle.radius),
                            ),
                            child: const Icon(Icons.difference_outlined,
                                size: 17, color: DVStudioStyle.warning),
                          ),
                          const SizedBox(width: DVStudioStyle.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _text('Apply this rule change?',
                                    size: 15, weight: FontWeight.w700),
                                const SizedBox(height: 2),
                                _text(
                                  '${flag.key} · ${changes.length} '
                                  'change${changes.length == 1 ? '' : 's'} · '
                                  'becomes rules v$nextVersion',
                                  size: 12,
                                  color: DVStudioStyle.muted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: DVStudioStyle.line),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(DVStudioStyle.space5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (int n = 0; n < changes.length; n++) ...<Widget>[
                              if (n > 0)
                                const SizedBox(height: DVStudioStyle.space2),
                              _diffRow(changes[n], n),
                            ],
                            const SizedBox(height: DVStudioStyle.space4),
                            _note(
                              tone: DVStudioStyle.warning,
                              icon: Icons.phone_iphone,
                              title: 'Local to this running app',
                              body: 'This replaces the rules in this process '
                                  'with DVFlags.setRules. It is not published '
                                  'to any environment, other devices do not '
                                  'see it, and the next synced rule set or a '
                                  'relaunch replaces it.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(height: 1, color: DVStudioStyle.line),
                    Padding(
                      padding: const EdgeInsets.all(DVStudioStyle.space4),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: DVStudioStyle.space2,
                        runSpacing: DVStudioStyle.space2,
                        children: <Widget>[
                          studioActionControl(
                            'dv-studio-flag-cancel',
                            'Cancel',
                            () => setState(() => _confirming = false),
                          ),
                          studioActionControl(
                            'dv-studio-flag-apply',
                            'Apply to this app',
                            built == null ? null : () => _apply(flag),
                            primary: true,
                            icon: Icons.check,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffRow(StudioRuleChange change, int n) {
    final (String label, Color tone, String title) = switch (change.kind) {
      StudioRuleChangeKind.added => (
          'Added',
          DVStudioStyle.success,
          'Rule ${change.to! + 1}',
        ),
      StudioRuleChangeKind.removed => (
          'Removed',
          DVStudioStyle.danger,
          'Rule ${change.from! + 1}',
        ),
      StudioRuleChangeKind.changed => (
          'Changed',
          DVStudioStyle.accent,
          'Rule ${change.to! + 1}',
        ),
      StudioRuleChangeKind.moved => (
          'Moved',
          DVStudioStyle.warning,
          'Rule ${change.from! + 1} is now rule ${change.to! + 1}',
        ),
    };
    return Container(
      key: ValueKey<String>('dv-studio-flag-diff-$n'),
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              DVStudioStyle.badge(label, tone: tone),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: _text(title, size: 13, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (change.before != null &&
              change.kind != StudioRuleChangeKind.moved)
            _diffLine('−', change.before!, DVStudioStyle.danger),
          if (change.after != null)
            _diffLine(
              change.kind == StudioRuleChangeKind.moved ? '↕' : '+',
              change.after!,
              change.kind == StudioRuleChangeKind.moved
                  ? DVStudioStyle.muted
                  : DVStudioStyle.success,
            ),
        ],
      ),
    );
  }

  Widget _diffLine(String sign, String text, Color tone) {
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 14,
            child: _text(sign, size: 12.5, color: tone, weight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _text(text, size: 12.5, maxLines: 4),
          ),
        ],
      ),
    );
  }

  // --- who gets what --------------------------------------------------------

  /// The evaluator's context, or null while its attributes cannot be read.
  (DVFlagContext?, String?) _evalContext() {
    String? field(String name) {
      final String value = (_eval[name] ?? '').trim();
      return value.isEmpty ? null : value;
    }

    final (Map<String, Object?> attributes, String? error) =
        studioParseAttributes(_eval['attributes'] ?? '');
    if (error != null) return (null, error);
    return (
      DVFlagContext(
        userId: field('user'),
        tenantId: field('tenant'),
        deviceId: field('device'),
        organizationRole: field('role'),
        platform: field('platform'),
        locale: field('locale'),
        appVersion: field('version'),
        attributes: attributes,
      ),
      null,
    );
  }

  DVFlagResolution<Object?>? _evaluated(DVFeatureFlag<Object?> flag) {
    final (DVFlagContext? context, _) = _evalContext();
    return context == null ? null : _evaluate(flag, context);
  }

  String _sourceLabel(DVFlagResolution<Object?> r) => switch (r.source) {
        DVFlagSource.override => 'Debug override',
        DVFlagSource.rules => 'Rules v${r.rulesVersion}',
        DVFlagSource.defaults => 'Compiled default',
      };

  String _explain(DVFeatureFlag<Object?> flag, DVFlagResolution<Object?> r) {
    final int? rule = r.rule;
    if (r.source == DVFlagSource.override) {
      return 'A debug override answers every read in this process '
          '(DV-FLAGS-008).';
    }
    if (r.codes.contains('DV-FLAGS-001')) {
      return 'No rule set has synced, so the compiled default answers '
          '(DV-FLAGS-001).';
    }
    if (rule != null && r.codes.contains('DV-FLAGS-005')) {
      final DVFlagSubject by = _rulesOf(flag)[rule].rollout!.by;
      return 'Rule ${rule + 1} rolls out by ${studioSubjectSingular(by)}, and '
          'this context has no ${studioSubjectSingular(by)}, so the flag holds '
          'its default (DV-FLAGS-005).';
    }
    if (rule != null && r.codes.contains('DV-FLAGS-006')) {
      return 'Rule ${rule + 1} admits this context, but its value is not a '
          '${studioFlagTypeLabel(flag)}, so the flag holds its default '
          '(DV-FLAGS-006).';
    }
    if (rule != null) {
      return 'Rule ${rule + 1} is the first rule that admits this context.';
    }
    return _rulesOf(flag).isEmpty
        ? 'The rule set has no rules for ${flag.key}, so the compiled default '
            'answers.'
        : 'No rule admits this context, so the compiled default answers.';
  }

  Widget _evaluator(
    DVFeatureFlag<Object?> flag,
    DVFlagResolution<Object?>? evaluated,
  ) {
    final (DVFlagContext? context, String? attrError) = _evalContext();
    final List<DVFlagRule> rules = _rulesOf(flag);

    DVFlagResolution<Object?>? after;
    if (_editing && context != null) {
      final (List<DVFlagRule>? built, _, _) = _built(flag);
      if (built != null && !studioSameRules(built, rules)) {
        after = _evaluate(
          flag,
          context,
          rules: studioRulesWith(DVFlags.rules, flag.key, built),
          useCurrent: false,
        );
      }
    }

    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _cardHeader(
            'Who gets what',
            'Answered by DVFlags.evaluate with this app\'s rules and '
                'overrides: the call every read makes.',
            icon: Icons.person_search_outlined,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _grid(<Widget>[
                  for (final String name in _evalFields)
                    _field(
                      _evalLabels[name]!,
                      _evalHints[name]!,
                      _eval[name] ?? '',
                      (String v) => setState(() => _eval[name] = v),
                      'dv-studio-flag-eval-$name',
                    ),
                ], minItem: 140),
                const SizedBox(height: DVStudioStyle.space2),
                _field(
                  'Attributes',
                  'plan=pro, beta=true',
                  _eval['attributes'] ?? '',
                  (String v) => setState(() => _eval['attributes'] = v),
                  'dv-studio-flag-eval-attributes',
                ),
                if (attrError != null) ...<Widget>[
                  const SizedBox(height: 6),
                  _errorLine(attrError),
                ],
                const SizedBox(height: DVStudioStyle.space3),
                if (evaluated == null)
                  _note(
                    tone: DVStudioStyle.muted,
                    icon: Icons.edit_note,
                    title: 'Fix the attributes to see an answer',
                    body: 'Attributes are key=value pairs; quote a value to '
                        'keep it text.',
                  )
                else
                  _evalResult(flag, context!, evaluated, rules, after),
                if (flag.settle == DVFlagSettle.onNextLaunch) ...<Widget>[
                  const SizedBox(height: DVStudioStyle.space2),
                  _text(
                    'Settles on next launch: a process that has already read '
                    'this flag keeps its first answer until it relaunches.',
                    size: 12,
                    color: DVStudioStyle.faint,
                    maxLines: 3,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _evalResult(
    DVFeatureFlag<Object?> flag,
    DVFlagContext context,
    DVFlagResolution<Object?> r,
    List<DVFlagRule> rules,
    DVFlagResolution<Object?>? after,
  ) {
    final Color tone = switch (r.source) {
      DVFlagSource.override => DVStudioStyle.warning,
      DVFlagSource.rules => DVStudioStyle.accent,
      DVFlagSource.defaults => DVStudioStyle.muted,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            tone.withValues(alpha: 0.06), DVStudioStyle.surface),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _text('ANSWER',
              size: 10.5, color: DVStudioStyle.muted, weight: FontWeight.w600),
          const SizedBox(height: 4),
          KeyedSubtree(
            key: const ValueKey<String>('dv-studio-flag-eval-value'),
            child: _text(studioFlagValueText(flag, r.value),
                size: 22, weight: FontWeight.w700),
          ),
          const SizedBox(height: DVStudioStyle.space2),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              KeyedSubtree(
                key: const ValueKey<String>('dv-studio-flag-eval-rule'),
                child: DVStudioStyle.badge(
                  r.rule == null ? 'No rule' : 'Rule ${r.rule! + 1}',
                  tone: r.rule == null ? DVStudioStyle.muted : DVStudioStyle.accent,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey<String>('dv-studio-flag-eval-source'),
                child: DVStudioStyle.badge(_sourceLabel(r), tone: tone),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _text(_explain(flag, r),
              size: 12, color: DVStudioStyle.muted, maxLines: 4),
          for (int i = 0; i < rules.length; i++)
            if (rules[i].rollout case final DVFlagRollout rollout)
              if (context.subjectFor(rollout.by) case final String subject)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _text(
                    'Rule ${i + 1}: ${studioSubjectSingular(rollout.by)} '
                    'bucket ${DVFlagRollout.bucket(flag.key, subject)} of '
                    '10000, ${rollout.includes(flag.key, subject) ? 'inside' : 'outside'} '
                    'its ${studioPercentText(rollout)}%',
                    size: 12,
                    color: DVStudioStyle.faint,
                    maxLines: 2,
                  ),
                ),
          if (after != null) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space2),
            Container(height: 1, color: tone.withValues(alpha: 0.2)),
            const SizedBox(height: DVStudioStyle.space2),
            KeyedSubtree(
              key: const ValueKey<String>('dv-studio-flag-eval-after'),
              child: _text(
                'After applying: ${studioFlagValueText(flag, after.value)} · '
                '${after.rule == null ? 'no rule' : 'rule ${after.rule! + 1}'}',
                size: 12.5,
                weight: FontWeight.w600,
                maxLines: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- override -------------------------------------------------------------

  Widget _override(DVFeatureFlag<Object?> flag) {
    final Map<String, Object?> overrides = DVFlags.debugOverrides;
    final bool on = overrides.containsKey(flag.key);
    final String? text = _overrideTextFor(flag);
    final String? error =
        _overrideError[flag.key] ?? studioParseFlagValue(flag, text).$2;
    final VoidCallback? toggle = on
        ? () => DVFlags.clearDebugOverride(flag)
        : error == null
            ? () => _setOverride(flag)
            : null;
    return Container(
      key: const ValueKey<String>('dv-studio-flag-override'),
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border.all(
          color: DVStudioStyle.warning.withValues(alpha: on ? 0.7 : 0.4),
        ),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
        boxShadow: DVStudioStyle.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: DVStudioStyle.warning.withValues(alpha: on ? 1 : 0.45),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DVStudioStyle.radiusLarge),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DVStudioStyle.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: DVStudioStyle.badge('Debug build only',
                      tone: DVStudioStyle.warning),
                ),
                const SizedBox(height: DVStudioStyle.space2),
                Row(
                  children: <Widget>[
                    const Icon(Icons.bug_report_outlined,
                        size: 16, color: DVStudioStyle.warning),
                    const SizedBox(width: DVStudioStyle.space2),
                    Expanded(
                      child: _text('Debug override',
                          size: 14, weight: FontWeight.w600),
                    ),
                    _Switch(
                      detectorKey: const ValueKey<String>(
                          'dv-studio-flag-override-toggle'),
                      on: on,
                      onTap: toggle,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _text(
                  on
                      ? 'On: every read of ${flag.key} in this process answers '
                          '${studioFlagValueText(flag, overrides[flag.key])}.'
                      : 'Makes every read of ${flag.key} in this process '
                          'answer the value below. A withOverrides zone still '
                          'wins, and release builds read no override.',
                  size: 12,
                  color: DVStudioStyle.muted,
                  maxLines: 4,
                ),
                const SizedBox(height: DVStudioStyle.space3),
                _label('Value'),
                _valueEditor(
                  flag,
                  text,
                  (String v) => _overrideChanged(flag, v),
                  'dv-studio-flag-override-value',
                ),
                if (error != null)
                  Padding(
                    key: const ValueKey<String>('dv-studio-flag-override-error'),
                    padding: const EdgeInsets.only(top: DVStudioStyle.space2),
                    child: _errorLine(error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overrideUnavailable() {
    return Container(
      key: const ValueKey<String>('dv-studio-flag-override-unavailable'),
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 15, color: DVStudioStyle.faint),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: _text(
              'Release build: the runtime reads no override, so none can be '
              'set here.',
              size: 12,
              color: DVStudioStyle.muted,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  // --- pieces ---------------------------------------------------------------

  Widget _cardHeader(
    String title,
    String subtitle, {
    Widget? trailing,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: DVStudioStyle.accent),
            ),
            const SizedBox(width: DVStudioStyle.space2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _text(title, size: 14, weight: FontWeight.w600),
                const SizedBox(height: 2),
                _text(subtitle,
                    size: 12, color: DVStudioStyle.muted, maxLines: 3),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: DVStudioStyle.space2),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _valueEditor(
    DVFeatureFlag<Object?> flag,
    String? text,
    ValueChanged<String> onChanged,
    String key,
  ) {
    final List<String> options = studioFlagOptions(flag);
    if (options.isNotEmpty) {
      return _choices(options, text, onChanged, key: key);
    }
    final StudioFlagKind kind = studioFlagKind(flag);
    return KeyedSubtree(
      key: ValueKey<String>(key),
      child: DVStudioTextInput(
        value: text ?? '',
        placeholder: switch (kind) {
          StudioFlagKind.integer => 'A whole number',
          StudioFlagKind.decimal => 'A number',
          _ => 'Text',
        },
        suffix: studioFlagTypeLabel(flag),
        onChanged: onChanged,
      ),
    );
  }

  Widget _choices(
    List<String> options,
    String? value,
    ValueChanged<String> onChanged, {
    required String key,
  }) {
    return Wrap(
      key: ValueKey<String>(key),
      spacing: 4,
      runSpacing: 4,
      children: <Widget>[
        for (final String option in options)
          GestureDetector(
            onTap: () => onChanged(option),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              // No alignment on the Container: one with an alignment fills
              // its constraints, which inside a Wrap is the whole row, and a
              // choice of three turns into three full-width bars.
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: option == value
                      ? DVStudioStyle.accentSoft
                      : DVStudioStyle.canvas,
                  border: Border.all(
                    color: option == value
                        ? DVStudioStyle.accent
                        : DVStudioStyle.line,
                  ),
                  borderRadius:
                      BorderRadius.circular(DVStudioStyle.radiusSmall),
                ),
                child: _text(
                  option,
                  size: 12,
                  color: option == value
                      ? DVStudioStyle.accent
                      : DVStudioStyle.ink,
                  weight: option == value ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    String label,
    String placeholder,
    String value,
    ValueChanged<String> onChanged,
    String key,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _text(label, size: 11.5, color: DVStudioStyle.muted),
        const SizedBox(height: 4),
        KeyedSubtree(
          key: ValueKey<String>(key),
          child: DVStudioTextInput(
            value: value,
            placeholder: placeholder,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _grid(List<Widget> children, {double minItem = 150}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int columns = (box.maxWidth / minItem).floor().clamp(1, 3);
        const double gap = DVStudioStyle.space2;
        final double width =
            ((box.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _text(text.toUpperCase(),
            size: 10.5, color: DVStudioStyle.muted, weight: FontWeight.w600),
      );

  Widget _errorLine(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline,
              size: 14, color: DVStudioStyle.danger),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _text(message,
              size: 12, color: DVStudioStyle.danger, maxLines: 3),
        ),
      ],
    );
  }

  Widget _note({
    Key? key,
    required Color tone,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _text(title, size: 12.5, weight: FontWeight.w600, maxLines: 2),
                const SizedBox(height: 3),
                _text(body, size: 12, color: DVStudioStyle.muted, maxLines: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _index(String label, {bool active = false}) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? DVStudioStyle.accent : DVStudioStyle.canvas,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? DVStudioStyle.accent : DVStudioStyle.lineStrong,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFFFFFFFF) : DVStudioStyle.muted,
          ),
        ),
      ),
    );
  }

  Widget _valuePill(String text, {Color tone = DVStudioStyle.accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: _text(text, size: 12.5, color: tone, weight: FontWeight.w600),
    );
  }
}

/// A flag in the list: its key and type, who owns it and what it defaults
/// to, and the marks that need attention — expired, overridden, edited here.
class _StudioFlagRow extends StatefulWidget {
  const _StudioFlagRow({
    super.key,
    required this.flag,
    required this.selected,
    required this.expired,
    required this.ruleCount,
    required this.overridden,
    required this.localEdit,
    required this.answer,
    required this.onTap,
  });

  final DVFeatureFlag<Object?> flag;
  final bool selected;
  final bool expired;
  final int ruleCount;
  final bool overridden;
  final bool localEdit;
  final String answer;
  final VoidCallback onTap;

  @override
  State<_StudioFlagRow> createState() => _StudioFlagRowState();
}

class _StudioFlagRowState extends State<_StudioFlagRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final DVFeatureFlag<Object?> flag = widget.flag;
    final String defaultText = studioFlagValueText(flag, flag.defaultValue);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: DVStudioStyle.space2, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? DVStudioStyle.selected
                : _hover
                    ? DVStudioStyle.hover
                    : const Color(0x00000000),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DVStudioStyle.dot(
                    widget.expired
                        ? DVStudioStyle.danger
                        : widget.overridden
                            ? DVStudioStyle.warning
                            : widget.ruleCount > 0
                                ? DVStudioStyle.success
                                : DVStudioStyle.faint,
                  ),
                  const SizedBox(width: DVStudioStyle.space2),
                  Expanded(
                    child: _text(
                      flag.key,
                      size: 13,
                      weight: FontWeight.w600,
                      color: widget.selected
                          ? DVStudioStyle.accent
                          : DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.canvas,
                      border: Border.all(color: DVStudioStyle.line),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _text(studioFlagTypeLabel(flag),
                        size: 11, color: DVStudioStyle.muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: _text(
                  '${flag.owner} · default $defaultText'
                  '${widget.answer == defaultText ? '' : ' · now ${widget.answer}'}',
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    if (widget.expired)
                      KeyedSubtree(
                        key: ValueKey<String>(
                            'dv-studio-flag-expired-${flag.key}'),
                        child: DVStudioStyle.badge('Expired',
                            tone: DVStudioStyle.danger),
                      )
                    else
                      DVStudioStyle.badge('Until ${_date(flag.expires)}',
                          tone: DVStudioStyle.muted),
                    DVStudioStyle.badge(
                      widget.ruleCount == 0
                          ? 'No rules'
                          : widget.ruleCount == 1
                              ? '1 rule'
                              : '${widget.ruleCount} rules',
                      tone: widget.ruleCount == 0
                          ? DVStudioStyle.faint
                          : DVStudioStyle.accent,
                    ),
                    if (widget.overridden)
                      DVStudioStyle.badge('Override',
                          tone: DVStudioStyle.warning),
                    if (widget.localEdit)
                      DVStudioStyle.badge('Local edit',
                          tone: DVStudioStyle.warning),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An on/off switch keyed on its detector, so whether it can be pressed is
/// something a test can ask.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.detectorKey,
    required this.on,
    required this.onTap,
  });

  final Key detectorKey;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color track = !enabled
        ? DVStudioStyle.line
        : on
            ? DVStudioStyle.warning
            : DVStudioStyle.lineStrong;
    return GestureDetector(
      key: detectorKey,
      onTap: onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 20,
          padding: const EdgeInsets.all(2),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
              boxShadow: DVStudioStyle.shadow,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _text(
  String text, {
  double size = 13,
  Color color = DVStudioStyle.ink,
  FontWeight weight = FontWeight.w400,
  int maxLines = 1,
}) =>
    Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.3,
      ),
    );

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime at) => '${at.day} ${_months[at.month - 1]} ${at.year}';

String _dateTime(DateTime at) {
  final DateTime utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_date(utc)}, ${two(utc.hour)}:${two(utc.minute)} UTC';
}

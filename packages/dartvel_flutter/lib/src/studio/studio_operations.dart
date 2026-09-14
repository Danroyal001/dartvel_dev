/// Studio's Operations section: service levels and their error budgets, alert
/// rules and where each delivery went, incidents and their timelines, and a
/// preview of the public status page.
///
/// Every figure on this screen is the runtime's own: `DVServiceLevels.status`
/// and `burnRate`, `DVErrorBudgetGate.evaluate`, `DVAlerting.state`, its signal
/// readers and `analyze`, and `DVStatusSnapshot.build`. Nothing is worked out
/// again here, because a dashboard that computes its own burn rate is a
/// dashboard that can disagree with the alert that pages.
///
/// Where the runtime answers null -- no traffic, no samples -- the screen says
/// so in words. A zero in that place reads as a service that is fine.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.operations;

import 'dart:async';

// Not re-exported by the dartvel_flutter barrel, whose core exports are a
// `show` list.
import 'package:dartvel_core/dartvel.dart'
    show
        DVAlertEpisode,
        DVAlertFinding,
        DVAlertRule,
        DVAlertState,
        DVAlertStatus,
        DVAlerting,
        DVAppliesToKind,
        DVErrorBudgetDecision,
        DVErrorBudgetGate,
        DVHealthReport,
        DVIncident,
        DVIncidentStatus,
        DVIncidents,
        DVObservability,
        DVServiceLevel,
        DVServiceLevelStatus,
        DVServiceLevels,
        DVSignalKind,
        DVSignalReading,
        DVSignalReadingStatus,
        DVStatusSnapshot;
import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import 'studio_incidents.dart';
import 'studio_ops_parts.dart';
import 'studio_review.dart' show studioBanner;

/// The views the section switches between.
enum StudioOpsTab { overview, alerts, incidents, status }

/// The Operations section of [DVStudioScreen].
class StudioOperationsSection extends StatefulWidget {
  const StudioOperationsSection({
    super.key,
    this.alerting,
    this.incidents,
    this.actor,
    this.now,
    this.health,
    this.refreshEvery = const Duration(seconds: 30),
  });

  /// The rule engine, and through its readers the service levels.
  final DVAlerting? alerting;

  /// The incidents this section lists and writes to.
  final DVIncidents? incidents;

  /// Who writes incident entries. Without one, nothing can be written.
  final String? actor;

  /// The clock burn rates, ages and new entries are judged by.
  final DateTime Function()? now;

  /// The health report the status page preview is built from.
  final Future<DVHealthReport> Function()? health;

  /// How often the section reads incidents, findings and health again. Rule
  /// state and service levels are read on every build.
  final Duration? refreshEvery;

  @override
  State<StudioOperationsSection> createState() =>
      _StudioOperationsSectionState();
}

class _StudioOperationsSectionState extends State<StudioOperationsSection> {
  StudioOpsTab _tab = StudioOpsTab.overview;
  bool _loaded = false;
  int _generation = 0;
  List<DVIncident> _incidents = const <DVIncident>[];
  List<DVAlertFinding> _findings = const <DVAlertFinding>[];
  DVHealthReport? _health;
  String? _healthError;
  String? _loadError;
  DateTime? _loadedAt;
  String? _rule;
  String? _incident;
  Timer? _timer;

  DateTime get _now => widget.now?.call() ?? DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    final Duration? every = widget.refreshEvery;
    if (every != null) {
      _timer = Timer.periodic(every, (_) => unawaited(_load()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Reads what is not cheap to read on every frame. The newest call wins, so
  /// a periodic refresh that finishes after an action's reload cannot put the
  /// older answer back.
  Future<void> _load() async {
    final int generation = ++_generation;
    final DateTime now = _now;
    List<DVIncident> incidents = _incidents;
    List<DVAlertFinding> findings = _findings;
    String? loadError;
    DVHealthReport? health;
    String? healthError;

    final DVIncidents? store = widget.incidents;
    if (store != null) {
      try {
        incidents = (await store.store.all())
          ..sort(
            (DVIncident a, DVIncident b) => b.openedAt.compareTo(a.openedAt),
          );
      } on Object catch (error) {
        loadError = 'Incidents could not be read: $error';
      }
    }
    final DVAlerting? alerting = widget.alerting;
    if (alerting != null) {
      try {
        findings = await alerting.analyze(now: now);
      } on Object catch (error) {
        loadError ??= 'Rules could not be analyzed: $error';
      }
    }
    try {
      health = await (widget.health ?? DVObservability.health.reportAsync)();
    } on Object catch (error) {
      healthError = '$error';
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _incidents = incidents;
      _findings = findings;
      _loadError = loadError;
      _health = health;
      _healthError = healthError;
      _loaded = true;
      _loadedAt = now;
    });
  }

  // --- counts ---------------------------------------------------------------

  List<(DVAlertRule, DVAlertState)> _ruleStates() {
    final DVAlerting? alerting = widget.alerting;
    if (alerting == null) return const <(DVAlertRule, DVAlertState)>[];
    return <(DVAlertRule, DVAlertState)>[
      for (final DVAlertRule rule in alerting.rules)
        (rule, alerting.state(rule.name)),
    ];
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<(DVAlertRule, DVAlertState)> rules = _ruleStates();
    final int firing = rules
        .where(
          ((DVAlertRule, DVAlertState) r) =>
              r.$2.status == DVAlertStatus.firing,
        )
        .length;
    final int open = _incidents.where((DVIncident i) => i.isOpen).length;
    return Container(
      color: DVStudioStyle.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(firing: firing, open: open),
          if (_loadError != null)
            studioBanner(
              key: const ValueKey<String>('dv-studio-ops-load-error'),
              tone: DVStudioStyle.danger,
              icon: Icons.error_outline,
              title: 'Part of this screen is out of date',
              detail: _loadError!,
              onDismiss: () => setState(() => _loadError = null),
            ),
          Expanded(
            child: !_loaded
                ? DVStudioStyle.placeholder('Reading operations…')
                : switch (_tab) {
                    StudioOpsTab.overview => _overview(rules),
                    StudioOpsTab.alerts => _alerts(),
                    StudioOpsTab.incidents => StudioIncidentsView(
                      incidents: widget.incidents,
                      list: _incidents,
                      actor: widget.actor,
                      now: () => _now,
                      selected: _incident,
                      onSelect: (String id) => setState(() => _incident = id),
                      onChanged: _load,
                    ),
                    StudioOpsTab.status => StudioStatusPreview(
                      snapshot: DVStatusSnapshot.build(
                        health: _health ?? opsNoChecks,
                        incidents: _incidents,
                        now: _now,
                      ),
                      healthError: _healthError,
                    ),
                  },
          ),
        ],
      ),
    );
  }

  Widget _header({required int firing, required int open}) {
    return Container(
      height: 56,
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
            child: const Icon(
              DVStudioIcons.operations,
              size: 16,
              color: DVStudioStyle.accent,
            ),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Flexible(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                opsText('Operations', size: 15, weight: FontWeight.w700),
                opsText(
                  _loadedAt == null
                      ? 'Reading…'
                      : 'As of ${opsTime(_loadedAt!)}',
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Flexible(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _tabButton(
                      StudioOpsTab.overview,
                      'Overview',
                      DVStudioIcons.dashboard,
                    ),
                    _tabButton(
                      StudioOpsTab.alerts,
                      'Alerts',
                      Icons.notifications_outlined,
                      count: firing,
                      tone: DVStudioStyle.danger,
                    ),
                    _tabButton(
                      StudioOpsTab.incidents,
                      'Incidents',
                      Icons.report_outlined,
                      count: open,
                      tone: DVStudioStyle.warning,
                    ),
                    _tabButton(
                      StudioOpsTab.status,
                      'Status page',
                      Icons.public,
                    ),
                    const SizedBox(width: DVStudioStyle.space2),
                    DVStudioIconButton(
                      key: const ValueKey<String>('dv-studio-ops-refresh'),
                      icon: Icons.refresh,
                      tooltip: 'Read again',
                      onTap: () => unawaited(_load()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(
    StudioOpsTab tab,
    String label,
    IconData icon, {
    int count = 0,
    Color tone = DVStudioStyle.accent,
  }) {
    final bool selected = _tab == tab;
    return GestureDetector(
      key: ValueKey<String>('dv-studio-ops-tab-${tab.name}'),
      onTap: () => setState(() => _tab = tab),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 32,
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? DVStudioStyle.selected : const Color(0x00000000),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected ? DVStudioStyle.accent : DVStudioStyle.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? DVStudioStyle.accent : DVStudioStyle.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- overview -------------------------------------------------------------

  Widget _overview(List<(DVAlertRule, DVAlertState)> rules) {
    final DateTime now = _now;
    final DVServiceLevels? levels = widget.alerting?.readers.serviceLevels;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double pad = box.maxWidth < 700
            ? DVStudioStyle.space4
            : DVStudioStyle.space6;
        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _stats(rules, levels, now),
                  const SizedBox(height: DVStudioStyle.space6),
                  _serviceLevels(levels, now),
                  const SizedBox(height: DVStudioStyle.space6),
                  _nowCards(rules, now),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stats(
    List<(DVAlertRule, DVAlertState)> rules,
    DVServiceLevels? levels,
    DateTime now,
  ) {
    int firing = 0;
    int resolving = 0;
    int missed = 0;
    for (final (DVAlertRule _, DVAlertState state) in rules) {
      if (state.status != DVAlertStatus.firing) continue;
      firing++;
      if (state.resolvingSince != null) resolving++;
      if (state.missed.isNotEmpty) missed++;
    }
    final List<DVIncident> open = _incidents
        .where((DVIncident i) => i.isOpen)
        .toList();
    final int monitoring = open
        .where((DVIncident i) => i.status == DVIncidentStatus.monitoring)
        .length;
    final List<DVServiceLevel> declared =
        levels?.levels ?? const <DVServiceLevel>[];
    final DVErrorBudgetDecision? gate = levels == null || declared.isEmpty
        ? null
        : DVErrorBudgetGate(levels).evaluate(now: now);

    final List<Widget> tiles = <Widget>[
      _tile(
        key: 'dv-studio-ops-firing',
        label: 'Firing alerts',
        value: '$firing',
        icon: Icons.notifications_active_outlined,
        tone: firing > 0 ? DVStudioStyle.danger : DVStudioStyle.success,
        detail: widget.alerting == null
            ? 'No alerting runtime attached'
            : firing == 0
            ? 'All ${rules.length} rules within threshold'
            : <String>[
                if (resolving > 0) '$resolving resolving',
                if (missed > 0) '$missed missed a target',
                if (resolving == 0 && missed == 0) 'Delivered',
              ].join(' · '),
        detailTone: missed > 0 ? DVStudioStyle.danger : DVStudioStyle.faint,
      ),
      _tile(
        key: 'dv-studio-ops-open-incidents',
        label: 'Open incidents',
        value: '${open.length}',
        icon: Icons.report_outlined,
        tone: open.isEmpty ? DVStudioStyle.success : DVStudioStyle.warning,
        detail: widget.incidents == null
            ? 'No incident store attached'
            : open.isEmpty
            ? 'Nothing open'
            : monitoring == 0
            ? 'None in monitoring yet'
            : '$monitoring in monitoring',
      ),
      _tile(
        key: 'dv-studio-ops-slo-count',
        label: 'Service levels',
        value: '${declared.length}',
        icon: Icons.speed,
        tone: DVStudioStyle.accent,
        detail: gate == null
            ? 'None declared'
            : gate.exhausted.isEmpty
            ? 'Every budget has room'
            : '${gate.exhausted.length} out of budget',
      ),
      _tile(
        key: 'dv-studio-ops-gate',
        label: 'Deploy gate',
        value: gate == null
            ? '—'
            : gate.hold
            ? 'Hold deploys'
            : 'Deploys clear',
        icon: DVStudioIcons.publish,
        tone: gate == null
            ? DVStudioStyle.muted
            : gate.hold
            ? DVStudioStyle.danger
            : DVStudioStyle.success,
        valueTone: gate == null
            ? DVStudioStyle.muted
            : gate.hold
            ? DVStudioStyle.danger
            : DVStudioStyle.ink,
        detail: gate == null
            ? 'No service levels to read'
            : gate.hold
            ? 'Budget exhausted: ${gate.exhausted.join(', ')}'
            : 'DVErrorBudgetGate holds nothing',
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int columns = box.maxWidth >= 900
            ? 4
            : box.maxWidth >= 480
            ? 2
            : 1;
        final double width =
            ((box.maxWidth - DVStudioStyle.space4 * (columns - 1)) / columns)
                .floorToDouble();
        return Wrap(
          spacing: DVStudioStyle.space4,
          runSpacing: DVStudioStyle.space4,
          children: <Widget>[
            for (final Widget tile in tiles)
              SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  Widget _tile({
    required String key,
    required String label,
    required String value,
    required IconData icon,
    required Color tone,
    required String detail,
    Color valueTone = DVStudioStyle.ink,
    Color detailTone = DVStudioStyle.faint,
  }) {
    return KeyedSubtree(
      key: ValueKey<String>(key),
      child: DVStudioStyle.card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(
                      DVStudioStyle.radiusSmall,
                    ),
                  ),
                  child: Icon(icon, size: 16, color: tone),
                ),
                const SizedBox(width: DVStudioStyle.space3),
                Expanded(
                  child: opsText(label, size: 12, color: DVStudioStyle.muted),
                ),
              ],
            ),
            const SizedBox(height: DVStudioStyle.space3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.2,
                  color: valueTone,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: DVStudioStyle.space1),
            opsText(detail, size: 12, color: detailTone, maxLines: 2),
          ],
        ),
      ),
    );
  }

  Widget _serviceLevels(DVServiceLevels? levels, DateTime now) {
    if (levels == null || levels.levels.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey<String>('dv-studio-ops-no-service-levels'),
        child: DVStudioStyle.card(
          padding: const EdgeInsets.all(DVStudioStyle.space5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DVStudioStyle.accentSoft,
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                ),
                child: const Icon(
                  Icons.speed,
                  size: 18,
                  color: DVStudioStyle.accent,
                ),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    opsText(
                      'No service levels',
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                    const SizedBox(height: 2),
                    opsText(
                      widget.alerting == null
                          ? 'Service levels are read through an alerting '
                                'runtime. Pass a DVAlerting whose '
                                'DVSignalReaders carry DVServiceLevels to see '
                                'objectives, error budgets and burn rates here.'
                          : 'This runtime\'s DVSignalReaders has no '
                                'DVServiceLevels, or none are declared. Add one '
                                'with DVServiceLevels.add and give it a source.',
                      size: 12.5,
                      color: DVStudioStyle.muted,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        opsText('Service levels', size: 15, weight: FontWeight.w700),
        const SizedBox(height: 2),
        opsText(
          'Burn rate is how many times faster than its objective allows a '
          'budget is being spent: 1× uses it up exactly at the end of the '
          'window.',
          size: 12.5,
          color: DVStudioStyle.muted,
          maxLines: 2,
        ),
        const SizedBox(height: DVStudioStyle.space3),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final int columns = box.maxWidth >= 1100
                ? 3
                : box.maxWidth >= 620
                ? 2
                : 1;
            final double width =
                ((box.maxWidth - DVStudioStyle.space4 * (columns - 1)) /
                        columns)
                    .floorToDouble();
            return Wrap(
              spacing: DVStudioStyle.space4,
              runSpacing: DVStudioStyle.space4,
              children: <Widget>[
                for (final DVServiceLevel level in levels.levels)
                  SizedBox(width: width, child: _levelCard(levels, level, now)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The windows a level's burn is shown over: the ones a rule alerting on
  /// it declares, so the card shows what the alert reads, else an hour and
  /// five minutes, the runtime's defaults.
  (Duration, Duration) _burnWindows(String level) {
    for (final DVAlertRule rule
        in widget.alerting?.rules ?? const <DVAlertRule>[]) {
      if (rule.signal.kind == DVSignalKind.errorBudgetBurn &&
          rule.signal.name == level) {
        return (rule.signal.window!, rule.signal.shortWindow!);
      }
    }
    return (const Duration(hours: 1), const Duration(minutes: 5));
  }

  Widget _levelCard(
    DVServiceLevels levels,
    DVServiceLevel level,
    DateTime now,
  ) {
    final String k = 'dv-studio-slo-${level.name}';
    final DVServiceLevelStatus status = levels.status(level.name, now: now);
    final (Duration long, Duration short) = _burnWindows(level.name);
    final double? burnLong = levels.burnRate(level.name, long, now: now);
    final double? burnShort = levels.burnRate(level.name, short, now: now);
    final (String label, Color tone, String explain) = _levelState(
      level,
      status,
      burnLong,
      burnShort,
      long,
      short,
    );

    final double? remaining = status.budgetRemaining;
    final double? errorRate = status.errorRate;
    final String budget = remaining == null
        ? 'No data'
        : status.exhausted
        ? 'Exhausted'
        : '${opsNumber(remaining * 100, digits: 1)}% left';
    final Color budgetTone = remaining == null
        ? DVStudioStyle.muted
        : remaining <= 0.2
        ? DVStudioStyle.danger
        : remaining <= 0.5
        ? DVStudioStyle.warning
        : DVStudioStyle.success;
    final double? coverage = status.coverage;

    return Container(
      key: ValueKey<String>(k),
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
        boxShadow: DVStudioStyle.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      opsText(level.name, size: 14, weight: FontWeight.w700),
                      const SizedBox(height: 2),
                      opsText(
                        _applies(level),
                        size: 12,
                        color: DVStudioStyle.muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: KeyedSubtree(
                    key: ValueKey<String>('$k-state'),
                    child: opsBadge(label, tone: tone),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.track_changes,
                  size: 14,
                  color: DVStudioStyle.faint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: opsText(
                    '${opsTarget(level.objective.target)} over '
                    '${opsLong(level.objective.over)}',
                    size: 12.5,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            key: ValueKey<String>('$k-budget'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: opsText(
                        'ERROR BUDGET',
                        size: 10.5,
                        color: DVStudioStyle.muted,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Flexible(
                      child: opsText(
                        budget,
                        size: 13,
                        color: status.exhausted
                            ? DVStudioStyle.danger
                            : DVStudioStyle.ink,
                        weight: FontWeight.w700,
                        align: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 8,
                    color: DVStudioStyle.canvas,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (remaining ?? 0).clamp(0.0, 1.0),
                      child: Container(color: budgetTone),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                opsText(
                  coverage == null
                      ? 'Fewer than two samples: nothing measured yet'
                      : 'Measured over ${opsLong(Duration(microseconds: (level.objective.over.inMicroseconds * coverage).round()))} '
                            'of ${opsLong(level.objective.over)}',
                  size: 11.5,
                  color: DVStudioStyle.faint,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                const double gap = DVStudioStyle.space3;
                final int columns = box.maxWidth >= 300 ? 3 : 1;
                final double width =
                    ((box.maxWidth - gap * (columns - 1)) / columns)
                        .floorToDouble();
                Widget fact(
                  String key,
                  String label,
                  String value,
                  Color tone,
                  String detail,
                ) => SizedBox(
                  width: width,
                  child: opsFact(
                    label,
                    value,
                    key: ValueKey<String>(key),
                    tone: tone,
                    detail: detail,
                    minWidth: 0,
                    maxWidth: width,
                  ),
                );
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    fact(
                      '$k-success',
                      'Success rate',
                      errorRate == null
                          ? 'No traffic'
                          : '${((1 - errorRate) * 100).toStringAsFixed(3)}%',
                      errorRate == null
                          ? DVStudioStyle.muted
                          : DVStudioStyle.ink,
                      errorRate == null
                          ? 'No requests in the window'
                          : 'Target ${opsTarget(level.objective.target)}',
                    ),
                    fact(
                      '$k-burn-long',
                      'Burn · ${opsShort(long)}',
                      opsBurn(burnLong),
                      opsBurnTone(burnLong),
                      burnLong == null
                          ? 'Nothing observed in ${opsShort(long)}'
                          : burnLong > 1
                          ? 'Faster than allowed'
                          : 'Within budget',
                    ),
                    fact(
                      '$k-burn-short',
                      'Burn · ${opsShort(short)}',
                      opsBurn(burnShort),
                      opsBurnTone(burnShort),
                      burnShort == null
                          ? 'Nothing observed in ${opsShort(short)}'
                          : burnShort > 1
                          ? 'Faster than allowed'
                          : 'Within budget',
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: DVStudioStyle.canvas,
              border: Border(top: BorderSide(color: DVStudioStyle.line)),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(DVStudioStyle.radiusLarge),
              ),
            ),
            child: opsText(
              explain,
              size: 12,
              color: DVStudioStyle.muted,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  /// Where a level stands, in a word and a sentence. Healthy only when both
  /// windows were measured and both are within budget: an unknown is never
  /// reported as fine.
  (String, Color, String) _levelState(
    DVServiceLevel level,
    DVServiceLevelStatus status,
    double? long,
    double? short,
    Duration longWindow,
    Duration shortWindow,
  ) {
    if (!status.hasData) {
      return (
        'No data',
        DVStudioStyle.muted,
        'Fewer than two samples have been read from its source, so nothing '
            'is measured yet.',
      );
    }
    if (status.exhausted) {
      return (
        'Budget exhausted',
        DVStudioStyle.danger,
        'The error budget for the trailing ${opsLong(level.objective.over)} '
            'is spent (DV-ALERT-003), so the deploy gate holds.',
      );
    }
    if (status.errorRate == null) {
      return (
        'No traffic',
        DVStudioStyle.muted,
        'No requests were observed in the window. That is not a clean '
            'record: a service that stopped answering looks the same.',
      );
    }
    if (long == null || short == null) {
      return (
        'No recent traffic',
        DVStudioStyle.muted,
        'No requests in the last '
            '${opsShort(long == null ? longWindow : shortWindow)}, so its '
            'burn rate cannot be read.',
      );
    }
    if (long > 1 && short > 1) {
      return (
        'Burning',
        long >= 14.4 && short >= 14.4
            ? DVStudioStyle.danger
            : DVStudioStyle.warning,
        'Both windows burn faster than the objective allows: the budget is '
            'in danger, and it is still happening.',
      );
    }
    if (long > 1) {
      return (
        'Recovering',
        DVStudioStyle.warning,
        'The last ${opsShort(longWindow)} burned fast, but the last '
            '${opsShort(shortWindow)} is within budget.',
      );
    }
    if (short > 1) {
      return (
        'Elevated',
        DVStudioStyle.warning,
        'The last ${opsShort(shortWindow)} burns fast; the last '
            '${opsShort(longWindow)} is still within budget.',
      );
    }
    return (
      'Healthy',
      DVStudioStyle.success,
      'Both windows are within budget.',
    );
  }

  static String _applies(DVServiceLevel level) => switch (level.applies.kind) {
    DVAppliesToKind.backendFunction => 'Backend function ${level.applies.name}',
    DVAppliesToKind.page => 'Page ${level.applies.name}',
    DVAppliesToKind.kioskFleet => 'Kiosk fleet ${level.applies.name}',
  };

  Widget _nowCards(List<(DVAlertRule, DVAlertState)> rules, DateTime now) {
    final List<(DVAlertRule, DVAlertState)> firing =
        <(DVAlertRule, DVAlertState)>[
          for (final (DVAlertRule, DVAlertState) r in rules)
            if (r.$2.status == DVAlertStatus.firing) r,
        ];
    final List<DVIncident> open = _incidents
        .where((DVIncident i) => i.isOpen)
        .toList();

    final Widget alerts = DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Firing now',
            'Open a rule for its signal and '
                'where the page went.',
            icon: Icons.notifications_active_outlined,
          ),
          if (widget.alerting == null)
            _cardNote('No alerting runtime is attached.')
          else if (firing.isEmpty)
            _cardNote('Nothing is firing.')
          else
            for (final (DVAlertRule rule, DVAlertState state) in firing)
              _linkRow(
                key: 'dv-studio-ops-firing-${rule.name}',
                tone: opsAlertTone(state),
                title: rule.name,
                subtitle: state.resolvingSince != null
                    ? 'Clear since ${opsAgo(state.resolvingSince!, now)}'
                    : 'Firing since ${opsAgo(state.firingSince!, now)}',
                badge: state.missed.isNotEmpty
                    ? opsBadge(
                        '${state.missed.length} missed',
                        tone: DVStudioStyle.danger,
                      )
                    : opsBadge(opsAlertLabel(state), tone: opsAlertTone(state)),
                onTap: () => setState(() {
                  _tab = StudioOpsTab.alerts;
                  _rule = rule.name;
                }),
              ),
        ],
      ),
    );
    final Widget incidents = DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Open incidents',
            'Newest first.',
            icon: Icons.report_outlined,
          ),
          if (widget.incidents == null)
            _cardNote('No incident store is attached.')
          else if (open.isEmpty)
            _cardNote('No incident is open.')
          else
            for (final DVIncident incident in open)
              _linkRow(
                key: 'dv-studio-ops-incident-${incident.id}',
                tone: opsIncidentTone(incident.status),
                title: incident.title,
                subtitle: 'Opened ${opsAgo(incident.openedAt, now)}',
                badge: opsBadge(
                  opsIncidentLabel(incident.status),
                  tone: opsIncidentTone(incident.status),
                ),
                onTap: () => setState(() {
                  _tab = StudioOpsTab.incidents;
                  _incident = incident.id;
                }),
              ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        if (box.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              alerts,
              const SizedBox(height: DVStudioStyle.space4),
              incidents,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: alerts),
            const SizedBox(width: DVStudioStyle.space4),
            Expanded(child: incidents),
          ],
        );
      },
    );
  }

  Widget _cardNote(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: opsText(text, size: 12.5, color: DVStudioStyle.muted),
  );

  Widget _linkRow({
    required String key,
    required Color tone,
    required String title,
    required String subtitle,
    required Widget badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: ValueKey<String>(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              DVStudioStyle.dot(tone, size: 8),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    opsText(title, size: 13, weight: FontWeight.w600),
                    opsText(subtitle, size: 12, color: DVStudioStyle.muted),
                  ],
                ),
              ),
              const SizedBox(width: DVStudioStyle.space2),
              Flexible(child: badge),
              const Icon(
                DVStudioIcons.chevronRight,
                size: 16,
                color: DVStudioStyle.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- alerts ---------------------------------------------------------------

  Widget _alerts() {
    final DVAlerting? alerting = widget.alerting;
    if (alerting == null) {
      return DVStudioStyle.emptyState(
        icon: Icons.notifications_outlined,
        title: 'No alerting runtime',
        message:
            'Pass a DVAlerting to DVStudioScreen to see its rules, their '
            'state and where each alert was delivered.',
      );
    }
    final List<DVAlertRule> rules = alerting.rules;
    if (rules.isEmpty) {
      return DVStudioStyle.emptyState(
        icon: Icons.notifications_outlined,
        title: 'No alert rules',
        message:
            'Add rules with DVAlerting.addRule. Each reads a signal the '
            'application already measures.',
      );
    }
    final DVAlertRule selected = rules.firstWhere(
      (DVAlertRule r) => r.name == _rule,
      orElse: () => rules.first,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          DVStudioStyle.panes(
            listWidth: box.maxWidth < 900 ? 240 : 300,
            list: _ruleList(alerting, rules, selected),
            detail: _ruleDetail(alerting, selected),
          ),
    );
  }

  Widget _ruleList(
    DVAlerting alerting,
    List<DVAlertRule> rules,
    DVAlertRule selected,
  ) {
    final int warnings = _findings.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: opsText(
                  'Alert rules',
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: KeyedSubtree(
                  key: const ValueKey<String>('dv-studio-alerts-findings'),
                  child: opsBadge(
                    warnings == 0
                        ? 'No warnings'
                        : warnings == 1
                        ? '1 warning'
                        : '$warnings warnings',
                    tone: warnings == 0
                        ? DVStudioStyle.faint
                        : DVStudioStyle.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final DVAlertRule rule in rules)
                  _ruleRow(
                    rule,
                    alerting.state(rule.name),
                    findings: _findings
                        .where((DVAlertFinding f) => f.rule == rule.name)
                        .length,
                    pendingResolves: alerting.pendingResolves(rule.name).length,
                    selected: rule.name == selected.name,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ruleRow(
    DVAlertRule rule,
    DVAlertState state, {
    required int findings,
    required int pendingResolves,
    required bool selected,
  }) {
    final String k = 'dv-studio-alert-${rule.name}';
    final bool missed =
        state.status == DVAlertStatus.firing && state.missed.isNotEmpty;
    return GestureDetector(
      key: ValueKey<String>(k),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _rule = rule.name),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: DVStudioStyle.space2,
            vertical: 1,
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: selected ? DVStudioStyle.selected : const Color(0x00000000),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DVStudioStyle.dot(opsAlertTone(state)),
                  const SizedBox(width: DVStudioStyle.space2),
                  Expanded(
                    child: opsText(
                      rule.name,
                      size: 13,
                      weight: FontWeight.w600,
                      color: selected
                          ? DVStudioStyle.accent
                          : DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: KeyedSubtree(
                      key: ValueKey<String>('$k-state'),
                      child: opsBadge(
                        opsAlertLabel(state),
                        tone: opsAlertTone(state),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: opsText(
                  '${rule.signal} ${_condition(rule)}',
                  size: 12,
                  color: DVStudioStyle.muted,
                ),
              ),
              if (missed || findings > 0 || pendingResolves > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 15, top: 6),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      if (missed)
                        opsBadge(
                          '${state.missed.length} missed',
                          key: ValueKey<String>('$k-missed'),
                          tone: DVStudioStyle.danger,
                        ),
                      if (findings > 0)
                        opsBadge(
                          findings == 1 ? '1 warning' : '$findings warnings',
                          tone: DVStudioStyle.warning,
                        ),
                      if (pendingResolves > 0)
                        opsBadge('Resolve queued', tone: DVStudioStyle.warning),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _threshold(DVAlertRule rule) {
    final Object limit = rule.condition.threshold;
    if (limit is Duration) {
      return '${opsNumber(limit.inMicroseconds / 1000, digits: 1)}ms';
    }
    if (limit is! num) return '$limit';
    return rule.signal.kind == DVSignalKind.errorBudgetBurn
        ? opsBurn(limit.toDouble())
        : opsNumber(limit);
  }

  static String _condition(DVAlertRule rule) =>
      '${rule.condition.above ? 'above' : 'below'} ${_threshold(rule)}';

  static String _reading(DVAlertRule rule, DVSignalReading reading) {
    switch (reading.status) {
      case DVSignalReadingStatus.missing:
        return 'Signal missing';
      case DVSignalReadingStatus.noData:
        return 'No data';
      case DVSignalReadingStatus.value:
        final Duration? duration = reading.duration;
        if (duration != null) {
          return '${opsNumber(duration.inMicroseconds / 1000, digits: 1)}ms';
        }
        final num value = reading.value!;
        return rule.signal.kind == DVSignalKind.errorBudgetBurn
            ? opsBurn(value.toDouble())
            : opsNumber(value);
    }
  }

  Widget _ruleDetail(DVAlerting alerting, DVAlertRule rule) {
    final DateTime now = _now;
    final DVAlertState state = alerting.state(rule.name);
    final DVSignalReading reading = alerting.readers.read(
      rule.signal,
      now: now,
    );
    final List<DVAlertFinding> findings = _findings
        .where((DVAlertFinding f) => f.rule == rule.name)
        .toList();
    final List<String> pending = alerting.pendingResolves(rule.name);
    final List<DVAlertEpisode> episodes = alerting.episodes(rule.name);
    final bool firing = state.status == DVAlertStatus.firing;
    final int targets = state.deliveredTo.length + state.missed.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
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
                  color: opsAlertTone(state).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  size: 16,
                  color: opsAlertTone(state),
                ),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    opsText(rule.name, size: 15, weight: FontWeight.w700),
                    const SizedBox(height: 2),
                    opsText(
                      'Reads ${rule.signal} · '
                      '${rule.notify.isEmpty
                          ? 'no targets'
                          : rule.notify.length == 1
                          ? '1 target'
                          : '${rule.notify.length} targets'}',
                      size: 12,
                      color: DVStudioStyle.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DVStudioStyle.space2),
              Flexible(
                child: opsBadge(
                  opsAlertLabel(state),
                  tone: opsAlertTone(state),
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < findings.length; i++)
          studioBanner(
            key: ValueKey<String>('dv-studio-alert-finding-$i'),
            tone: DVStudioStyle.warning,
            icon: Icons.warning_amber_rounded,
            title: _findingTitle(findings[i], rule),
            detail: '${findings[i].code}: this rule ${findings[i].message}.',
          ),
        if (firing && state.missed.isNotEmpty)
          studioBanner(
            key: const ValueKey<String>('dv-studio-alert-missed'),
            tone: DVStudioStyle.danger,
            icon: Icons.notifications_off_outlined,
            title:
                '${state.missed.length} of $targets '
                '${targets == 1 ? 'target' : 'targets'} missed this alert',
            detail:
                '${state.missed.keys.map(_targetName).join(', ')}. Each is '
                'tried again at the next evaluation while it fires'
                '${state.delivered ? '.' : '; nobody has been reached yet (DV-ALERT-002).'}',
          ),
        if (pending.isNotEmpty)
          studioBanner(
            key: const ValueKey<String>('dv-studio-alert-pending-resolves'),
            tone: DVStudioStyle.warning,
            icon: Icons.sync_problem_outlined,
            title: 'Resolve still owed to ${pending.join(', ')}',
            detail:
                'The pager refused the resolve. It is retried at every '
                'evaluation until it lands, and until then the pager\'s own '
                'incident stays open.',
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final bool wide = box.maxWidth >= 900;
              final double pad = box.maxWidth < 600
                  ? DVStudioStyle.space4
                  : DVStudioStyle.space6;
              final Widget delivery = _delivery(rule, state, now);
              final Widget episode = _episode(state, episodes, now);
              return SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _signal(rule, state, reading, now),
                    const SizedBox(height: DVStudioStyle.space4),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 3, child: delivery),
                          const SizedBox(width: DVStudioStyle.space4),
                          Expanded(flex: 2, child: episode),
                        ],
                      )
                    else ...<Widget>[
                      delivery,
                      const SizedBox(height: DVStudioStyle.space4),
                      episode,
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _findingTitle(DVAlertFinding finding, DVAlertRule rule) {
    if (finding.code == 'DV-ALERT-006') return 'Its signal does not exist';
    if (finding.code == 'DV-ALERT-005' &&
        rule.notify.isEmpty &&
        finding.message.contains('no target')) {
      return 'No target: when it fires, nobody hears';
    }
    if (finding.code == 'DV-ALERT-005') {
      return 'Noisy: it fires routinely and nothing changes';
    }
    return finding.code;
  }

  static String _targetName(String key) {
    final int colon = key.indexOf(':');
    final String kind = key.substring(0, colon);
    final String name = key.substring(colon + 1);
    return kind == 'user' ? name : '$kind $name';
  }

  Widget _signal(
    DVAlertRule rule,
    DVAlertState state,
    DVSignalReading reading,
    DateTime now,
  ) {
    final bool breaching =
        state.status != DVAlertStatus.inactive && state.resolvingSince == null;
    final String since = switch (state.status) {
      DVAlertStatus.inactive => 'Within its threshold',
      DVAlertStatus.pending =>
        'Breaching since ${opsAgo(state.pendingSince!, now)}; fires after '
            '${opsShort(rule.forDuration)}',
      DVAlertStatus.firing =>
        state.resolvingSince != null
            ? 'Clear since ${opsAgo(state.resolvingSince!, now)}; resolves after '
                  '${opsShort(rule.effectiveResolveAfter)}'
            : 'Since ${opsAgo(state.firingSince!, now)}',
    };
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Signal',
            'Read now through the rule\'s own reader: the value the next '
                'evaluation compares.',
            icon: Icons.show_chart,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: DVStudioStyle.space6,
              runSpacing: DVStudioStyle.space3,
              children: <Widget>[
                opsFact(
                  'Current value',
                  _reading(rule, reading),
                  key: const ValueKey<String>('dv-studio-alert-value'),
                  size: 20,
                  tone:
                      reading.status == DVSignalReadingStatus.missing ||
                          breaching
                      ? DVStudioStyle.danger
                      : reading.status == DVSignalReadingStatus.noData
                      ? DVStudioStyle.muted
                      : DVStudioStyle.ink,
                  detail: reading.detail ?? '${rule.signal}',
                ),
                opsFact(
                  'Threshold',
                  _condition(rule),
                  key: const ValueKey<String>('dv-studio-alert-threshold'),
                  size: 20,
                  detail: 'Held for ${opsShort(rule.forDuration)} to fire',
                ),
                opsFact(
                  'Resolves',
                  'After ${opsShort(rule.effectiveResolveAfter)} clear',
                  detail: rule.repeatEvery == null
                      ? 'Not repeated while firing'
                      : 'Repeats every ${opsShort(rule.repeatEvery!)}',
                ),
                opsFact(
                  'State',
                  opsAlertLabel(state),
                  tone: opsAlertTone(state),
                  detail: since,
                  maxWidth: 280,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _delivery(DVAlertRule rule, DVAlertState state, DateTime now) {
    final bool firing = state.status == DVAlertStatus.firing;
    final Set<String> explicit = <String>{
      for (final target in rule.notify) '${target.kind.name}:${target.name}',
    };
    final List<String> viaTeams = <String>[
      for (final String key in <String>{
        ...state.deliveredTo,
        ...state.missed.keys,
      })
        if (!explicit.contains(key)) key,
    ]..sort();
    return KeyedSubtree(
      key: const ValueKey<String>('dv-studio-alert-delivery'),
      child: DVStudioStyle.card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            opsCardHeader(
              'Delivery',
              !firing
                  ? 'Tracked per firing. Nothing is firing, so nothing is '
                        'being delivered.'
                  : state.lastNotifiedAt == null
                  ? 'This firing has not been delivered yet.'
                  : 'This firing. Last reached somebody '
                        '${opsAgo(state.lastNotifiedAt!, now)}.',
              icon: Icons.send_outlined,
            ),
            if (rule.notify.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: opsNote(
                  tone: DVStudioStyle.danger,
                  icon: Icons.notifications_off_outlined,
                  title: 'No targets',
                  body:
                      'When this rule fires nobody hears. Notify a user, a '
                      'team or a pager.',
                ),
              ),
            for (final String key in explicit)
              _deliveryRow(key, state, firing: firing),
            for (final String key in viaTeams)
              _deliveryRow(key, state, firing: firing, viaTeam: true),
          ],
        ),
      ),
    );
  }

  Widget _deliveryRow(
    String key,
    DVAlertState state, {
    required bool firing,
    bool viaTeam = false,
  }) {
    final int colon = key.indexOf(':');
    final String kind = key.substring(0, colon);
    final String name = key.substring(colon + 1);
    final IconData icon = switch (kind) {
      'pager' => Icons.campaign_outlined,
      'team' => DVStudioIcons.team,
      _ => Icons.person_outline,
    };
    final String? reason = firing ? state.missed[key] : null;
    final (String label, Color tone) = !firing
        ? ('Not firing', DVStudioStyle.faint)
        : reason != null
        ? ('Missed', DVStudioStyle.danger)
        : state.deliveredTo.contains(key)
        ? ('Delivered', DVStudioStyle.success)
        : kind == 'team'
        ? ('Resolved to members', DVStudioStyle.muted)
        : ('Not reached yet', DVStudioStyle.warning);
    final String kindLabel = viaTeam
        ? 'through a team'
        : switch (kind) {
            'pager' => 'pager',
            'team' => 'team',
            _ => 'user',
          };
    return Container(
      key: ValueKey<String>('dv-studio-alert-delivery-$key'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: reason != null
            ? DVStudioStyle.danger.withValues(alpha: 0.04)
            : null,
        border: const Border(top: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: DVStudioStyle.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: opsText(name, size: 13, weight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: opsText(
                        kindLabel,
                        size: 12,
                        color: DVStudioStyle.faint,
                      ),
                    ),
                  ],
                ),
                if (reason != null) ...<Widget>[
                  const SizedBox(height: 2),
                  opsText(
                    reason,
                    size: 12,
                    color: DVStudioStyle.danger,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 2),
                  opsText(
                    'Retried at the next evaluation while this fires.',
                    size: 11.5,
                    color: DVStudioStyle.muted,
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          Flexible(child: opsBadge(label, tone: tone)),
        ],
      ),
    );
  }

  Widget _episode(
    DVAlertState state,
    List<DVAlertEpisode> episodes,
    DateTime now,
  ) {
    final DVAlertEpisode? last = episodes.isEmpty ? null : episodes.last;
    final int week = episodes
        .where(
          (DVAlertEpisode e) =>
              e.firedAt.isAfter(now.subtract(const Duration(days: 7))),
        )
        .length;
    return KeyedSubtree(
      key: const ValueKey<String>('dv-studio-alert-last-episode'),
      child: DVStudioStyle.card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            opsCardHeader(
              'Last episode',
              last == null
                  ? 'Has not fired in the last '
                        '${opsLong(DVAlerting.episodeRetention)}.'
                  : '$week in the last 7 days.',
              icon: DVStudioIcons.history,
            ),
            if (last != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: DVStudioStyle.space6,
                  runSpacing: DVStudioStyle.space3,
                  children: <Widget>[
                    if (last.resolvedAt == null)
                      opsFact(
                        'Status',
                        'Firing',
                        tone: DVStudioStyle.danger,
                        detail: 'since ${opsTime(last.firedAt)}',
                      )
                    else
                      opsFact(
                        'Status',
                        'Resolved',
                        tone: DVStudioStyle.success,
                        detail:
                            'after '
                            '${opsShort(last.resolvedAt!.difference(last.firedAt))}',
                      ),
                    opsFact(
                      'Fired',
                      opsTime(last.firedAt),
                      detail: opsAgo(last.firedAt, now),
                    ),
                    opsFact(
                      'Acknowledged',
                      last.acknowledgedAt == null
                          ? 'No'
                          : opsTime(last.acknowledgedAt!),
                      tone: last.acknowledgedAt == null
                          ? DVStudioStyle.muted
                          : DVStudioStyle.ink,
                    ),
                    opsFact(
                      'Action',
                      last.action ?? 'None recorded',
                      tone: last.action == null
                          ? DVStudioStyle.muted
                          : DVStudioStyle.ink,
                      maxWidth: 300,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

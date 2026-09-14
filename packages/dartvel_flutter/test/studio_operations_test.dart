// Studio's Operations section, driven the way somebody on call drives it.
//
// The quiet failures: an internal timeline entry -- a host name, a pool size,
// what an alert wrote -- shown in the preview of the public page; a service
// level with no traffic shown as burning at 0x or as healthy, when nothing was
// measured at all; a resolve button offered while the incident is still being
// investigated, so the public page says "resolved" before anyone watched it
// hold; and an alert that paged one person and missed the pager shown as
// delivered.
import 'package:dartvel_core/dartvel.dart'
    show
        DVAlertDeliveryException,
        DVAlertEvent,
        DVAlertPager,
        DVAlertRule,
        DVAlertTarget,
        DVAlertWhen,
        DVAlerting,
        DVAppliesTo,
        DVHealthReport,
        DVHealthResult,
        DVHealthStatus,
        DVIncident,
        DVIncidentEntry,
        DVIncidentStatus,
        DVIncidentStore,
        DVIncidents,
        DVMemoryIncidentStore,
        DVNotificationMessage,
        DVNotificationProvider,
        DVNotificationProviderKind,
        DVNotificationsService,
        DVObjective,
        DVServiceLevel,
        DVServiceLevelCounts,
        DVServiceLevels,
        DVSignalReaders,
        DVSignalRef;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime.utc(2026, 9, 14, 12);

DateTime ago(Duration d) => now.subtract(d);

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

Finder inKey(String key, Finder matching) =>
    find.descendant(of: byKey(key), matching: matching);

GestureDetector detector(WidgetTester tester, String key) =>
    tester.widget<GestureDetector>(byKey(key));

class _Provider implements DVNotificationProvider {
  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.local;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {}
}

class _DownPager implements DVAlertPager {
  @override
  Future<void> trigger(DVAlertEvent event) async =>
      throw const DVAlertDeliveryException('PagerDuty refused: HTTP 503');

  @override
  Future<void> resolve(DVAlertEvent event) async =>
      throw const DVAlertDeliveryException('PagerDuty refused: HTTP 503');
}

/// A memory store whose saves can be made to fail.
class _Store implements DVIncidentStore {
  final DVMemoryIncidentStore _inner = DVMemoryIncidentStore();
  bool failSaves = false;

  @override
  Future<void> save(DVIncident incident) async {
    if (failSaves) throw StateError('incident store is read-only right now');
    await _inner.save(incident);
  }

  @override
  Future<DVIncident?> find(String id) => _inner.find(id);

  @override
  Future<List<DVIncident>> all() => _inner.all();
}

/// Text an alert or a person wrote for the people fixing it. It must never
/// reach anything public.
const String internalNote = 'db-7 connection pool at 480/500';

final DVHealthReport health = DVHealthReport(
  status: DVHealthStatus.degraded,
  checks: <String, DVHealthResult>{
    'API': DVHealthResult.up(),
    'Search': DVHealthResult.degraded('db-7.internal:5432 pool exhausted'),
    'Payments': DVHealthResult.up(),
  },
  uptime: const Duration(hours: 3),
);

void main() {
  late DVServiceLevels levels;
  late DVAlerting alerting;
  late DVIncidents incidents;
  late _Store store;
  late String searchIncident;
  late String exportsIncident;
  late String paymentsIncident;
  late String loginIncident;

  setUp(() async {
    const DVNotificationsService notifications = DVNotificationsService();
    notifications
      ..resetRouting()
      ..register(_Provider());

    final Map<String, (num, num)> counts = <String, (num, num)>{
      'checkout': (0, 0),
      'search': (0, 0),
      'exports': (0, 0),
    };
    levels = DVServiceLevels(onDiagnostic: (String c, String m) {})
      ..add(
        const DVServiceLevel(
          name: 'checkout',
          objective: DVObjective.successRate(0.999, over: Duration(days: 30)),
          applies: DVAppliesTo.backendFunction('createOrder'),
        ),
      )
      ..add(
        const DVServiceLevel(
          name: 'search',
          objective: DVObjective.successRate(0.99, over: Duration(hours: 2)),
          applies: DVAppliesTo.backendFunction('search'),
        ),
      )
      ..add(
        const DVServiceLevel(
          name: 'exports',
          objective: DVObjective.successRate(0.995, over: Duration(days: 30)),
          applies: DVAppliesTo.page('/exports'),
        ),
      );
    for (final String name in counts.keys) {
      levels.source(
        name == 'checkout'
            ? const DVAppliesTo.backendFunction('createOrder')
            : name == 'search'
            ? const DVAppliesTo.backendFunction('search')
            : const DVAppliesTo.page('/exports'),
        () => DVServiceLevelCounts(
          total: counts[name]!.$1,
          failed: counts[name]!.$2,
        ),
      );
    }

    num? mail = 20;
    num? exports = 50;
    final DVSignalReaders readers = DVSignalReaders(serviceLevels: levels)
      ..register(const DVSignalRef.queueDepth('mail'), () => mail)
      ..register(const DVSignalRef.queueDepth('exports'), () => exports)
      ..register(const DVSignalRef.queueDepth('reports'), () => null);

    store = _Store();
    int ids = 0;
    incidents = DVIncidents(store: store, newId: () => 'inc-${++ids}');

    alerting =
        DVAlerting(
            readers: readers,
            notifications: notifications,
            pagers: <String, DVAlertPager>{'pagerduty': _DownPager()},
            teams: (String team) async => <String>['ana'],
            incidents: incidents,
            onDiagnostic: (String c, String m) {},
          )
          ..addRule(
            const DVAlertRule(
              name: 'search-burn',
              signal: DVSignalRef.errorBudgetBurn('search'),
              condition: DVAlertWhen.above(2),
              forDuration: Duration(minutes: 5),
              notify: <DVAlertTarget>[
                DVAlertTarget.user('ops-1'),
                DVAlertTarget.pager('pagerduty'),
              ],
            ),
          )
          ..addRule(
            const DVAlertRule(
              name: 'mail-backlog',
              signal: DVSignalRef.queueDepth('mail'),
              condition: DVAlertWhen.above(100),
              forDuration: Duration(minutes: 5),
              notify: <DVAlertTarget>[DVAlertTarget.team('ops')],
            ),
          )
          ..addRule(
            const DVAlertRule(
              name: 'exports-queue',
              signal: DVSignalRef.queueDepth('exports'),
              condition: DVAlertWhen.above(10),
              forDuration: Duration(minutes: 5),
              notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
            ),
          )
          ..addRule(
            const DVAlertRule(
              name: 'reports-queue',
              signal: DVSignalRef.queueDepth('reports'),
              condition: DVAlertWhen.above(10),
              forDuration: Duration(minutes: 5),
            ),
          );

    for (final int minutes in <int>[120, 60, 30, 5, 0]) {
      counts['checkout'] = (
        counts['checkout']!.$1 + 10000,
        counts['checkout']!.$2 + 2,
      );
      counts['search'] = (
        counts['search']!.$1 + 1000,
        counts['search']!.$2 + 50,
      );
      if (minutes == 0) exports = 0;
      await alerting.evaluate(now: ago(Duration(minutes: minutes)));
    }
    mail = 20;
    for (int day = 1; day <= 6; day++) {
      alerting.recordEpisode(
        'mail-backlog',
        firedAt: ago(Duration(days: day, hours: 2)),
        resolvedAt: ago(Duration(days: day, hours: 1)),
        acknowledged: true,
      );
    }

    searchIncident = alerting.state('search-burn').incidentId!;
    exportsIncident = alerting.state('exports-queue').incidentId!;
    await incidents.update(
      searchIncident,
      message: internalNote,
      actor: 'sam',
      now: ago(const Duration(minutes: 20)),
    );
    await incidents.update(
      searchIncident,
      message: 'Search is slower than usual. We are investigating.',
      status: DVIncidentStatus.identified,
      public: true,
      actor: 'sam',
      now: ago(const Duration(minutes: 15)),
    );

    paymentsIncident = (await incidents.openIncident(
      title: 'Payment confirmations delayed',
      message: 'webhook queue backing up behind worker-3',
      components: <String>['Payments'],
      now: ago(const Duration(minutes: 90)),
    )).id;
    await incidents.update(
      paymentsIncident,
      message: 'Some payment confirmations are delayed.',
      public: true,
      now: ago(const Duration(minutes: 80)),
    );
    await incidents.update(
      paymentsIncident,
      message: 'The backlog has cleared. We are watching it.',
      status: DVIncidentStatus.monitoring,
      public: true,
      now: ago(const Duration(minutes: 40)),
    );

    loginIncident = (await incidents.openIncident(
      title: 'Sign-in failures',
      message: 'Sign-in is failing for some users.',
      public: true,
      now: ago(const Duration(days: 3)),
    )).id;
    await incidents.resolve(
      loginIncident,
      message: 'Sign-in is working again.',
      actor: 'sam',
      now: ago(const Duration(days: 3) - const Duration(hours: 1)),
    );
  });

  Future<void> pumpStudio(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool withAlerting = true,
    bool withIncidents = true,
    Object? actor = 'dana',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DVStudioScreen(
            alerting: withAlerting ? alerting : null,
            incidents: withIncidents ? incidents : null,
            actor: actor,
            clock: () => now,
            statusHealth: () async => health,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (withAlerting || withIncidents) {
      await tester.tap(byKey('dv-studio-section-operations'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final Finder field = inKey(key, find.byType(EditableText));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) =>
      tapKey(tester, 'dv-studio-ops-tab-$name');

  Future<void> openIncident(WidgetTester tester, String id) async {
    await tab(tester, 'incidents');
    await tapKey(tester, 'dv-studio-incident-$id');
  }

  group('opt-in', () {
    testWidgets('Studio has no Operations section without alerting or '
        'incidents', (WidgetTester tester) async {
      await pumpStudio(tester, withAlerting: false, withIncidents: false);
      expect(byKey('dv-studio-section-operations'), findsNothing);
    });

    testWidgets('incidents alone are enough, and the overview says there are '
        'no service levels rather than showing none', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, withAlerting: false);
      expect(byKey('dv-studio-operations'), findsOneWidget);
      expect(byKey('dv-studio-ops-no-service-levels'), findsOneWidget);
      expect(
        inKey('dv-studio-ops-open-incidents', find.text('3')),
        findsOneWidget,
      );
    });
  });

  group('overview', () {
    testWidgets('each service level shows its objective, success rate, budget '
        'left, both burn rates and where it stands', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      expect(
        inKey('dv-studio-slo-checkout', find.text('99.9% over 30 days')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-checkout-success', find.text('99.980%')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-checkout-budget', find.text('99.9% left')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-checkout-burn-long', find.text('0.2×')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-checkout-burn-short', find.text('0.2×')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-checkout-state', find.text('Healthy')),
        findsOneWidget,
      );

      expect(
        inKey('dv-studio-slo-search-success', find.text('95.000%')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-search-burn-long', find.text('5.0×')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-search-budget', find.text('Exhausted')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-slo-search-state', find.text('Budget exhausted')),
        findsOneWidget,
      );
    });

    testWidgets('a service level with no traffic says so, never 0× and never '
        'healthy', (WidgetTester tester) async {
      await pumpStudio(tester);
      for (final String part in <String>[
        'success',
        'burn-long',
        'burn-short',
      ]) {
        expect(
          inKey('dv-studio-slo-exports-$part', find.text('No traffic')),
          findsOneWidget,
          reason: part,
        );
      }
      expect(
        inKey('dv-studio-slo-exports', find.textContaining('0.0×')),
        findsNothing,
      );
      expect(inKey('dv-studio-slo-exports', find.text('0×')), findsNothing);
      expect(
        inKey('dv-studio-slo-exports', find.text('Healthy')),
        findsNothing,
      );
      expect(
        inKey('dv-studio-slo-exports-state', find.text('No traffic')),
        findsOneWidget,
      );

      // Its budget was not measured, so it is neither full nor green.
      const String budget = 'dv-studio-slo-exports-budget';
      expect(inKey(budget, find.text('Not measured')), findsOneWidget);
      expect(inKey(budget, find.textContaining('%')), findsNothing);
      expect(inKey(budget, find.textContaining('left')), findsNothing);
      for (final FractionallySizedBox bar
          in tester.widgetList<FractionallySizedBox>(
            inKey(budget, find.byType(FractionallySizedBox)),
          )) {
        expect(bar.widthFactor, 0);
      }
    });

    testWidgets(
      'the budget gate\'s decision, open incidents and firing alerts',
      (WidgetTester tester) async {
        await pumpStudio(tester);
        expect(
          inKey('dv-studio-ops-gate', find.text('Hold deploys')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-ops-gate', find.textContaining('search')),
          findsWidgets,
        );
        expect(
          inKey('dv-studio-ops-open-incidents', find.text('3')),
          findsOneWidget,
        );
        expect(inKey('dv-studio-ops-firing', find.text('2')), findsOneWidget);
        // exports saw no requests: it is not a budget with room.
        expect(
          inKey('dv-studio-ops-slo-count', find.textContaining('1 not measured')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-ops-slo-count', find.textContaining('has room')),
          findsNothing,
        );
      },
    );

    testWidgets('with no budget spent, a level that was not measured is not '
        'counted as having room, and the gate tile names it', (
      WidgetTester tester,
    ) async {
      // The fixture above always has an exhausted level, which hides what the
      // overview says when nothing is spent and one level was never measured.
      const DVAppliesTo orders = DVAppliesTo.backendFunction('createOrder');
      const DVAppliesTo exports = DVAppliesTo.page('/exports');
      int total = 0;
      final DVServiceLevels calm =
          DVServiceLevels(onDiagnostic: (String c, String m) {})
            ..add(
              const DVServiceLevel(
                name: 'checkout',
                objective: DVObjective.successRate(
                  0.999,
                  over: Duration(days: 30),
                ),
                applies: orders,
              ),
            )
            ..add(
              const DVServiceLevel(
                name: 'exports',
                objective: DVObjective.successRate(
                  0.995,
                  over: Duration(days: 30),
                ),
                applies: exports,
              ),
            )
            ..source(
              orders,
              () => DVServiceLevelCounts(total: total, failed: 0),
            )
            ..source(
              exports,
              () => const DVServiceLevelCounts(total: 0, failed: 0),
            );
      calm.sample(ago(const Duration(hours: 1)));
      total = 5000;
      calm.sample(now);

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: DVStudioScreen(
              alerting: DVAlerting(
                readers: DVSignalReaders(serviceLevels: calm),
                onDiagnostic: (String c, String m) {},
              ),
              actor: 'dana',
              clock: () => now,
              statusHealth: () async => health,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(byKey('dv-studio-section-operations'));
      await tester.pumpAndSettle();

      expect(
        inKey('dv-studio-ops-slo-count', find.text('1 not measured')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-ops-slo-count', find.textContaining('has room')),
        findsNothing,
      );
      expect(
        inKey('dv-studio-ops-gate', find.textContaining('not measured: exports')),
        findsOneWidget,
      );
    });
  });

  group('alerts', () {
    testWidgets(
      'each rule says whether it is ok, pending, firing or resolving',
      (WidgetTester tester) async {
        await pumpStudio(tester);
        await tab(tester, 'alerts');
        for (final (String rule, String state) in <(String, String)>[
          ('search-burn', 'Firing'),
          ('mail-backlog', 'OK'),
          ('exports-queue', 'Resolving'),
          ('reports-queue', 'OK'),
        ]) {
          expect(
            inKey('dv-studio-alert-$rule-state', find.text(state)),
            findsOneWidget,
            reason: rule,
          );
        }
      },
    );

    testWidgets('a rule shows its signal against its threshold and its last '
        'episode', (WidgetTester tester) async {
      await pumpStudio(tester);
      await tab(tester, 'alerts');
      await tapKey(tester, 'dv-studio-alert-search-burn');
      expect(inKey('dv-studio-alert-value', find.text('5.0×')), findsOneWidget);
      expect(
        inKey('dv-studio-alert-threshold', find.text('above 2.0×')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-alert-last-episode', find.textContaining('Firing')),
        findsWidgets,
      );

      await tapKey(tester, 'dv-studio-alert-mail-backlog');
      expect(inKey('dv-studio-alert-value', find.text('20')), findsOneWidget);
      expect(
        inKey('dv-studio-alert-last-episode', find.textContaining('Resolved')),
        findsWidgets,
      );
    });

    testWidgets('a delivery that missed a target says who and why, beside the '
        'targets it reached', (WidgetTester tester) async {
      await pumpStudio(tester);
      await tab(tester, 'alerts');
      expect(byKey('dv-studio-alert-search-burn-missed'), findsOneWidget);
      await tapKey(tester, 'dv-studio-alert-search-burn');
      expect(byKey('dv-studio-alert-missed'), findsOneWidget);
      expect(
        inKey('dv-studio-alert-delivery-user:ops-1', find.text('Delivered')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-alert-delivery-pager:pagerduty', find.text('Missed')),
        findsOneWidget,
      );
      expect(
        inKey(
          'dv-studio-alert-delivery-pager:pagerduty',
          find.textContaining('HTTP 503'),
        ),
        findsOneWidget,
      );
      expect(
        inKey(
          'dv-studio-alert-delivery-pager:pagerduty',
          find.textContaining('Retried at the next evaluation'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('analysis findings are warnings on the rule they name', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await tab(tester, 'alerts');
      expect(
        inKey('dv-studio-alerts-findings', find.text('2 warnings')),
        findsOneWidget,
      );
      await tapKey(tester, 'dv-studio-alert-mail-backlog');
      expect(
        inKey(
          'dv-studio-alert-finding-0',
          find.textContaining('fired on 6 of the last 7 days'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'dv-studio-alert-reports-queue');
      expect(
        inKey('dv-studio-alert-finding-0', find.textContaining('no target')),
        findsOneWidget,
      );
      await tapKey(tester, 'dv-studio-alert-search-burn');
      expect(byKey('dv-studio-alert-finding-0'), findsNothing);
    });
  });

  group('incidents', () {
    testWidgets('lists open, monitoring and resolved incidents', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await tab(tester, 'incidents');
      for (final (String group, String id) in <(String, String)>[
        ('open', searchIncident),
        ('open', exportsIncident),
        ('monitoring', paymentsIncident),
        ('resolved', loginIncident),
      ]) {
        expect(
          find.descendant(
            of: byKey('dv-studio-incidents-$group'),
            matching: byKey('dv-studio-incident-$id'),
          ),
          findsOneWidget,
          reason: '$group $id',
        );
      }
    });

    testWidgets('the timeline marks what is internal and what is public', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      expect(
        inKey('dv-studio-incident-entry-1', find.text(internalNote)),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-incident-entry-1', find.text('Internal')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-incident-entry-2', find.text('Public')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-incident-entry-2', find.textContaining('sam')),
        findsWidgets,
      );
    });

    testWidgets('what an alert wrote on the timeline reads its value the way '
        'the rule does', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      expect(
        inKey(
          'dv-studio-incident-entry-0',
          find.textContaining('×, above 2.0×'),
        ),
        findsOneWidget,
      );
      expect(
        inKey(
          'dv-studio-incident-entry-0',
          find.textContaining(RegExp(r'\d\.\d{3,}')),
        ),
        findsNothing,
      );
    });

    testWidgets('resolve is offered only while the incident is in monitoring', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      expect(byKey('dv-studio-incident-resolve'), findsNothing);
      expect(byKey('dv-studio-incident-resolve-unavailable'), findsOneWidget);

      await tapKey(tester, 'dv-studio-incident-$loginIncident');
      expect(byKey('dv-studio-incident-resolve'), findsNothing);

      await tapKey(tester, 'dv-studio-incident-$paymentsIncident');
      expect(byKey('dv-studio-incident-resolve'), findsOneWidget);
      expect(byKey('dv-studio-incident-resolve-unavailable'), findsNothing);
    });

    testWidgets('an internal note is written through the runtime, as the '
        'actor, and is not public', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      expect(byKey('dv-studio-incident-internal-warning'), findsOneWidget);
      await type(
        tester,
        'dv-studio-incident-message',
        'Paged the database on-call.',
      );
      await tapKey(tester, 'dv-studio-incident-post');

      final DVIncidentEntry entry = (await tester.runAsync<DVIncident?>(
        () => incidents.find(searchIncident),
      ))!.timeline.last;
      expect(entry.message, 'Paged the database on-call.');
      expect(entry.public, isFalse);
      expect(entry.actor, 'dana');
      expect(entry.at, now);
      expect(find.text('Paged the database on-call.'), findsOneWidget);
    });

    testWidgets('a public update previews exactly what the status page will '
        'show, and never an internal note', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      await tapKey(tester, 'dv-studio-incident-mode-public');
      expect(byKey('dv-studio-incident-internal-warning'), findsOneWidget);
      await type(
        tester,
        'dv-studio-incident-message',
        'Search has recovered for most users.',
      );
      await tapKey(tester, 'dv-studio-incident-status-monitoring');
      await type(tester, 'dv-studio-incident-public-title', 'Slow search');

      const String preview = 'dv-studio-incident-public-preview';
      expect(inKey(preview, find.text('Slow search')), findsOneWidget);
      expect(inKey(preview, find.text('Alert search-burn')), findsNothing);
      expect(
        inKey(preview, find.text('Search has recovered for most users.')),
        findsOneWidget,
      );
      expect(
        inKey(
          preview,
          find.text('Search is slower than usual. We are investigating.'),
        ),
        findsOneWidget,
      );
      expect(inKey(preview, find.textContaining('db-7')), findsNothing);
      expect(
        inKey(preview, find.textContaining('alert search-burn fired')),
        findsNothing,
      );
      expect(inKey(preview, find.text('Monitoring')), findsWidgets);

      await tapKey(tester, 'dv-studio-incident-post');
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(searchIncident),
      ))!;
      expect(stored.timeline.last.public, isTrue);
      expect(stored.timeline.last.actor, 'dana');
      expect(stored.status, DVIncidentStatus.monitoring);
      expect(stored.title, 'Slow search');
      expect(stored.publicTitle, 'Slow search');
      // Now in monitoring, it can be resolved.
      expect(byKey('dv-studio-incident-resolve'), findsOneWidget);
    });

    testWidgets('a public update on an incident named after its alert asks for '
        'the public title first, and previews the title that will be '
        'published', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      await tapKey(tester, 'dv-studio-incident-mode-public');
      await type(
        tester,
        'dv-studio-incident-message',
        'Search is back to normal speed.',
      );

      // No title typed: nothing can be posted, and the preview shows what the
      // runtime publishes in its place -- never the rule name.
      expect(detector(tester, 'dv-studio-incident-post').onTap, isNull);
      expect(
        find.textContaining('Give it a public title'),
        findsWidgets,
      );
      const String preview = 'dv-studio-incident-public-preview';
      expect(inKey(preview, find.text('Service issue')), findsOneWidget);
      expect(
        inKey(preview, find.textContaining('search-burn')),
        findsNothing,
      );

      await type(tester, 'dv-studio-incident-public-title', 'Slow search');
      expect(inKey(preview, find.text('Slow search')), findsOneWidget);
      expect(inKey(preview, find.text('Service issue')), findsNothing);
      expect(detector(tester, 'dv-studio-incident-post').onTap, isNotNull);

      await tapKey(tester, 'dv-studio-incident-post');
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(searchIncident),
      ))!;
      expect(stored.publicTitle, 'Slow search');
      expect(stored.timeline.last.public, isTrue);
      expect(stored.timeline.last.message, 'Search is back to normal speed.');

      // Titled now: the next public update does not ask again.
      await tapKey(tester, 'dv-studio-incident-mode-public');
      expect(byKey('dv-studio-incident-public-title'), findsNothing);
    });

    testWidgets('a public update on an incident a person named asks for no '
        'title', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, paymentsIncident);
      await tapKey(tester, 'dv-studio-incident-mode-public');
      expect(byKey('dv-studio-incident-public-title'), findsNothing);
      await type(tester, 'dv-studio-incident-message', 'Still watching.');
      expect(detector(tester, 'dv-studio-incident-post').onTap, isNotNull);
    });

    testWidgets('renaming for the public changes the title the status page '
        'shows', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      await type(tester, 'dv-studio-incident-title', 'Slow search results');
      await tapKey(tester, 'dv-studio-incident-rename');
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(searchIncident),
      ))!;
      expect(stored.title, 'Slow search results');
      expect(stored.timeline.last.public, isFalse);

      await tab(tester, 'status');
      expect(
        inKey('dv-studio-status-preview', find.text('Slow search results')),
        findsOneWidget,
      );
    });

    testWidgets('resolving from monitoring is done by the actor, in public', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await openIncident(tester, paymentsIncident);
      await type(
        tester,
        'dv-studio-incident-resolve-message',
        'Payment confirmations are arriving normally.',
      );
      await tapKey(tester, 'dv-studio-incident-resolve');
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(paymentsIncident),
      ))!;
      expect(stored.status, DVIncidentStatus.resolved);
      expect(stored.timeline.last.actor, 'dana');
      expect(stored.timeline.last.public, isTrue);
      expect(
        find.descendant(
          of: byKey('dv-studio-incidents-resolved'),
          matching: byKey('dv-studio-incident-$paymentsIncident'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an incident moved out of monitoring elsewhere is refused, '
        'inline, and not resolved', (WidgetTester tester) async {
      await pumpStudio(tester);
      await openIncident(tester, paymentsIncident);
      await tester.runAsync(
        () => incidents.update(
          paymentsIncident,
          message: 'Backlog is growing again.',
          status: DVIncidentStatus.investigating,
        ),
      );
      await type(tester, 'dv-studio-incident-resolve-message', 'All clear.');
      await tapKey(tester, 'dv-studio-incident-resolve');

      expect(
        inKey('dv-studio-incident-error', find.textContaining('investigating')),
        findsWidgets,
      );
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(paymentsIncident),
      ))!;
      expect(stored.status, DVIncidentStatus.investigating);
      expect(byKey('dv-studio-incident-resolve'), findsNothing);
    });

    testWidgets('a store that refuses the write is shown where it happened', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await openIncident(tester, searchIncident);
      store.failSaves = true;
      await type(tester, 'dv-studio-incident-message', 'Checking replicas.');
      await tapKey(tester, 'dv-studio-incident-post');
      expect(
        inKey('dv-studio-incident-error', find.textContaining('read-only')),
        findsWidgets,
      );
      store.failSaves = false;
      final DVIncident stored = (await tester.runAsync<DVIncident?>(
        () => incidents.find(searchIncident),
      ))!;
      expect(stored.timeline.last.message, isNot('Checking replicas.'));
    });

    testWidgets('with no actor, nothing can be written and nothing resolved', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, actor: null);
      await openIncident(tester, paymentsIncident);
      await type(tester, 'dv-studio-incident-message', 'A note.');
      expect(detector(tester, 'dv-studio-incident-post').onTap, isNull);
      expect(byKey('dv-studio-incident-resolve'), findsNothing);
    });
  });

  group('status page preview', () {
    testWidgets('is marked as a preview and shows what the public sees, '
        'without internal entries or check detail', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester);
      await tab(tester, 'status');
      const String page = 'dv-studio-status-preview';
      expect(byKey('dv-studio-status-preview-mark'), findsOneWidget);
      expect(
        inKey(page, find.text('Payment confirmations delayed')),
        findsOneWidget,
      );
      expect(inKey(page, find.text('Sign-in failures')), findsOneWidget);
      expect(
        inKey(
          page,
          find.text('Search is slower than usual. We are investigating.'),
        ),
        findsOneWidget,
      );
      // Opened by an alert and never given a public update: not listed.
      expect(inKey(page, find.text('Alert exports-queue')), findsNothing);
      // Opened by an alert, given a public update, never renamed: listed,
      // under a title that names no rule.
      expect(inKey(page, find.textContaining('search-burn')), findsNothing);
      expect(inKey(page, find.text('Service issue')), findsOneWidget);
      expect(inKey(page, find.textContaining('db-7')), findsNothing);
      expect(inKey(page, find.textContaining('worker-3')), findsNothing);
      expect(
        inKey(page, find.textContaining('alert search-burn fired')),
        findsNothing,
      );
      expect(inKey(page, find.text('Search')), findsWidgets);
      expect(inKey(page, find.text('Degraded performance')), findsWidgets);
    });
  });

  group('fits', () {
    for (final Size size in const <Size>[
      Size(800, 600),
      Size(1024, 700),
      Size(1920, 1080),
    ]) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        await pumpStudio(tester, size: size);
        expect(tester.takeException(), isNull);
        await tab(tester, 'alerts');
        for (final String rule in <String>[
          'search-burn',
          'mail-backlog',
          'exports-queue',
          'reports-queue',
        ]) {
          await tapKey(tester, 'dv-studio-alert-$rule');
          expect(tester.takeException(), isNull, reason: rule);
        }
        await tab(tester, 'incidents');
        for (final String id in <String>[
          searchIncident,
          exportsIncident,
          paymentsIncident,
          loginIncident,
        ]) {
          await tapKey(tester, 'dv-studio-incident-$id');
          expect(tester.takeException(), isNull, reason: id);
        }
        await tapKey(tester, 'dv-studio-incident-$searchIncident');
        await tapKey(tester, 'dv-studio-incident-mode-public');
        await type(
          tester,
          'dv-studio-incident-message',
          'We have identified the cause and are rolling out a fix now.',
        );
        expect(tester.takeException(), isNull);
        await tab(tester, 'status');
        expect(tester.takeException(), isNull);
        await tab(tester, 'overview');
        expect(tester.takeException(), isNull);
      });
    }
  });
}

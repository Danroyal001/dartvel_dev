import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Entitlements and recorded events.
///
/// Both read local providers, because those are the only ones holding a record
/// this admin can see: a hosted billing provider or analytics backend answers
/// from someone else's infrastructure. Saying so beats rendering an empty list
/// that reads as "nothing happened".
class DVTelemetryAdmin extends StatefulWidget {
  /// The billing provider to read entitlements from.
  final DVLocalBillingProvider? billing;

  /// The analytics provider to read recorded events from.
  final LocalAnalyticsProvider? analytics;

  /// How many events to show, newest first. A long-running app records more
  /// than a screen can hold.
  final int eventLimit;

  const DVTelemetryAdmin({
    super.key,
    this.billing,
    this.analytics,
    this.eventLimit = 50,
  });

  @override
  State<DVTelemetryAdmin> createState() => _DVTelemetryAdminState();
}

class _DVTelemetryAdminState extends State<DVTelemetryAdmin> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final billing = widget.billing;
    final analytics = widget.analytics;
    return DVBox.scrollableList(<Widget>[
      const DVText('Entitlements and Events')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      GestureDetector(
        key: const ValueKey<String>('dv-telemetry-refresh'),
        onTap: _refresh,
        child: const DVText('Refresh'),
      ),
      if (billing == null && analytics == null)
        const DVText(
          'No local provider configured. A hosted billing or analytics '
          'provider keeps its records on its own infrastructure.',
        ),
      if (billing != null) _entitlements(billing),
      if (analytics != null) _events(analytics),
    ]);
  }

  Widget _entitlements(DVLocalBillingProvider billing) {
    final grants = billing.grants;
    final customers = grants.keys.toList()..sort();
    return DVBox.list(<Widget>[
      DVText('Entitlements (${customers.length} customers)').modifier(
          const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      // A customer who lost access and one who never had it both answer false
      // to hasEntitlement; the list is what tells them apart.
      if (customers.isEmpty) const DVText('Nobody holds an entitlement.'),
      for (final customer in customers)
        DVBox.list(<Widget>[
          DVText(customer),
          DVText((grants[customer]!.toList()..sort()).join(', ')),
        ]),
    ]).modifier(const DVModifier().card().padding(16));
  }

  Widget _events(LocalAnalyticsProvider analytics) {
    // Newest first, because the reason someone opens this is something that
    // just happened.
    final events = analytics.events.reversed.take(widget.eventLimit).toList();
    return DVBox.list(<Widget>[
      DVText('Events (${analytics.events.length})').modifier(
          const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      if (events.isEmpty) const DVText('No events recorded.'),
      if (analytics.events.length > events.length)
        DVText('showing the most recent ${events.length}'),
      for (final event in events)
        DVBox.list(<Widget>[
          DVText(event.name),
          DVText(event.timestamp.toIso8601String()),
          if (event.parameters.isNotEmpty)
            DVText(event.parameters.entries
                .map((MapEntry<String, Object> e) => '${e.key}=${e.value}')
                .join(', ')),
        ]),
    ]).modifier(const DVModifier().card().padding(16));
  }
}

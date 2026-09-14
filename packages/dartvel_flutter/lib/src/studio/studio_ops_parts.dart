/// The pieces Studio's Operations section is built from: formatting that
/// never turns an unknown into a number, labels and tones for the runtime's
/// states, and the public rendering of an incident that both the update
/// preview and the status page preview share, so the two cannot disagree.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.ops_parts;

import 'package:dartvel_core/dartvel.dart'
    show
        DVAlertState,
        DVAlertStatus,
        DVComponentStatus,
        DVHealthReport,
        DVHealthResult,
        DVHealthStatus,
        DVIncidentStatus,
        DVPublicIncident,
        DVPublicIncidentUpdate;
import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// A health report with no checks, for a snapshot built only to show
/// incidents.
const DVHealthReport opsNoChecks = DVHealthReport(
  status: DVHealthStatus.up,
  checks: <String, DVHealthResult>{},
  uptime: Duration.zero,
);

/// One line of text that is cut with an ellipsis rather than overflowing.
Widget opsText(
  String text, {
  double size = 13,
  Color color = DVStudioStyle.ink,
  FontWeight weight = FontWeight.w400,
  int maxLines = 1,
  TextAlign? align,
}) => Text(
  text,
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
  style: TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: 1.3,
  ),
);

/// A small coloured label that shortens instead of overflowing.
Widget opsBadge(String text, {Color tone = DVStudioStyle.accent, Key? key}) {
  return Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: opsText(text, size: 11, color: tone, weight: FontWeight.w600),
  );
}

/// A boxed note inside a card: a warning, an explanation, a refusal.
Widget opsNote({
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
              opsText(title, size: 12.5, weight: FontWeight.w600, maxLines: 2),
              const SizedBox(height: 3),
              opsText(body, size: 12, color: DVStudioStyle.muted, maxLines: 6),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The title strip of a card.
Widget opsCardHeader(
  String title,
  String? subtitle, {
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
              opsText(title, size: 14, weight: FontWeight.w600),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                opsText(
                  subtitle,
                  size: 12,
                  color: DVStudioStyle.muted,
                  maxLines: 3,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: DVStudioStyle.space2),
          Flexible(child: trailing),
        ],
      ],
    ),
  );
}

/// A labelled figure. The key goes on the whole fact, so a finder looking
/// for its value finds the value and not a neighbour's.
Widget opsFact(
  String label,
  String value, {
  Key? key,
  Color tone = DVStudioStyle.ink,
  String? detail,
  double size = 15,
  double minWidth = 90,
  double maxWidth = 220,
}) {
  return ConstrainedBox(
    key: key,
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        opsText(
          label.toUpperCase(),
          size: 10.5,
          color: DVStudioStyle.muted,
          weight: FontWeight.w600,
        ),
        const SizedBox(height: 4),
        opsText(value, size: size, color: tone, weight: FontWeight.w600),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 2),
          opsText(detail, size: 11.5, color: DVStudioStyle.faint, maxLines: 2),
        ],
      ],
    ),
  );
}

/// A keyed control that is a whole-width segment of a choice.
Widget opsChoice({
  required String key,
  required String label,
  required bool selected,
  required VoidCallback? onTap,
  IconData? icon,
}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? DVStudioStyle.accentSoft : DVStudioStyle.canvas,
          border: Border.all(
            color: selected ? DVStudioStyle.accent : DVStudioStyle.line,
          ),
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 14,
                color: selected ? DVStudioStyle.accent : DVStudioStyle.muted,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: opsText(
                label,
                size: 12,
                color: selected ? DVStudioStyle.accent : DVStudioStyle.ink,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// --- formatting ---------------------------------------------------------------

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// `14 Sep, 11:30 UTC`.
String opsTime(DateTime at) {
  final DateTime utc = at.toUtc();
  return '${utc.day} ${_months[utc.month - 1]}, '
      '${_two(utc.hour)}:${_two(utc.minute)} UTC';
}

/// `30m ago`, `3h ago`, `2d ago`; `just now` under a minute.
String opsAgo(DateTime at, DateTime now) {
  final Duration since = now.difference(at);
  if (since.inMinutes < 1) return 'just now';
  return '${opsShort(since)} ago';
}

/// `45s`, `5m`, `2h`, `3d`, the largest whole unit.
String opsShort(Duration d) {
  if (d.inDays >= 1 && d.inHours % 24 == 0 || d.inDays >= 2) {
    return '${d.inDays}d';
  }
  if (d.inHours >= 1 && d.inMinutes % 60 == 0 || d.inHours >= 2) {
    return '${d.inHours}h';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// `30 days`, `2 hours`, `1 hour`, `15 minutes`.
String opsLong(Duration d) {
  String unit(int n, String name) => '$n $name${n == 1 ? '' : 's'}';
  if (d.inHours >= 24 && d.inHours % 24 == 0) return unit(d.inDays, 'day');
  if (d.inMinutes >= 60 && d.inMinutes % 60 == 0) {
    return unit(d.inHours, 'hour');
  }
  return unit(d.inMinutes, 'minute');
}

/// A number with at most [digits] decimals and no trailing zeros.
String opsNumber(num value, {int digits = 2}) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.round().toString();
  }
  String text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}

/// A burn rate, or `No traffic` when the runtime had nothing to divide.
///
/// Never `0×` for null: no requests is not a perfect score, and a zero here
/// reads as a service that is fine when it may have stopped answering.
String opsBurn(double? rate) {
  if (rate == null) return 'No traffic';
  return '${rate >= 100 ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1)}×';
}

Color opsBurnTone(double? rate) {
  if (rate == null) return DVStudioStyle.muted;
  if (rate >= 14.4) return DVStudioStyle.danger;
  if (rate > 1) return DVStudioStyle.warning;
  return DVStudioStyle.success;
}

/// `99.9%` from 0.999.
String opsTarget(double target) => '${opsNumber(target * 100, digits: 3)}%';

// --- states -------------------------------------------------------------------

/// OK, Pending, Firing, or Resolving: firing with its condition clear and
/// the resolve delay running.
String opsAlertLabel(DVAlertState state) => switch (state.status) {
  DVAlertStatus.inactive => 'OK',
  DVAlertStatus.pending => 'Pending',
  DVAlertStatus.firing => state.resolvingSince == null ? 'Firing' : 'Resolving',
};

Color opsAlertTone(DVAlertState state) => switch (state.status) {
  DVAlertStatus.inactive => DVStudioStyle.success,
  DVAlertStatus.pending => DVStudioStyle.warning,
  DVAlertStatus.firing =>
    state.resolvingSince == null ? DVStudioStyle.danger : opsMonitoringTone,
};

const Color opsMonitoringTone = Color(0xFF0E8FC7);

String opsIncidentLabel(DVIncidentStatus status) => switch (status) {
  DVIncidentStatus.investigating => 'Investigating',
  DVIncidentStatus.identified => 'Identified',
  DVIncidentStatus.monitoring => 'Monitoring',
  DVIncidentStatus.resolved => 'Resolved',
};

Color opsIncidentTone(DVIncidentStatus status) => switch (status) {
  DVIncidentStatus.investigating => DVStudioStyle.danger,
  DVIncidentStatus.identified => DVStudioStyle.warning,
  DVIncidentStatus.monitoring => opsMonitoringTone,
  DVIncidentStatus.resolved => DVStudioStyle.success,
};

String opsComponentLabel(DVComponentStatus status) => switch (status) {
  DVComponentStatus.operational => 'Operational',
  DVComponentStatus.degraded => 'Degraded performance',
  DVComponentStatus.outage => 'Outage',
};

Color opsComponentTone(DVComponentStatus status) => switch (status) {
  DVComponentStatus.operational => DVStudioStyle.success,
  DVComponentStatus.degraded => DVStudioStyle.warning,
  DVComponentStatus.outage => DVStudioStyle.danger,
};

// --- the public rendering ------------------------------------------------------

/// An incident as the public status page shows it: its title, where it
/// stands, what it affects, and its public updates, newest first.
///
/// Built only from a [DVPublicIncident], which `DVStatusSnapshot.build` makes
/// from public entries alone. Nothing here can reach an internal entry,
/// because nothing here is given one.
class OpsPublicIncidentView extends StatelessWidget {
  const OpsPublicIncidentView({
    super.key,
    required this.incident,
    this.highlightLatest = false,
  });

  final DVPublicIncident incident;

  /// Marks the newest update, for the preview of one about to be posted.
  final bool highlightLatest;

  @override
  Widget build(BuildContext context) {
    final List<DVPublicIncidentUpdate> updates = incident.updates.reversed
        .toList();
    final Color tone = opsIncidentTone(incident.status);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DVStudioStyle.radius),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: opsText(
                    incident.title,
                    size: 15,
                    weight: FontWeight.w700,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: opsBadge(
                    opsIncidentLabel(incident.status),
                    tone: tone,
                  ),
                ),
              ],
            ),
          ),
          if (incident.components.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: opsText(
                'Affects ${incident.components.join(', ')}',
                size: 12,
                color: DVStudioStyle.muted,
                maxLines: 2,
              ),
            ),
          for (int i = 0; i < updates.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: highlightLatest && i == 0
                    ? DVStudioStyle.accent.withValues(alpha: 0.06)
                    : null,
                border: const Border(
                  top: BorderSide(color: DVStudioStyle.line),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (updates[i].status != null) ...<Widget>[
                        Flexible(
                          child: opsText(
                            opsIncidentLabel(updates[i].status!),
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: opsIncidentTone(updates[i].status!),
                          ),
                        ),
                        const SizedBox(width: DVStudioStyle.space2),
                      ],
                      Flexible(
                        child: opsText(
                          opsTime(updates[i].at),
                          size: 12,
                          color: DVStudioStyle.faint,
                        ),
                      ),
                      if (highlightLatest && i == 0) ...<Widget>[
                        const SizedBox(width: DVStudioStyle.space2),
                        Flexible(
                          child: opsBadge(
                            'This update',
                            tone: DVStudioStyle.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  opsText(updates[i].message, size: 13, maxLines: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The icon for where an incident stands.
IconData opsIncidentIcon(DVIncidentStatus status) => switch (status) {
  DVIncidentStatus.investigating => Icons.search,
  DVIncidentStatus.identified => Icons.build_circle_outlined,
  DVIncidentStatus.monitoring => Icons.visibility_outlined,
  DVIncidentStatus.resolved => Icons.check_circle_outline,
};

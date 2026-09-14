/// The status page: a snapshot built from health checks and incident state,
/// and a client that keeps answering when the application it reports on does
/// not.
///
/// The specification ships the page as a federated micro-site module. This is
/// the runtime underneath one: what the application publishes, and what the
/// separately deployed page does with it. A page that reads incident state
/// through the API, not the database, needs exactly these two halves.
library;

import 'dart:async';
import 'dart:convert';

import '../../dartvel.dart';
import 'alert_diagnostics.dart';

enum DVComponentStatus { operational, degraded, outage }

/// One public update on an incident.
class DVPublicIncidentUpdate {
  const DVPublicIncidentUpdate({
    required this.at,
    required this.message,
    this.status,
  });

  final DateTime at;
  final String message;
  final DVIncidentStatus? status;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'message': message,
        if (status != null) 'status': status!.name,
      };

  static DVPublicIncidentUpdate fromJson(Map<String, Object?> json) =>
      DVPublicIncidentUpdate(
        at: DateTime.parse(json['at']! as String),
        message: json['message']! as String,
        status: json['status'] == null
            ? null
            : DVIncidentStatus.values.byName(json['status']! as String),
      );
}

/// An incident as the public sees it: its public updates and nothing else.
class DVPublicIncident {
  const DVPublicIncident({
    required this.id,
    required this.title,
    required this.status,
    required this.openedAt,
    this.resolvedAt,
    this.components = const <String>[],
    required this.updates,
  });

  final String id;
  final String title;
  final DVIncidentStatus status;
  final DateTime openedAt;
  final DateTime? resolvedAt;
  final List<String> components;
  final List<DVPublicIncidentUpdate> updates;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'status': status.name,
        'openedAt': openedAt.toUtc().toIso8601String(),
        if (resolvedAt != null)
          'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
        'components': components,
        'updates': <Map<String, Object?>>[
          for (final DVPublicIncidentUpdate u in updates) u.toJson(),
        ],
      };

  static DVPublicIncident fromJson(Map<String, Object?> json) =>
      DVPublicIncident(
        id: json['id']! as String,
        title: json['title']! as String,
        status: DVIncidentStatus.values.byName(json['status']! as String),
        openedAt: DateTime.parse(json['openedAt']! as String),
        resolvedAt: json['resolvedAt'] == null
            ? null
            : DateTime.parse(json['resolvedAt']! as String),
        components: <String>[
          for (final Object? c
              in (json['components'] as List<Object?>?) ?? <Object?>[])
            c! as String,
        ],
        updates: <DVPublicIncidentUpdate>[
          for (final Object? u in json['updates']! as List<Object?>)
            DVPublicIncidentUpdate.fromJson(u! as Map<String, Object?>),
        ],
      );
}

/// What the application publishes for its status page.
class DVStatusSnapshot {
  const DVStatusSnapshot({
    required this.generatedAt,
    required this.components,
    required this.incidents,
  });

  /// Builds the public snapshot.
  ///
  /// Components are the health checks, by name and status only: a check's
  /// detail is where a connection string or an internal host ends up, and a
  /// public page is the last place it should. Incidents appear once someone
  /// has written a public update -- an alert opens one internally, and what it
  /// wrote is for the people fixing it. Resolved incidents stay listed for
  /// [resolvedWithin].
  static DVStatusSnapshot build({
    required DVHealthReport health,
    required List<DVIncident> incidents,
    required DateTime now,
    Duration resolvedWithin = const Duration(days: 7),
  }) {
    final DateTime cutoff = now.subtract(resolvedWithin);
    final List<DVIncident> listed = <DVIncident>[
      for (final DVIncident incident in incidents)
        if (incident.timeline.any((DVIncidentEntry e) => e.public) &&
            (incident.isOpen ||
                (incident.resolvedAt != null &&
                    incident.resolvedAt!.isAfter(cutoff))))
          incident,
    ]..sort((DVIncident a, DVIncident b) => b.openedAt.compareTo(a.openedAt));

    return DVStatusSnapshot(
      generatedAt: now,
      components: <String, DVComponentStatus>{
        for (final MapEntry<String, DVHealthResult> check
            in health.checks.entries)
          check.key: switch (check.value.status) {
            DVHealthStatus.up => DVComponentStatus.operational,
            DVHealthStatus.degraded => DVComponentStatus.degraded,
            DVHealthStatus.down => DVComponentStatus.outage,
          },
      },
      incidents: <DVPublicIncident>[
        for (final DVIncident incident in listed)
          DVPublicIncident(
            id: incident.id,
            title: incident.title,
            status: incident.status,
            openedAt: incident.openedAt,
            resolvedAt: incident.resolvedAt,
            components: List<String>.of(incident.components),
            updates: <DVPublicIncidentUpdate>[
              for (final DVIncidentEntry entry in incident.timeline)
                if (entry.public)
                  DVPublicIncidentUpdate(
                    at: entry.at,
                    message: entry.message,
                    status: entry.status,
                  ),
            ],
          ),
      ],
    );
  }

  static DVStatusSnapshot fromJson(Map<String, Object?> json) =>
      DVStatusSnapshot(
        generatedAt: DateTime.parse(json['generatedAt']! as String),
        components: <String, DVComponentStatus>{
          for (final MapEntry<String, Object?> c
              in (json['components']! as Map<String, Object?>).entries)
            c.key: DVComponentStatus.values.byName(c.value! as String),
        },
        incidents: <DVPublicIncident>[
          for (final Object? i in json['incidents']! as List<Object?>)
            DVPublicIncident.fromJson(i! as Map<String, Object?>),
        ],
      );

  /// When this was true.
  final DateTime generatedAt;
  final Map<String, DVComponentStatus> components;
  final List<DVPublicIncident> incidents;

  /// The worst component -- and never "operational" while a listed incident
  /// is open, which is the page contradicting its own incident notice.
  DVComponentStatus get overall {
    DVComponentStatus worst = DVComponentStatus.operational;
    for (final DVComponentStatus status in components.values) {
      if (status.index > worst.index) worst = status;
    }
    if (worst == DVComponentStatus.operational &&
        incidents.any((DVPublicIncident i) => i.status != DVIncidentStatus.resolved)) {
      return DVComponentStatus.degraded;
    }
    return worst;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'overall': overall.name,
        'components': <String, Object?>{
          for (final MapEntry<String, DVComponentStatus> c
              in components.entries)
            c.key: c.value.name,
        },
        'incidents': <Map<String, Object?>>[
          for (final DVPublicIncident i in incidents) i.toJson(),
        ],
      };
}

/// What the page shows.
class DVStatusView {
  const DVStatusView({this.snapshot, required this.stale, this.error});

  /// The newest snapshot the page has, or null when it has never had one.
  final DVStatusSnapshot? snapshot;

  /// True when [snapshot] is not what the application says now, because the
  /// application could not be asked.
  final bool stale;

  /// Why the application could not be asked.
  final String? error;

  /// When the snapshot was true -- not when it was served.
  DateTime? get asOf => snapshot?.generatedAt;

  /// Nothing to show: never reached, and nothing kept.
  bool get isUnknown => snapshot == null;
}

/// Where the page keeps its last good snapshot.
///
/// It has to outlive the page's own process: a page restarted during the
/// outage it exists to explain comes back with nothing otherwise.
abstract class DVStatusSnapshotCache {
  Future<DVStatusSnapshot?> read();
  Future<void> write(DVStatusSnapshot snapshot);
}

class DVMemoryStatusSnapshotCache implements DVStatusSnapshotCache {
  String? _json;

  @override
  Future<DVStatusSnapshot?> read() async {
    final String? json = _json;
    return json == null
        ? null
        : DVStatusSnapshot.fromJson(jsonDecode(json) as Map<String, Object?>);
  }

  @override
  Future<void> write(DVStatusSnapshot snapshot) async {
    _json = jsonEncode(snapshot.toJson());
  }
}

/// The status page's side: asks the application, and degrades to the last
/// known state when it cannot.
class DVStatusPageClient {
  DVStatusPageClient({
    required Future<DVHttpResponse> Function() fetch,
    required this.cache,
    this.timeout = const Duration(seconds: 5),
    DateTime Function()? clock,
    void Function(String code, String message)? onDiagnostic,
  })  : _fetch = fetch,
        _clock = clock ?? DateTime.now,
        _diagnose = onDiagnostic ?? dvLogAlertDiagnostic;

  final DVStatusSnapshotCache cache;

  /// How long the application gets to answer. An unreachable host often does
  /// not refuse, it just does not answer, and a page that waits with it is a
  /// spinner where the explanation should be.
  final Duration timeout;

  final Future<DVHttpResponse> Function() _fetch;
  final DateTime Function() _clock;
  final void Function(String code, String message) _diagnose;
  bool _reportedStale = false;

  Future<DVStatusView> load() async {
    String? error;
    DVStatusSnapshot? fresh;
    try {
      final DVHttpResponse response = await _withTimeout();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // A gateway's 503 can carry a perfectly parseable body. It is still
        // not the application speaking, and caching it would overwrite the
        // last true answer with an empty one.
        error = 'HTTP ${response.statusCode}';
      } else {
        fresh = DVStatusSnapshot.fromJson(
            jsonDecode(response.body) as Map<String, Object?>);
      }
    } on Object catch (e) {
      error = '$e';
    }

    if (fresh != null) {
      try {
        await cache.write(fresh);
      } on Object {
        // Serving the fresh answer matters more than keeping it.
      }
      _reportedStale = false;
      return DVStatusView(snapshot: fresh, stale: false);
    }

    DVStatusSnapshot? last;
    try {
      last = await cache.read();
    } on Object {
      last = null;
    }
    if (last != null && !_reportedStale) {
      _reportedStale = true;
      final Duration age = _clock().difference(last.generatedAt);
      _diagnose(
        'DV-ALERT-004',
        'the application was unreachable ($error); serving the snapshot from '
        '${last.generatedAt.toUtc().toIso8601String()}, '
        '${age.inMinutes} minutes old',
      );
    }
    return DVStatusView(snapshot: last, stale: true, error: error);
  }

  Future<DVHttpResponse> _withTimeout() {
    final Completer<DVHttpResponse> done = Completer<DVHttpResponse>();
    final Timer timer = Timer(timeout, () {
      if (!done.isCompleted) {
        done.completeError(
            TimeoutException('no answer', timeout), StackTrace.current);
      }
    });
    unawaited(Future<DVHttpResponse>.sync(_fetch).then(
      (DVHttpResponse response) {
        if (!done.isCompleted) done.complete(response);
      },
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
    ));
    return done.future.whenComplete(timer.cancel);
  }
}

/// People who asked to hear about incidents, through the same notification
/// channels as everything else.
class DVStatusSubscribers {
  DVStatusSubscribers({
    DVNotificationsService notifications = const DVNotificationsService(),
    this.channels = const <DVNotificationChannel>[
      DVNotificationChannel.email,
      DVNotificationChannel.inApp,
    ],
  }) : _notifications = notifications;

  final DVNotificationsService _notifications;
  final List<DVNotificationChannel> channels;
  final Set<String> _recipients = <String>{};

  void subscribe(String recipient) => _recipients.add(recipient);
  void unsubscribe(String recipient) => _recipients.remove(recipient);

  /// Sends [incident]'s latest public update to every subscriber, and returns
  /// how many it reached. An incident with no public update sends nothing.
  Future<int> announce(DVIncident incident) async {
    DVIncidentEntry? latest;
    for (final DVIncidentEntry entry in incident.timeline) {
      if (entry.public) latest = entry;
    }
    if (latest == null) return 0;

    final DVNotificationMessage message = DVNotificationMessage(
      title: incident.title,
      body: latest.message,
      channels: channels,
      data: <String, String>{
        'incident': incident.id,
        'status': incident.status.name,
      },
    );
    int reached = 0;
    for (final String recipient in _recipients) {
      try {
        final DVNotificationDelivery delivery =
            await _notifications.send(recipient, message);
        if (!delivery.isSilent) reached++;
      } on Object {
        // One unreachable subscriber is not a reason to skip the rest.
      }
    }
    return reached;
  }
}

/// Incidents: what alerts open, what crash spikes link into, and what a
/// status page tells the public.
///
/// The specification describes an incident as a generated model. The runtime
/// has no model of its own to generate from, so this is the record and its
/// store; an application that declares an incident model supplies a
/// [DVIncidentStore] over it.
library;

import 'dart:math';

enum DVIncidentStatus { investigating, identified, monitoring, resolved }

/// One line of an incident's timeline.
class DVIncidentEntry {
  const DVIncidentEntry({
    required this.at,
    required this.message,
    this.status,
    this.public = false,
    this.source = 'human',
    this.actor,
  });

  final DateTime at;
  final String message;

  /// The status this entry moved the incident to, if it moved it.
  final DVIncidentStatus? status;

  /// Whether a status page shows it.
  ///
  /// Off by default. What an alert writes -- a metric name, a threshold, a
  /// host -- is for the people fixing it, and a timeline that published every
  /// entry would put internal detail on a public page the first time an alert
  /// fired.
  final bool public;

  /// `alert`, `crash` or `human`.
  final String source;

  /// Who wrote it, for an entry a person wrote. Kept on the timeline and
  /// never published: a status page names what happened, not who typed it.
  final String? actor;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'message': message,
        if (status != null) 'status': status!.name,
        'public': public,
        'source': source,
        if (actor != null) 'actor': actor,
      };

  static DVIncidentEntry fromJson(Map<String, Object?> json) => DVIncidentEntry(
        at: DateTime.parse(json['at']! as String),
        message: json['message']! as String,
        status: json['status'] == null
            ? null
            : DVIncidentStatus.values.byName(json['status']! as String),
        public: json['public'] == true,
        source: (json['source'] as String?) ?? 'human',
        actor: json['actor'] as String?,
      );
}

/// An incident and its timeline.
class DVIncident {
  DVIncident({
    required this.id,
    required this.title,
    required this.openedAt,
    this.status = DVIncidentStatus.investigating,
    this.resolvedAt,
    List<String> components = const <String>[],
    List<DVIncidentEntry> timeline = const <DVIncidentEntry>[],
    Set<String> rules = const <String>{},
    Set<String> crashFingerprints = const <String>{},
    String? titleSource,
  })  : titleSource = titleSource ??
            (timeline.isEmpty ? 'human' : timeline.first.source),
        components = <String>[...components],
        timeline = <DVIncidentEntry>[...timeline],
        rules = <String>{...rules},
        crashFingerprints = <String>{...crashFingerprints};

  final String id;
  String title;

  /// Who wrote [title]: `alert`, `crash` or `human`, as for an entry.
  ///
  /// When not given it is the source of the entry that opened the incident,
  /// which is who [DVIncidents.openIncident] titled it for -- and what an
  /// incident stored before titles were attributed is read as.
  String titleSource;

  /// The title a status page shows.
  ///
  /// [title] when a person wrote it. An alert titles its incident after the
  /// rule and a crash spike after the release, and both are internal names:
  /// in their place this names the public components affected, or says
  /// `Service issue` when there are none. Publishing an incident is a person's
  /// decision, but naming it is a separate one, and the update that should be
  /// on the page at 03:00 is not held back because nobody got to the rename.
  String get publicTitle {
    if (titleSource == 'human') return title;
    if (components.isEmpty) return 'Service issue';
    final String names = components.length == 1
        ? components.single
        : '${components.sublist(0, components.length - 1).join(', ')} and '
            '${components.last}';
    return 'Issue affecting $names';
  }

  final DateTime openedAt;
  DVIncidentStatus status;
  DateTime? resolvedAt;

  /// The status-page components it affects.
  final List<String> components;
  final List<DVIncidentEntry> timeline;

  /// The alert rules that opened or joined it.
  final Set<String> rules;

  /// The crash groups linked into it.
  final Set<String> crashFingerprints;

  bool get isOpen => status != DVIncidentStatus.resolved;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'titleSource': titleSource,
        'openedAt': openedAt.toUtc().toIso8601String(),
        'status': status.name,
        if (resolvedAt != null) 'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
        'components': components,
        'timeline': <Map<String, Object?>>[
          for (final DVIncidentEntry entry in timeline) entry.toJson(),
        ],
        'rules': rules.toList(),
        'crashFingerprints': crashFingerprints.toList(),
      };

  static DVIncident fromJson(Map<String, Object?> json) => DVIncident(
        id: json['id']! as String,
        title: json['title']! as String,
        titleSource: json['titleSource'] as String?,
        openedAt: DateTime.parse(json['openedAt']! as String),
        status: DVIncidentStatus.values.byName(json['status']! as String),
        resolvedAt: json['resolvedAt'] == null
            ? null
            : DateTime.parse(json['resolvedAt']! as String),
        components: <String>[
          for (final Object? c in (json['components'] as List<Object?>?) ?? <Object?>[])
            c! as String,
        ],
        timeline: <DVIncidentEntry>[
          for (final Object? e in (json['timeline'] as List<Object?>?) ?? <Object?>[])
            DVIncidentEntry.fromJson(e! as Map<String, Object?>),
        ],
        rules: <String>{
          for (final Object? r in (json['rules'] as List<Object?>?) ?? <Object?>[])
            r! as String,
        },
        crashFingerprints: <String>{
          for (final Object? f
              in (json['crashFingerprints'] as List<Object?>?) ?? <Object?>[])
            f! as String,
        },
      );
}

/// Where incidents are kept.
abstract class DVIncidentStore {
  Future<void> save(DVIncident incident);
  Future<DVIncident?> find(String id);
  Future<List<DVIncident>> all();
}

/// Incidents in memory, for tests and a single process.
class DVMemoryIncidentStore implements DVIncidentStore {
  final Map<String, Map<String, Object?>> _rows =
      <String, Map<String, Object?>>{};

  // Stored as JSON, so a caller holding an incident it read cannot change the
  // stored one without saving -- which is how a real store behaves, and a
  // memory store that shares instances hides every missing save.
  @override
  Future<void> save(DVIncident incident) async {
    _rows[incident.id] = incident.toJson();
  }

  @override
  Future<DVIncident?> find(String id) async {
    final Map<String, Object?>? row = _rows[id];
    return row == null ? null : DVIncident.fromJson(row);
  }

  @override
  Future<List<DVIncident>> all() async => <DVIncident>[
        for (final Map<String, Object?> row in _rows.values)
          DVIncident.fromJson(row),
      ];
}

/// Opens, updates and resolves incidents.
class DVIncidents {
  DVIncidents({
    required this.store,
    DateTime Function()? clock,
    String Function()? newId,
  })  : _clock = clock ?? DateTime.now,
        _newId = newId ?? _randomId;

  final DVIncidentStore store;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final Random _random = Random.secure();
  static String _randomId() => <String>[
        for (int i = 0; i < 8; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();

  Future<DVIncident?> find(String id) => store.find(id);

  /// Open incidents, newest first.
  Future<List<DVIncident>> open() async => (await store.all())
      .where((DVIncident i) => i.isOpen)
      .toList()
    ..sort((DVIncident a, DVIncident b) => b.openedAt.compareTo(a.openedAt));

  Future<DVIncident> openIncident({
    required String title,
    required String message,
    List<String> components = const <String>[],
    String? rule,
    String source = 'human',
    bool public = false,
    DateTime? now,
  }) async {
    final DateTime at = now ?? _clock();
    final DVIncident incident = DVIncident(
      id: _newId(),
      title: title,
      titleSource: source,
      openedAt: at,
      components: components,
      rules: <String>{if (rule != null) rule},
      timeline: <DVIncidentEntry>[
        DVIncidentEntry(
          at: at,
          message: message,
          status: DVIncidentStatus.investigating,
          public: public,
          source: source,
        ),
      ],
    );
    await store.save(incident);
    return incident;
  }

  /// Appends [message] to the timeline, moving the incident to [status] when
  /// given.
  Future<DVIncident> update(
    String id, {
    required String message,
    DVIncidentStatus? status,
    bool public = false,
    String source = 'human',
    String? rule,
    String? title,
    String? actor,
    DateTime? now,
  }) async {
    final DVIncident? incident = await store.find(id);
    if (incident == null) {
      throw ArgumentError.value(id, 'id', 'no incident with this id');
    }
    // An alert names its incident after the rule. The title a status page
    // shows is the one a person gives it.
    if (title != null) {
      incident
        ..title = title
        ..titleSource = source;
    }
    final DateTime at = now ?? _clock();
    incident.timeline.add(DVIncidentEntry(
      at: at,
      message: message,
      status: status,
      public: public,
      source: source,
      actor: actor,
    ));
    if (rule != null) incident.rules.add(rule);
    if (status != null) {
      incident.status = status;
      incident.resolvedAt = status == DVIncidentStatus.resolved ? at : null;
    }
    await store.save(incident);
    return incident;
  }

  /// Declares the incident over, in public.
  Future<DVIncident> resolve(String id,
          {required String message, String? actor, DateTime? now}) =>
      update(id,
          message: message,
          status: DVIncidentStatus.resolved,
          public: true,
          actor: actor,
          now: now);

  /// Links a crash spike into the newest open incident, or opens one.
  ///
  /// A crash spike during an outage is almost always the outage, and two
  /// incidents for one event split the evidence a postmortem needs in half.
  Future<DVIncident> linkCrashSpike({
    required String fingerprint,
    required String release,
    required String message,
    DateTime? now,
  }) async {
    final List<DVIncident> current = await open();
    if (current.isEmpty) {
      final DVIncident opened = await openIncident(
        title: 'Crash spike in $release',
        message: message,
        source: 'crash',
        now: now,
      );
      opened.crashFingerprints.add(fingerprint);
      await store.save(opened);
      return opened;
    }
    final DVIncident incident = current.first;
    incident.crashFingerprints.add(fingerprint);
    incident.timeline.add(DVIncidentEntry(
      at: now ?? _clock(),
      message: message,
      source: 'crash',
    ));
    await store.save(incident);
    return incident;
  }
}

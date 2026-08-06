/// Presence: who is currently on a channel, generated from authenticated
/// session state rather than a separate realtime facade.
library dartvel_core.sync.presence;

import 'dart:async';

import '../tenancy/tenants.dart';

/// One participant on a channel.
class DVPresenceMember {
  /// The authenticated identity — a user id, not a connection id, so the same
  /// person on two devices is one member.
  final String id;

  /// Arbitrary state the member publishes: display name, cursor, status.
  final Map<String, Object?> state;

  /// The tenant this membership belongs to, captured when it was recorded.
  final String tenant;

  /// When the member was last heard from. Presence is a liveness claim, so
  /// it has to be refreshed or it expires.
  final DateTime lastSeen;

  DVPresenceMember({
    required this.id,
    Map<String, Object?>? state,
    String? tenant,
    DateTime? lastSeen,
  })  : state = state ?? <String, Object?>{},
        tenant = tenant ?? const DVTenants().currentTenant,
        lastSeen = lastSeen ?? DateTime.now();

  DVPresenceMember copyWith({
    Map<String, Object?>? state,
    DateTime? lastSeen,
  }) =>
      DVPresenceMember(
        id: id,
        state: state ?? this.state,
        tenant: tenant,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'state': state,
        'tenant': tenant,
        'lastSeen': lastSeen.toIso8601String(),
      };

  static DVPresenceMember fromJson(Map<String, Object?> json) =>
      DVPresenceMember(
        id: json['id']! as String,
        state: (json['state'] as Map?)?.cast<String, Object?>(),
        tenant: json['tenant'] as String?,
        lastSeen: DateTime.parse(json['lastSeen']! as String),
      );
}

/// What happened on a channel.
enum DVPresenceEventKind { joined, left, updated }

class DVPresenceEvent {
  final DVPresenceEventKind kind;
  final String channel;
  final DVPresenceMember member;

  const DVPresenceEvent({
    required this.kind,
    required this.channel,
    required this.member,
  });
}

/// Carries presence between processes, the way [DVModelSyncTransport] carries
/// model changes. Without one, presence is per-process.
abstract class DVPresenceTransport {
  Future<void> send(Map<String, Object?> envelope);

  Stream<Map<String, Object?>> get incoming;
}

/// Channel membership.
///
/// Not a realtime namespace — the spec forbids one. This is membership state
/// built from authenticated identity, delivered through the same kind of
/// transport seam model sync uses.
class DVPresence {
  DVPresence._();

  static final Map<String, Map<String, DVPresenceMember>> _channels = {};
  static final StreamController<DVPresenceEvent> _events =
      StreamController<DVPresenceEvent>.broadcast();
  static DVPresenceTransport? _transport;
  static StreamSubscription<Map<String, Object?>>? _subscription;
  static Timer? _sweeper;

  /// How long a membership survives without a heartbeat.
  ///
  /// Presence claims liveness; a member that stopped heartbeating is gone
  /// whether or not it announced a departure, which is the case a crashed
  /// client always produces.
  static Duration timeout = const Duration(seconds: 45);

  /// Every presence change, filtered to the current tenant.
  static Stream<DVPresenceEvent> get events => _events.stream.where(
        (DVPresenceEvent event) =>
            event.member.tenant == const DVTenants().currentTenant,
      );

  /// Changes on one channel.
  static Stream<DVPresenceEvent> channel(String name) =>
      events.where((DVPresenceEvent event) => event.channel == name);

  /// Connects the cross-process transport.
  static void useTransport(DVPresenceTransport transport) {
    unawaited(_subscription?.cancel());
    _transport = transport;
    _subscription = transport.incoming.listen(_receive);
  }

  /// Records [member] as present on [channel], or refreshes them.
  ///
  /// Idempotent: joining twice updates rather than duplicating, because a
  /// reconnect is a join and must not double-count the same identity.
  static Future<void> join(
    String channel,
    DVPresenceMember member, {
    bool broadcast = true,
  }) async {
    final members = _channels.putIfAbsent(
      channel,
      () => <String, DVPresenceMember>{},
    );
    final existing = members[member.id];
    members[member.id] = member;
    _events.add(
      DVPresenceEvent(
        kind: existing == null
            ? DVPresenceEventKind.joined
            : DVPresenceEventKind.updated,
        channel: channel,
        member: member,
      ),
    );
    if (broadcast) {
      await _send(<String, Object?>{
        'op': existing == null ? 'join' : 'update',
        'channel': channel,
        'member': member.toJson(),
      });
    }
  }

  /// Refreshes a member's liveness, and optionally their state.
  ///
  /// A heartbeat for someone not on the channel is a join: a client that
  /// missed its own join message should still appear.
  static Future<void> heartbeat(
    String channel,
    String memberId, {
    Map<String, Object?>? state,
  }) async {
    final existing = _channels[channel]?[memberId];
    final member = existing?.copyWith(
          state: state,
          lastSeen: DateTime.now(),
        ) ??
        DVPresenceMember(id: memberId, state: state);
    await join(channel, member);
  }

  static Future<void> leave(
    String channel,
    String memberId, {
    bool broadcast = true,
  }) async {
    final member = _channels[channel]?.remove(memberId);
    if (member == null) return;
    if (_channels[channel]?.isEmpty ?? false) _channels.remove(channel);
    _events.add(
      DVPresenceEvent(
        kind: DVPresenceEventKind.left,
        channel: channel,
        member: member,
      ),
    );
    if (broadcast) {
      await _send(<String, Object?>{
        'op': 'leave',
        'channel': channel,
        'member': member.toJson(),
      });
    }
  }

  /// Who is on [channel] now, for the current tenant.
  ///
  /// Expired members are excluded here as well as swept, so a caller reading
  /// between sweeps never sees someone who has gone silent.
  static List<DVPresenceMember> members(String channel) {
    final tenant = const DVTenants().currentTenant;
    final now = DateTime.now();
    return <DVPresenceMember>[
      for (final member
          in _channels[channel]?.values ?? const <DVPresenceMember>[])
        if (member.tenant == tenant &&
            now.difference(member.lastSeen) <= timeout)
          member,
    ];
  }

  /// Channels with at least one live member for the current tenant.
  static List<String> get channels => <String>[
        for (final name in _channels.keys)
          if (members(name).isNotEmpty) name,
      ]..sort();

  /// Drops members whose heartbeat lapsed, emitting a `left` for each.
  ///
  /// Returns how many were removed, so a caller can log a mass disconnect.
  static Future<int> sweep() async {
    final now = DateTime.now();
    final expired = <({String channel, DVPresenceMember member})>[];
    for (final entry in _channels.entries) {
      for (final member in entry.value.values) {
        if (now.difference(member.lastSeen) > timeout) {
          expired.add((channel: entry.key, member: member));
        }
      }
    }
    for (final item in expired) {
      // Not broadcast: every process sweeps its own copy on the same rule,
      // so announcing would multiply one departure by the fleet size.
      await leave(item.channel, item.member.id, broadcast: false);
    }
    return expired.length;
  }

  /// Sweeps on an interval. Call once at boot on a long-lived process.
  static void startSweeping({Duration every = const Duration(seconds: 15)}) {
    _sweeper?.cancel();
    _sweeper = Timer.periodic(every, (_) => unawaited(sweep()));
  }

  static void stopSweeping() {
    _sweeper?.cancel();
    _sweeper = null;
  }

  static Future<void> _send(Map<String, Object?> envelope) async {
    final transport = _transport;
    if (transport == null) return;
    await transport.send(envelope);
  }

  static void _receive(Map<String, Object?> envelope) {
    final channel = envelope['channel'];
    final raw = envelope['member'];
    if (channel is! String || raw is! Map) return;
    final member = DVPresenceMember.fromJson(raw.cast<String, Object?>());
    // Arriving events are applied locally but never rebroadcast, or two
    // processes would echo each other forever.
    switch (envelope['op']) {
      case 'join':
      case 'update':
        unawaited(join(channel, member, broadcast: false));
      case 'leave':
        unawaited(leave(channel, member.id, broadcast: false));
    }
  }

  /// Clears everything. Intended for tests.
  static Future<void> reset() async {
    stopSweeping();
    await _subscription?.cancel();
    _subscription = null;
    _transport = null;
    _channels.clear();
    timeout = const Duration(seconds: 45);
  }
}

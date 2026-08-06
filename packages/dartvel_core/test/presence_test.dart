// Presence: membership built from authenticated identity, tenant-filtered,
// expiring on silence rather than trusting a departure message.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A loopback transport: what goes out comes back, the way a fanout returns a
/// peer's event.
class _Loopback implements DVPresenceTransport {
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);

  void deliver(Map<String, Object?> envelope) => _incoming.add(envelope);

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  Future<void> close() => _incoming.close();
}

void main() {
  tearDown(() async {
    await DVPresence.reset();
    DVTenants.reset();
  });

  test('joining puts a member on the channel', () async {
    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));

    expect(DVPresence.members('room:1').single.id, 'ada');
    expect(DVPresence.channels, <String>['room:1']);
  });

  test('joining twice updates rather than duplicating', () async {
    // A reconnect is a join; counting the same identity twice would report a
    // phantom participant.
    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    await DVPresence.join(
      'room:1',
      DVPresenceMember(id: 'ada', state: <String, Object?>{'status': 'away'}),
    );

    expect(DVPresence.members('room:1'), hasLength(1));
    expect(DVPresence.members('room:1').single.state['status'], 'away');
  });

  test('events report joined, updated and left distinctly', () async {
    final kinds = <DVPresenceEventKind>[];
    final subscription =
        DVPresence.channel('room:1').listen((e) => kinds.add(e.kind));

    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    await DVPresence.leave('room:1', 'ada');
    await Future<void>.delayed(Duration.zero);

    expect(kinds, <DVPresenceEventKind>[
      DVPresenceEventKind.joined,
      DVPresenceEventKind.updated,
      DVPresenceEventKind.left,
    ]);
    await subscription.cancel();
  });

  test('a member that stops heartbeating expires', () async {
    // The case a crashed client always produces: no departure message ever
    // arrives, so silence has to be enough.
    DVPresence.timeout = const Duration(milliseconds: 40);
    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    expect(DVPresence.members('room:1'), hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Excluded from reads immediately, not only after a sweep.
    expect(DVPresence.members('room:1'), isEmpty);
    expect(await DVPresence.sweep(), 1);
  });

  test('a heartbeat keeps a member alive', () async {
    DVPresence.timeout = const Duration(milliseconds: 80);
    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));

    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await DVPresence.heartbeat('room:1', 'ada');
    }

    expect(DVPresence.members('room:1'), hasLength(1));
  });

  test('a heartbeat for an unknown member joins them', () async {
    // A client that missed its own join should still appear rather than
    // heartbeating into nothing.
    await DVPresence.heartbeat('room:1', 'grace');

    expect(DVPresence.members('room:1').single.id, 'grace');
  });

  test('sweeping emits left for each expired member', () async {
    DVPresence.timeout = const Duration(milliseconds: 30);
    final left = <String>[];
    final subscription = DVPresence.events
        .where((e) => e.kind == DVPresenceEventKind.left)
        .listen((e) => left.add(e.member.id));

    await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    await DVPresence.join('room:1', DVPresenceMember(id: 'grace'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await DVPresence.sweep();
    await Future<void>.delayed(Duration.zero);

    expect(left, unorderedEquals(<String>['ada', 'grace']));
    await subscription.cancel();
  });

  test('presence is tenant-scoped', () async {
    const tenants = DVTenants();
    await tenants.withTenant('acme', () async {
      await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
    });
    await tenants.withTenant('globex', () async {
      await DVPresence.join('room:1', DVPresenceMember(id: 'bob'));
    });

    expect(
      (await tenants.withTenant(
        'acme',
        () async => DVPresence.members('room:1'),
      ))
          .single
          .id,
      'ada',
    );
    // The default tenant sees neither.
    expect(DVPresence.members('room:1'), isEmpty);
  });

  group('transport', () {
    test('local changes go out and remote ones come in', () async {
      final transport = _Loopback();
      addTearDown(transport.close);
      DVPresence.useTransport(transport);

      await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
      expect(transport.sent.single['op'], 'join');
      expect(transport.sent.single['channel'], 'room:1');

      transport.deliver(<String, Object?>{
        'op': 'join',
        'channel': 'room:1',
        'member': DVPresenceMember(id: 'remote').toJson(),
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        DVPresence.members('room:1').map((m) => m.id),
        unorderedEquals(<String>['ada', 'remote']),
      );
    });

    test('an arriving event is not rebroadcast', () async {
      // Two processes echoing each other would never settle.
      final transport = _Loopback();
      addTearDown(transport.close);
      DVPresence.useTransport(transport);

      transport.deliver(<String, Object?>{
        'op': 'join',
        'channel': 'room:1',
        'member': DVPresenceMember(id: 'remote').toJson(),
      });
      await Future<void>.delayed(Duration.zero);

      expect(transport.sent, isEmpty);
    });

    test('a sweep does not broadcast departures', () async {
      // Every process sweeps on the same rule, so announcing would multiply
      // one departure by the size of the fleet.
      final transport = _Loopback();
      addTearDown(transport.close);
      DVPresence.timeout = const Duration(milliseconds: 20);
      DVPresence.useTransport(transport);
      await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
      transport.sent.clear();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await DVPresence.sweep();

      expect(transport.sent, isEmpty);
    });

    test('a malformed envelope is ignored, not fatal', () async {
      final transport = _Loopback();
      addTearDown(transport.close);
      DVPresence.useTransport(transport);

      transport.deliver(<String, Object?>{'op': 'join'});
      await Future<void>.delayed(Duration.zero);

      // Still usable afterwards.
      await DVPresence.join('room:1', DVPresenceMember(id: 'ada'));
      expect(DVPresence.members('room:1'), hasLength(1));
    });
  });
}

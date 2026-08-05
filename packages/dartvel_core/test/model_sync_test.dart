import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Note {
  final String id;
  final String owner;

  const _Note(this.id, this.owner);

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'owner': owner};

  static _Note fromJson(Map<String, Object?> json) =>
      _Note(json['id']! as String, json['owner']! as String);
}

/// A loopback transport: what goes out comes back in, the way a WebSocket
/// fanout returns a peer's publish. Real wire behaviour, one process.
class _LoopbackTransport implements DVModelSyncTransport {
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
  }

  /// Delivers an envelope as if a remote peer had published it.
  void deliver(Map<String, Object?> envelope) => _incoming.add(envelope);

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  Future<void> close() => _incoming.close();
}

void main() {
  tearDown(() async {
    await DVModelSync.reset();
    DVTenants.reset();
  });

  test('watchers receive typed changes for their model type', () async {
    final received = <DVModelChange<_Note>>[];
    final sub = DVModelSync.changes<_Note>().listen(received.add);

    await DVModelSync.publish(
      const _Note('n1', 'ada'),
      kind: DVModelChangeKind.created,
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.kind, DVModelChangeKind.created);
    expect(received.single.model.id, 'n1');
    await sub.cancel();
  });

  test('changes from another tenant are not delivered', () async {
    const tenants = DVTenants();
    final received = <DVModelChange<_Note>>[];
    final sub = DVModelSync.changes<_Note>().listen(received.add);

    await tenants.withTenant('acme', () async {
      await DVModelSync.publish(const _Note('n1', 'ada'));
    });
    await DVModelSync.publish(const _Note('n2', 'ada'));
    await Future<void>.delayed(Duration.zero);

    // The listener runs as the default tenant: acme's change stays invisible.
    expect(received.map((DVModelChange<_Note> c) => c.model.id), <String>['n2']);
    await sub.cancel();
  });

  test('a policy filter runs before delivery, not in the UI', () async {
    DVModelSync.registerPolicy<_Note>((note) => note.owner == 'ada');
    final received = <DVModelChange<_Note>>[];
    final sub = DVModelSync.changes<_Note>().listen(received.add);

    await DVModelSync.publish(const _Note('mine', 'ada'));
    await DVModelSync.publish(const _Note('theirs', 'bob'));
    await Future<void>.delayed(Duration.zero);

    expect(received.map((c) => c.model.id), <String>['mine']);
    await sub.cancel();
  });

  test('a transport carries changes out and back in', () async {
    final transport = _LoopbackTransport();
    addTearDown(transport.close);
    DVModelSync.registerCodec<_Note>(
      name: 'Note',
      encode: (note) => note.toJson(),
      decode: _Note.fromJson,
    );
    DVModelSync.useTransport(transport);

    await DVModelSync.publish(
      const _Note('n1', 'ada'),
      kind: DVModelChangeKind.synced,
    );
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single['type'], 'Note');
    expect(transport.sent.single['kind'], 'synced');

    // A remote peer's change reaches local typed watchers.
    final received = <DVModelChange<_Note>>[];
    final sub = DVModelSync.changes<_Note>().listen(received.add);
    transport.deliver(<String, Object?>{
      'type': 'Note',
      'kind': 'updated',
      'tenant': 'default',
      'model': <String, Object?>{'id': 'remote', 'owner': 'ada'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.model.id, 'remote');
    expect(received.single.kind, DVModelChangeKind.updated);
    await sub.cancel();
  });

  test('an unknown envelope type is dropped, not crashed on', () async {
    final transport = _LoopbackTransport();
    addTearDown(transport.close);
    DVModelSync.useTransport(transport);

    transport.deliver(<String, Object?>{'type': 'Ghost', 'model': <String, Object?>{}});
    await Future<void>.delayed(Duration.zero);
    // Nothing to assert beyond "no throw": the stream stays usable.
    await DVModelSync.publish(const _Note('still-works', 'ada'));
  });
}

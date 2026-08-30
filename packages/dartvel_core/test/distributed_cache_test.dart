// A cache spread across several nodes.
//
// The property that matters is not "keys land somewhere" -- any hash does that
// -- it is what happens when the set of nodes changes. With `hash % n`, adding
// one node moves almost every key: the cache does not report an error, it just
// misses on nearly everything at once, and the database behind it takes the
// full load while every dashboard says the cache is healthy.
//
// So most of what follows measures redistribution rather than placement.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A node that can be told to fail, so a partition is testable.
class FlakyNode implements DVCacheAdapter, DVAtomicCacheAdapter {
  FlakyNode(this.name);

  final String name;
  final Map<String, Object?> entries = <String, Object?>{};
  bool down = false;
  int reads = 0;

  void _check() {
    if (down) throw StateError('$name is down');
  }

  @override
  Future<Object?> read(String key) async {
    _check();
    reads += 1;
    return entries[key];
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    _check();
    entries[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _check();
    entries.remove(key);
  }

  @override
  Future<void> clear() async {
    _check();
    entries.clear();
  }

  @override
  Future<int> purgeExpired() async {
    _check();
    return 0;
  }

  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async {
    _check();
    if (entries.containsKey(key)) return false;
    entries[key] = value;
    return true;
  }
}

List<String> keys(int count) =>
    List<String>.generate(count, (int i) => 'user:$i');

void main() {
  group('placement', () {
    test('a key always lands on the same node', () {
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{
          'a': FlakyNode('a'),
          'b': FlakyNode('b'),
          'c': FlakyNode('c'),
        },
      );

      for (final String key in keys(50)) {
        expect(cache.nodesFor(key), cache.nodesFor(key));
      }
    });

    test('keys spread across the nodes rather than piling on one', () {
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{
          'a': FlakyNode('a'),
          'b': FlakyNode('b'),
          'c': FlakyNode('c'),
        },
      );

      final Map<String, int> counts = <String, int>{};
      for (final String key in keys(600)) {
        final String owner = cache.nodesFor(key).first;
        counts[owner] = (counts[owner] ?? 0) + 1;
      }

      expect(counts.length, 3);
      // Even placement is the point; a hash that favours one node makes that
      // node the bottleneck and the others useless.
      for (final int count in counts.values) {
        expect(count, greaterThan(600 ~/ 3 ~/ 2));
        expect(count, lessThan(600 ~/ 3 * 2));
      }
    });
  });

  group('changing the node set', () {
    test('removing a node moves only the keys it owned', () {
      // The whole reason for rendezvous hashing. With `hash % n` this is
      // nearly 100%, and the cache silently empties.
      final Map<String, DVCacheAdapter> three = <String, DVCacheAdapter>{
        'a': FlakyNode('a'),
        'b': FlakyNode('b'),
        'c': FlakyNode('c'),
      };
      final DVDistributedCacheAdapter before =
          DVDistributedCacheAdapter(nodes: three);
      final DVDistributedCacheAdapter after = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': three['a']!, 'b': three['b']!},
      );

      final List<String> sample = keys(900);
      int moved = 0;
      int ownedByRemoved = 0;
      for (final String key in sample) {
        final String was = before.nodesFor(key).first;
        final String now = after.nodesFor(key).first;
        if (was == 'c') ownedByRemoved += 1;
        if (was != now) moved += 1;
      }

      // Every key that moved was one the departed node owned, and no others.
      expect(moved, ownedByRemoved);
      expect(moved / sample.length, lessThan(0.45));
    });

    test('adding a node moves only about its share', () {
      final Map<String, DVCacheAdapter> three = <String, DVCacheAdapter>{
        'a': FlakyNode('a'),
        'b': FlakyNode('b'),
        'c': FlakyNode('c'),
      };
      final DVDistributedCacheAdapter before =
          DVDistributedCacheAdapter(nodes: three);
      final DVDistributedCacheAdapter after = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{...three, 'd': FlakyNode('d')},
      );

      final List<String> sample = keys(900);
      final int moved = sample
          .where((String k) => before.nodesFor(k).first != after.nodesFor(k).first)
          .length;

      // A fourth node should claim roughly a quarter, not the lot.
      expect(moved / sample.length, lessThan(0.4));
      expect(moved, greaterThan(0));
    });
  });

  group('reads and writes', () {
    late FlakyNode a;
    late FlakyNode b;
    late DVDistributedCacheAdapter cache;

    setUp(() {
      a = FlakyNode('a');
      b = FlakyNode('b');
      cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a, 'b': b},
      );
    });

    test('a value written comes back', () async {
      await cache.write('k', 'v', null);

      expect(await cache.read('k'), 'v');
    });

    test('it is stored on the owning node only', () async {
      await cache.write('k', 'v', null);

      final String owner = cache.nodesFor('k').first;
      final FlakyNode holder = owner == 'a' ? a : b;
      final FlakyNode other = owner == 'a' ? b : a;
      expect(holder.entries.containsKey('k'), isTrue);
      expect(other.entries.containsKey('k'), isFalse);
    });

    test('delete removes it', () async {
      await cache.write('k', 'v', null);
      await cache.remove('k');

      expect(await cache.read('k'), isNull);
    });

    test('clear reaches every node, not just the one a key maps to', () async {
      await cache.write('one', 1, null);
      await cache.write('two', 2, null);
      await cache.clear();

      expect(a.entries, isEmpty);
      expect(b.entries, isEmpty);
    });

    test('purgeExpired sums what every node reclaimed', () async {
      expect(await cache.purgeExpired(), 0);
    });
  });

  group('a node going down', () {
    test('keys owned by a healthy node still read', () async {
      final FlakyNode a = FlakyNode('a');
      final FlakyNode b = FlakyNode('b');
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a, 'b': b},
      );

      await cache.write('one', 1, null);
      await cache.write('two', 2, null);
      final String ownerOfOne = cache.nodesFor('one').first;
      (ownerOfOne == 'a' ? b : a).down = true;

      // A cache is not a database: one node failing must cost its own keys,
      // not the whole cache.
      expect(await cache.read('one'), 1);
    });

    test('a read from a downed node is a miss, not an exception', () async {
      final FlakyNode a = FlakyNode('a');
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a},
      );

      await cache.write('k', 'v', null);
      a.down = true;

      // Throwing here would turn a cache outage into an application outage.
      expect(await cache.read('k'), isNull);
    });

    test('with replication a read falls through to the replica', () async {
      final FlakyNode a = FlakyNode('a');
      final FlakyNode b = FlakyNode('b');
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a, 'b': b},
        replicas: 2,
      );

      await cache.write('k', 'v', null);
      expect(a.entries.containsKey('k'), isTrue);
      expect(b.entries.containsKey('k'), isTrue);

      // Whichever is primary, the other still answers.
      final String primary = cache.nodesFor('k').first;
      (primary == 'a' ? a : b).down = true;
      expect(await cache.read('k'), 'v');
    });

    test('replicas beyond the node count are clamped, not an error', () {
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': FlakyNode('a')},
        replicas: 5,
      );

      expect(cache.nodesFor('k').length, 1);
    });
  });

  group('compare-and-set', () {
    test('the first writer wins and the second is refused', () async {
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{
          'a': FlakyNode('a'),
          'b': FlakyNode('b'),
        },
      );

      expect(await cache.writeIfAbsent('lock', 1, null), isTrue);
      expect(await cache.writeIfAbsent('lock', 2, null), isFalse);
      expect(await cache.read('lock'), 1);
    });

    test('it runs on the primary alone, so two callers cannot both win',
        () async {
      // Asking every replica would let two callers each win on a different
      // node, which is a lock that does not lock.
      final FlakyNode a = FlakyNode('a');
      final FlakyNode b = FlakyNode('b');
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a, 'b': b},
        replicas: 2,
      );

      expect(await cache.writeIfAbsent('lock', 1, null), isTrue);
      expect(await cache.writeIfAbsent('lock', 2, null), isFalse);
    });

    test('a node that cannot be reached refuses rather than claiming the lock',
        () async {
      final FlakyNode a = FlakyNode('a');
      final DVDistributedCacheAdapter cache = DVDistributedCacheAdapter(
        nodes: <String, DVCacheAdapter>{'a': a},
      );
      a.down = true;

      // Returning true here would hand out a lock nobody is holding.
      expect(await cache.writeIfAbsent('lock', 1, null), isFalse);
    });
  });

  test('a cache with no nodes is refused at construction', () {
    // Silently behaving as a null cache would make every read a miss and look
    // like a cold cache forever.
    expect(
      () => DVDistributedCacheAdapter(nodes: const <String, DVCacheAdapter>{}),
      throwsArgumentError,
    );
  });
}

/// A cache spread across several nodes.
///
/// Redis and Memcached adapters each talk to one server. This spreads keys
/// across a set of them, which is the fourth provider the spec asks for, and
/// implements the compare-and-set it requires before stampede protection is
/// enabled.
///
/// Placement is **rendezvous hashing** rather than `hash % n`. That choice is
/// the whole point of the class: with a modulo, adding or removing one node
/// remaps almost every key. Nothing errors -- the cache simply misses on
/// nearly everything at once, the database behind it takes the full load, and
/// every dashboard still reports the cache as healthy. Under rendezvous
/// hashing only the keys belonging to the node that came or went move.
///
/// It also needs no virtual nodes to distribute evenly, which a hash ring
/// does; a ring without them piles keys onto whichever node happens to own a
/// large arc.
library dartvel_core.cache.distributed;

import 'dart:async';

import 'adapters.dart';

/// Spreads keys across several cache nodes.
class DVDistributedCacheAdapter
    implements DVCacheAdapter, DVAtomicCacheAdapter, DVCountingCacheAdapter {
  DVDistributedCacheAdapter({
    required Map<String, DVCacheAdapter> nodes,
    this.replicas = 1,
  }) : nodes = Map<String, DVCacheAdapter>.unmodifiable(nodes) {
    if (nodes.isEmpty) {
      // A cache with nowhere to put anything would answer every read with a
      // miss and look like a cache that is merely cold, forever.
      throw ArgumentError.value(nodes, 'nodes', 'needs at least one node');
    }
    if (replicas < 1) {
      throw ArgumentError.value(replicas, 'replicas', 'must be at least one');
    }
  }

  /// The nodes, by a stable name. The name is what placement hashes, so it
  /// must not change when a host is replaced or every key moves.
  final Map<String, DVCacheAdapter> nodes;

  /// How many nodes hold each key. One is a plain shard; more trades memory
  /// for surviving a node loss without losing those keys.
  final int replicas;

  /// The nodes holding [key], best first.
  ///
  /// Rendezvous hashing: score every node for this key and take the highest.
  /// Removing a node changes the winner only for keys it was winning, because
  /// the other nodes' scores for every other key are untouched.
  List<String> nodesFor(String key) {
    final List<String> ranked = nodes.keys.toList()
      ..sort((String a, String b) {
        final int byScore = _score(b, key).compareTo(_score(a, key));
        // Ties broken by name, so placement is deterministic across processes
        // rather than depending on map iteration order.
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    final int count = replicas > ranked.length ? ranked.length : replicas;
    return List<String>.unmodifiable(ranked.take(count));
  }

  /// A 32-bit mix of node and key: FNV-1a, then murmur3's finalizer.
  ///
  /// Thirty-two bits rather than sixty-four because this runs on the web
  /// too, where an `int` is a JavaScript number and a literal like
  /// `0xcbf29ce484222325` cannot be represented at all. That is a compile
  /// error, and it takes the whole package down rather than only this file --
  /// which is how it surfaced: as "XmlElement isn't a type" in an unrelated
  /// file, while building the site.
  ///
  /// The avalanche step is not decoration. FNV alone leaves the low bits
  /// poorly distributed, and the low bits decide placement: the result is a
  /// cache that works, with a hot node nobody can explain.
  ///
  /// The separator is a NUL so that ("ab", "c") and ("a", "bc") cannot hash
  /// alike -- node names and keys are both arbitrary strings.
  int _score(String node, String key) {
    int hash = 0x811c9dc5;
    for (final int unit in '$node\u0000$key'.codeUnits) {
      hash = _mul32(hash ^ unit, 0x01000193);
    }
    hash ^= hash >>> 16;
    hash = _mul32(hash, 0x85ebca6b);
    hash ^= hash >>> 13;
    hash = _mul32(hash, 0xc2b2ae35);
    hash ^= hash >>> 16;
    return hash & 0x7FFFFFFF;
  }

  /// A 32-bit multiply that stays exact on the web.
  ///
  /// Two 32-bit values multiply to as much as 64 bits, which a JavaScript
  /// number cannot hold exactly -- and the low bits, the ones that decide
  /// placement, are the first it loses. Split into halves, every step stays
  /// inside the exact range.
  static int _mul32(int a, int b) {
    final int low = (a & 0xffff) * b;
    final int high = (((a >>> 16) * b) & 0xffff) << 16;
    return (low + high) & 0xFFFFFFFF;
  }

  @override
  Future<Object?> read(String key) async {
    for (final String name in nodesFor(key)) {
      try {
        final Object? value = await nodes[name]!.read(key);
        if (value != null) return value;
      } on Object {
        // A cache is not a database. A node that cannot be reached costs its
        // own keys; throwing here would turn a cache outage into an
        // application outage.
        continue;
      }
    }
    return null;
  }

  @override
  Future<void> write(String key, Object? value, Duration? ttl) async {
    for (final String name in nodesFor(key)) {
      try {
        await nodes[name]!.write(key, value, ttl);
      } on Object {
        continue;
      }
    }
  }

  @override
  Future<void> remove(String key) async {
    for (final String name in nodesFor(key)) {
      try {
        await nodes[name]!.remove(key);
      } on Object {
        continue;
      }
    }
  }

  @override
  Future<void> clear() async {
    // Every node, not only the ones some key maps to: a clear that left
    // entries on an unvisited node would resurrect them the moment placement
    // changed.
    for (final DVCacheAdapter node in nodes.values) {
      try {
        await node.clear();
      } on Object {
        continue;
      }
    }
  }

  @override
  Future<int> purgeExpired() async {
    int purged = 0;
    for (final DVCacheAdapter node in nodes.values) {
      try {
        purged += await node.purgeExpired();
      } on Object {
        continue;
      }
    }
    return purged;
  }

  @override
  Future<bool> writeIfAbsent(String key, Object? value, Duration? ttl) async {
    // The primary alone. Asking every replica would let two callers each win
    // on a different node -- a lock that does not lock -- and a node that
    // cannot be reached must refuse rather than hand out a lock nobody holds.
    final String primary = nodesFor(key).first;
    final DVCacheAdapter node = nodes[primary]!;
    if (node is! DVAtomicCacheAdapter) {
      throw StateError(
        'The node "$primary" does not implement compare-and-set, so a '
        'distributed lock over it would not be atomic. Use Redis or '
        'Memcached nodes for a cache that takes locks.',
      );
    }
    try {
      return await (node as DVAtomicCacheAdapter)
          .writeIfAbsent(key, value, ttl);
    } on Object {
      return false;
    }
  }

  @override
  Future<int> increment(String key, {int by = 1, Duration? ttl}) async {
    // The primary alone, for the same reason a lock takes it alone: adding
    // on every replica counts each hit once per replica, so a rate limit
    // over a two-replica cache would refuse at half the budget it states.
    //
    // A node that joins or leaves moves this key's counter with it, which
    // hands its callers one fresh window. That is a cache topology change,
    // it is rare, and the alternative is a counter that cannot move at all.
    final String primary = nodesFor(key).first;
    final DVCacheAdapter node = nodes[primary]!;
    if (node is! DVCountingCacheAdapter) {
      throw StateError(
        'The node "$primary" cannot count, so adding to a number on it '
        'would mean reading it, adding one and writing it back -- which '
        'loses every hit that arrives in between. Use Redis nodes for a '
        'cache that counts.',
      );
    }
    return (node as DVCountingCacheAdapter).increment(key, by: by, ttl: ttl);
  }
}

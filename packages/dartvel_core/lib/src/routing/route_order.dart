/// The order routes are matched in, decided once for every source.
///
/// go_router matches the first route in its list that fits. A parameter route
/// listed ahead of a static one therefore hides it: `/users/:id` first and
/// `/users/new` is a page nobody can reach, with nothing reported. Next.js and
/// Expo Router avoid that by ranking a static segment above a parameter no
/// matter where either was declared, and so does this.
///
/// It lives in core, not beside the router, because two things need the same
/// answer: the generated router orders its routes with it at startup, and the
/// build refuses an order that cannot be satisfied before anything is written.
library;

/// A route reduced to what matching sees: parameter names and a trailing
/// slash do not make two routes different.
///
/// `/users/:id` and `/users/:slug` have the same shape, so declaring both is
/// declaring one route twice.
String dvRouteShape(String path) {
  final List<String> segments = _segments(path)
      .map(
        (String s) => s.startsWith(':')
            ? ':'
            : s.startsWith('*')
            ? '*'
            : s,
      )
      .toList();
  return '/${segments.join('/')}';
}

/// Whether some URL would match both [a] and [b].
bool dvRoutesOverlap(String a, String b) {
  final List<String> left = _segments(a);
  final List<String> right = _segments(b);
  final int length = left.length < right.length ? left.length : right.length;
  for (int i = 0; i < length; i++) {
    final String l = left[i];
    final String r = right[i];
    // A catch-all takes the rest of the path, whatever it is.
    if (l.startsWith('*') || r.startsWith('*')) return true;
    if (_isParameter(l) || _isParameter(r)) continue;
    if (l != r) return false;
  }
  if (left.length == right.length) return true;
  // One ran out first. They still meet when the longer one's next segment is
  // a catch-all, which can match nothing more.
  final List<String> longer = left.length > right.length ? left : right;
  return longer[length].startsWith('*') && longer.length == length + 1;
}

/// Whether [a] has to be matched before [b]: they meet, and at the first
/// segment where they differ in kind, [a] is the more specific.
bool dvRouteMatchesFirst(String a, String b) {
  if (!dvRoutesOverlap(a, b)) return false;
  final List<String> left = _segments(a);
  final List<String> right = _segments(b);
  final int length = left.length > right.length ? left.length : right.length;
  for (int i = 0; i < length; i++) {
    final int l = i < left.length ? _rank(left[i]) : -1;
    final int r = i < right.length ? _rank(right[i]) : -1;
    if (l != r) return l < r;
  }
  return false;
}

/// [routes] in an order where no route hides another.
///
/// Each item is a group of paths that stays together -- a shell route and
/// everything under it, a route and its children -- because go_router cannot
/// match half a shell first. [paths] gives every full path an item serves.
///
/// Items with nothing between them keep the order they came in, so a list
/// that was already right is returned unchanged. Throws
/// [DVRouteOrderException] (`DV-ROUTE-004`) when two groups would each have
/// to come before the other.
List<T> dvOrderRoutes<T>(
  List<T> routes,
  Iterable<String> Function(T route) paths,
) {
  final List<List<String>> leaves = <List<String>>[
    for (final T route in routes) paths(route).toList(growable: false),
  ];
  final int n = routes.length;
  // before[i] holds every j that i has to precede, with the paths that say so.
  final List<Map<int, (String, String)>> before =
      List<Map<int, (String, String)>>.generate(
        n,
        (_) => <int, (String, String)>{},
      );
  final List<int> incoming = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      if (i == j) continue;
      final (String, String)? reason = _firstPrecedence(leaves[i], leaves[j]);
      if (reason == null) continue;
      final (String, String)? back = _firstPrecedence(leaves[j], leaves[i]);
      if (back != null) {
        throw DVRouteOrderException(first: reason, second: back);
      }
      if (before[i].containsKey(j)) continue;
      before[i][j] = reason;
      incoming[j]++;
    }
  }

  // Kahn's algorithm, always taking the earliest item that is free, so the
  // given order survives wherever nothing forces a change.
  final List<T> ordered = <T>[];
  final List<bool> placed = List<bool>.filled(n, false);
  for (int step = 0; step < n; step++) {
    int next = -1;
    for (int i = 0; i < n; i++) {
      if (!placed[i] && incoming[i] == 0) {
        next = i;
        break;
      }
    }
    if (next == -1) {
      // A cycle through three or more groups. Name one link of it.
      final int stuck = placed.indexOf(false);
      final MapEntry<int, (String, String)> link = before[stuck].entries
          .firstWhere((MapEntry<int, (String, String)> e) => !placed[e.key]);
      final (String, String) back = before[link.key].values.first;
      throw DVRouteOrderException(first: link.value, second: back);
    }
    placed[next] = true;
    ordered.add(routes[next]);
    for (final int j in before[next].keys) {
      incoming[j]--;
    }
  }
  return ordered;
}

/// Routes that cannot be put in any order where each is reachable.
class DVRouteOrderException implements Exception {
  const DVRouteOrderException({required this.first, required this.second});

  /// A path that has to be matched before another, as `(specific, general)`.
  final (String, String) first;

  /// The opposite requirement, from the same two groups.
  final (String, String) second;

  @override
  String toString() =>
      'DV-ROUTE-004: ${first.$1} has to be matched before ${first.$2}, and '
      '${second.$1} before ${second.$2}, but each pair sits in a group that '
      'is matched as a whole -- a shell route, or a route with children. '
      'Whichever group goes first hides a route in the other. Move one of '
      'these routes out of its group.';
}

(String, String)? _firstPrecedence(List<String> a, List<String> b) {
  for (final String x in a) {
    for (final String y in b) {
      if (dvRouteMatchesFirst(x, y)) return (x, y);
    }
  }
  return null;
}

List<String> _segments(String path) => path
    .split('?')
    .first
    .split('/')
    .where((String s) => s.isNotEmpty)
    .toList(growable: false);

bool _isParameter(String segment) => segment.startsWith(':');

int _rank(String segment) => segment.startsWith('*')
    ? 2
    : _isParameter(segment)
    ? 1
    : 0;

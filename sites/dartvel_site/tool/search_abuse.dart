/// Throws traffic at a running site's search the way a scraper or a script
/// would, and reports what it got back.
///
///     dart run tool/search_abuse.dart http://127.0.0.1:8740 [--proxied]
///
/// Against a server with no trusted proxy: a burst from one caller, the same
/// burst with a new X-Forwarded-For on every request (which must not buy a
/// new budget), an oversized query, and concurrent requests. With --proxied,
/// against a server that trusts 127.0.0.1 as its proxy (as dartvel.dev trusts
/// nginx): distinct forwarded clients each get their own budget.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Future<({int status, int millis, String? retryAfter, int results})> ask(
  HttpClient client,
  Uri base,
  String q, {
  String? forwardedFor,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  final HttpClientRequest request = await client
      .getUrl(base.replace(path: '/api/search', queryParameters: <String, String>{'q': q}));
  if (forwardedFor != null) request.headers.set('x-forwarded-for', forwardedFor);
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  int results = -1;
  if (response.statusCode == 200) {
    final Object? decoded = jsonDecode(body);
    results = decoded is List ? decoded.length : -1;
  }
  return (
    status: response.statusCode,
    millis: watch.elapsedMilliseconds,
    retryAfter: response.headers.value('retry-after'),
    results: results,
  );
}

Map<int, int> tally(Iterable<({int status, int millis, String? retryAfter, int results})> r) {
  final Map<int, int> by = <int, int>{};
  for (final x in r) {
    by[x.status] = (by[x.status] ?? 0) + 1;
  }
  return by;
}

Future<void> main(List<String> args) async {
  final Uri base = Uri.parse(args.isEmpty ? 'http://127.0.0.1:8740' : args.first);
  final bool proxied = args.contains('--proxied');
  final HttpClient client = HttpClient()..maxConnectionsPerHost = 32;

  if (proxied) {
    // Three callers behind the trusted proxy, 120 requests each, interleaved.
    final List<({int status, int millis, String? retryAfter, int results})> a = [],
        b = [], c = [];
    for (int i = 0; i < 120; i++) {
      a.add(await ask(client, base, 'cache', forwardedFor: '198.51.100.10'));
      b.add(await ask(client, base, 'cache', forwardedFor: '198.51.100.11'));
      c.add(await ask(client, base, 'cache', forwardedFor: '198.51.100.12'));
    }
    stdout.writeln('proxied, three forwarded clients x120: '
        '${tally(a)} ${tally(b)} ${tally(c)}');
    client.close();
    return;
  }

  // 1. A burst from one caller.
  final List<({int status, int millis, String? retryAfter, int results})> burst = [];
  for (int i = 0; i < 130; i++) {
    burst.add(await ask(client, base, 'deploy'));
  }
  final int firstRefused = burst.indexWhere((x) => x.status == 429);
  stdout.writeln('burst of 130 from one caller: ${tally(burst)}; first 429 at '
      'request ${firstRefused + 1}, Retry-After ${burst[firstRefused].retryAfter}s');

  // 2. The same caller writing a new X-Forwarded-For each time: the server
  // trusts no proxy, so the header is the client's own and is ignored.
  final math.Random random = math.Random(7);
  final List<({int status, int millis, String? retryAfter, int results})> spoofed = [];
  for (int i = 0; i < 20; i++) {
    spoofed.add(await ask(client, base, 'deploy',
        forwardedFor: '203.0.113.${random.nextInt(250)}'));
  }
  stdout.writeln('20 more with a forged X-Forwarded-For each: ${tally(spoofed)}');

  // 3. Wait out the window, then the expensive shapes.
  final int wait = int.tryParse(burst[firstRefused].retryAfter ?? '') ?? 60;
  stdout.writeln('waiting ${wait + 1}s for the window to pass...');
  await Future<void>.delayed(Duration(seconds: wait + 1));
  final big = await ask(client, base, 'cache ' * 10000);
  stdout.writeln('a 60,000-character query: ${big.status} in ${big.millis} ms, '
      '${big.results} results');
  final junk = await ask(client, base, List<String>.generate(40, (int i) => 'zq${i}x').join(' '));
  stdout.writeln('forty words of nonsense: ${junk.status}, ${junk.results} results');

  // 4. Thirty at once.
  final List<({int status, int millis, String? retryAfter, int results})> together =
      await Future.wait(<Future<({int status, int millis, String? retryAfter, int results})>>[
    for (int i = 0; i < 30; i++) ask(client, base, 'hot reload on device $i'),
  ]);
  final List<int> times = together.map((x) => x.millis).toList()..sort();
  stdout.writeln('30 concurrent: ${tally(together)}, slowest ${times.last} ms, '
      'median ${times[times.length ~/ 2]} ms');
  client.close();
}

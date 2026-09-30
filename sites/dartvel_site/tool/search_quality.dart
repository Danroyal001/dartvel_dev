/// How good the site search is, measured on the site's own pages.
///
///     dart run tool/search_quality.dart [path/to/dartvel_routes.json]
///
/// Reads the route manifest a web-server build writes (build/web by default,
/// or a copy fetched from the live site), indexes it exactly as the server
/// does, and runs every query in tool/search_queries.json. Each query names
/// the pages that answer it; a query counts at 1 when one of them is first,
/// at 3 when one is in the first three. The queries were written before the
/// search was tuned, from what a reader of the docs would type, and are
/// kept as they were so the numbers can be compared from run to run.
///
///     dart run tool/search_quality.dart http://127.0.0.1:8740
///
/// asks a running server instead, through /api/search, so the times are the
/// compiled server's and include HTTP.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_site/backend/site_search.dart';
import 'package:dartvel_site/dartvel_client/dartvel_server.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first.startsWith('http')) {
    return overHttp(Uri.parse(args.first));
  }
  final String manifest =
      args.isNotEmpty ? args.first : 'build/web/dartvel_routes.json';
  final File file = File(manifest);
  if (!file.existsSync()) {
    stderr.writeln('No route manifest at $manifest. Run dartvel build '
        'web-server, or pass the path of a dartvel_routes.json.');
    exitCode = 2;
    return;
  }
  final Directory root = Directory.systemTemp.createTempSync('site_search_q');
  file.copySync('${root.path}/dartvel_routes.json');
  DVSitePages.webRoot = root.path;

  registerDartvelModels();
  const DVDatabase().configure(SqliteDVDatabaseAdapter.memory());
  await const DVDatabase().execute(
      'CREATE TABLE IF NOT EXISTS sitepages (id TEXT, path TEXT, title TEXT, '
      'heading TEXT, body TEXT, _dv_version INTEGER NOT NULL DEFAULT 1, '
      '_dv_deleted_at TEXT)');

  final List<Map<String, Object?>> queries = <Map<String, Object?>>[
    for (final Object? q
        in jsonDecode(File('tool/search_queries.json').readAsStringSync()) as List)
      (q as Map).cast<String, Object?>(),
  ];

  final Stopwatch indexing = Stopwatch()..start();
  await siteSearch('warm up');
  indexing.stop();
  stdout.writeln('pages ${(await DVSitePages.load()).length}, sections '
      '${(await SitePage.all()).length}, indexed in '
      '${indexing.elapsedMilliseconds} ms');

  final List<String> modes = args.length > 1 ? args.sublist(1) : <String>['hybrid@0.3'];
  for (final String setting in modes) {
    final List<String> parts = setting.split('@');
    final DVSearchMode mode = DVSearchMode.values.byName(parts.first);
    final double floor = parts.length > 1 ? double.parse(parts[1]) : kSiteSearchMinScore;
    int top1 = 0, top3 = 0;
    double reciprocal = 0;
    final List<int> micros = <int>[];
    final List<String> misses = <String>[];
    for (final Map<String, Object?> q in queries) {
      final String text = q['q']! as String;
      final List<String> want = (q['want']! as List).cast<String>();
      final Stopwatch watch = Stopwatch()..start();
      final List<SiteSearchResult> found =
          await siteSearch(text, mode: mode, minScore: floor);
      micros.add(watch.elapsedMicroseconds);
      final List<String> paths = <String>[for (final r in found) r.path];
      final int at = paths.indexWhere(want.contains);
      if (at == 0) top1++;
      if (at >= 0 && at < 3) top3++;
      if (at >= 0 && at < 5) reciprocal += 1 / (at + 1);
      if (at != 0) {
        misses.add('  "$text": wanted ${want.join(' or ')}, got '
            '${paths.take(3).join(', ')}${paths.isEmpty ? '(nothing)' : ''}');
      }
    }
    micros.sort();
    final int n = queries.length;
    stdout.writeln('$setting: hit@1 $top1/$n, hit@3 $top3/$n, MRR@5 '
        '${(reciprocal / n).toStringAsFixed(3)}, p50 '
        '${(micros[n ~/ 2] / 1000).toStringAsFixed(1)} ms, p95 '
        '${(micros[(n * 0.95).floor()] / 1000).toStringAsFixed(1)} ms');
    misses.forEach(stdout.writeln);
  }
  root.deleteSync(recursive: true);
}

Future<void> overHttp(Uri base) async {
  final List<Map<String, Object?>> queries = <Map<String, Object?>>[
    for (final Object? q
        in jsonDecode(File('tool/search_queries.json').readAsStringSync()) as List)
      (q as Map).cast<String, Object?>(),
  ];
  final HttpClient client = HttpClient();
  int top1 = 0, top3 = 0;
  double reciprocal = 0;
  final List<int> micros = <int>[];
  for (final Map<String, Object?> q in queries) {
    final List<String> want = (q['want']! as List).cast<String>();
    final Stopwatch watch = Stopwatch()..start();
    final HttpClientRequest request = await client.getUrl(base.replace(
        path: '/api/search',
        queryParameters: <String, String>{'q': q['q']! as String}));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    micros.add(watch.elapsedMicroseconds);
    if (response.statusCode != 200) {
      stdout.writeln('  "${q['q']}": HTTP ${response.statusCode}');
      continue;
    }
    final List<String> paths = <String>[
      for (final Object? r in jsonDecode(body) as List) '${(r as Map)['path']}',
    ];
    final int at = paths.indexWhere(want.contains);
    if (at == 0) top1++;
    if (at >= 0 && at < 3) top3++;
    if (at >= 0 && at < 5) reciprocal += 1 / (at + 1);
  }
  client.close();
  micros.sort();
  final int n = queries.length;
  stdout.writeln('over HTTP: hit@1 $top1/$n, hit@3 $top3/$n, MRR@5 '
      '${(reciprocal / n).toStringAsFixed(3)}, p50 '
      '${(micros[n ~/ 2] / 1000).toStringAsFixed(1)} ms, p95 '
      '${(micros[(n * 0.95).floor()] / 1000).toStringAsFixed(1)} ms, first '
      '${(micros.reduce((int a, int b) => a > b ? a : b) / 1000).toStringAsFixed(0)} ms max');
}

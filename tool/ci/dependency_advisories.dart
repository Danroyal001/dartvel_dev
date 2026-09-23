/// Known vulnerabilities in the packages this repository pins.
///
/// Every tracked `pubspec.lock`, every hosted package in it, asked of OSV
/// (`https://osv.dev`) in one batch per file. OSV carries the Pub ecosystem,
/// which is the database GitHub's own advisories for Dart packages land in.
///
/// The quiet failures are what this is shaped around. A lock file's git, path
/// and SDK entries look like packages and are not ones pub.dev has ever heard
/// of, so asking about them returns an empty answer that reads exactly like a
/// clean one -- the difference between checking a dependency and believing it
/// was checked. And OSV answers a batch positionally, so a response read in
/// any other order attaches an advisory to the wrong package, or drops it.
///
/// Imports only `dart:` libraries, so it runs as `dart tool/ci/...` with no
/// package resolution.
library;

import 'dart:convert';
import 'dart:io';

/// One package with something reported against the version pinned here.
class DVAdvisory {
  const DVAdvisory({
    required this.package,
    required this.version,
    required this.ids,
    this.file = '',
  });

  final String package;
  final String version;

  /// The OSV ids, which are usually `GHSA-` identifiers.
  final List<String> ids;

  /// The lock file it was pinned in.
  final String file;

  @override
  String toString() => '$package $version: ${ids.join(', ')}';
}

/// The hosted packages in [lock], by name, with the version it pins.
///
/// Hosted only. A `path` dependency is this repository's own, a `git` one is
/// a fork whose advisories OSV tracks under the upstream name if at all, and
/// `sdk` is Dart or Flutter itself.
Map<String, String> dvLockedPackages(String lock) {
  final Map<String, String> found = <String, String>{};
  final List<String> lines = lock.split('\n');
  String? name;
  String? version;
  bool hosted = false;

  void take() {
    if (name != null && version != null && hosted) found[name!] = version!;
    name = null;
    version = null;
    hosted = false;
  }

  for (final String line in lines) {
    if (line.trimLeft().startsWith('#') || line.trim().isEmpty) continue;
    // `sdks:` at the end of the file, and `packages:` at the start.
    if (!line.startsWith(' ')) {
      take();
      continue;
    }
    // A package entry: exactly two spaces, then the name and a colon.
    final RegExpMatch? entry =
        RegExp(r'^  ([A-Za-z_][A-Za-z0-9_]*):\s*$').firstMatch(line);
    if (entry != null) {
      take();
      name = entry.group(1);
      continue;
    }
    if (name == null) continue;
    final String trimmed = line.trim();
    if (trimmed == 'source: hosted') hosted = true;
    final RegExpMatch? pinned =
        RegExp(r'^version:\s*"?([^"\s]+)"?$').firstMatch(trimmed);
    if (pinned != null) version = pinned.group(1);
  }
  take();
  return found;
}

/// [packages] in the order they are asked about.
///
/// Sorted, and the query is built from the same list: OSV answers a batch
/// positionally, and sorting one side only is how an advisory is reported
/// against the wrong package.
List<String> dvOsvNames(Map<String, String> packages) =>
    packages.keys.toList()..sort();

/// The OSV `querybatch` body for [packages].
String dvOsvQuery(Map<String, String> packages) => jsonEncode(<String, Object?>{
      'queries': <Object?>[
        for (final String name in dvOsvNames(packages))
          <String, Object?>{
            'package': <String, Object?>{'name': name, 'ecosystem': 'Pub'},
            'version': packages[name],
          },
      ],
    });

/// The advisories in [body], an OSV `querybatch` response for [names].
///
/// A response of any other length is refused rather than read as far as it
/// goes: a truncated batch would report the packages it covered as clean and
/// say nothing at all about the rest.
List<DVAdvisory> dvOsvFindings(
  String body,
  List<String> names,
  Map<String, String> packages, {
  String file = '',
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw FormatException('OSV answered with something that is not JSON: $e');
  }
  if (decoded is! Map || decoded['results'] is! List) {
    throw const FormatException('OSV answered without a results list');
  }
  final List<Object?> results = decoded['results'] as List<Object?>;
  if (results.length != names.length) {
    throw FormatException('OSV answered for ${results.length} of '
        '${names.length} packages; nothing in this batch can be trusted');
  }

  final List<DVAdvisory> found = <DVAdvisory>[];
  for (int i = 0; i < names.length; i++) {
    final Object? result = results[i];
    if (result is! Map) continue;
    final Object? vulns = result['vulns'];
    if (vulns is! List || vulns.isEmpty) continue;
    found.add(DVAdvisory(
      package: names[i],
      version: packages[names[i]] ?? '',
      ids: <String>[
        for (final Object? v in vulns)
          if (v is Map && v['id'] != null) '${v['id']}',
      ],
      file: file,
    ));
  }
  return found;
}

/// Every tracked lock file in this repository, and what each pins.
Map<String, Map<String, String>> dvRepositoryPackages({String root = '.'}) {
  final Map<String, Map<String, String>> byFile =
      <String, Map<String, String>>{};
  for (final String path in dvLockFiles(root: root)) {
    final File file = File('$root/$path');
    if (!file.existsSync()) continue;
    byFile[path] = dvLockedPackages(file.readAsStringSync());
  }
  return byFile;
}

/// The lock files to read: the workspace root, every package, every example.
///
/// Found rather than listed, because a list goes stale the first time a
/// package is added and the check then reports a clean run over a file it
/// never opened.
List<String> dvLockFiles({String root = '.'}) {
  final List<String> found = <String>[
    if (File('$root/pubspec.lock').existsSync()) 'pubspec.lock',
  ];
  for (final String directory in <String>['packages', 'examples', 'sites']) {
    final Directory parent = Directory('$root/$directory');
    if (!parent.existsSync()) continue;
    for (final FileSystemEntity entity in parent.listSync()) {
      if (entity is! Directory) continue;
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (File('${entity.path}/pubspec.lock').existsSync()) {
        found.add('$directory/$name/pubspec.lock');
      }
    }
  }
  found.sort();
  return found;
}

/// Asks OSV about [packages] and returns what it reports.
///
/// Separated from the parsing so everything above is testable without a
/// network, which is also what keeps this function small enough to read.
Future<List<DVAdvisory>> dvQueryOsv(
  Map<String, String> packages, {
  String file = '',
  Uri? endpoint,
}) async {
  if (packages.isEmpty) return const <DVAdvisory>[];
  final List<String> names = dvOsvNames(packages);
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .postUrl(endpoint ?? Uri.parse('https://api.osv.dev/v1/querybatch'));
    request.headers.contentType = ContentType.json;
    request.write(dvOsvQuery(packages));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw FormatException(
          'OSV answered ${response.statusCode}: ${body.trim()}');
    }
    return dvOsvFindings(body, names, packages, file: file);
  } finally {
    client.close(force: true);
  }
}

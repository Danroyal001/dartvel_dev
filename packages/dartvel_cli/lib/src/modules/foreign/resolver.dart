/// Stages 1 to 3 of the generation pipeline: resolve the canonical source
/// and version, fetch it and verify it, and say what kind it is.
///
/// Every scheme lands in the same place -- a directory under
/// `.dartvel/sources/` holding exactly what was fetched, and a digest of it --
/// so the stages after this read one shape whatever the source was. The
/// network is behind [DVSourceFetcher], so what is resolved from where is
/// tested without a registry.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../../module_trust/package_digest.dart';

/// Thrown when a source cannot be resolved; nothing has been written.
class DVSourceUnresolved implements Exception {
  const DVSourceUnresolved(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the network does for a resolver. Real by default; a test passes its
/// own.
class DVSourceFetcher {
  const DVSourceFetcher();

  /// The body at [url] as text.
  Future<String> getText(Uri url) async =>
      utf8.decode(await getBytes(url));

  /// The body at [url].
  Future<List<int>> getBytes(Uri url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final HttpClientRequest request = await client.getUrl(url);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw DVSourceUnresolved('$url answered ${response.statusCode}.');
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on SocketException catch (e) {
      throw DVSourceUnresolved('$url could not be reached: ${e.message}.');
    } finally {
      client.close(force: true);
    }
  }

  /// Runs [executable] and throws with its output when it fails.
  Future<String> run(String executable, List<String> args,
      {String? workingDirectory}) async {
    final ProcessResult result = await Process.run(executable, args,
        workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw DVSourceUnresolved(
          '$executable ${args.join(' ')} failed: ${result.stderr}'.trim());
    }
    return '${result.stdout}'.trim();
  }
}

/// A fetched source, ready to be inspected.
class DVResolvedSource {
  const DVResolvedSource({
    required this.descriptor,
    required this.name,
    required this.version,
    required this.directory,
    required this.sourceDigest,
    required this.resolvedFrom,
    required this.dependency,
  });

  /// The canonical descriptor, version included: `pub:textkit@1.2.3`.
  final String descriptor;

  /// The package's own name.
  final String name;

  /// The exact version resolved; a commit for a git source.
  final String version;

  /// Where the fetched source is on disk.
  final String directory;

  /// sha256 of what was fetched: pub.dev's archive digest, or the digest of
  /// the tree for a git or path source.
  final String sourceDigest;

  /// Where it actually came from, for a reader asking what the digest is of.
  final String resolvedFrom;

  /// The YAML value a module's pubspec depends on it with, pinned to what
  /// was resolved.
  final String dependency;
}

/// Resolves a Dart package source: `pub:<name>[@<version or constraint>]`,
/// `git:<url>[#<ref>]`, or a local path to a package.
Future<DVResolvedSource> dvResolveDartSource(
  String root,
  String descriptor, {
  DVSourceFetcher fetcher = const DVSourceFetcher(),
}) async {
  if (descriptor.startsWith('pub:')) {
    return _resolvePub(root, descriptor.substring(4), fetcher);
  }
  if (descriptor.startsWith('git:')) {
    return _resolveGit(root, descriptor.substring(4), fetcher);
  }
  final Directory dir = Directory(p.normalize(p.join(root, descriptor)));
  if (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    throw DVSourceUnresolved('$descriptor has no pubspec.yaml.');
  }
  final String name = _nameIn(dir.path);
  final String relative =
      p.relative(dir.path, from: p.join(root, 'modules', 'x')).replaceAll('\\', '/');
  return DVResolvedSource(
    descriptor: 'path:${p.relative(dir.path, from: root).replaceAll('\\', '/')}',
    name: name,
    version: _versionIn(dir.path),
    directory: dir.path,
    sourceDigest: dvModulePackageDigest(dir.path),
    resolvedFrom: dir.path,
    dependency: '{path: $relative}',
  );
}

Future<DVResolvedSource> _resolvePub(
    String root, String spec, DVSourceFetcher fetcher) async {
  final int at = spec.indexOf('@');
  final String name = at < 0 ? spec : spec.substring(0, at);
  final String? wanted = at < 0 ? null : spec.substring(at + 1);
  if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name)) {
    throw DVSourceUnresolved('"$name" is not a pub package name.');
  }
  final Map<String, Object?> info = jsonDecode(await fetcher
          .getText(Uri.parse('https://pub.dev/api/packages/$name')))
      as Map<String, Object?>;
  final List<Map<String, Object?>> versions = <Map<String, Object?>>[
    for (final Object? v in info['versions'] as List<Object?>? ?? <Object?>[])
      (v! as Map).cast<String, Object?>(),
  ];
  final VersionConstraint constraint = wanted == null
      ? VersionConstraint.any
      : VersionConstraint.parse(wanted);
  Map<String, Object?>? chosen;
  Version? best;
  for (final Map<String, Object?> v in versions) {
    final Version version = Version.parse(v['version']! as String);
    if (!constraint.allows(version)) continue;
    // A prerelease only when asked for by name: `^1.0.0` is not a request
    // for 2.0.0-dev.
    if (version.isPreRelease && wanted != v['version']) continue;
    if (best == null || version > best) {
      best = version;
      chosen = v;
    }
  }
  if (chosen == null || best == null) {
    throw DVSourceUnresolved('pub.dev has no version of $name matching '
        '${wanted ?? 'any'}.');
  }
  final String archiveUrl = chosen['archive_url']! as String;
  final String? expected = chosen['archive_sha256'] as String?;
  final List<int> archive = await fetcher.getBytes(Uri.parse(archiveUrl));
  final String digest = sha256.convert(archive).toString();
  if (expected != null && expected != digest) {
    throw DVSourceUnresolved('The archive of $name $best has sha256 $digest, '
        'and pub.dev says $expected. Nothing was written (DV-MODULE-004).');
  }
  final Directory into = Directory(
      p.join(root, '.dartvel', 'sources', 'pub', '$name-$best'));
  if (into.existsSync()) into.deleteSync(recursive: true);
  into.createSync(recursive: true);
  final File tarball = File('${into.path}.tar.gz')..writeAsBytesSync(archive);
  try {
    await fetcher.run('tar', <String>['-xzf', tarball.path, '-C', into.path]);
  } finally {
    if (tarball.existsSync()) tarball.deleteSync();
  }
  return DVResolvedSource(
    descriptor: 'pub:$name@$best',
    name: name,
    version: '$best',
    directory: into.path,
    sourceDigest: digest,
    resolvedFrom: archiveUrl,
    dependency: '$best',
  );
}

Future<DVResolvedSource> _resolveGit(
    String root, String spec, DVSourceFetcher fetcher) async {
  final int hash = spec.lastIndexOf('#');
  final String url = hash < 0 ? spec : spec.substring(0, hash);
  final String? ref = hash < 0 ? null : spec.substring(hash + 1);
  final String key =
      sha256.convert(utf8.encode(spec)).toString().substring(0, 16);
  final Directory into =
      Directory(p.join(root, '.dartvel', 'sources', 'git', key));
  if (into.existsSync()) into.deleteSync(recursive: true);
  into.parent.createSync(recursive: true);
  await fetcher.run('git', <String>['clone', '--quiet', url, into.path]);
  if (ref != null) {
    await fetcher.run('git', <String>['checkout', '--quiet', ref],
        workingDirectory: into.path);
  }
  final String commit = await fetcher
      .run('git', <String>['rev-parse', 'HEAD'], workingDirectory: into.path);
  if (!File(p.join(into.path, 'pubspec.yaml')).existsSync()) {
    throw DVSourceUnresolved('$url has no pubspec.yaml at its root.');
  }
  // The digest is of the tree, without git's own bookkeeping.
  final Directory git = Directory(p.join(into.path, '.git'));
  if (git.existsSync()) git.deleteSync(recursive: true);
  return DVResolvedSource(
    descriptor: 'git:$url#$commit',
    name: _nameIn(into.path),
    version: commit,
    directory: into.path,
    sourceDigest: dvModulePackageDigest(into.path),
    resolvedFrom: url,
    dependency: '{git: {url: ${jsonEncode(url)}, ref: $commit}}',
  );
}

String _nameIn(String dir) {
  final RegExpMatch? m = RegExp(r'^name:\s*([a-z0-9_]+)', multiLine: true)
      .firstMatch(File(p.join(dir, 'pubspec.yaml')).readAsStringSync());
  if (m == null) throw DVSourceUnresolved('$dir/pubspec.yaml names no package.');
  return m.group(1)!;
}

String _versionIn(String dir) {
  final RegExpMatch? m = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(File(p.join(dir, 'pubspec.yaml')).readAsStringSync());
  return m?.group(1) ?? '0.0.0';
}

/// Resolves `npm:<name>[@<version or range>]` from the npm registry.
///
/// The newest version the range allows, or `latest` when none is given; the
/// tarball is checked against the registry's `integrity` (sha512) before it
/// is unpacked. A range is an exact version, `^`, `~` or a comparator pair;
/// anything else is refused rather than read as the nearest thing.
Future<DVResolvedSource> dvResolveNpmSource(
  String root,
  String spec, {
  DVSourceFetcher fetcher = const DVSourceFetcher(),
}) async {
  final int at = spec.indexOf('@', spec.startsWith('@') ? 1 : 0);
  final String name = at < 0 ? spec : spec.substring(0, at);
  final String? wanted = at < 0 ? null : spec.substring(at + 1);
  if (!RegExp(r'^(@[a-z0-9][\w.-]*/)?[a-z0-9][\w.-]*$').hasMatch(name)) {
    throw DVSourceUnresolved('"$name" is not an npm package name.');
  }
  final Map<String, Object?> info = jsonDecode(await fetcher.getText(
          Uri.parse('https://registry.npmjs.org/${name.replaceAll('/', '%2F')}')))
      as Map<String, Object?>;
  final Map<String, Object?> versions =
      (info['versions'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  String? chosen;
  if (wanted == null) {
    chosen = ((info['dist-tags'] as Map?)?['latest']) as String?;
  } else {
    final VersionConstraint constraint = _npmRange(wanted);
    Version? best;
    for (final String v in versions.keys) {
      final Version version;
      try {
        version = Version.parse(v);
      } on FormatException {
        continue;
      }
      if (!constraint.allows(version)) continue;
      if (version.isPreRelease && wanted != v) continue;
      if (best == null || version > best) best = version;
    }
    chosen = best?.toString();
  }
  final Map<String, Object?>? release =
      chosen == null ? null : (versions[chosen] as Map?)?.cast<String, Object?>();
  if (release == null) {
    throw DVSourceUnresolved('npm has no version of $name matching '
        '${wanted ?? 'latest'}.');
  }
  final Map<String, Object?> dist =
      (release['dist']! as Map).cast<String, Object?>();
  final String tarballUrl = dist['tarball']! as String;
  final List<int> tarball = await fetcher.getBytes(Uri.parse(tarballUrl));
  final String? integrity = dist['integrity'] as String?;
  if (integrity != null && integrity.startsWith('sha512-')) {
    final String actual = base64Encode(sha512.convert(tarball).bytes);
    if (actual != integrity.substring(7)) {
      throw DVSourceUnresolved('The tarball of $name $chosen does not match '
          'the integrity the registry publishes. Nothing was written '
          '(DV-MODULE-004).');
    }
  }
  final String safe = name.replaceAll('@', '').replaceAll('/', '__');
  final Directory into =
      Directory(p.join(root, '.dartvel', 'sources', 'npm', '$safe-$chosen'));
  if (into.existsSync()) into.deleteSync(recursive: true);
  into.createSync(recursive: true);
  final File file = File('${into.path}.tgz')..writeAsBytesSync(tarball);
  try {
    await fetcher.run('tar', <String>['-xzf', file.path, '-C', into.path]);
  } finally {
    if (file.existsSync()) file.deleteSync();
  }
  // npm packs everything under package/.
  final String dir = Directory(p.join(into.path, 'package')).existsSync()
      ? p.join(into.path, 'package')
      : into.path;
  return DVResolvedSource(
    descriptor: 'npm:$name@$chosen',
    name: name,
    version: chosen!,
    directory: dir,
    sourceDigest: sha256.convert(tarball).toString(),
    resolvedFrom: tarballUrl,
    dependency: '',
  );
}

VersionConstraint _npmRange(String range) {
  final String r = range.trim();
  final RegExpMatch? tilde = RegExp(r'^~(\d+)\.(\d+)\.(\d+)$').firstMatch(r);
  if (tilde != null) {
    final int major = int.parse(tilde.group(1)!);
    final int minor = int.parse(tilde.group(2)!);
    return VersionRange(
      min: Version.parse(r.substring(1)),
      includeMin: true,
      max: Version(major, minor + 1, 0),
    );
  }
  try {
    return VersionConstraint.parse(r);
  } on FormatException {
    throw DVSourceUnresolved('"$range" is not a range this reads: use an '
        'exact version, ^, ~ or a pair such as ">=1.2.0 <2.0.0".');
  }
}

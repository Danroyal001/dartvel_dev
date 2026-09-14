/// `dartvel.module.lock`: what was resolved, pinned.
///
/// One entry per module package: the version, the content digest, the
/// publisher the registry verified, the signing key, and the capabilities the
/// installed manifest declared. Written by `dartvel modules pin` and meant to
/// be committed. Every resolution after that is compared against it.
///
/// Read strictly. An entry that cannot be read is a problem the evaluation
/// fails on, never an entry quietly skipped: a lockfile that stopped pinning a
/// module because its digest was mistyped would be the lockfile saying
/// nothing, which is what an attacker would write.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'capabilities.dart';
import 'package_digest.dart';

/// The lockfile, at the parent's root.
const String dvModuleLockFile = 'dartvel.module.lock';

/// One pinned module package.
class DVModulePin {
  const DVModulePin({
    required this.package,
    required this.version,
    required this.sha256,
    required this.capabilities,
    this.publisher,
    this.key,
  });

  final String package;
  final String version;
  final String sha256;

  /// The publisher the registry verified when this was pinned. Null when no
  /// registry could be asked -- never the module's own claim.
  final String? publisher;

  /// The public key that signed the pinned release; null if it was unsigned.
  final String? key;

  /// The capability kinds the pinned release declared, in table order.
  final List<String> capabilities;
}

final RegExp _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');

/// A parsed lockfile.
class DVModuleLock {
  DVModuleLock(this.pins, [this.problems = const <String>[]]);

  final Map<String, DVModulePin> pins;

  /// What could not be read.
  final List<String> problems;

  /// The lockfile at [root]; empty when there is none.
  static DVModuleLock read(String root) {
    final File file = File(p.join(root, dvModuleLockFile));
    if (!file.existsSync()) return DVModuleLock(<String, DVModulePin>{});
    final Object? doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } on Object {
      return DVModuleLock(<String, DVModulePin>{}, <String>[
        '$dvModuleLockFile is not YAML, so nothing in it is pinned.',
      ]);
    }
    if (doc == null) return DVModuleLock(<String, DVModulePin>{});
    if (doc is! Map) {
      return DVModuleLock(<String, DVModulePin>{}, <String>[
        '$dvModuleLockFile is not a map of packages.',
      ]);
    }

    final Map<String, DVModulePin> pins = <String, DVModulePin>{};
    final List<String> problems = <String>[];
    for (final MapEntry<Object?, Object?> entry in doc.entries) {
      final String package = '${entry.key}';
      final Object? body = entry.value;
      String where(String field) => '$dvModuleLockFile: $package.$field';
      if (!_packageName.hasMatch(package) || body is! Map) {
        problems.add('$dvModuleLockFile: "$package" is not a pinned package.');
        continue;
      }
      final Object? version = body['version'];
      final Object? sha256 = body['sha256'];
      final Object? publisher = body['publisher'];
      final Object? key = body['key'];
      final Object? capabilities = body['capabilities'];
      final int before = problems.length;
      if (version is! String || version.isEmpty) {
        problems.add('${where('version')} is not a version.');
      }
      if (sha256 is! String || !dvIsModuleDigest(sha256)) {
        problems.add(
          '${where('sha256')} is "$sha256", and a digest is exactly '
          '64 lowercase hex characters. It is not compared in any shorter or '
          'other form, so the package is not pinned.',
        );
      }
      if (publisher != null && publisher is! String) {
        problems.add('${where('publisher')} is not a name.');
      }
      if (key != null && key is! String) {
        problems.add('${where('key')} is not a public key.');
      }
      if (capabilities is! List ||
          capabilities.any(
            (Object? c) => !dvModuleCapabilityKinds.contains(c),
          )) {
        problems.add(
          '${where('capabilities')} is not a list of capability '
          'kinds.',
        );
      }
      if (problems.length != before) continue;
      pins[package] = DVModulePin(
        package: package,
        version: version! as String,
        sha256: sha256! as String,
        publisher: publisher as String?,
        key: key as String?,
        capabilities: <String>[
          for (final Object? c in capabilities! as List) '$c',
        ],
      );
    }
    return DVModuleLock(pins, problems);
  }

  /// The lockfile's text: packages sorted, values quoted.
  String render() {
    final StringBuffer out = StringBuffer()
      ..writeln('# dartvel.module.lock -- written by `dartvel modules pin`.')
      ..writeln('# Commit it. Every resolution is compared against these pins,')
      ..writeln('# and a changed digest, key or publisher is a build error.');
    final List<String> packages = pins.keys.toList()..sort();
    for (final String package in packages) {
      final DVModulePin pin = pins[package]!;
      out
        ..writeln('$package:')
        ..writeln('  version: ${jsonEncode(pin.version)}')
        ..writeln('  sha256: ${jsonEncode(pin.sha256)}')
        ..writeln('  publisher: ${jsonEncode(pin.publisher)}')
        ..writeln('  key: ${jsonEncode(pin.key)}')
        ..writeln('  capabilities: [${pin.capabilities.join(', ')}]');
    }
    return out.toString();
  }

  void write(String root) =>
      File(p.join(root, dvModuleLockFile)).writeAsStringSync(render());
}

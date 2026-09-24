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

/// One pinned module, from pub.dev or from a foreign source.
///
/// A pub.dev module pins [sha256], the archive the registry served, and
/// carries the [publisher] the registry verified. A foreign source -- a Maven
/// coordinate, a crate, an .xcframework, an OpenAPI URL -- has neither: nobody
/// verifies it against a domain and nothing signs it, so it pins [sourceDigest]
/// and [wrapperHash] instead, and the pin is the only thing there is.
class DVModulePin {
  const DVModulePin({
    required this.package,
    required this.version,
    required this.capabilities,
    this.sha256,
    this.publisher,
    this.key,
    this.source,
    this.sourceDigest,
    this.wrapperHash,
    this.generator,
    this.resolvedFrom,
    this.targets = const <String>[],
  });

  final String package;
  final String version;

  /// The pub.dev archive's digest. Null for a foreign source, which has no
  /// archive: a Maven artifact is pinned by [sourceDigest] instead.
  final String? sha256;

  /// The publisher the registry verified when this was pinned. Null when no
  /// registry could be asked -- never the module's own claim, and always null
  /// for a foreign source, which has no publisher to verify.
  final String? publisher;

  /// The public key that signed the pinned release; null if it was unsigned.
  final String? key;

  /// The source descriptor a foreign module was resolved from, such as
  /// `maven:com.vendor:scanner` or `cargo:image`. Null for a pub.dev module.
  final String? source;

  /// The digest of what was fetched. A change here is `DV-MODULE-004`, the
  /// same supply-chain error a changed pub.dev archive raises.
  final String? sourceDigest;

  /// The digest of the module generated from it. A change here while
  /// [sourceDigest] and [generator] did not change is `DV-BIND-002`: a
  /// generator non-determinism bug rather than a supply-chain event. The
  /// distinction matters because the fixes are opposite -- one is a bug to
  /// fix, the other is an artifact not to trust.
  final String? wrapperHash;

  /// The generator version that produced [wrapperHash]. Part of a wrapper's
  /// identity, so an upgrade explains a changed hash rather than alarming.
  final String? generator;

  /// Where the source was actually fetched from, for a reader asking what a
  /// digest is the digest of.
  final String? resolvedFrom;

  /// The targets the generated module declares, sorted.
  final List<String> targets;

  /// The capability kinds the pinned release declared, in table order.
  final List<String> capabilities;

  /// Whether this was resolved from outside pub.dev.
  bool get isForeign => source != null;

  /// The digest the installed module is compared against.
  ///
  /// A pub.dev module is its archive; a foreign one is the wrapper generated
  /// from the source, because that is what is installed. Comparing a foreign
  /// module against [sha256] would compare it against nothing and report
  /// every one of them as substituted.
  String? get pinnedDigest => isForeign ? wrapperHash : sha256;
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
      // A foreign source is pinned by what was fetched and what was
      // generated from it, because it has no pub.dev archive and no
      // publisher anybody verified.
      final Object? source = body['source'];
      final Object? sourceDigest = body['sourceDigest'];
      final Object? wrapperHash = body['wrapperHash'];
      final Object? generator = body['generator'];
      final Object? resolvedFrom = body['resolvedFrom'];
      final Object? targets = body['targets'];
      final bool foreign = source != null;
      final int before = problems.length;
      if (version is! String || version.isEmpty) {
        problems.add('${where('version')} is not a version.');
      }
      if (foreign && source is! String) {
        problems.add('${where('source')} is not a source descriptor.');
      }
      if (!foreign && (sha256 is! String || !dvIsModuleDigest(sha256))) {
        problems.add(
          '${where('sha256')} is "$sha256", and a digest is exactly '
          '64 lowercase hex characters. It is not compared in any shorter or '
          'other form, so the package is not pinned.',
        );
      }
      if (foreign && sha256 != null) {
        problems.add(
          '${where('sha256')} pins a pub.dev archive, and this module came '
          'from $source. A foreign source pins sourceDigest instead.',
        );
      }
      if (foreign) {
        // Refused rather than skipped, for the reason the whole file is read
        // strictly: an entry that pins nothing reads as resolved, which is
        // exactly what somebody substituting an artifact would write.
        for (final (String, Object?) digest in <(String, Object?)>[
          ('sourceDigest', sourceDigest),
          ('wrapperHash', wrapperHash),
        ]) {
          if (digest.$2 is! String || !dvIsModuleDigest(digest.$2! as String)) {
            problems.add(
              '${where(digest.$1)} is "${digest.$2}", and a digest is exactly '
              '64 lowercase hex characters. Without it nothing about this '
              'source is pinned.',
            );
          }
        }
        if (generator != null && generator is! String) {
          problems.add('${where('generator')} is not a version.');
        }
        if (resolvedFrom != null && resolvedFrom is! String) {
          problems.add('${where('resolvedFrom')} is not a location.');
        }
        if (targets != null &&
            (targets is! List || targets.any((Object? t) => t is! String))) {
          problems.add('${where('targets')} is not a list of targets.');
        }
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
        sha256: sha256 as String?,
        publisher: publisher as String?,
        key: key as String?,
        source: source as String?,
        sourceDigest: sourceDigest as String?,
        wrapperHash: wrapperHash as String?,
        generator: generator as String?,
        resolvedFrom: resolvedFrom as String?,
        targets: <String>[
          for (final Object? t in (targets as List?) ?? const <Object?>[]) '$t',
        ]..sort(),
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
      out.writeln('$package:');
      if (pin.isForeign) {
        // What was fetched and what was generated from it. A reader asking
        // which of the two changed is asking whether this is a supply-chain
        // event or a generator bug, so both are here and named apart.
        out
          ..writeln('  source: ${jsonEncode(pin.source)}')
          ..writeln('  version: ${jsonEncode(pin.version)}')
          ..writeln('  sourceDigest: ${jsonEncode(pin.sourceDigest)}')
          ..writeln('  wrapperHash: ${jsonEncode(pin.wrapperHash)}');
        if (pin.generator != null) {
          out.writeln('  generator: ${jsonEncode(pin.generator)}');
        }
        if (pin.resolvedFrom != null) {
          out.writeln('  resolvedFrom: ${jsonEncode(pin.resolvedFrom)}');
        }
        if (pin.targets.isNotEmpty) {
          out.writeln('  targets: [${pin.targets.join(', ')}]');
        }
      } else {
        out
          ..writeln('  version: ${jsonEncode(pin.version)}')
          ..writeln('  sha256: ${jsonEncode(pin.sha256)}')
          ..writeln('  publisher: ${jsonEncode(pin.publisher)}')
          ..writeln('  key: ${jsonEncode(pin.key)}');
      }
      out.writeln('  capabilities: [${pin.capabilities.join(', ')}]');
    }
    return out.toString();
  }

  void write(String root) =>
      File(p.join(root, dvModuleLockFile)).writeAsStringSync(render());
}

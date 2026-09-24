/// Whether a parent may run the modules it mounts: pins and grants.
///
/// Two separate questions, and keeping them apart is the point.
///
/// *Is this the module that was reviewed?* The installed package is compared
/// against `dartvel.module.lock`: the digest recomputed from the bytes on
/// disk, the signing key, the publisher the registry verified, the version.
/// A changed digest is DV-MODULE-004; a changed key or publisher is
/// DV-MODULE-005, fixed by an explicit re-pin and never by a flag.
///
/// *May it do what it does?* The capabilities its code uses and its manifest
/// declares are compared against the parent's grant. An ungranted use is
/// DV-MODULE-001; a manifest that differs from the grant is DV-MODULE-003. A
/// module does not acquire a capability by being upgraded, and pinning does
/// not grant anything -- pinning is identity, not permission.
///
/// Nothing is trusted because a module says so. The publisher field in a
/// signed statement is the publisher's own claim; the key a signature file
/// names is the file's own claim. Both are compared against what was pinned.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'capabilities.dart';
import 'capability_analysis.dart';
import 'module_lock.dart';
import 'module_signature.dart';
import 'package_digest.dart';

/// The registry's answer to "who publishes this package?".
///
/// pub.dev verifies publishers against a domain, and that verification is the
/// trust anchor. Dartvel does not ask it over the network during a build:
/// without a directory the publisher is simply not checked, and the lockfile
/// records null rather than the module's own claim.
abstract interface class DVModulePublisherDirectory {
  String? verifiedPublisher(String package);
}

/// One thing the evaluation found.
class DVModuleTrustFinding {
  const DVModuleTrustFinding({
    required this.module,
    required this.message,
    this.code,
    this.level = 'error',
  });

  /// The module id, or the file the finding is about.
  final String module;

  /// A DV-MODULE code, or null for a declaration that cannot be read.
  final String? code;

  /// `error` or `warning`.
  final String level;
  final String message;

  bool get isError => level == 'error';

  @override
  String toString() => '${code ?? 'dartvel.modules'} $module: $message';
}

/// Every finding, and whether the parent may build.
class DVModuleTrustReport {
  const DVModuleTrustReport(this.findings);

  final List<DVModuleTrustFinding> findings;

  bool get ok => !findings.any((DVModuleTrustFinding f) => f.isError);

  List<String> lines() => <String>[
    for (final DVModuleTrustFinding f in findings) f.toString(),
  ];
}

/// A mounted module, located.
class _Module {
  const _Module({
    required this.id,
    required this.packageName,
    required this.root,
    required this.viaPackage,
    required this.grant,
  });

  final String id;
  final String packageName;
  final String root;

  /// Mounted as a dependency (`package:`), rather than from a source path
  /// beside the parent. A dependency is distributed, so it must be signed and
  /// pinned; a source module is the parent's own composition and is pinned
  /// only once somebody pins it.
  final bool viaPackage;
  final DVCapabilityParse grant;
}

class _Parent {
  const _Parent(this.name, this.modules, this.revoked, this.problems);

  final String name;
  final List<_Module> modules;
  final Set<String> revoked;
  final List<DVModuleTrustFinding> problems;
}

Map<Object?, Object?> _pubspec(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return const <Object?, Object?>{};
  try {
    final Object? doc = loadYaml(file.readAsStringSync());
    return doc is Map ? doc : const <Object?, Object?>{};
  } on Object {
    return const <Object?, Object?>{};
  }
}

/// Where [package] resolves for the project at [root], from its
/// `.dart_tool/package_config.json`.
String? dvResolvePackageRoot(String root, String package) {
  final File config = File(p.join(root, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return null;
  try {
    final Object? json = jsonDecode(config.readAsStringSync());
    final Object? packages = json is Map ? json['packages'] : null;
    if (packages is! List) return null;
    for (final Object? entry in packages) {
      if (entry is! Map || entry['name'] != package) continue;
      final Object? rootUri = entry['rootUri'];
      if (rootUri is! String) return null;
      final Uri resolved = Uri.directory(
        p.join(root, '.dart_tool'),
      ).resolve(rootUri);
      if (resolved.scheme != 'file') return null;
      return p.normalize(resolved.toFilePath());
    }
  } on Object {
    return null;
  }
  return null;
}

_Parent _parent(String root) {
  final Map<Object?, Object?> pubspec = _pubspec(root);
  final String name = pubspec['name'] is String
      ? pubspec['name']! as String
      : 'the application';
  final Object? dartvel = pubspec['dartvel'];
  final Map<Object?, Object?> section = dartvel is Map
      ? dartvel
      : const <Object?, Object?>{};
  final List<DVModuleTrustFinding> problems = <DVModuleTrustFinding>[];

  final Set<String> revoked = <String>{};
  final Object? trust = section['moduleTrust'];
  final Object? revokedKeys = trust is Map ? trust['revokedKeys'] : null;
  if (revokedKeys != null) {
    if (revokedKeys is! List) {
      problems.add(
        const DVModuleTrustFinding(
          module: 'dartvel.moduleTrust',
          message:
              'revokedKeys is a list of key fingerprints. A revocation '
              'list that cannot be read revokes nothing, so the build stops.',
        ),
      );
    } else {
      for (final Object? key in revokedKeys) {
        // Lowercased: widening a revocation is the safe direction.
        final String fingerprint = '$key'.toLowerCase();
        if (dvIsModuleDigest(fingerprint)) {
          revoked.add(fingerprint);
        } else {
          problems.add(
            DVModuleTrustFinding(
              module: 'dartvel.moduleTrust',
              message:
                  'revokedKeys has "$key", which is not a key fingerprint '
                  '(64 hex characters). It revokes nothing, so the build stops.',
            ),
          );
        }
      }
    }
  }

  final List<_Module> modules = <_Module>[];
  final Object? declared = section['modules'];
  if (declared is Map) {
    for (final MapEntry<Object?, Object?> entry in declared.entries) {
      final String id = '${entry.key}';
      final Object? rawBody = entry.value;
      final Map<Object?, Object?> body = rawBody is Map
          ? rawBody
          : const <Object?, Object?>{};
      // A federated module is deployed elsewhere and trusted through its
      // signed manifest; nothing of it runs in this application.
      if ('${body['deployment']}' == 'federated') continue;

      final Object? package = body['package'];
      final Object? source = body['source'];
      final Object? sourcePath = source is Map ? source['path'] : source;
      String? moduleRoot;
      var viaPackage = false;
      if (package is String && package.isNotEmpty) {
        viaPackage = true;
        moduleRoot = dvResolvePackageRoot(root, package);
        if (moduleRoot == null || !Directory(moduleRoot).existsSync()) {
          problems.add(
            DVModuleTrustFinding(
              module: id,
              message:
                  'dartvel.modules.$id.package is "$package", and it does '
                  'not resolve. Run pub get, then dartvel modules pin $id.',
            ),
          );
          continue;
        }
      } else if (sourcePath is String && sourcePath.isNotEmpty) {
        moduleRoot = p.normalize(p.join(root, sourcePath));
        // A missing source is the mount's problem and is reported there.
        if (!Directory(moduleRoot).existsSync()) continue;
      } else {
        continue;
      }

      final Object? moduleName = _pubspec(moduleRoot)['name'];
      final String packageName = moduleName is String
          ? moduleName
          : (package is String ? package : id);
      if (viaPackage && packageName != package) {
        problems.add(
          DVModuleTrustFinding(
            module: id,
            message:
                'dartvel.modules.$id.package is "$package", and the package '
                'it resolves to is named "$packageName".',
          ),
        );
        continue;
      }

      modules.add(
        _Module(
          id: id,
          packageName: packageName,
          root: moduleRoot,
          viaPackage: viaPackage,
          grant: dvParseModuleCapabilities(
            body['grant'],
            where: 'dartvel.modules.$id.grant',
          ),
        ),
      );
    }
  }
  return _Parent(name, modules, revoked, problems);
}

/// The installed module's declared capabilities.
///
/// A list under `capabilities` is the older federated form -- what a target
/// must provide, such as `[camera]` -- and asks the parent for nothing.
DVCapabilityParse _declared(_Module m) {
  final Object? module = dvModuleDartvelSection(m.root)['module'];
  final Object? raw = module is Map ? module['capabilities'] : null;
  if (raw is List) {
    return const DVCapabilityParse(DVModuleCapabilities.none, <String>[]);
  }
  return dvParseModuleCapabilities(
    raw,
    where: '${m.packageName} dartvel.module.capabilities',
  );
}

String? _versionOf(String root) {
  final Object? version = _pubspec(root)['version'];
  return version == null ? null : '$version';
}

String _fingerprintOr(String key) {
  try {
    return dvModuleKeyFingerprint(key);
  } on DVModuleSignatureException {
    return 'an unreadable key';
  }
}

/// Evaluates every module the project at [root] mounts.
DVModuleTrustReport dvEvaluateModuleTrust(
  String root, {
  DVModulePublisherDirectory? publishers,
}) {
  final _Parent parent = _parent(root);
  final List<DVModuleTrustFinding> findings = <DVModuleTrustFinding>[
    ...parent.problems,
  ];
  final DVModuleLock lock = DVModuleLock.read(root);
  for (final String problem in lock.problems) {
    findings.add(
      DVModuleTrustFinding(module: dvModuleLockFile, message: problem),
    );
  }

  for (final _Module m in parent.modules) {
    final DVCapabilityParse declared = _declared(m);
    _checkCapabilities(parent.name, m, declared, findings);
    _checkPin(
      m,
      declared.capabilities,
      lock,
      parent.revoked,
      publishers,
      findings,
    );
  }
  return DVModuleTrustReport(findings);
}

void _checkCapabilities(
  String parent,
  _Module m,
  DVCapabilityParse declared,
  List<DVModuleTrustFinding> findings,
) {
  void add(String? code, String message, {String level = 'error'}) =>
      findings.add(
        DVModuleTrustFinding(
          module: m.id,
          code: code,
          level: level,
          message: message,
        ),
      );

  for (final String problem in declared.problems) {
    add(null, problem);
  }
  for (final String problem in m.grant.problems) {
    add(
      'DV-MODULE-001',
      '$problem $parent grants module "${m.id}" nothing '
          'from that entry.',
    );
  }

  final DVModuleCodeAnalysis code = dvAnalyseModuleProject(m.root);
  final DVModuleCapabilities grant = m.grant.capabilities;
  final DVModuleCapabilities manifest = declared.capabilities;

  for (final DVModuleCodeUse use in code.ownNetwork) {
    add(
      'DV-MODULE-008',
      'module "${m.id}" (${m.packageName}) opens its own '
          'connection at ${use.file}:${use.line} (${use.what}). Egress is '
          'enforced per domain only through calls Dartvel owns, so a module '
          'that opens a socket or HttpClient is refused.',
    );
  }
  for (final DVModuleCodeUse use in code.unresolved) {
    add(
      'DV-MODULE-001',
      'module "${m.id}" (${m.packageName}) reaches '
          '${use.what} at ${use.file}:${use.line}. $parent cannot grant what '
          'the build cannot read, and the runtime check that would enforce it '
          '(DV-MODULE-002) is not built, so this is refused.',
    );
  }
  for (final String item in code.uses.missingFrom(grant)) {
    add(
      'DV-MODULE-001',
      'module "${m.id}" (${m.packageName}) uses $item, '
          'and $parent did not grant it. Grant it under '
          'dartvel.modules.${m.id}.grant if that is meant.',
    );
  }
  for (final String item in manifest.missingFrom(grant)) {
    add(
      'DV-MODULE-003',
      'the installed ${m.packageName} asks for $item, '
          'which $parent has not granted to module "${m.id}". Upgrading does '
          'not grant it: grant it deliberately, or stay on a release that did '
          'not ask.',
    );
  }
  for (final String item in grant.missingFrom(manifest)) {
    add(
      'DV-MODULE-003',
      '$parent grants $item to module "${m.id}", and the '
          'installed ${m.packageName} does not ask for it. Remove it from the '
          'grant: least privilege only works if the grant matches the ask.',
    );
  }
  for (final String item in code.uses.missingFrom(manifest)) {
    add(
      'DV-MODULE-007',
      '${m.packageName} uses $item and its manifest does '
          'not declare it.',
      level: 'warning',
    );
  }
  for (final String item in manifest.missingFrom(code.uses)) {
    add(
      'DV-MODULE-007',
      '${m.packageName} declares $item and its code never '
          'uses it.',
      level: 'warning',
    );
  }
}

void _checkPin(
  _Module m,
  DVModuleCapabilities manifest,
  DVModuleLock lock,
  Set<String> revoked,
  DVModulePublisherDirectory? publishers,
  List<DVModuleTrustFinding> findings,
) {
  void add(String? code, String message) => findings.add(
    DVModuleTrustFinding(module: m.id, code: code, message: message),
  );

  final DVModulePin? pin = lock.pins[m.packageName];
  final File signatureFile = File(p.join(m.root, dvModuleSignatureFile));
  final bool signed = signatureFile.existsSync();
  if (pin == null) {
    if (m.viaPackage || signed) {
      add(
        null,
        'module "${m.id}" (${m.packageName}) is not pinned. Review it '
        'and run dartvel modules pin ${m.id}; every resolution after that '
        'is compared against the pin.',
      );
    }
    return;
  }

  final String? installed = _versionOf(m.root);
  final Version? installedVersion = _parseVersion(installed);
  final Version? pinnedVersion = _parseVersion(pin.version);
  if (installedVersion == null || pinnedVersion == null) {
    add(
      'DV-MODULE-004',
      '${m.packageName} is at "$installed" and pinned at '
          '"${pin.version}", and one of them is not a version.',
    );
  } else if (installedVersion < pinnedVersion) {
    add(
      'DV-MODULE-004',
      '${m.packageName} $installed is older than the '
          'pinned ${pin.version}. An older release is signed as validly as a '
          'newer one, so it is refused rather than rolled back to; re-pin with '
          '--allow-downgrade if that is deliberate.',
    );
  } else if (installedVersion != pinnedVersion) {
    add(
      'DV-MODULE-004',
      '${m.packageName} resolved to $installed and the '
          'lockfile pins ${pin.version}. Review it and run dartvel modules pin '
          '${m.id}.',
    );
  }

  String? digest;
  try {
    digest = dvModulePackageDigest(m.root);
  } on DVModuleDigestException catch (e) {
    add('DV-MODULE-004', '${m.packageName}: ${e.message}');
  }
  // Against the digest the pin actually carries. A pub.dev module is pinned
  // by its archive and a foreign one by the wrapper generated from its
  // source, and comparing the second against sha256 would compare it against
  // nothing -- reporting every foreign module as substituted for having
  // exactly the bytes it was pinned with.
  if (digest != null && digest != pin.pinnedDigest) {
    add(
      'DV-MODULE-004',
      '${m.packageName}\'s digest is $digest and the '
          'lockfile pins ${pin.pinnedDigest}. The installed bytes are not the '
          'ones that were reviewed.',
    );
  }

  final String? pinnedKey = pin.key;
  if (pinnedKey != null) {
    final String pinnedFingerprint = _fingerprintOr(pinnedKey);
    if (revoked.contains(pinnedFingerprint)) {
      add(
        'DV-MODULE-005',
        '${m.packageName} is pinned to key '
            '$pinnedFingerprint, which dartvel.moduleTrust.revokedKeys revokes.',
      );
    }
    if (!signed) {
      add(
        'DV-MODULE-005',
        '${m.packageName} was signed by key '
            '$pinnedFingerprint when it was pinned and carries no signature '
            'now. A signature removed is an identity changed.',
      );
    } else {
      final String document = signatureFile.readAsStringSync();
      final String? claimed = dvClaimedModuleSigningKey(document);
      if (claimed == null) {
        add(
          'DV-MODULE-004',
          '${m.packageName}\'s $dvModuleSignatureFile '
              'cannot be read.',
        );
      } else if (claimed != pinnedKey) {
        final String claimedFingerprint = _fingerprintOr(claimed);
        add(
          'DV-MODULE-005',
          '${m.packageName} is signed by key '
              '$claimedFingerprint and was pinned to $pinnedFingerprint. A key '
              'that changes looks exactly like a routine upgrade until somebody '
              'looks: confirm the rotation with the publisher, then re-pin with '
              'dartvel modules pin ${m.id}.'
              '${revoked.contains(claimedFingerprint) ? ' The new key is revoked.' : ''}',
        );
      } else {
        try {
          final DVModuleSignedStatement statement = dvVerifyModuleSignature(
            document,
            publicKey: pinnedKey,
          ).statement;
          final String? mismatch = _statementMismatch(
            statement,
            packageName: m.packageName,
            version: installed,
            digest: digest,
            capabilities: manifest,
          );
          if (mismatch != null) {
            add('DV-MODULE-004', '${m.packageName}: $mismatch');
          }
        } on DVModuleSignatureException catch (e) {
          add('DV-MODULE-004', '${m.packageName}: ${e.message}');
        }
      }
    }
  } else if (signed) {
    add(
      'DV-MODULE-005',
      '${m.packageName} was unsigned when it was pinned and '
          'is signed now. A key appearing is an identity change like a key '
          'changing: re-pin with dartvel modules pin ${m.id}.',
    );
  }

  if (publishers != null) {
    final String? verified = publishers.verifiedPublisher(m.packageName);
    if (verified != pin.publisher) {
      add(
        'DV-MODULE-005',
        '${m.packageName} was pinned from publisher '
            '"${pin.publisher}" and the registry now verifies "$verified". '
            'Package takeover looks exactly like this; re-pin only once you '
            'know why.',
      );
    }
  }

  final List<String> kinds = manifest.kinds;
  if (kinds.join(',') != pin.capabilities.join(',')) {
    add(
      'DV-MODULE-003',
      '${m.packageName} was pinned declaring '
          '[${pin.capabilities.join(', ')}] and the installed manifest declares '
          '[${kinds.join(', ')}].',
    );
  }
}

Version? _parseVersion(String? value) {
  if (value == null) return null;
  try {
    return Version.parse(value);
  } on FormatException {
    return null;
  }
}

/// Why [statement] does not describe the installed package, or null.
String? _statementMismatch(
  DVModuleSignedStatement statement, {
  required String packageName,
  required String? version,
  required String? digest,
  required DVModuleCapabilities capabilities,
}) {
  if (statement.package != packageName) {
    return 'the signature is for package "${statement.package}".';
  }
  if (statement.version != version) {
    return 'the signature is for version ${statement.version} and the '
        'installed package is $version.';
  }
  if (digest == null || statement.sha256 != digest) {
    return 'the signature covers digest ${statement.sha256} and the installed '
        'bytes digest to $digest.';
  }
  if (statement.capabilities != capabilities) {
    return 'the signature covers capabilities (${statement.capabilities}) and '
        'the installed manifest declares ($capabilities).';
  }
  return null;
}

/// What pinning did.
class DVModulePinResult {
  const DVModulePinResult(this.pinned, this.refused);

  /// One line per module pinned, saying what changed.
  final List<String> pinned;
  final List<DVModuleTrustFinding> refused;

  bool get ok => refused.isEmpty;
}

/// Pins the modules the project at [root] mounts -- all of them, or the ids
/// in [only] -- into `dartvel.module.lock`.
///
/// Trust on first use, and the explicit re-pin after a reviewed change. It
/// refuses what no review can make right: a signature that does not verify, a
/// statement that does not describe the installed bytes, a revoked key, a
/// publisher claim the registry contradicts, an unsigned dependency, and --
/// unless [allowDowngrade] -- a version older than the current pin.
///
/// It grants nothing. Capabilities are compared against the grant by
/// [dvEvaluateModuleTrust] whatever the lockfile says.
DVModulePinResult dvPinModules(
  String root, {
  Set<String>? only,
  DVModulePublisherDirectory? publishers,
  bool allowDowngrade = false,
}) {
  final _Parent parent = _parent(root);
  final List<DVModuleTrustFinding> refused = <DVModuleTrustFinding>[
    ...parent.problems,
  ];
  final DVModuleLock lock = DVModuleLock.read(root);
  if (lock.problems.isNotEmpty) {
    // Rewriting would drop the entries that could not be read, which is a
    // pin silently removed.
    for (final String problem in lock.problems) {
      refused.add(
        DVModuleTrustFinding(
          module: dvModuleLockFile,
          message: '$problem Fix or delete it before pinning.',
        ),
      );
    }
    return DVModulePinResult(const <String>[], refused);
  }

  final Map<String, DVModulePin> pins = Map<String, DVModulePin>.of(lock.pins);
  final List<String> pinned = <String>[];

  for (final _Module m in parent.modules) {
    if (only != null && !only.contains(m.id)) continue;
    final int before = refused.length;
    void refuse(String? code, String message) => refused.add(
      DVModuleTrustFinding(module: m.id, code: code, message: message),
    );

    final String? version = _versionOf(m.root);
    final Version? parsedVersion = _parseVersion(version);
    if (parsedVersion == null) {
      refuse(
        'DV-MODULE-004',
        '${m.packageName} has no valid version, so there '
            'is nothing to pin.',
      );
      continue;
    }
    final String digest;
    try {
      digest = dvModulePackageDigest(m.root);
    } on DVModuleDigestException catch (e) {
      refuse('DV-MODULE-004', '${m.packageName}: ${e.message}');
      continue;
    }
    final DVCapabilityParse declared = _declared(m);
    for (final String problem in declared.problems) {
      refuse(null, problem);
    }

    String? key;
    String? fingerprint;
    String? publisher;
    final File signatureFile = File(p.join(m.root, dvModuleSignatureFile));
    if (signatureFile.existsSync()) {
      final String document = signatureFile.readAsStringSync();
      final String? claimed = dvClaimedModuleSigningKey(document);
      if (claimed == null) {
        refuse(
          'DV-MODULE-004',
          '${m.packageName}\'s $dvModuleSignatureFile '
              'cannot be read.',
        );
        continue;
      }
      fingerprint = _fingerprintOr(claimed);
      if (parent.revoked.contains(fingerprint)) {
        refuse(
          'DV-MODULE-005',
          '${m.packageName} is signed by key '
              '$fingerprint, which dartvel.moduleTrust.revokedKeys revokes. It '
              'is not pinned.',
        );
        continue;
      }
      final DVModuleSignedStatement statement;
      try {
        statement = dvVerifyModuleSignature(
          document,
          publicKey: claimed,
        ).statement;
      } on DVModuleSignatureException catch (e) {
        refuse('DV-MODULE-004', '${m.packageName}: ${e.message}');
        continue;
      }
      final String? mismatch = _statementMismatch(
        statement,
        packageName: m.packageName,
        version: version,
        digest: digest,
        capabilities: declared.capabilities,
      );
      if (mismatch != null) {
        refuse('DV-MODULE-004', '${m.packageName}: $mismatch');
        continue;
      }
      key = claimed;
      if (publishers != null) {
        publisher = publishers.verifiedPublisher(m.packageName);
        if (statement.publisher != null && statement.publisher != publisher) {
          refuse(
            'DV-MODULE-005',
            '${m.packageName} claims publisher '
                '"${statement.publisher}", and the registry verifies '
                '"$publisher". The claim is written by whoever signed it.',
          );
          continue;
        }
      }
    } else {
      if (m.viaPackage) {
        refuse(
          null,
          '${m.packageName} is a dependency and carries no '
          'signature. A distributed module is signed by its publisher; '
          'there is no key to pin.',
        );
        continue;
      }
      publisher = publishers?.verifiedPublisher(m.packageName);
    }

    final DVModulePin? existing = lock.pins[m.packageName];
    final List<String> changes = <String>[];
    if (existing != null) {
      final Version? previous = _parseVersion(existing.version);
      if (previous != null && parsedVersion < previous && !allowDowngrade) {
        refuse(
          'DV-MODULE-004',
          '${m.packageName} $version is older than the '
              'pinned ${existing.version}. Pass --allow-downgrade if rolling '
              'back is deliberate.',
        );
        continue;
      }
      if (existing.key != key) {
        changes.add(
          'key changed from '
          '${existing.key == null ? 'unsigned' : _fingerprintOr(existing.key!)} '
          'to ${fingerprint ?? 'unsigned'}',
        );
      }
      if (existing.publisher != publisher) {
        changes.add(
          'publisher changed from "${existing.publisher}" to '
          '"$publisher"',
        );
      }
    }
    if (refused.length != before) continue;

    pins[m.packageName] = DVModulePin(
      package: m.packageName,
      version: version!,
      sha256: digest,
      publisher: publisher,
      key: key,
      capabilities: declared.capabilities.kinds,
    );
    pinned.add(
      '${m.packageName} $version sha256 $digest, '
      'key ${fingerprint ?? 'unsigned'}'
      '${changes.isEmpty ? '' : ' (${changes.join('; ')})'}',
    );
  }

  if (pinned.isNotEmpty) DVModuleLock(pins).write(root);
  return DVModulePinResult(pinned, refused);
}

/// `dartvel modules publish`: the manifest derived, checked and signed.
///
/// The manifest is not a promise the module makes about itself. The
/// capabilities are derived from the code and compared with the declaration,
/// and a disagreement in either direction refuses the publish: a capability
/// used and never declared asks a parent for nothing it will then be given,
/// and one declared and never used asks a parent to grant something for no
/// reason (DV-MODULE-007).
///
/// Only once both agree is the package digested and the statement signed.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart' show dvModuleSigningPublicKey;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'capabilities.dart';
import 'capability_analysis.dart';
import 'module_signature.dart';
import 'module_trust.dart';
import 'package_digest.dart';

/// What publishing prepared, or why it did not.
class DVModulePublishResult {
  const DVModulePublishResult({
    required this.ok,
    required this.findings,
    this.signaturePath,
    this.statement,
    this.fingerprint,
  });

  final bool ok;
  final List<DVModuleTrustFinding> findings;
  final String? signaturePath;
  final DVModuleSignedStatement? statement;

  /// The signing key's fingerprint, which is how a parent names it.
  final String? fingerprint;
}

/// Checks the module at [moduleRoot] and writes its signature file.
///
/// Nothing is written when anything is refused.
DVModulePublishResult dvPrepareModulePublish(
  String moduleRoot, {
  required Uint8List privateKey,
  required String keyId,
  String? publisher,
}) {
  final List<DVModuleTrustFinding> findings = <DVModuleTrustFinding>[];
  Map<Object?, Object?> pubspec = const <Object?, Object?>{};
  try {
    final Object? doc = loadYaml(
      File(p.join(moduleRoot, 'pubspec.yaml')).readAsStringSync(),
    );
    if (doc is Map) pubspec = doc;
  } on Object {
    // Reported below as a missing name.
  }
  final Object? name = pubspec['name'];
  final String package = name is String ? name : p.basename(moduleRoot);
  void refuse(String? code, String message) => findings.add(
    DVModuleTrustFinding(module: package, code: code, message: message),
  );

  if (name is! String) refuse(null, 'There is no pubspec.yaml with a name.');
  final String version = '${pubspec['version']}';
  try {
    Version.parse(version);
  } on FormatException {
    refuse(null, 'The pubspec version is "$version", which is not a version.');
  }

  final Object? dartvel = pubspec['dartvel'];
  final Object? module = dartvel is Map ? dartvel['module'] : null;
  final Object? raw = module is Map ? module['capabilities'] : null;
  final DVCapabilityParse declared = raw is List
      ? const DVCapabilityParse(DVModuleCapabilities.none, <String>[])
      : dvParseModuleCapabilities(raw, where: 'dartvel.module.capabilities');
  for (final String problem in declared.problems) {
    refuse(null, problem);
  }

  final DVModuleCodeAnalysis code = dvAnalyseModuleProject(moduleRoot);
  for (final DVModuleCodeUse use in code.ownNetwork) {
    refuse(
      'DV-MODULE-008',
      'opens its own connection at ${use.file}:'
          '${use.line} (${use.what}). Make the call through DV.Http, so that '
          'the domain can be declared and granted.',
    );
  }
  for (final DVModuleCodeUse use in code.unresolved) {
    refuse(
      null,
      'reaches ${use.what} at ${use.file}:${use.line}. The '
      'capability list cannot be derived from a value built at runtime, and '
      'a parent cannot grant what it cannot see.',
    );
  }
  for (final String item in code.uses.missingFrom(declared.capabilities)) {
    refuse(
      'DV-MODULE-007',
      'the code uses $item and '
          'dartvel.module.capabilities does not declare it.',
    );
  }
  for (final String item in declared.capabilities.missingFrom(code.uses)) {
    refuse(
      'DV-MODULE-007',
      'dartvel.module.capabilities declares $item and '
          'the code never uses it.',
    );
  }
  if (findings.isNotEmpty) {
    return DVModulePublishResult(ok: false, findings: findings);
  }

  final String digest;
  try {
    digest = dvModulePackageDigest(moduleRoot);
  } on DVModuleDigestException catch (e) {
    refuse(null, e.message);
    return DVModulePublishResult(ok: false, findings: findings);
  }

  final DVModuleSignedStatement statement = DVModuleSignedStatement(
    package: package,
    version: version,
    sha256: digest,
    capabilities: declared.capabilities,
    publisher: publisher,
    dartvel: _dartvelRange(pubspec),
  );
  final File signature = File(p.join(moduleRoot, dvModuleSignatureFile))
    ..writeAsStringSync(
      dvSignModulePackage(statement, privateKey: privateKey, keyId: keyId),
    );
  return DVModulePublishResult(
    ok: true,
    findings: findings,
    signaturePath: signature.path,
    statement: statement,
    fingerprint: dvModuleKeyFingerprint(dvModuleSigningPublicKey(privateKey)),
  );
}

/// The Dartvel range the module depends on, as its pubspec writes it.
String? _dartvelRange(Map<Object?, Object?> pubspec) {
  final Object? dependencies = pubspec['dependencies'];
  if (dependencies is! Map) return null;
  for (final String name in const <String>['dartvel_flutter', 'dartvel_core']) {
    final Object? value = dependencies[name];
    if (value is String) return value;
    if (value is Map && value['version'] is String) {
      return value['version'] as String;
    }
  }
  return null;
}

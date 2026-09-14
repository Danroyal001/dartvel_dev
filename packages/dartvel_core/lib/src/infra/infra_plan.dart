/// What a host has, and the steps that converge it on the manifest.
///
/// A plan is a diff, never a script: it is recomputed from what the host
/// reports, so a step that already landed is not in it, and running it again
/// after a failure repeats nothing that succeeded.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'infra_desired.dart';

/// Resolves a secret's value where the provision runs. Null when unset.
typedef DVInfraSecretLookup = String? Function(String name);

/// One resource as the host reports it.
final class DVObservedResource {
  const DVObservedResource({
    required this.kind,
    required this.id,
    this.sha256,
    this.mode,
    this.owner,
    this.enabled = false,
    this.active = false,
    this.credentialSalt,
    this.credentialMac,
    this.firewall,
    this.installedVersion,
    this.recordedVersion,
  });

  final DVInfraResourceKind kind;
  final String id;

  /// SHA-256 of a file's or unit's content; null for a unit its package
  /// ships.
  final String? sha256;
  final String? mode;
  final String? owner;
  final bool enabled;
  final bool active;

  /// A credential is never read back. The provisioner leaves a random salt
  /// and an HMAC of the value beside it, which says whether the value changed
  /// without the value being recoverable from what is on the host.
  final String? credentialSalt;
  final String? credentialMac;

  /// The rules actually loaded, which can differ from the file on disk: a
  /// rule added with `nft add rule` during an incident is in one and not the
  /// other.
  final DVInfraFirewallRules? firewall;

  /// The package version installed now, and the one recorded when it was
  /// provisioned.
  final String? installedVersion;
  final String? recordedVersion;
}

/// A certificate as the host reports it.
final class DVObservedCertificate {
  const DVObservedCertificate({this.notAfter, this.renewalFailing = false});

  /// Null when there is no certificate yet.
  final DateTime? notAfter;

  /// Whether the proxy's recent renewal attempts have failed.
  final bool renewalFailing;
}

/// Everything the provisioner reads from one host.
final class DVInfraObservation {
  const DVInfraObservation({
    required this.host,
    required this.resources,
    this.releasePresent = false,
    this.certificates = const <String, DVObservedCertificate>{},
    this.lastVerifiedRestore,
  });

  final String host;

  /// Managed resources only: files and units carrying the marker, this
  /// application's credentials, and the packages and packaged units the
  /// manifest names.
  final List<DVObservedResource> resources;

  /// Whether a release has put the backend binary on the host.
  final bool releasePresent;
  final Map<String, DVObservedCertificate> certificates;
  final DateTime? lastVerifiedRestore;

  DVObservedResource? find(DVInfraResourceKind kind, String id) {
    for (final DVObservedResource r in resources) {
      if (r.kind == kind && r.id == id) return r;
    }
    return null;
  }
}

enum DVInfraAction { install, create, write, deliver, enable, start, restart, remove }

/// One step of a plan.
final class DVInfraStep {
  const DVInfraStep({
    required this.action,
    required this.kind,
    required this.id,
    required this.reason,
  });

  final DVInfraAction action;
  final DVInfraResourceKind kind;
  final String id;
  final String reason;

  /// Removing something stops a service or deletes what it held, so it is
  /// never applied without somebody saying yes.
  bool get destructive => action == DVInfraAction.remove;

  Map<String, Object?> toJson() => <String, Object?>{
    'action': action.name,
    'kind': kind.name,
    'id': id,
    'reason': reason,
  };

  static DVInfraStep fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a plan step must be a map');
    DVInfraAction? action;
    DVInfraResourceKind? kind;
    for (final DVInfraAction a in DVInfraAction.values) {
      if (a.name == json['action']) action = a;
    }
    for (final DVInfraResourceKind k in DVInfraResourceKind.values) {
      if (k.name == json['kind']) kind = k;
    }
    final Object? id = json['id'];
    final Object? reason = json['reason'];
    if (action == null || kind == null || id is! String || reason is! String) {
      throw FormatException('not a plan step: $json');
    }
    return DVInfraStep(action: action, kind: kind, id: id, reason: reason);
  }

  @override
  String toString() => '${action.name} $id ($reason)';
}

/// The steps for one host, and what they were computed from.
final class DVInfraPlan {
  DVInfraPlan({
    required this.host,
    required this.desiredDigest,
    required List<DVInfraStep> steps,
    List<String> unsupported = const <String>[],
    List<String> notes = const <String>[],
  }) : steps = List<DVInfraStep>.unmodifiable(steps),
       unsupported = List<String>.unmodifiable(unsupported),
       notes = List<String>.unmodifiable(notes);

  final String host;
  final String desiredDigest;
  final List<DVInfraStep> steps;

  /// Non-empty refuses the apply.
  final List<String> unsupported;
  final List<String> notes;

  bool get isEmpty => steps.isEmpty;

  List<DVInfraStep> get destructive =>
      steps.where((DVInfraStep s) => s.destructive).toList();

  /// Identifies this plan: the manifest rendering and every step. An apply
  /// proceeds only when the plan it computes has the digest that was
  /// approved, so what is applied is what was read.
  String get digest {
    final StringBuffer b = StringBuffer('$host\n$desiredDigest\n');
    for (final DVInfraStep s in steps) {
      b.write('${s.action.name} ${s.kind.name} ${s.id}\n');
    }
    for (final String u in unsupported) {
      b.write('unsupported $u\n');
    }
    return sha256.convert(utf8.encode(b.toString())).toString();
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(
    <String, Object?>{
      'host': host,
      'desiredDigest': desiredDigest,
      'digest': digest,
      'steps': <Object?>[for (final DVInfraStep s in steps) s.toJson()],
      'unsupported': unsupported,
      'notes': notes,
    },
  );

  /// Reads a plan written by [toJsonString], refusing one whose digest does
  /// not match its steps: an edited plan file is not the plan approved.
  static DVInfraPlan fromJsonString(String text) {
    final Object? json = jsonDecode(text);
    if (json is! Map) throw const FormatException('a plan must be an object');
    final Object? steps = json['steps'];
    final Object? host = json['host'];
    final Object? desired = json['desiredDigest'];
    if (steps is! List || host is! String || desired is! String) {
      throw const FormatException('a plan needs host, desiredDigest and steps');
    }
    final DVInfraPlan plan = DVInfraPlan(
      host: host,
      desiredDigest: desired,
      steps: <DVInfraStep>[for (final Object? s in steps) DVInfraStep.fromJson(s)],
      unsupported: <String>[
        for (final Object? u in (json['unsupported'] as List?) ?? const <Object?>[])
          '$u',
      ],
      notes: <String>[
        for (final Object? n in (json['notes'] as List?) ?? const <Object?>[]) '$n',
      ],
    );
    if (plan.digest != json['digest']) {
      throw const FormatException(
        'the plan file does not match its own digest; it was edited after it '
        'was written',
      );
    }
    return plan;
  }
}

/// HMAC-SHA256 of [value] keyed by [salt], hex.
String dvInfraCredentialMac(String salt, String value) =>
    Hmac(sha256, utf8.encode(salt)).convert(utf8.encode(value)).toString();

/// The steps that take [observed] to [desired].
///
/// Converging steps run in resource-kind order, so a package is installed
/// before its unit is started and a credential delivered before the service
/// that loads it. Removals come last, services before what they used.
DVInfraPlan dvInfraPlan(
  DVInfraDesiredState desired,
  DVInfraObservation observed, {
  required DVInfraSecretLookup secret,
}) {
  final List<DVInfraStep> converge = <DVInfraStep>[];
  final List<String> unsupported = <String>[...desired.unsupported];
  final List<String> notes = <String>[...desired.notes];
  final Set<String> delivered = <String>{};
  final Set<String> desiredKeys = <String>{};
  int waiting = 0;

  final List<DVInfraResource> ordered = <DVInfraResource>[...desired.resources]
    ..sort(
      (DVInfraResource a, DVInfraResource b) =>
          a.kind.index.compareTo(b.kind.index),
    );

  void step(DVInfraAction action, DVInfraResource r, String reason) =>
      converge.add(
        DVInfraStep(action: action, kind: r.kind, id: r.id, reason: reason),
      );

  for (final DVInfraResource r in ordered) {
    desiredKeys.add(r.key);
    final DVObservedResource? o = observed.find(r.kind, r.id);
    switch (r.kind) {
      case DVInfraResourceKind.package:
        if (o == null) step(DVInfraAction.install, r, 'not installed');
      case DVInfraResourceKind.user:
        if (o == null) step(DVInfraAction.create, r, 'no such user');
      case DVInfraResourceKind.file:
        final String? why = _contentDiffers(r, o);
        if (why != null) step(DVInfraAction.write, r, why);
      case DVInfraResourceKind.firewall:
        String? why = _contentDiffers(r, o);
        if (why == null && o != null) {
          why = _firewallDiffers(r.firewall!, o.firewall);
        }
        if (why != null) step(DVInfraAction.write, r, why);
      case DVInfraResourceKind.credential:
        final String? value = secret(r.id);
        if (value == null) {
          unsupported.add(
            '${r.id} is delivered to the host and does not resolve here',
          );
          continue;
        }
        if (o == null || o.credentialSalt == null || o.credentialMac == null) {
          step(DVInfraAction.deliver, r, 'not on the host');
          delivered.add(r.id);
        } else if (dvInfraCredentialMac(o.credentialSalt!, value) !=
            o.credentialMac) {
          step(DVInfraAction.deliver, r, 'the value has changed');
          delivered.add(r.id);
        }
      case DVInfraResourceKind.unit:
        bool written = false;
        if (r.content != null) {
          final String? why = _contentDiffers(r, o);
          if (why != null) {
            step(DVInfraAction.write, r, why);
            written = true;
          }
        }
        if (r.enabled && !(o?.enabled ?? false)) {
          step(DVInfraAction.enable, r, 'not enabled at boot');
        }
        if (!r.active) continue;
        if (r.requiresRelease && !observed.releasePresent) {
          waiting++;
          continue;
        }
        if (!(o?.active ?? false)) {
          step(DVInfraAction.start, r, 'not running');
        } else if (written) {
          step(DVInfraAction.restart, r, 'its unit changed');
        } else {
          final List<String> rotated =
              r.credentials.where(delivered.contains).toList();
          if (rotated.isNotEmpty) {
            step(
              DVInfraAction.restart,
              r,
              'it loads ${rotated.join(', ')}, which changed',
            );
          }
        }
    }
  }

  if (waiting > 0) {
    notes.add(
      'No release at /opt/${desired.appName}/server yet: $waiting service '
      'unit(s) are enabled and start with the first deploy',
    );
  }

  final List<DVObservedResource> extra = observed.resources
      .where(
        (DVObservedResource o) =>
            !desiredKeys.contains('${o.kind.name}:${o.id}') &&
            switch (o.kind) {
              DVInfraResourceKind.file ||
              DVInfraResourceKind.credential ||
              DVInfraResourceKind.firewall => true,
              // A unit its package ships is the package's, not ours.
              DVInfraResourceKind.unit => o.sha256 != null,
              DVInfraResourceKind.package || DVInfraResourceKind.user => false,
            },
      )
      .toList()
    ..sort(
      (DVObservedResource a, DVObservedResource b) =>
          b.kind.index.compareTo(a.kind.index),
    );
  final List<DVInfraStep> removals = <DVInfraStep>[
    for (final DVObservedResource o in extra)
      DVInfraStep(
        action: DVInfraAction.remove,
        kind: o.kind,
        id: o.id,
        reason: 'no longer in the manifest',
      ),
  ];

  return DVInfraPlan(
    host: observed.host,
    desiredDigest: desired.digest,
    steps: <DVInfraStep>[...converge, ...removals],
    unsupported: unsupported,
    notes: notes,
  );
}

String? _contentDiffers(DVInfraResource r, DVObservedResource? o) {
  if (o == null) return 'not on the host';
  final List<String> why = <String>[];
  if (o.sha256 != r.contentSha256) why.add('content differs');
  if (r.mode != null && o.mode != r.mode) why.add('mode is ${o.mode}, not ${r.mode}');
  if (r.owner != null && o.owner != r.owner) {
    why.add('owner is ${o.owner}, not ${r.owner}');
  }
  return why.isEmpty ? null : why.join('; ');
}

String? _firewallDiffers(DVInfraFirewallRules want, DVInfraFirewallRules? live) {
  if (live == null) return 'the live ruleset could not be read';
  if (live == want) return null;
  final List<String> why = <String>[];
  if (live.policy != want.policy) {
    why.add('the live input policy is ${live.policy}, not ${want.policy}');
  }
  void ports(String proto, Set<int> have, Set<int> should) {
    final List<int> open = (have.difference(should).toList()..sort());
    final List<int> closed = (should.difference(have).toList()..sort());
    if (open.isNotEmpty) {
      why.add('the live ruleset opens $proto ${open.join(', ')}, which the '
          'manifest does not');
    }
    if (closed.isNotEmpty) {
      why.add('the live ruleset does not open $proto ${closed.join(', ')}');
    }
  }

  ports('tcp', live.tcpPorts, want.tcpPorts);
  ports('udp', live.udpPorts, want.udpPorts);
  return why.join('; ');
}

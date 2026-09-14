/// The resources a manifest becomes on a host: packages, the service user,
/// files, encrypted credentials, the firewall and supervised units.
///
/// Pure. The same manifest always renders the same resources, which is what
/// lets a plan be compared with the one that was approved.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'infra_manifest.dart';

/// What the built backend binary honours when a unit starts it.
///
/// The provisioner can only supervise what the binary can be told to be. The
/// generated `startBackend` binds the port fixed at generation, reads none
/// from its environment, ticks every `@DVBackendCron` schedule in every
/// process, and has no worker entry point -- so the defaults are all false,
/// and a manifest that needs one of them is refused rather than rendered
/// into units that would crash-loop on a taken port or run each schedule
/// once per instance.
///
/// The contract, when a flag is true:
///  * [portFromEnvironment]: the process binds `DARTVEL_PORT`;
///  * [workerRole]: `DARTVEL_ROLE=worker` with `DARTVEL_QUEUE` works that
///    queue and serves nothing;
///  * [cronRole]: `DARTVEL_ROLE=cron` ticks the schedules, and
///    `DARTVEL_ROLE=backend` does not.
final class DVInfraBackendCapabilities {
  const DVInfraBackendCapabilities({
    this.portFromEnvironment = false,
    this.workerRole = false,
    this.cronRole = false,
  });

  final bool portFromEnvironment;
  final bool workerRole;
  final bool cronRole;
}

/// Kinds, in the order they are converged. Removal runs in reverse.
enum DVInfraResourceKind { package, user, file, credential, firewall, unit }

/// The firewall's meaning, independent of how a ruleset happens to be spelt.
final class DVInfraFirewallRules {
  const DVInfraFirewallRules({
    required this.policy,
    required this.tcpPorts,
    this.udpPorts = const <int>{},
  });

  /// The input chain's policy: `drop` or `accept`.
  final String policy;
  final Set<int> tcpPorts;
  final Set<int> udpPorts;

  /// A canonical spelling, compared between desired and observed.
  String get canonical {
    String ports(Set<int> p) => (p.toList()..sort()).join(',');
    return 'policy=$policy;tcp=${ports(tcpPorts)};udp=${ports(udpPorts)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DVInfraFirewallRules && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => canonical;
}

/// One thing a provisioned host has.
final class DVInfraResource {
  const DVInfraResource({
    required this.kind,
    required this.id,
    this.content,
    this.mode,
    this.owner,
    this.enabled = false,
    this.active = false,
    this.requiresRelease = false,
    this.credentials = const <String>[],
    this.firewall,
    this.path,
  });

  final DVInfraResourceKind kind;

  /// A package name, user name, absolute path, credential name, or unit name.
  final String id;

  /// A file's or unit's text. Null for a unit a package ships, and always
  /// null for a credential: the plan carries names, never values.
  final String? content;

  /// Octal, e.g. `0644`.
  final String? mode;
  final String? owner;

  /// For units: enabled at boot, and expected to be running.
  final bool enabled;
  final bool active;

  /// A unit that runs the released binary. It cannot run before a release
  /// has put one on the host, so it is enabled but not started until then.
  final bool requiresRelease;

  /// For units: the credentials they load, so rotating one restarts them.
  final List<String> credentials;

  final DVInfraFirewallRules? firewall;

  /// Where a unit, credential or firewall ruleset lives on the host.
  final String? path;

  /// SHA-256 of [content], or null when there is none.
  String? get contentSha256 =>
      content == null ? null : sha256.convert(utf8.encode(content!)).toString();

  /// `kind:id`, unique within a desired state.
  String get key => '${kind.name}:$id';
}

/// A manifest rendered for one application.
final class DVInfraDesiredState {
  const DVInfraDesiredState({
    required this.appName,
    required this.manifest,
    required this.resources,
    required this.unsupported,
    required this.notes,
  });

  final String appName;
  final DVInfraManifest manifest;
  final List<DVInfraResource> resources;

  /// Declarations the provisioner cannot honour. A non-empty list refuses
  /// the provision: a host reported provisioned without them is the failure.
  final List<String> unsupported;

  /// Things the operator should know that are not refusals.
  final List<String> notes;

  DVInfraResource? byId(String id) {
    for (final DVInfraResource r in resources) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// SHA-256 over every resource, so two renderings can be compared.
  String get digest {
    final StringBuffer b = StringBuffer();
    for (final DVInfraResource r in resources) {
      b
        ..write(r.key)
        ..write('|${r.contentSha256}|${r.mode}|${r.owner}')
        ..write('|${r.enabled}|${r.active}|${r.requiresRelease}')
        ..write('|${r.credentials.join(',')}|${r.firewall?.canonical}')
        ..write('|${r.path}\n');
    }
    return sha256.convert(utf8.encode(b.toString())).toString();
  }
}

/// The marker every file the provisioner writes starts with, so the observer
/// can find what it manages and nothing else.
String dvInfraMarker(String appName) =>
    '# Managed by dartvel infra ($appName). Edit dartvel.infra in '
    'pubspec.yaml, not this file.';

/// Where the credential [name] of [appName] is kept, encrypted, on a host.
String dvInfraCredentialPath(String appName, String name) =>
    '/etc/credstore.encrypted/$appName.$name';

/// Renders [manifest] for [appName].
///
/// [secretNames] are the backend secrets to deliver: declared, and resolved
/// where the provision runs. `PUBLIC_` names are left out because they ship
/// in the bundle. [backendPort] is `dartvel.server.port`.
DVInfraDesiredState dvInfraDesiredState(
  DVInfraManifest manifest, {
  required String appName,
  required int backendPort,
  DVInfraBackendCapabilities capabilities = const DVInfraBackendCapabilities(),
  Set<String> secretNames = const <String>{},
}) {
  if (!RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(appName)) {
    throw ArgumentError.value(appName, 'appName', 'not a package name');
  }
  final String marker = dvInfraMarker(appName);
  final String env = 'dartvel.infra.${manifest.environment}';
  final List<String> unsupported = <String>[];
  final List<String> notes = <String>[];
  final List<DVInfraResource> resources = <DVInfraResource>[];
  final DVInfraServices services = manifest.services;

  if (manifest.adapter != DVInfraAdapterKind.ssh) {
    unsupported.add(
      '$env.adapter: ${manifest.adapter.configName} is not built; only ssh '
      'provisions a host',
    );
  }
  if (manifest.logsShip != null) {
    unsupported.add(
      '$env.logs.ship: ${manifest.logsShip} is not built; the units log to '
      'the journal and nothing ships it',
    );
  }

  int instances = services.backendInstances;
  if (instances > 1 && !capabilities.portFromEnvironment) {
    unsupported.add(
      '$env.services.backend.instances: $instances. The generated backend '
      'binds dartvel.server.port ($backendPort), fixed when it was generated, '
      'and reads no port from its environment, so a second instance on the '
      'same host could not bind',
    );
    instances = 1;
  }
  if (services.workerQueues.isNotEmpty && !capabilities.workerRole) {
    unsupported.add(
      '$env.services.workers: the generated backend has no worker entry '
      'point, so a worker unit would start a second web server rather than '
      'work ${services.workerQueues.join(', ')}',
    );
  }
  final bool cronUnit = services.cron == true && capabilities.cronRole;
  if (!capabilities.cronRole) {
    if (services.cron == false) {
      unsupported.add(
        '$env.services.cron.enabled: false. The generated backend ticks its '
        'schedules in every process, so they cannot be switched off here',
      );
    } else if (services.backendInstances > 1) {
      final String message =
          '$env.services: the generated backend ticks its schedules in every '
          'process, so with ${services.backendInstances} instances each '
          'schedule would fire ${services.backendInstances} times';
      if (services.cron == true) {
        unsupported.add(message);
      } else {
        notes.add(message);
      }
    } else if (services.cron == true) {
      notes.add(
        'Schedules tick inside $appName-backend-1.service: the generated '
        'backend runs them in-process, so no separate cron unit is installed',
      );
    }
  }

  final DVInfraBackup? backup = manifest.database?.backup;
  final bool backupBuilt = backup != null && secretNames.contains('DATABASE_URL');
  if (backup != null && !backupBuilt) {
    unsupported.add(
      '$env.database.backup needs DATABASE_URL declared under dartvel.secrets '
      'and resolvable here: it is the connection the backup is taken over',
    );
  }

  final List<String> credentials =
      secretNames.where((String n) => !n.startsWith('PUBLIC_')).toList()..sort();

  // Packages.
  if (manifest.proxy == 'caddy') {
    resources.add(const DVInfraResource(kind: DVInfraResourceKind.package, id: 'caddy'));
  }
  resources.add(const DVInfraResource(kind: DVInfraResourceKind.package, id: 'nftables'));
  if (backupBuilt) {
    resources.add(
      const DVInfraResource(kind: DVInfraResourceKind.package, id: 'postgresql-client'),
    );
  }

  // The service user.
  resources.add(DVInfraResource(kind: DVInfraResourceKind.user, id: appName));

  // Files.
  final List<int> ports = <int>[
    for (int i = 0; i < instances; i++) backendPort + i,
  ];
  if (manifest.proxy == 'caddy') {
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.file,
      id: '/etc/caddy/Caddyfile',
      path: '/etc/caddy/Caddyfile',
      mode: '0644',
      owner: 'root',
      content: _caddyfile(marker, manifest.tls, ports),
    ));
  }
  if (backupBuilt) {
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.file,
      id: '/usr/local/lib/dartvel/$appName/backup.sh',
      path: '/usr/local/lib/dartvel/$appName/backup.sh',
      mode: '0755',
      owner: 'root',
      content: _backupScript(marker, appName, backup.retain),
    ));
  }

  // Credentials: names only.
  for (final String name in credentials) {
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.credential,
      id: name,
      path: dvInfraCredentialPath(appName, name),
    ));
  }

  // The firewall. Closed unless the manifest opened it; the port the
  // provisioner connects on is always open, or the first apply locks it out.
  final DVInfraFirewallRules rules = DVInfraFirewallRules(
    policy: 'drop',
    tcpPorts: <int>{
      manifest.ssh.port,
      if (manifest.proxy != null) ...<int>[80, 443] else ...ports,
    },
  );
  resources.add(DVInfraResource(
    kind: DVInfraResourceKind.firewall,
    id: '/etc/nftables.conf',
    path: '/etc/nftables.conf',
    mode: '0644',
    owner: 'root',
    content: _nftables(marker, rules),
    firewall: rules,
  ));

  // Units.
  String unit(String name) => '/etc/systemd/system/$name';
  resources.add(const DVInfraResource(
    kind: DVInfraResourceKind.unit,
    id: 'nftables.service',
    enabled: true,
    active: true,
  ));
  if (manifest.proxy == 'caddy') {
    resources.add(const DVInfraResource(
      kind: DVInfraResourceKind.unit,
      id: 'caddy.service',
      enabled: true,
      active: true,
    ));
  }
  for (int i = 1; i <= instances; i++) {
    final String name = '$appName-backend-$i.service';
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.unit,
      id: name,
      path: unit(name),
      mode: '0644',
      owner: 'root',
      enabled: true,
      active: true,
      requiresRelease: true,
      credentials: credentials,
      content: _serviceUnit(
        marker: marker,
        appName: appName,
        description: '$appName backend $i',
        environment: <String, String>{
          'DARTVEL_ENVIRONMENT': manifest.environment,
          if (capabilities.portFromEnvironment) 'DARTVEL_PORT': '${backendPort + i - 1}',
          if (capabilities.cronRole) 'DARTVEL_ROLE': 'backend',
        },
        credentials: credentials,
      ),
    ));
  }
  if (capabilities.workerRole) {
    for (final String queue in services.workerQueues) {
      for (int i = 1; i <= services.workerInstances; i++) {
        final String name = '$appName-worker-$queue-$i.service';
        resources.add(DVInfraResource(
          kind: DVInfraResourceKind.unit,
          id: name,
          path: unit(name),
          mode: '0644',
          owner: 'root',
          enabled: true,
          active: true,
          requiresRelease: true,
          credentials: credentials,
          content: _serviceUnit(
            marker: marker,
            appName: appName,
            description: '$appName worker $queue $i',
            environment: <String, String>{
              'DARTVEL_ENVIRONMENT': manifest.environment,
              'DARTVEL_ROLE': 'worker',
              'DARTVEL_QUEUE': queue,
            },
            credentials: credentials,
          ),
        ));
      }
    }
  }
  if (cronUnit) {
    final String name = '$appName-cron.service';
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.unit,
      id: name,
      path: unit(name),
      mode: '0644',
      owner: 'root',
      enabled: true,
      active: true,
      requiresRelease: true,
      credentials: credentials,
      content: _serviceUnit(
        marker: marker,
        appName: appName,
        description: '$appName schedules',
        environment: <String, String>{
          'DARTVEL_ENVIRONMENT': manifest.environment,
          'DARTVEL_ROLE': 'cron',
        },
        credentials: credentials,
      ),
    ));
  }
  if (backupBuilt) {
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.unit,
      id: '$appName-backup.service',
      path: unit('$appName-backup.service'),
      mode: '0644',
      owner: 'root',
      // Started by its timer, not at boot, and not running between backups.
      credentials: const <String>['DATABASE_URL'],
      content: _backupService(marker, appName),
    ));
    resources.add(DVInfraResource(
      kind: DVInfraResourceKind.unit,
      id: '$appName-backup.timer',
      path: unit('$appName-backup.timer'),
      mode: '0644',
      owner: 'root',
      enabled: true,
      active: true,
      content: _backupTimer(marker, appName, dvCronToOnCalendar(backup.schedule)),
    ));
  }
  if (manifest.database != null && backup == null) {
    notes.add(
      '$env.database declares no backup. Nothing is scheduled, and '
      'dartvel infra check has no restore to report the age of',
    );
  }

  return DVInfraDesiredState(
    appName: appName,
    manifest: manifest,
    resources: List<DVInfraResource>.unmodifiable(resources),
    unsupported: List<String>.unmodifiable(unsupported),
    notes: List<String>.unmodifiable(notes),
  );
}

String _caddyfile(String marker, DVInfraTls? tls, List<int> ports) {
  final StringBuffer b = StringBuffer()..writeln(marker);
  if (tls != null) {
    // Caddy obtains and renews the certificate itself, from inside a
    // supervised unit, retrying on failure; the account email is where the
    // CA writes before an expiry.
    b
      ..writeln('{')
      ..writeln('\temail ${tls.acmeEmail}')
      ..writeln('}')
      ..writeln()
      ..writeln('${tls.domains.join(', ')} {');
  } else {
    b.writeln(':80 {');
  }
  b
    ..writeln('\treverse_proxy ${ports.map((int p) => '127.0.0.1:$p').join(' ')}')
    ..writeln('}');
  return b.toString();
}

String _nftables(String marker, DVInfraFirewallRules rules) {
  final List<int> tcp = rules.tcpPorts.toList()..sort();
  return '#!/usr/sbin/nft -f\n'
      '$marker\n'
      'flush ruleset\n'
      '\n'
      'table inet dartvel {\n'
      '\tchain input {\n'
      '\t\ttype filter hook input priority filter; policy ${rules.policy};\n'
      '\t\tct state established,related accept\n'
      '\t\tct state invalid drop\n'
      '\t\tiifname "lo" accept\n'
      '\t\tmeta l4proto { icmp, ipv6-icmp } accept\n'
      '\t\ttcp dport { ${tcp.join(', ')} } accept\n'
      '\t}\n'
      '\tchain forward {\n'
      '\t\ttype filter hook forward priority filter; policy drop;\n'
      '\t}\n'
      '}\n';
}

String _serviceUnit({
  required String marker,
  required String appName,
  required String description,
  required Map<String, String> environment,
  required List<String> credentials,
}) {
  final StringBuffer b = StringBuffer()
    ..writeln(marker)
    ..writeln('[Unit]')
    ..writeln('Description=$description')
    ..writeln('After=network-online.target')
    ..writeln('Wants=network-online.target')
    ..writeln()
    ..writeln('[Service]')
    ..writeln('Type=simple')
    ..writeln('User=$appName')
    ..writeln('Group=$appName')
    ..writeln('WorkingDirectory=/opt/$appName')
    ..writeln('ExecStart=/opt/$appName/server');
  for (final MapEntry<String, String> e in environment.entries) {
    b.writeln('Environment=${e.key}=${e.value}');
  }
  // Encrypted at rest with the host's credential key, decrypted into a
  // private in-memory directory only while the unit runs. An
  // EnvironmentFile would be the same secret in plaintext on disk.
  for (final String name in credentials) {
    b.writeln(
      'LoadCredentialEncrypted=$name:${dvInfraCredentialPath(appName, name)}',
    );
  }
  b
    ..writeln('StateDirectory=$appName')
    ..writeln('Restart=always')
    ..writeln('RestartSec=2')
    ..writeln('NoNewPrivileges=true')
    ..writeln('ProtectSystem=strict')
    ..writeln('ProtectHome=true')
    ..writeln('PrivateTmp=true')
    ..writeln()
    ..writeln('[Install]')
    ..writeln('WantedBy=multi-user.target');
  return b.toString();
}

String _backupScript(String marker, String appName, Duration retain) {
  final String age = retain.inHours % 24 == 0
      ? '-mtime +${retain.inDays}'
      : '-mmin +${retain.inMinutes}';
  return '#!/bin/sh\n'
      '$marker\n'
      'set -eu\n'
      'umask 077\n'
      'dir=/var/backups/$appName\n'
      'stamp=\$(date -u +%Y%m%dT%H%M%SZ)\n'
      'partial="\$dir/$appName-\$stamp.dump.partial"\n'
      '# Written under another name and renamed, so a dump that died half way\n'
      '# is never mistaken for a backup.\n'
      'pg_dump --format=custom --file="\$partial" '
      '--dbname="\$(cat "\$CREDENTIALS_DIRECTORY/DATABASE_URL")"\n'
      'mv "\$partial" "\$dir/$appName-\$stamp.dump"\n'
      "find \"\$dir\" -name '$appName-*.dump' $age -delete\n"
      "find \"\$dir\" -name '*.partial' -mmin +1440 -delete\n";
}

String _backupService(String marker, String appName) =>
    '$marker\n'
    '[Unit]\n'
    'Description=$appName database backup\n'
    'After=network-online.target\n'
    'Wants=network-online.target\n'
    '\n'
    '[Service]\n'
    'Type=oneshot\n'
    'User=$appName\n'
    'Group=$appName\n'
    'ExecStartPre=+/usr/bin/install -d -m 0700 -o $appName -g $appName /var/backups/$appName\n'
    'ExecStart=/usr/local/lib/dartvel/$appName/backup.sh\n'
    'LoadCredentialEncrypted=DATABASE_URL:${dvInfraCredentialPath(appName, 'DATABASE_URL')}\n'
    'ReadWritePaths=/var/backups/$appName\n'
    '# pg_dump takes the connection string, password included, as an\n'
    '# argument. Other users must not be able to read the process list.\n'
    'ProtectProc=invisible\n'
    'ProcSubset=pid\n'
    'NoNewPrivileges=true\n'
    'ProtectSystem=strict\n'
    'ProtectHome=true\n'
    'PrivateTmp=true\n';

String _backupTimer(String marker, String appName, String onCalendar) =>
    '$marker\n'
    '[Unit]\n'
    'Description=$appName database backup schedule\n'
    '\n'
    '[Timer]\n'
    'OnCalendar=$onCalendar\n'
    '# A host that was off at the scheduled time backs up when it comes back.\n'
    'Persistent=true\n'
    'Unit=$appName-backup.service\n'
    '\n'
    '[Install]\n'
    'WantedBy=timers.target\n';

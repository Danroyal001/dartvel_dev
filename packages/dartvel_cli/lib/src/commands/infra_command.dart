/// `dartvel infra plan | provision | check <environment>`.
///
/// Everything a provision needs is checked before a host is reached: the ssh
/// client, the manifest, the secrets the environment requires, and the file
/// that pins each host's key. A provision that connects and then finds a
/// secret missing has already half-changed a host for nothing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/dartvel_config.dart';
import '../infra/ssh_host.dart';
import '../secrets/secrets_analysis.dart';
import '../utils/logger.dart';
import '../utils/toolchain.dart' show isCiEnvironment, isExecutableOnPath;

/// Builds the adapter for one host.
typedef DVInfraHostFactory = DVInfraHost Function(
  String host,
  DVInfraDesiredState desired,
);

class _Prepared {
  _Prepared(this.desired, this.hosts, this.secret);

  final DVInfraDesiredState desired;
  final List<DVInfraHost> hosts;
  final DVInfraSecretLookup secret;
}

/// The operations behind the command, apart from argument parsing.
class DVInfraCli {
  DVInfraCli({
    required this.root,
    Map<String, String>? environment,
    bool Function(String executable)? onPath,
    this.secretLookup,
    this.hostFactory,
    DVSshRun? sshRun,
    this.interactive,
    String? Function()? readLine,
    DateTime Function()? now,
    void Function(String line)? out,
    this.capabilities = const DVInfraBackendCapabilities(),
  })  : _environment = environment ?? Platform.environment,
        _onPath = onPath ?? isExecutableOnPath,
        _sshRun = sshRun ?? _processRun,
        _readLine = readLine ?? stdin.readLineSync,
        _now = now ?? (() => DateTime.now().toUtc()),
        _out = out ?? Logger.log;

  final String root;

  /// What the built backend honours. The generated backend honours none of
  /// the roles yet, so a manifest needing one is refused.
  final DVInfraBackendCapabilities capabilities;

  final Map<String, String> _environment;
  final bool Function(String executable) _onPath;

  /// Resolves secret values; DV.Secrets with the project's .env when null.
  final DVInfraSecretLookup? secretLookup;

  /// Builds each host's adapter; the SSH adapter when null.
  final DVInfraHostFactory? hostFactory;
  final DVSshRun _sshRun;

  /// Whether a destructive plan may be confirmed at a prompt; whether stdin
  /// is a terminal when null. Never in CI.
  final bool? interactive;
  final String? Function() _readLine;
  final DateTime Function() _now;
  final void Function(String line) _out;

  static Future<DVSshOutput> _processRun(
    String executable,
    List<String> arguments, {
    List<int>? stdin,
  }) async {
    final Process process = await Process.start(executable, arguments);
    final Future<String> out = process.stdout.transform(utf8.decoder).join();
    final Future<String> err = process.stderr.transform(utf8.decoder).join();
    if (stdin != null) process.stdin.add(stdin);
    await process.stdin.close();
    return DVSshOutput(await process.exitCode, await out, await err);
  }

  Future<_Prepared?> _prepare(String environment) async {
    // Tooling first, before any work: a plan that reads the manifest and then
    // cannot connect has told nobody anything.
    if (!_onPath('ssh')) {
      _out('dartvel infra needs an OpenSSH client (`ssh`) on PATH. It comes '
          'with the operating system rather than from Dartvel, so it is not '
          'installed for you:\n'
          '  Debian/Ubuntu: sudo apt install openssh-client\n'
          '  Fedora:        sudo dnf install openssh-clients\n'
          '  macOS:         included\n'
          '  Windows:       Settings > Optional features > OpenSSH Client');
      return null;
    }

    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      _out('No pubspec.yaml in $root.');
      return null;
    }
    final String text = pubspec.readAsStringSync();
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      _out('pubspec.yaml does not parse: ${e.message}');
      return null;
    }
    final Object? name = doc is Map ? doc['name'] : null;
    final Object? dartvel = doc is Map ? doc['dartvel'] : null;

    final Map<String, DVInfraManifest> manifests;
    try {
      manifests = DVInfraManifest.fromConfig(dartvel is Map ? dartvel['infra'] : null);
    } on FormatException catch (e) {
      _out(e.message);
      return null;
    }
    final DVInfraManifest? manifest = manifests[environment];
    if (manifest == null) {
      _out('dartvel.infra.$environment is not declared in pubspec.yaml'
          '${manifests.isEmpty ? '' : '; declared: ${manifests.keys.join(', ')}'}.');
      return null;
    }
    if (name is! String || !RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(name)) {
      _out('The pubspec name "$name" cannot name a service user and units.');
      return null;
    }

    int backendPort = 3000;
    try {
      backendPort = (await DartvelConfig.load(Directory(root))).backendPort;
    } on Object catch (e) {
      _out('Could not read the Dartvel configuration: $e');
      return null;
    }

    // Secrets: declared, resolved here, and required ones present, all
    // before a host is reached.
    final Map<String, DVSecretDeclaration> declared =
        dvParseSecretDeclarations(text);
    final DVInfraSecretLookup secret =
        secretLookup ?? _resolveSecrets(declared.keys);
    final Set<String> resolved = <String>{
      for (final String n in declared.keys)
        if (secret(n) != null) n,
    };
    final List<String> problems = dvValidateEnvironment(
      declared: declared,
      environment: environment,
      resolved: resolved,
    );
    if (problems.isNotEmpty) {
      _out('$environment is missing ${problems.length} required secret(s); '
          'no host was contacted:');
      for (final String problem in problems) {
        _out('  $problem');
      }
      return null;
    }
    final Set<String> delivered = <String>{
      for (final DVSecretDeclaration d in declared.values)
        if (d.scope == DVSecretScope.backend &&
            !d.name.startsWith('PUBLIC_') &&
            resolved.contains(d.name))
          d.name,
    };

    final DVInfraDesiredState desired = dvInfraDesiredState(
      manifest,
      appName: name,
      backendPort: backendPort,
      capabilities: capabilities,
      secretNames: delivered,
    );

    final String knownHostsPath = p.isAbsolute(manifest.ssh.knownHosts)
        ? manifest.ssh.knownHosts
        : p.join(root, manifest.ssh.knownHosts);
    final File knownHosts = File(knownHostsPath);
    if (!knownHosts.existsSync()) {
      final String first = manifest.hosts.first;
      _out('No known_hosts file at ${manifest.ssh.knownHosts}, so no host key '
          'is pinned and nothing connects. Pin each host:\n'
          '  ssh-keyscan -p ${manifest.ssh.port} $first >> ${manifest.ssh.knownHosts}\n'
          'then compare `ssh-keygen -lf ${manifest.ssh.knownHosts}` with the '
          'fingerprint the host shows on its own console before committing '
          'the file.');
      return null;
    }
    final String knownHostsText = knownHosts.readAsStringSync();

    final List<DVInfraHost> hosts = <DVInfraHost>[];
    for (final String host in manifest.hosts) {
      try {
        hosts.add(
          hostFactory?.call(host, desired) ??
              DVSshInfraHost(
                host: host,
                desired: desired,
                knownHostsPath: knownHostsPath,
                knownHostsText: knownHostsText,
                run: _sshRun,
              ),
        );
      } on DVSshHostNotPinned catch (e) {
        _out('$e');
        return null;
      }
    }
    return _Prepared(desired, hosts, secret);
  }

  /// Reads each declared secret once through DV.Secrets, with the project's
  /// .env, and puts DV.Secrets back as it was. The values stay in this
  /// process's memory for the length of the command.
  DVInfraSecretLookup _resolveSecrets(Iterable<String> names) {
    final DVSecretsState before = DVSecrets.captureState();
    final Map<String, String> values = <String, String>{};
    try {
      DVSecrets.useEnvFile(p.join(root, '.env'));
      for (final String n in names) {
        final String? v = const DVSecrets().maybeGet(n);
        if (v != null) values[n] = v;
      }
    } finally {
      DVSecrets.reset();
      DVSecrets.restoreState(before);
    }
    return (String n) => values[n];
  }

  void _printPlan(String environment, DVInfraPlan plan) {
    _out('$environment - ${plan.host}: '
        '${plan.isEmpty ? 'nothing to do' : '${plan.steps.length} step(s)'}');
    for (final DVInfraStep s in plan.steps) {
      _out('  ${s.action.name} ${s.id}  (${s.reason})'
          '${s.destructive ? '  [destructive]' : ''}');
    }
    for (final String n in plan.notes) {
      _out('  note: $n');
    }
    for (final String u in plan.unsupported) {
      _out('  cannot: $u');
    }
  }

  Future<List<DVInfraPlan>?> _observeAndPlan(_Prepared ready) async {
    final List<DVInfraPlan> plans = <DVInfraPlan>[];
    for (final DVInfraHost host in ready.hosts) {
      try {
        plans.add(dvInfraPlan(
          ready.desired,
          await host.observe(),
          secret: ready.secret,
        ));
      } on Object catch (e) {
        _out('${host.name} could not be observed: $e');
        return null;
      }
    }
    return plans;
  }

  /// `dartvel infra plan`. Exits 1 when the plan cannot be applied.
  Future<int> plan(String environment, {String? outFile}) async {
    final _Prepared? ready = await _prepare(environment);
    if (ready == null) return 1;
    final List<DVInfraPlan>? plans = await _observeAndPlan(ready);
    if (plans == null) return 1;
    for (final DVInfraPlan plan in plans) {
      _printPlan(environment, plan);
    }
    if (plans.any((DVInfraPlan p) => p.unsupported.isNotEmpty)) {
      _out('This plan cannot be applied; nothing was written.');
      return 1;
    }
    if (outFile != null) {
      File(outFile).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'environment': environment,
          'plans': <Object?>[
            for (final DVInfraPlan plan in plans) jsonDecode(plan.toJsonString()),
          ],
        },
      ));
      _out('Wrote the plan to $outFile. `dartvel infra provision $environment '
          '--plan $outFile` applies it only while it is still the plan.');
    }
    return 0;
  }

  /// `dartvel infra provision`. Exits 0 only when every host was applied and
  /// verified.
  Future<int> provision(
    String environment, {
    String? planFile,
    bool confirmDestructive = false,
  }) async {
    final _Prepared? ready = await _prepare(environment);
    if (ready == null) return 1;

    final List<DVInfraPlan> plans;
    if (planFile != null) {
      try {
        final Object? json = jsonDecode(File(planFile).readAsStringSync());
        final Object? list = json is Map ? json['plans'] : null;
        if (json is! Map || json['environment'] != environment || list is! List) {
          throw FormatException('$planFile is not a plan for $environment');
        }
        final Map<String, DVInfraPlan> byHost = <String, DVInfraPlan>{
          for (final Object? entry in list)
            if (DVInfraPlan.fromJsonString(jsonEncode(entry)) case final DVInfraPlan plan)
              plan.host: plan,
        };
        plans = <DVInfraPlan>[
          for (final DVInfraHost host in ready.hosts)
            byHost[host.name] ??
                (throw FormatException('$planFile has no plan for ${host.name}')),
        ];
      } on FormatException catch (e) {
        _out('${e.message}. Nothing was applied.');
        return 1;
      } on FileSystemException catch (e) {
        _out('Could not read $planFile: ${e.message}');
        return 1;
      }
    } else {
      final List<DVInfraPlan>? observed = await _observeAndPlan(ready);
      if (observed == null) return 1;
      plans = observed;
    }

    for (final DVInfraPlan plan in plans) {
      _printPlan(environment, plan);
    }
    if (plans.any((DVInfraPlan p) => p.unsupported.isNotEmpty)) {
      _out('The manifest declares what this provisioner cannot do; nothing '
          'was applied.');
      return 1;
    }

    final List<DVInfraStep> destructive = <DVInfraStep>[
      for (final DVInfraPlan plan in plans) ...plan.destructive,
    ];
    bool confirmed = confirmDestructive;
    if (destructive.isNotEmpty && !confirmed) {
      final String what = destructive.map((DVInfraStep s) => s.id).join(', ');
      final bool canAsk = (interactive ?? stdin.hasTerminal) &&
          !isCiEnvironment(_environment);
      if (!canAsk) {
        _out('The plan removes $what. Nothing was applied: pass '
            '--confirm-destructive to apply it unattended.');
        return 1;
      }
      _out('The plan removes $what. Type yes to apply it:');
      final String? answer = _readLine();
      if (answer?.trim() != 'yes') {
        _out('Not confirmed; nothing was applied.');
        return 1;
      }
      confirmed = true;
    }

    for (int i = 0; i < ready.hosts.length; i++) {
      final DVInfraApplyResult result = await dvApplyInfraPlan(
        approved: plans[i],
        desired: ready.desired,
        host: ready.hosts[i],
        secret: ready.secret,
        confirmDestructive: confirmed,
      );
      _out(result.message);
      if (!result.ok) {
        if (i + 1 < ready.hosts.length) {
          _out('The remaining ${ready.hosts.length - i - 1} host(s) were not '
              'touched.');
        }
        return 1;
      }
    }
    return 0;
  }

  /// `dartvel infra check`. Exits 1 when a host cannot be observed or a
  /// finding is an error.
  Future<int> check(String environment, {bool json = false}) async {
    final _Prepared? ready = await _prepare(environment);
    if (ready == null) return 1;
    bool failed = false;
    final List<Map<String, Object?>> report = <Map<String, Object?>>[];
    for (final DVInfraHost host in ready.hosts) {
      final DVInfraObservation observation;
      try {
        observation = await host.observe();
      } on Object catch (e) {
        failed = true;
        if (json) {
          report.add(<String, Object?>{'host': host.name, 'error': '$e'});
        } else {
          _out('${host.name} could not be checked: $e');
        }
        continue;
      }
      final List<DVInfraFinding> findings = dvInfraCheck(
        desired: ready.desired,
        observation: observation,
        secret: ready.secret,
        now: _now(),
      );
      if (findings.any((DVInfraFinding f) => f.level == 'error')) failed = true;
      if (json) {
        report.addAll(findings.map((DVInfraFinding f) => f.toJson()));
        continue;
      }
      if (findings.isEmpty) _out('${host.name}: no findings');
      for (final DVInfraFinding f in findings) {
        _out('$f');
      }
    }
    if (json) {
      _out(jsonEncode(report));
    } else {
      for (final String u in ready.desired.unsupported) {
        _out('note: the manifest cannot be provisioned as written: $u');
      }
    }
    return failed ? 1 : 0;
  }
}

class InfraCommand extends Command<void> {
  InfraCommand() {
    addSubcommand(_InfraSubcommand(
      'plan',
      'Show the steps that would converge each host on dartvel.infra.<env>.',
      (DVInfraCli cli, String env, ArgResults args) =>
          cli.plan(env, outFile: args['out'] as String?),
      (ArgParser parser) => parser.addOption('out',
          help: 'Write the plan to this file for `provision --plan`.'),
    ));
    addSubcommand(_InfraSubcommand(
      'provision',
      'Apply the plan to each host and verify the host matches afterwards.',
      (DVInfraCli cli, String env, ArgResults args) => cli.provision(
        env,
        planFile: args['plan'] as String?,
        confirmDestructive: args['confirm-destructive'] as bool,
      ),
      (ArgParser parser) => parser
        ..addOption('plan',
            help: 'Apply this plan file, and only while it is still the plan.')
        ..addFlag('confirm-destructive',
            negatable: false,
            help: 'Apply steps that remove units, files or credentials '
                'without asking.'),
    ));
    addSubcommand(_InfraSubcommand(
      'check',
      'Report drift, stopped services, failing certificate renewal and stale '
          'restores as DV-INFRA findings.',
      (DVInfraCli cli, String env, ArgResults args) =>
          cli.check(env, json: args['json'] as bool),
      (ArgParser parser) =>
          parser.addFlag('json', negatable: false, help: 'Print findings as JSON.'),
    ));
  }

  @override
  final String name = 'infra';

  @override
  final String description =
      'Provision and check the hosts declared under dartvel.infra.';
}

class _InfraSubcommand extends Command<void> {
  _InfraSubcommand(this.name, this.description, this._run, void Function(ArgParser) options) {
    options(argParser);
  }

  @override
  final String name;

  @override
  final String description;

  @override
  String get invocation => 'dartvel infra $name <environment>';

  final Future<int> Function(DVInfraCli cli, String environment, ArgResults args) _run;

  @override
  Future<void> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) usageException('Name one environment.');
    exitCode = await _run(DVInfraCli(root: Directory.current.path), rest.single, argResults!);
  }
}

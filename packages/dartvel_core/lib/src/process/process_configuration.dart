/// What a backend process is told to be: its role, its port, its queues.
///
/// One built backend runs as any of three processes, chosen when it starts
/// rather than when it is built, so a host runs the same binary under
/// different units:
///
///  * `web` serves the application over HTTP. It is what a process told
///    nothing is, and a process told nothing is a whole deployment by itself,
///    so it also ticks the `@DVBackendCron` schedules. A process *declared*
///    `web` is one of several, and leaves the schedules to the `cron` one.
///  * `worker` works `DVQueues` jobs from the queues in `DARTVEL_QUEUE` and
///    serves nothing.
///  * `cron` ticks the schedules and serves nothing.
///
/// Read from `DARTVEL_ROLE` or a `--role` argument, and the port from
/// `DARTVEL_PORT`. Every value is validated and a bad one refuses the start:
/// a port that fell back to the generated one is a second instance crash
/// looping on a taken port, and a misspelt role that became `web` is a worker
/// that never works a job.
library;

/// The process a backend runs as.
enum DVProcessRole { web, worker, cron }

/// A process setting that cannot be honoured. The process must not start.
final class DVProcessConfigurationError implements Exception {
  const DVProcessConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The resolved settings for one backend process.
final class DVProcessConfiguration {
  const DVProcessConfiguration({
    required this.role,
    required this.roleDeclared,
    required this.port,
    this.queues = const <String>[],
  });

  final DVProcessRole role;

  /// Whether `DARTVEL_ROLE` or `--role` said so, rather than the default.
  final bool roleDeclared;

  /// The port a web process binds: `DARTVEL_PORT`, else the generated one.
  final int port;

  /// The queues a worker works, in order. Empty for any other role.
  final List<String> queues;

  /// Only the web role answers HTTP.
  bool get servesHttp => role == DVProcessRole.web;

  /// Whether this process ticks the backend schedules.
  ///
  /// A cron process does. So does a web process nobody gave a role, because
  /// it is the only process there is. A declared web process does not: a
  /// deployment that names roles runs its schedules in the cron process, and
  /// every web instance ticking them would fire each once per instance.
  bool get ticksSchedules =>
      role == DVProcessRole.cron ||
      (role == DVProcessRole.web && !roleDeclared);

  static final RegExp _digits = RegExp(r'^[0-9]{1,5}$');
  static final RegExp _queueName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]*$');

  /// Resolves a process from [environment] and [arguments].
  ///
  /// [generatedPort] is `dartvel.server.port` as it was when the backend was
  /// generated. Throws [DVProcessConfigurationError] for anything that cannot
  /// be honoured.
  static DVProcessConfiguration resolve({
    required Map<String, String> environment,
    List<String> arguments = const <String>[],
    required int generatedPort,
  }) {
    final String? fromArguments = _roleArgument(arguments);
    final String? fromEnvironment = environment['DARTVEL_ROLE'];
    if (fromArguments != null &&
        fromEnvironment != null &&
        fromArguments != fromEnvironment) {
      throw DVProcessConfigurationError(
        '--role=$fromArguments and DARTVEL_ROLE=$fromEnvironment disagree. '
        'Say which process this is once.',
      );
    }
    final String? declared = fromArguments ?? fromEnvironment;
    final DVProcessRole role;
    if (declared == null) {
      role = DVProcessRole.web;
    } else {
      final DVProcessRole? named = DVProcessRole.values
          .where((DVProcessRole r) => r.name == declared)
          .firstOrNull;
      if (named == null) {
        throw DVProcessConfigurationError(
          'DARTVEL_ROLE is "$declared", which is not a role. The roles are '
          '${DVProcessRole.values.map((DVProcessRole r) => r.name).join(', ')}.',
        );
      }
      role = named;
    }

    int port = generatedPort;
    final String? rawPort = environment['DARTVEL_PORT'];
    if (rawPort != null) {
      final int? parsed = _digits.hasMatch(rawPort) ? int.parse(rawPort) : null;
      if (parsed == null || parsed < 1 || parsed > 65535) {
        throw DVProcessConfigurationError(
          'DARTVEL_PORT is "$rawPort", which is not a port (a whole number from '
          '1 to 65535). The backend does not start on another port instead.',
        );
      }
      port = parsed;
    }

    final String? rawQueues = environment['DARTVEL_QUEUE'];
    List<String> queues = const <String>[];
    if (rawQueues != null) {
      if (role != DVProcessRole.worker) {
        throw DVProcessConfigurationError(
          'DARTVEL_QUEUE is set to "$rawQueues" for a ${role.name} process, '
          'which works no queue. A process meant to work it needs '
          'DARTVEL_ROLE=worker.',
        );
      }
      final List<String> named = rawQueues.split(',');
      if (named.any((String q) => !_queueName.hasMatch(q))) {
        throw DVProcessConfigurationError(
          'DARTVEL_QUEUE is "$rawQueues". It is a comma-separated list of '
          'queue names, with no spaces or empty entries.',
        );
      }
      queues = List<String>.unmodifiable(named);
    } else if (role == DVProcessRole.worker) {
      queues = const <String>['default'];
    }

    return DVProcessConfiguration(
      role: role,
      roleDeclared: declared != null,
      port: port,
      queues: queues,
    );
  }

  static String? _roleArgument(List<String> arguments) {
    String? role;
    for (int i = 0; i < arguments.length; i++) {
      final String argument = arguments[i];
      String? value;
      if (argument.startsWith('--role=')) {
        value = argument.substring('--role='.length);
      } else if (argument == '--role') {
        value = i + 1 < arguments.length ? arguments[++i] : null;
        if (value == null || value.startsWith('--')) {
          throw const DVProcessConfigurationError(
            '--role needs a value: --role=web, --role=worker or --role=cron.',
          );
        }
      } else {
        continue;
      }
      if (role != null && role != value) {
        throw DVProcessConfigurationError(
          '--role is given twice, as $role and $value.',
        );
      }
      role = value;
    }
    return role;
  }
}

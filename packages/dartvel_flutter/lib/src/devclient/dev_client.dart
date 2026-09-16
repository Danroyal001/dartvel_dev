/// Loading bundles into a dev-client shell, and the shell's dev menu.
///
/// A shell is paired with one `dartvel dev` server by a link carrying the
/// server's key and a fetch token. Loading fetches the current bundle for the
/// shell's target, opens it with the paired key, checks it is for the paired
/// branch and not older than the last one, compares what it needs against the
/// binding manifest the shell was built from, and only then applies it through
/// the same installer OTA page bundles use.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show
        DVDevClientManifest,
        DVDevClientPairing,
        DVDevClientRefusal,
        DVHttpRequest,
        DVHttpResponse,
        DVSignedBundle,
        DVSignedBundleException,
        dvDevClientCompatibility,
        dvDevClientShellMarker,
        dvDevClientUnreachable,
        dvSendHttpRequest;
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart'
    show
        DVDeepLinks,
        DVNativeBridge,
        DVPageBundle,
        DVPageBundleInstaller,
        DVStudioPageRoute;

/// What a [DVDevClient.load] did.
enum DVDevClientOutcome {
  /// The bundle was applied and its pages are live.
  applied,

  /// This exact bundle is the one already applied.
  alreadyApplied,

  /// The server could not be reached (`DV-DEVCLIENT-001`).
  unreachable,

  /// The server was reached and refused this device's token
  /// (`DV-DEVCLIENT-001`).
  unpaired,

  /// The bundle was not trusted: unsigned, sealed by another key, for another
  /// branch, older than one already loaded, or malformed.
  rejected,

  /// The bundle needs a binding this shell was not built with
  /// (`DV-DEVCLIENT-002`).
  incompatible,
}

class DVDevClientLoad {
  const DVDevClientLoad(
    this.outcome,
    this.message, {
    this.code,
    this.version,
    this.routes = const <String>[],
    this.missing = const <String>[],
  });

  final DVDevClientOutcome outcome;
  final String message;

  /// The diagnostic code, where the outcome has one.
  final String? code;

  final String? version;

  /// Routes the applied bundle carries pages for.
  final List<String> routes;

  /// Bindings the bundle needs and the shell lacks.
  final List<String> missing;

  bool get loaded =>
      outcome == DVDevClientOutcome.applied ||
      outcome == DVDevClientOutcome.alreadyApplied;
}

/// Loads bundles from the server [pairing] names into a shell built from
/// [shell].
class DVDevClient {
  DVDevClient({
    required this.pairing,
    required this.shell,
    this.installer = const DVPageBundleInstaller(),
    this.timeout = const Duration(seconds: 10),
  });

  final DVDevClientPairing pairing;
  final DVDevClientManifest shell;
  final DVPageBundleInstaller installer;
  final Duration timeout;

  /// What loading has done, newest last, for the dev menu's log view.
  final List<String> log = <String>[];

  int? _lastSequence;

  Future<DVDevClientLoad> load() async {
    final DVDevClientLoad result = await _load();
    log.add(<String>[
      if (result.code != null) '${result.code}:',
      result.outcome.name,
      '-',
      result.message,
    ].join(' '));
    return result;
  }

  Future<DVDevClientLoad> _load() async {
    final Uri source = pairing.bundleUri(shell.target);
    final String where = '${source.host}:${source.port}';

    final DVHttpResponse response;
    try {
      response = await dvSendHttpRequest(DVHttpRequest(
        url: source,
        method: 'GET',
        headers: <String, String>{'authorization': 'Bearer ${pairing.token}'},
      )).timeout(timeout);
    } on Object catch (error) {
      return DVDevClientLoad(
        DVDevClientOutcome.unreachable,
        'Could not reach the dev server at $where: $error',
        code: dvDevClientUnreachable,
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return DVDevClientLoad(
        DVDevClientOutcome.unpaired,
        'The dev server at $where refused this device. Its pairing ends when '
        '`dartvel dev` restarts; scan the new link.',
        code: dvDevClientUnreachable,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DVDevClientLoad(
        DVDevClientOutcome.unreachable,
        'The dev server at $where answered HTTP ${response.statusCode}.',
        code: dvDevClientUnreachable,
      );
    }

    final DVSignedBundle opened;
    try {
      opened = DVSignedBundle.open(
        response.body,
        publicKey: pairing.publicKey,
        requireContentVersion: true,
      );
    } on DVSignedBundleException catch (error) {
      return DVDevClientLoad(DVDevClientOutcome.rejected, error.message);
    }

    if (opened.channel != pairing.branch) {
      return DVDevClientLoad(
        DVDevClientOutcome.rejected,
        'The server is serving ${opened.channel ?? 'no branch'}, and this '
        'device was paired for ${pairing.branch}.',
      );
    }
    final int? sequence = opened.sequence;
    if (sequence == null) {
      return const DVDevClientLoad(
        DVDevClientOutcome.rejected,
        'The bundle carries no sequence, so a replayed older bundle could not '
        'be told from a new one.',
      );
    }
    final int? last = _lastSequence;
    if (last != null && sequence < last) {
      return DVDevClientLoad(
        DVDevClientOutcome.rejected,
        'The bundle is older ($sequence) than the one already loaded ($last).',
      );
    }
    final DVDevClientManifest? requires = opened.requires;
    if (requires == null) {
      return const DVDevClientLoad(
        DVDevClientOutcome.rejected,
        'The bundle does not say which bindings it needs, so it cannot be '
        'checked against this shell.',
      );
    }
    final DVDevClientRefusal? refusal =
        dvDevClientCompatibility(shell: shell, bundle: requires);
    if (refusal != null) {
      return DVDevClientLoad(
        DVDevClientOutcome.incompatible,
        refusal.message,
        code: refusal.code,
        missing: refusal.missing,
      );
    }

    final DVPageBundle bundle;
    try {
      bundle = DVPageBundle.fromJson(opened.bundle);
    } on Object catch (error) {
      return DVDevClientLoad(
        DVDevClientOutcome.rejected,
        'The bundle is signed but its pages do not decode: $error',
      );
    }
    final List<String> routes = <String>[
      for (final page in bundle.pages) page.route,
    ];

    final List<String> applied = await installer.appliedVersions();
    _lastSequence = sequence;
    if (applied.isNotEmpty && applied.last == bundle.version) {
      return DVDevClientLoad(
        DVDevClientOutcome.alreadyApplied,
        '${bundle.version} is already applied',
        version: bundle.version,
        routes: routes,
      );
    }
    // Applied before but not last: the content went back to an earlier
    // state. The installer is idempotent by version and would take this for
    // a redelivery, leaving the later content on screen.
    if (applied.contains(bundle.version)) {
      await installer.forget(bundle.version);
    }
    await installer.apply(bundle);
    return DVDevClientLoad(
      DVDevClientOutcome.applied,
      'applied ${bundle.version} (${routes.length} pages)',
      version: bundle.version,
      routes: routes,
    );
  }
}

/// The dev menu: reload, the capability report for this device, and the log.
///
/// The capability report reads what is registered on the device now rather
/// than the manifest the shell was built from: the two can differ, and the
/// device in somebody's hand is the one being asked about.
class DVDevMenu extends StatelessWidget {
  const DVDevMenu({
    super.key,
    required this.shell,
    required this.branch,
    required this.log,
    required this.onReload,
  });

  final DVDevClientManifest shell;
  final String? branch;
  final List<String> log;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final List<String> registered = DVNativeBridge.registered;
    return Scaffold(
      appBar: AppBar(title: const Text('Dev menu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Branch: ${branch ?? 'not paired'} · ${shell.target}'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => unawaited(onReload()),
              child: const Text('Reload'),
            ),
          ),
          const _Heading('Built with'),
          for (final String binding in shell.normalizedBindings) Text(binding),
          const _Heading('Registered on this device'),
          if (registered.isEmpty) const Text('No native bindings registered.'),
          for (final String binding in registered) Text(binding),
          const _Heading('Log'),
          if (log.isEmpty) const Text('Nothing loaded yet.'),
          for (final String line in log.reversed) Text(line),
          // Referenced here so the compiled shell carries it and `dartvel
          // publish` can recognise the artifact; see dvDevClientShellMarker.
          const _Heading('Shell'),
          const Text(dvDevClientShellMarker),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// The application a dev-client build runs: pairing, loading, the pages the
/// bundle carries, and the dev menu.
///
/// [manifest] is the binding manifest the build recorded; the generated
/// entrypoint passes it as a constant. A pairing link arrives as the launch
/// deep link, as a later deep link, or pasted by hand.
class DVDevClientShell extends StatefulWidget {
  const DVDevClientShell({
    super.key,
    required this.manifest,
    this.pollInterval = const Duration(seconds: 2),
  });

  final DVDevClientManifest manifest;

  /// How often a paired shell asks for the next bundle.
  final Duration pollInterval;

  @override
  State<DVDevClientShell> createState() => _DVDevClientShellState();
}

class _DVDevClientShellState extends State<DVDevClientShell> {
  DVDevClient? _client;
  DVDevClientLoad? _last;
  String? _route;
  String? _pairingError;
  Timer? _poll;
  StreamSubscription<String>? _links;
  final TextEditingController _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    _links = const DVDeepLinks().getLinkStream().listen(_pair);
    unawaited(_initialLink());
  }

  Future<void> _initialLink() async {
    try {
      final String? link = await const DVDeepLinks().getInitialLink();
      if (link != null && mounted) _pair(link);
    } on Object {
      // No deep-link binding on this target; the link can still be pasted.
    }
  }

  void _pair(String link) {
    final Uri? uri = Uri.tryParse(link.trim());
    try {
      if (uri == null) throw const FormatException('Not a link.');
      final DVDevClientPairing pairing = DVDevClientPairing.parse(uri);
      _poll?.cancel();
      setState(() {
        _pairingError = null;
        _client = DVDevClient(pairing: pairing, shell: widget.manifest);
      });
      unawaited(_reload());
      _poll = Timer.periodic(widget.pollInterval, (_) => unawaited(_reload()));
    } on FormatException catch (error) {
      setState(() => _pairingError = error.message);
    }
  }

  Future<void> _reload() async {
    final DVDevClient? client = _client;
    if (client == null) return;
    final DVDevClientLoad load = await client.load();
    if (!mounted) return;
    setState(() {
      _last = load;
      if (load.loaded && (_route == null || !load.routes.contains(_route))) {
        _route = load.routes.isEmpty ? null : load.routes.first;
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_links?.cancel());
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (BuildContext context) {
        final DVDevClient? client = _client;
        final DVDevClientLoad? last = _last;
        final String? route = _route;
        return Scaffold(
          appBar: AppBar(
            title: Text(
                client == null ? 'Dartvel dev client' : client.pairing.branch),
            actions: <Widget>[
              IconButton(
                tooltip: 'Dev menu',
                icon: const Icon(Icons.developer_mode),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DVDevMenu(
                      shell: widget.manifest,
                      branch: client?.pairing.branch,
                      log: client?.log ?? const <String>[],
                      onReload: _reload,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: client == null
              ? _PairingForm(
                  controller: _link,
                  error: _pairingError,
                  onSubmit: _pair,
                )
              : Column(
                  children: <Widget>[
                    if (last != null && !last.loaded)
                      MaterialBanner(
                        content: Text(last.code == null
                            ? last.message
                            : '${last.code}: ${last.message}'),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => unawaited(_reload()),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    if (last != null && last.routes.length > 1)
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          for (final String r in last.routes)
                            ChoiceChip(
                              label: Text(r),
                              selected: r == route,
                              onSelected: (_) => setState(() => _route = r),
                            ),
                        ],
                      ),
                    Expanded(
                      child: route == null
                          ? const Center(child: Text('Waiting for a bundle.'))
                          : DVStudioPageRoute(route),
                    ),
                  ],
                ),
        );
      }),
    );
  }
}

class _PairingForm extends StatelessWidget {
  const _PairingForm({
    required this.controller,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? error;
  final void Function(String link) onSubmit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Scan the QR code `dartvel dev` prints, '
                'or paste its dartvel-dev:// link.'),
            TextField(
              controller: controller,
              decoration: InputDecoration(errorText: error),
              onSubmitted: onSubmit,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => onSubmit(controller.text),
              child: const Text('Pair'),
            ),
          ],
        ),
      );
}

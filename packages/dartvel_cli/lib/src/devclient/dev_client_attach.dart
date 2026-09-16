/// `flutter attach` for a device paired with `dartvel dev --dev-client`.
///
/// Flutter's own attach does the work -- the incremental compiler, the DevFS
/// upload, the reload and restart RPCs -- pointed at the loopback URL the
/// tunnel gives and driven over its `--machine` protocol, so a save reloads
/// the phone the same way `r` reloads a local `flutter run`.
library dartvel_cli.devclient.dev_client_attach;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'android_dev_client.dart';

typedef DVAttachProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// The `flutter` arguments that attach to a device at [debugUrl].
///
/// `-d flutter-tester` because attach needs a device, and there is no adb
/// connection to find the phone by. With `--debug-url` the device is used
/// only for its port forwarder, and flutter-tester's forwards nothing, which
/// is right for a URL that is already on this machine. Kernel is the same for
/// every platform, and the plugin registrant is generated for all of them at
/// once, so nothing Android-specific is lost in the compile.
List<String> dvDevClientAttachArguments(Uri debugUrl) => <String>[
  '--show-test-device',
  'attach',
  '--machine',
  '-d',
  'flutter-tester',
  '--debug-url',
  debugUrl.toString(),
  '-t',
  dvDevelopmentEntrypoint,
];

class DVDevClientAttach {
  DVDevClientAttach._(this._process, this._log);

  final Process _process;
  final void Function(String line) _log;

  String? _appId;
  int _nextId = 1;
  final Map<int, Completer<bool>> _pending = <int, Completer<bool>>{};
  bool _synced = false;
  bool _ended = false;

  /// Whether the device has been brought up to date with the sources since
  /// it attached.
  bool get synced => _synced;

  Future<int> get exitCode => _process.exitCode;

  static Future<DVDevClientAttach> start({
    required Uri debugUrl,
    required String root,
    required void Function(String line) log,
    DVAttachProcessStarter? startProcess,
  }) async {
    final DVAttachProcessStarter starter =
        startProcess ??
        (String executable, List<String> arguments, {String? workingDirectory}) =>
            Process.start(
              executable,
              arguments,
              workingDirectory: workingDirectory,
              runInShell: true,
            );
    final Process process = await starter(
      'flutter',
      dvDevClientAttachArguments(debugUrl),
      workingDirectory: root,
    );
    final DVDevClientAttach attach = DVDevClientAttach._(process, log);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(attach._line);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log);
    unawaited(
      process.exitCode.then((int code) {
        attach._ended = true;
        for (final Completer<bool> pending in attach._pending.values) {
          if (!pending.isCompleted) pending.complete(false);
        }
        attach._pending.clear();
      }),
    );
    return attach;
  }

  /// A hot reload, or with [full] a hot restart. True when Flutter reports
  /// it applied.
  Future<bool> reload({bool full = false, String reason = 'dartvel dev: save'}) {
    final String? appId = _appId;
    if (appId == null || _ended) return Future<bool>.value(false);
    final int id = _nextId++;
    final Completer<bool> done = Completer<bool>();
    _pending[id] = done;
    _process.stdin.writeln(
      jsonEncode(<Object>[
        <String, Object?>{
          'id': id,
          'method': 'app.restart',
          'params': <String, Object?>{
            'appId': appId,
            'fullRestart': full,
            'reason': reason,
          },
        },
      ]),
    );
    return done.future;
  }

  /// Detaches, leaving the application running on the device.
  Future<void> stop() async {
    if (_ended) return;
    _process.kill();
    await _process.exitCode;
  }

  void _line(String line) {
    final String trimmed = line.trim();
    if (!trimmed.startsWith('[')) {
      if (trimmed.isNotEmpty) _log(trimmed);
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      _log(trimmed);
      return;
    }
    if (decoded is! List) return;
    for (final Object? message in decoded) {
      if (message is Map) _message(message.cast<String, Object?>());
    }
  }

  void _message(Map<String, Object?> message) {
    final Object? id = message['id'];
    if (id is int && _pending.containsKey(id)) {
      final Completer<bool> done = _pending.remove(id)!;
      final Object? result = message['result'];
      final bool ok = result is Map && result['code'] == 0;
      final String text = result is Map
          ? '${result['message'] ?? ''}'
          : '${message['error'] ?? 'no answer'}';
      if (text.isNotEmpty) _log(ok ? text : 'reload failed: $text');
      done.complete(ok);
      return;
    }
    final Object? params = message['params'];
    final Map<String, Object?> p = params is Map
        ? params.cast<String, Object?>()
        : const <String, Object?>{};
    switch (message['event']) {
      case 'app.start':
        _appId = p['appId'] as String?;
      case 'app.started':
        _appId ??= p['appId'] as String?;
        _log('attached; bringing the device up to date with a hot restart');
        unawaited(
          reload(full: true, reason: 'dartvel dev: paired').then((bool ok) {
            _synced = ok;
            _log(
              ok
                  ? 'the device is up to date with the sources'
                  : 'the device could not be brought up to date',
            );
          }),
        );
      case 'app.log':
        final Object? text = p['log'];
        if (text is String) _log(text.trimRight());
      case 'app.stop':
        _log('the application on the device stopped');
      case 'daemon.logMessage':
        final Object? text = p['message'];
        if (text is String) _log(text);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';

/// `dartvel capture firefox` — photograph a page in Firefox, once it has drawn.
///
/// `firefox --screenshot` fires on the load event, which is before a Flutter
/// application has started: the capture is a blank white page and looks
/// exactly like a build that failed. This drives the browser instead, waits
/// for the page to lay out, and reports the page's own text so a capture of
/// the wrong page can be told from a capture of the right one.
///
/// Marionette is Firefox's own automation protocol, built into the browser, so
/// this needs no driver binary. Messages are `<byte-length>:<json>` and each is
/// `[0, id, "Command", params]`.
class FirefoxCaptureCommand extends Command<void> {
  @override
  final String name = 'firefox';

  @override
  final String description =
      'Photograph a page in Firefox after it has drawn.';

  @override
  String get invocation =>
      'dartvel capture firefox <url> <output.png> --profile <dir>';

  FirefoxCaptureCommand() {
    argParser
      ..addOption('firefox',
          defaultsTo: 'firefox', help: 'The Firefox binary to drive.')
      ..addOption('profile', help: 'A prepared profile directory.')
      ..addOption('settle',
          defaultsTo: '40',
          help: 'Seconds to wait for the page to lay out before giving up.')
      ..addOption('width', defaultsTo: '1280')
      ..addOption('height', defaultsTo: '900');
  }

  @override
  Future<void> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length < 2) {
      Logger.log('❌ Give a URL and an output path.');
      Logger.log('   $invocation');
      exit(64);
    }
    final String url = rest[0];
    final String output = rest[1];
    final String? profile = argResults!['profile'] as String?;
    final int settle = int.tryParse(argResults!['settle'] as String) ?? 40;

    final Process browser = await Process.start(
      argResults!['firefox'] as String,
      <String>[
        if (profile != null) ...<String>['--profile', profile],
        '--headless',
        '--marionette',
        // Marionette refuses the chrome context without this, and the chrome
        // context is the only way to open a moz-extension:// URL. Firefox
        // says so itself when it is missing.
        '-remote-allow-system-access',
        '--window-size=${argResults!['width']},${argResults!['height']}',
        'about:blank',
      ],
      mode: ProcessStartMode.detachedWithStdio,
    );

    // Kept, not discarded: with devtools.console.stdout.content set on the
    // profile, the page's own console lands here, and that is the only place
    // a Flutter start-up error appears. The DOM looks the same either way.
    final File console = File('$output.console.log');
    console.parent.createSync(recursive: true);
    final IOSink consoleSink = console.openWrite();
    unawaited(browser.stdout.forEach(consoleSink.add));
    unawaited(browser.stderr.forEach(consoleSink.add));

    _Marionette? session;
    try {
      session = await _Marionette.connect();
      await session.send('WebDriver:NewSession', <String, Object?>{
        'capabilities': <String, Object?>{},
      });

      final Set<String> before = await session.handles();

      // moz-extension:// is privileged and Marionette refuses to navigate to
      // one from content: "Navigation to ... is not allowed in this context".
      // Opening it from the chrome context with the system principal is what
      // typing it in the address bar does.
      await session.send('Marionette:SetContext', <String, Object?>{
        'value': 'chrome',
      });
      await session.send('WebDriver:ExecuteScript', <String, Object?>{
        'script': 'const [target] = arguments;'
            'gBrowser.selectedTab = gBrowser.addTab(target, {'
            '  triggeringPrincipal:'
            '    Services.scriptSecurityManager.getSystemPrincipal(),'
            '});',
        'args': <Object?>[url],
      });
      await session.send('Marionette:SetContext', <String, Object?>{
        'value': 'content',
      });

      await session.switchToNewWindow(before);

      // Polled rather than slept: a page that is ready early should not cost
      // the whole budget, and one that never draws has to be reported as that
      // rather than photographed blank.
      final bool drawn = await session.waitForBody(settle);

      // A moment more for the first frame after layout settles.
      await Future<void>.delayed(const Duration(seconds: 2));

      final String? text = await session.evaluate(
        "return (document.body ? document.body.innerText : '').slice(0, 300);",
      );
      Logger.log('   page text: ${text ?? ''}');

      if (!drawn) {
        // What the page thinks happened. A picture of nothing is the same
        // picture whether the script was blocked, the bundle 404'd, or the
        // application threw.
        final String? state = await session.evaluate(
          'return JSON.stringify({'
          '  title: document.title,'
          '  readyState: document.readyState,'
          "  scripts: Array.from(document.querySelectorAll('script'))"
          '    .map(s => s.src || \'(inline)\'),'
          '  flutterLoader: typeof window._flutter'
          '});',
        );
        Logger.log('   page state: ${state ?? ''}');
      }

      final String? shot = await session.evaluate(null,
          command: 'WebDriver:TakeScreenshot',
          params: <String, Object?>{'full': true});
      if (shot == null) {
        Logger.log('❌ Firefox returned no image.');
        exit(1);
      }
      File(output)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(shot));
      Logger.log('   wrote $output (body laid out: $drawn)');

      if (!drawn) {
        Logger.log('❌ The page never laid out a body taller than 100px.');
        exit(1);
      }
    } finally {
      await session?.close();
      browser.kill(ProcessSignal.sigterm);
      await consoleSink.flush();
      await consoleSink.close();
    }
  }
}

/// The little of Marionette this needs.
class _Marionette {
  _Marionette._(this._socket, this._incoming);

  final Socket _socket;
  final StreamQueue<List<int>> _incoming;
  final List<int> _buffer = <int>[];
  int _id = 0;

  static Future<_Marionette> connect({
    String host = '127.0.0.1',
    int port = 2828,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    Object? last;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final Socket socket = await Socket.connect(host, port);
        final _Marionette session =
            _Marionette._(socket, StreamQueue<List<int>>(socket));
        await session._read(); // the handshake it sends unprompted
        return session;
      } on SocketException catch (error) {
        // Firefox has not opened the port yet, which is the normal case for
        // the first second or two.
        last = error;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('Marionette never accepted a connection: $last');
  }

  /// One `<length>:<json>` message.
  Future<Object?> _read() async {
    while (true) {
      final int colon = _buffer.indexOf(0x3A); // ':'
      if (colon > 0) {
        final int size =
            int.parse(utf8.decode(_buffer.sublist(0, colon)));
        if (_buffer.length >= colon + 1 + size) {
          final String body =
              utf8.decode(_buffer.sublist(colon + 1, colon + 1 + size));
          _buffer.removeRange(0, colon + 1 + size);
          return jsonDecode(body);
        }
      }
      _buffer.addAll(await _incoming.next);
    }
  }

  Future<Object?> send(String command, Map<String, Object?> params) async {
    _id++;
    final String body = jsonEncode(<Object?>[0, _id, command, params]);
    final List<int> bytes = utf8.encode(body);
    _socket.add(<int>[...utf8.encode('${bytes.length}:'), ...bytes]);

    final Object? message = await _read();
    // [1, id, error, result]
    if (message is List && message.length > 2 && message[2] != null) {
      throw StateError('$command failed: ${message[2]}');
    }
    return message is List && message.length > 3 ? message[3] : null;
  }

  Future<Set<String>> handles() async {
    final Object? result = await send('WebDriver:GetWindowHandles', const {});
    return <String>{
      if (result is List) ...result.map((Object? h) => '$h'),
    };
  }

  /// Move to whichever tab appeared, rather than assuming a handle.
  Future<void> switchToNewWindow(Set<String> before) async {
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final Set<String> now = await handles();
      final Set<String> fresh = now.difference(before);
      if (fresh.isNotEmpty) {
        await send('WebDriver:SwitchToWindow',
            <String, Object?>{'handle': fresh.first});
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('the page never opened a tab');
  }

  Future<bool> waitForBody(int seconds) async {
    final DateTime deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final String? height = await evaluate(
        'return document.body ? '
        'String(document.body.getBoundingClientRect().height) : "0";',
      );
      if ((double.tryParse(height ?? '0') ?? 0) > 100) return true;
    }
    return false;
  }

  /// Run a script and return its value, or issue [command] directly.
  Future<String?> evaluate(
    String? script, {
    String command = 'WebDriver:ExecuteScript',
    Map<String, Object?>? params,
  }) async {
    final Object? result = await send(
      command,
      params ?? <String, Object?>{'script': script, 'args': <Object?>[]},
    );
    if (result is Map && result['value'] != null) return '${result['value']}';
    return null;
  }

  Future<void> close() async {
    await _incoming.cancel(immediate: true);
    await _socket.close();
  }
}

/// A queue over a stream, so a message can be read a chunk at a time.
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _subscription = stream.listen(
      (T event) {
        if (_waiting.isNotEmpty) {
          _waiting.removeAt(0).complete(event);
        } else {
          _ready.add(event);
        }
      },
      onError: (Object error) {
        for (final Completer<T> completer in _waiting) {
          completer.completeError(error);
        }
        _waiting.clear();
      },
    );
  }

  late final StreamSubscription<T> _subscription;
  final List<T> _ready = <T>[];
  final List<Completer<T>> _waiting = <Completer<T>>[];

  Future<T> get next {
    if (_ready.isNotEmpty) return Future<T>.value(_ready.removeAt(0));
    final Completer<T> completer = Completer<T>();
    _waiting.add(completer);
    return completer.future;
  }

  Future<void> cancel({bool immediate = false}) => _subscription.cancel();
}

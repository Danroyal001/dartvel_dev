// How `dartvel dev` drives `flutter attach` for a paired device.
//
// Flutter's own attach, pointed at the loopback URL the tunnel gives, and
// driven over its --machine protocol. The device is attached as the hidden
// flutter-tester device because there is no adb connection to find it by:
// with --debug-url, attach needs a device only to pick a port forwarder, and
// flutter-tester's forwards nothing, which is right for a URL that is already
// local. Kernel is platform-independent, so the compile is the same.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_cli/src/devclient/dev_client_attach.dart';
import 'package:test/test.dart';

class FakeAttachProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  late final IOSink _stdin = IOSink(_StdinConsumer(this));

  void emit(Object message) =>
      _stdout.add(utf8.encode('${jsonEncode(<Object>[message])}\n'));

  void say(String line) => _stdout.add(utf8.encode('$line\n'));

  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  IOSink get stdin => _stdin;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }
}

class _StdinConsumer implements StreamConsumer<List<int>> {
  _StdinConsumer(this.process);
  final FakeAttachProcess process;
  final StringBuffer _buffer = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      _buffer.write(utf8.decode(chunk));
      final String text = _buffer.toString();
      final int end = text.lastIndexOf('\n');
      if (end < 0) continue;
      for (final String line in text.substring(0, end).split('\n')) {
        if (line.trim().isEmpty) continue;
        final List<Object?> messages = jsonDecode(line) as List<Object?>;
        for (final Object? message in messages) {
          process.sent.add((message! as Map<Object?, Object?>).cast());
        }
      }
      _buffer
        ..clear()
        ..write(text.substring(end + 1));
    }
  }

  @override
  Future<void> close() async {}
}

void main() {
  final Uri debugUrl = Uri.parse('http://127.0.0.1:40123/Q52L-EEB5A0=/');

  test('attach is Flutter\'s, at the tunnel URL, with the development '
      'entrypoint', () {
    final List<String> arguments = dvDevClientAttachArguments(debugUrl);
    expect(arguments.first, '--show-test-device');
    expect(arguments, contains('attach'));
    expect(arguments, contains('--machine'));
    expect(arguments, containsAllInOrder(<String>['-d', 'flutter-tester']));
    expect(
      arguments,
      containsAllInOrder(<String>['--debug-url', debugUrl.toString()]),
    );
    // A hot restart runs the entrypoint attach was given, and only this one
    // starts the tunnel again.
    expect(
      arguments,
      containsAllInOrder(<String>['-t', dvDevelopmentEntrypoint]),
    );
  });

  group('a session', () {
    late FakeAttachProcess process;
    late List<String> started;
    late List<String> log;
    late DVDevClientAttach attach;

    setUp(() async {
      process = FakeAttachProcess();
      started = <String>[];
      log = <String>[];
      attach = await DVDevClientAttach.start(
        debugUrl: debugUrl,
        root: '/project',
        log: log.add,
        startProcess:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
            }) async {
              started.add('$executable ${arguments.join(' ')} @ $workingDirectory');
              return process;
            },
      );
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('runs flutter attach in the project', () {
      expect(started.single, startsWith('flutter --show-test-device attach'));
      expect(started.single, endsWith('@ /project'));
    });

    test('brings the device up to date with a hot restart once attached',
        () async {
      // The build on the phone is whatever was built; the sources are what
      // is on disk now. Attach alone uploads nothing, so edits made between
      // the build and the pairing would not be seen until a restart.
      process.emit(<String, Object?>{
        'event': 'app.start',
        'params': <String, Object?>{'appId': 'app-1'},
      });
      await settle();
      expect(process.sent, isEmpty);

      process.emit(<String, Object?>{
        'event': 'app.started',
        'params': <String, Object?>{'appId': 'app-1'},
      });
      await settle();
      expect(process.sent, hasLength(1));
      expect(process.sent.single['method'], 'app.restart');
      expect(process.sent.single['params'], <String, Object?>{
        'appId': 'app-1',
        'fullRestart': true,
        'reason': 'dartvel dev: paired',
      });

      process.emit(<String, Object?>{
        'id': process.sent.single['id'],
        'result': <String, Object?>{'code': 0, 'message': ''},
      });
      await settle();
      expect(attach.synced, isTrue);
      expect(log.join('\n'), contains('up to date'));
    });

    test('a reload is a hot reload, answered by Flutter\'s result', () async {
      process.emit(<String, Object?>{
        'event': 'app.started',
        'params': <String, Object?>{'appId': 'app-1'},
      });
      await settle();
      process.emit(<String, Object?>{
        'id': process.sent.single['id'],
        'result': <String, Object?>{'code': 0, 'message': ''},
      });
      await settle();

      final Future<bool> reloaded = attach.reload();
      await settle();
      final Map<String, Object?> request = process.sent.last;
      expect(request['method'], 'app.restart');
      expect((request['params']! as Map<String, Object?>)['fullRestart'], false);
      process.emit(<String, Object?>{
        'id': request['id'],
        'result': <String, Object?>{
          'code': 0,
          'message': 'Reloaded 1 of 532 libraries',
        },
      });
      expect(await reloaded, isTrue);
      expect(log.last, contains('Reloaded 1 of 532 libraries'));

      final Future<bool> failed = attach.reload();
      await settle();
      process.emit(<String, Object?>{
        'id': process.sent.last['id'],
        'result': <String, Object?>{
          'code': 1,
          'message': 'Reload rejected: a const constructor changed',
        },
      });
      expect(await failed, isFalse);
      expect(log.last, contains('Reload rejected'));
    });

    test('a reload before the device is attached sends nothing', () async {
      expect(await attach.reload(), isFalse);
      expect(process.sent, isEmpty);
    });

    test('attach ending ends every pending reload as failed', () async {
      process.emit(<String, Object?>{
        'event': 'app.started',
        'params': <String, Object?>{'appId': 'app-1'},
      });
      await settle();
      final Future<bool> pending = attach.reload(full: true);
      process.kill();
      expect(await pending, isFalse);
    });

    test('what Flutter prints for people is passed on', () async {
      process.say('Launching lib/main.dart on Flutter test device...');
      process.emit(<String, Object?>{
        'event': 'app.log',
        'params': <String, Object?>{'log': 'flutter: hello from the phone'},
      });
      await settle();
      expect(log, contains('flutter: hello from the phone'));
    });
  });
}

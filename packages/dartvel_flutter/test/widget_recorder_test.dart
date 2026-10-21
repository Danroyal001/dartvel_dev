// DVWidgetRecorder: what a part of the screen shows, recorded or streamed.
//
// The encoder is a fake here; the Linux encoder has its own suite. What is
// tested is the part every target shares: the frames are the subtree's
// pixels at the size asked for, they keep coming while it records, a stream
// goes to the URL given, and a target with no encoder refuses instead of
// pretending to record.
import 'dart:async';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeEncoder implements DVFrameEncoder {
  final List<DVVideoFrame> frames = <DVVideoFrame>[];
  DVFrameEncoderTarget? target;
  (int, int)? size;
  bool? audio;
  bool stopped = false;
  final StreamController<String> _failures = StreamController<String>.broadcast();

  @override
  DVFrameEncoderCapabilities get capabilities =>
      const DVFrameEncoderCapabilities(file: true, stream: true, audio: true);

  @override
  Stream<String> get failures => _failures.stream;

  void fail(String message) => _failures.add(message);

  @override
  Future<void> start(DVFrameEncoderTarget target,
      {required int width, required int height, required int fps, required bool audio}) async {
    this.target = target;
    size = (width, height);
    this.audio = audio;
  }

  @override
  void push(DVVideoFrame frame) => frames.add(frame);

  @override
  Future<Duration> stop() async {
    stopped = true;
    return const Duration(seconds: 2);
  }

  @override
  Future<void> dispose() async => _failures.close();
}

final class MemoryFiles implements DVCaptureFiles {
  final List<String> reserved = <String>[];
  @override
  Future<String> reserve(String extension) async {
    final String path = '/private/out-${reserved.length}.$extension';
    reserved.add(path);
    return path;
  }

  @override
  Future<int> seal(String path) async => 4096;

  @override
  Future<void> discard(String path) async {}
}

Widget stage(DVWidgetRecorder recorder) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: DVBox.recorded(
            recorder: recorder,
            child: const ColoredBox(color: Color(0xffff0000)),
          ),
        ),
      ),
    );

void main() {
  late FakeEncoder encoder;
  late MemoryFiles files;

  setUp(() {
    encoder = FakeEncoder();
    files = MemoryFiles();
    DVMediaBackends.registerFrameEncoder(() => encoder,
        capabilities: encoder.capabilities);
    DVMediaBackends.useCaptureFiles(files);
  });
  tearDown(DVMediaBackends.resetFrameEncoder);

  testWidgets('records the subtree, at the height asked for, into a file',
      (WidgetTester tester) async {
    final DVWidgetRecorder recorder =
        DVWidgetRecorder(fps: 20, quality: DVVideoQuality.sd480, audio: false);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(stage(recorder));
    await tester.runAsync(() async {
      await recorder.start();
      expect(recorder.state.value, DVWidgetRecorderState.recording);
      expect(encoder.target!.path, '/private/out-0.mp4');
      // 320x180 at 480 lines: 853.3 wide, made even.
      expect(encoder.size, (854, 480));
      expect(encoder.audio, isFalse);
      final DateTime end = DateTime.now().add(const Duration(seconds: 5));
      while (encoder.frames.length < 3 && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(encoder.frames.length, greaterThanOrEqualTo(3));
    final DVVideoFrame frame = encoder.frames.first;
    expect((frame.width, frame.height), (854, 480));
    final int middle = (240 * 854 + 427) * 4;
    expect(frame.rgba.sublist(middle, middle + 4), <int>[255, 0, 0, 255]);

    late DVFile? file;
    await tester.runAsync(() async => file = await recorder.stop());
    expect(encoder.stopped, isTrue);
    expect(file!.path, '/private/out-0.mp4');
    expect(file!.mimeType, 'video/mp4');
    expect(file!.duration, const Duration(seconds: 2));
    expect(file!.sizeBytes, 4096);
    expect(recorder.state.value, DVWidgetRecorderState.idle);
  });

  testWidgets('streams to the URL given, and keeps no file',
      (WidgetTester tester) async {
    final DVWidgetRecorder recorder = DVWidgetRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(stage(recorder));
    late DVFile? file;
    await tester.runAsync(() async {
      await recorder.start(streamTo: Uri.parse('rtmp://live.example/app/key'));
      expect(recorder.state.value, DVWidgetRecorderState.streaming);
      file = await recorder.stop();
    });
    expect(encoder.target!.url, Uri.parse('rtmp://live.example/app/key'));
    expect(encoder.target!.path, isNull);
    expect(files.reserved, isEmpty);
    expect(file, isNull);
  });

  testWidgets('a stream URL that is not RTMP is refused', (WidgetTester tester) async {
    final DVWidgetRecorder recorder = DVWidgetRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(stage(recorder));
    await tester.runAsync(() async {
      await expectLater(recorder.start(streamTo: Uri.parse('https://example.com/x')),
          throwsArgumentError);
    });
    expect(recorder.state.value, DVWidgetRecorderState.idle);
  });

  testWidgets('an encoder failure is reported and the recording ends',
      (WidgetTester tester) async {
    final DVWidgetRecorder recorder = DVWidgetRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(stage(recorder));
    await tester.runAsync(() async {
      await recorder.start();
      encoder.fail('the disk is full');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(recorder.state.value, DVWidgetRecorderState.failed);
    expect(recorder.error.value, 'the disk is full');
  });

  testWidgets('with no encoder bound it refuses, naming why',
      (WidgetTester tester) async {
    DVMediaBackends.resetFrameEncoder();
    final DVWidgetRecorder recorder = DVWidgetRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(stage(recorder));
    await tester.runAsync(() async {
      await expectLater(recorder.start(), throwsA(isA<DVRecordingUnavailable>()));
    });
    expect(recorder.state.value, DVWidgetRecorderState.idle);
    expect(DV.Platform.media.recordingCapabilities.file, isFalse);
  });

  testWidgets('starting before the box is on screen is refused',
      (WidgetTester tester) async {
    final DVWidgetRecorder recorder = DVWidgetRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await expectLater(recorder.start(), throwsStateError);
    });
  });

  test('a frame of the wrong size is never pushed into a fixed-size encoder', () {
    expect(() => DVVideoFrame(width: 2, height: 2, rgba: Uint8List(15)),
        throwsArgumentError);
  });
}

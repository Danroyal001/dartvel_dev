// The Linux video encoder behind DVWidgetRecorder: frames pushed through
// appsrc into H.264, muxed into MP4 or sent over RTMP.
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_media_gst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

DVVideoFrame solid(int width, int height, List<int> rgba) {
  final Uint8List bytes = Uint8List(width * height * 4);
  for (int i = 0; i < bytes.length; i += 4) {
    bytes.setRange(i, i + 4, rgba);
  }
  return DVVideoFrame(width: width, height: height, rgba: bytes);
}

void main() {
  final bool available = DVGStreamer.load();
  const List<String> needed = <String>[
    'appsrc', 'videoconvert', 'x264enc', 'h264parse', 'mp4mux', 'qtdemux',
    'avdec_h264', 'appsink', 'videoscale', 'audiotestsrc',
  ];
  final String? skip = !available
      ? 'GStreamer is not installed here'
      : needed.every(DVGStreamer.hasElement)
          ? null
          : 'the encoder elements are not installed';

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dv-enc-'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('reports what it can do from the registry', () {
    final DVFrameEncoderCapabilities can = DVGStreamerFrameEncoder.probe();
    expect(can.file, <String>['appsrc', 'x264enc', 'h264parse', 'mp4mux']
        .every(DVGStreamer.hasElement));
    expect(can.stream, can.file &&
        DVGStreamer.hasElement('flvmux') && DVGStreamer.hasElement('rtmp2sink'));
  }, skip: available ? null : 'GStreamer is not installed here');

  test('writes an MP4 of the frames pushed, that plays back as them', () async {
    final DVGStreamerFrameEncoder encoder = DVGStreamerFrameEncoder(
        audioSource: 'audiotestsrc is-live=true wave=silence');
    addTearDown(encoder.dispose);
    final String path = '${dir.path}/out.mp4';
    File(path).createSync();
    await encoder.start(DVFrameEncoderTarget.file(path),
        width: 320, height: 180, fps: 20, audio: true);
    final DVVideoFrame blue = solid(320, 180, <int>[0, 0, 255, 255]);
    for (int i = 0; i < 30; i++) {
      encoder.push(blue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final Duration length = await encoder.stop();
    expect(length.inMilliseconds, inInclusiveRange(1000, 3000));
    expect(File(path).lengthSync(), greaterThan(1000));

    final DVGStreamerPlayer player = DVGStreamerPlayer(audioSink: 'fakesink');
    addTearDown(player.dispose);
    await player.open(DVMediaSource.file(path));
    await player.play();
    await until(() => player.frame.value != null);
    final DVVideoFrame frame = player.frame.value!;
    expect((frame.width, frame.height), (320, 180));
    final int middle = (90 * 320 + 160) * 4;
    expect(frame.rgba[middle + 2], greaterThan(200));
    expect(frame.rgba[middle], lessThan(60));
  }, skip: skip);

  test('with no microphone that opens, it records the picture without sound', () async {
    // v4l2src with no camera does not open, as a sound server that is not
    // running does not.
    final DVGStreamerFrameEncoder encoder = DVGStreamerFrameEncoder(microphones: const <String>['v4l2src']);
    addTearDown(encoder.dispose);
    final String path = '${dir.path}/silent.mp4';
    File(path).createSync();
    final List<String> failures = <String>[];
    final StreamSubscription<String> sub = encoder.failures.listen(failures.add);
    addTearDown(sub.cancel);
    await encoder.start(DVFrameEncoderTarget.file(path), width: 320, height: 180, fps: 20, audio: true);
    final DVVideoFrame frame = solid(320, 180, <int>[0, 255, 0, 255]);
    for (int i = 0; i < 20; i++) {
      encoder.push(frame);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await encoder.stop();
    expect(failures, isEmpty);
    expect(File(path).lengthSync(), greaterThan(1000));
  }, skip: skip ?? (File('/dev/video0').existsSync() ? 'a camera is connected here' : null));

  test('a frame of another size is dropped, not pushed', () async {
    final DVGStreamerFrameEncoder encoder = DVGStreamerFrameEncoder();
    addTearDown(encoder.dispose);
    final String path = '${dir.path}/out.mp4';
    File(path).createSync();
    await encoder.start(DVFrameEncoderTarget.file(path),
        width: 320, height: 180, fps: 20, audio: false);
    encoder.push(solid(160, 90, <int>[255, 255, 255, 255]));
    expect(encoder.dropped, 1);
    await encoder.stop();
  }, skip: skip);

  test('a stream the server refuses is reported as a failure', () async {
    final DVGStreamerFrameEncoder encoder = DVGStreamerFrameEncoder(
        audioSource: 'audiotestsrc is-live=true wave=silence');
    addTearDown(encoder.dispose);
    final List<String> failures = <String>[];
    final StreamSubscription<String> sub = encoder.failures.listen(failures.add);
    addTearDown(sub.cancel);
    // Nothing listens on port 1.
    await encoder.start(DVFrameEncoderTarget.stream(Uri.parse('rtmp://127.0.0.1:1/live/key')),
        width: 320, height: 180, fps: 20, audio: false);
    final DVVideoFrame frame = solid(320, 180, <int>[0, 0, 0, 255]);
    final DateTime end = DateTime.now().add(const Duration(seconds: 10));
    while (failures.isEmpty && DateTime.now().isBefore(end)) {
      encoder.push(frame);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(failures, isNotEmpty);
  }, skip: skip ?? (DVGStreamerFrameEncoder.probe().stream ? null : 'no rtmp2sink'));

  testWidgets('DVBox.recorded through this encoder: the widget, back out of the MP4',
      (WidgetTester tester) async {
    DVMediaBackends.registerFrameEncoder(
        () => DVGStreamerFrameEncoder(audioSource: 'audiotestsrc is-live=true wave=silence'),
        capabilities: DVGStreamerFrameEncoder.probe());
    DVMediaBackends.useCaptureFiles(DVPrivateCaptureFiles(dir.path));
    addTearDown(DVMediaBackends.resetFrameEncoder);
    final DVWidgetRecorder recorder =
        DVWidgetRecorder(fps: 15, quality: DVVideoQuality.sd480, audio: false);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: DVBox.recorded(
              recorder: recorder, child: const ColoredBox(color: Color(0xff00c000))),
        ),
      ),
    ));
    late DVFile? file;
    await tester.runAsync(() async {
      await recorder.start();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      file = await recorder.stop();
    });
    expect(file!.mimeType, 'video/mp4');
    expect(file!.sizeBytes, greaterThan(1000));
    await tester.runAsync(() async {
      final DVGStreamerPlayer player = DVGStreamerPlayer(audioSink: 'fakesink');
      await player.open(DVMediaSource.file(file!.path));
      await player.play();
      await until(() => player.frame.value != null);
      final DVVideoFrame frame = player.frame.value!;
      expect((frame.width, frame.height), (640, 480));
      final int middle = (240 * 640 + 320) * 4;
      expect(frame.rgba[middle + 1], greaterThan(150));
      expect(frame.rgba[middle], lessThan(60));
      await player.dispose();
    });
  }, skip: skip != null);
}

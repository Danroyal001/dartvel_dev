// The Linux camera and screen: GStreamer over dart:ffi.
//
// A runner has no webcam and no display, so the device element is replaced
// by videotestsrc -- everything after it is the pipeline an application
// gets: the tee, the RGBA frames for the preview, the JPEG encoder, the H.264
// encoder and the MP4 muxer. A photo that is not a JPEG, a clip that does not
// play back, or a preview that never draws fails here.
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_media_gst.dart';
import 'package:flutter/painting.dart' show Rect;
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

const String green = 'videotestsrc is-live=true pattern=solid-color '
    'foreground-color=0xff00ff00 ! video/x-raw,width=320,height=240,framerate=15/1';
const String blue = 'videotestsrc is-live=true pattern=solid-color '
    'foreground-color=0xff0000ff ! video/x-raw,width=640,height=360,framerate=15/1';

void main() {
  final bool available = DVGStreamer.load();
  const List<String> needed = <String>[
    'videotestsrc', 'tee', 'queue', 'appsink', 'videoconvert', 'videoscale',
    'jpegenc', 'rawvideoparse', 'x264enc', 'h264parse', 'mp4mux', 'qtdemux',
    'avdec_h264', 'audiotestsrc',
  ];
  final List<String> missing = available
      ? needed.where((String e) => !DVGStreamer.hasElement(e)).toList()
      : const <String>[];
  final String? skip = !available
      ? 'GStreamer is not installed here'
      : missing.isEmpty
          ? null
          : 'these GStreamer elements are not installed: ${missing.join(', ')}';

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dv-cam-'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  DVGStreamerCamera camera({Map<String, String> environment = const <String, String>{}}) {
    final DVGStreamerCamera backend = DVGStreamerCamera(
      videoSource: green,
      screenSource: blue,
      audioSource: 'audiotestsrc is-live=true wave=sine',
      environment: environment,
    );
    addTearDown(backend.dispose);
    return backend;
  }

  Future<List<DVCameraEvent>> events(DVGStreamerCamera backend) async {
    final List<DVCameraEvent> seen = <DVCameraEvent>[];
    final StreamSubscription<DVCameraEvent> sub = backend.events.listen(seen.add);
    addTearDown(sub.cancel);
    return seen;
  }

  group('devices', () {
    test('lists capture nodes by their names, not metadata nodes', () async {
      final Directory sysfs = Directory('${dir.path}/video4linux')..createSync();
      void node(String name, String label, int index) {
        final Directory d = Directory('${sysfs.path}/$name')..createSync();
        File('${d.path}/name').writeAsStringSync('$label\n');
        File('${d.path}/index').writeAsStringSync('$index\n');
      }

      node('video0', 'Integrated Camera', 0);
      node('video1', 'Integrated Camera', 1); // its metadata node
      node('video2', 'USB Capture HDMI', 0);
      final DVGStreamerCamera backend = DVGStreamerCamera(
          sysfsRoot: sysfs.path, environment: const <String, String>{});
      addTearDown(backend.dispose);
      final List<DVCameraDevice> found = await backend.devices();
      expect(found.map((DVCameraDevice d) => (d.id, d.name, d.lens)), <Object>[
        ('/dev/video0', 'Integrated Camera', DVCameraLens.external),
        ('/dev/video2', 'USB Capture HDMI', DVCameraLens.external),
      ]);
    });

    test('with two displays, each is a screen of its own, by name and place', () async {
      final DVGStreamerCamera backend = DVGStreamerCamera(
        sysfsRoot: '${dir.path}/none',
        environment: const <String, String>{'DISPLAY': ':0'},
        displays: () async => const <DVDisplay>[
          DVDisplay(id: 'a', name: 'eDP-1', bounds: Rect.fromLTWH(0, 0, 1280, 800),
              devicePixelRatio: 1.5, refreshRate: 60, isPrimary: true, hasLayout: true),
          DVDisplay(id: 'b', name: 'HDMI-1', bounds: Rect.fromLTWH(1920, 0, 1920, 1080),
              devicePixelRatio: 1, refreshRate: 60, isPrimary: false, hasLayout: true),
        ],
      );
      addTearDown(backend.dispose);
      final List<DVCameraDevice> screens = (await backend.devices())
          .where((DVCameraDevice d) => d.lens == DVCameraLens.screen)
          .toList();
      expect(screens.map((DVCameraDevice d) => (d.id, d.name)), <Object>[
        ('screen:0,0,1920,1200', 'Screen: eDP-1 (main)'),
        ('screen:1920,0,1920,1080', 'Screen: HDMI-1'),
      ]);
      expect(DVGStreamerCamera.screenDescriptionFor('screen:1920,0,1920,1080'),
          contains('startx=1920 starty=0 endx=3839 endy=1079'));
      expect(DVGStreamerCamera.screenDescriptionFor('screen:1920,0,x,1080'), isNull);
    }, skip: available && DVGStreamer.hasElement('ximagesrc') ? null : 'no ximagesrc');

    test('offers the screen on an X11 display, not without one', () async {
      final DVGStreamerCamera withDisplay = DVGStreamerCamera(
          sysfsRoot: '${dir.path}/none',
          environment: const <String, String>{'DISPLAY': ':0'});
      final DVGStreamerCamera headless = DVGStreamerCamera(
          sysfsRoot: '${dir.path}/none', environment: const <String, String>{});
      addTearDown(withDisplay.dispose);
      addTearDown(headless.dispose);
      expect((await withDisplay.devices()).map((DVCameraDevice d) => d.lens),
          DVGStreamer.hasElement('ximagesrc') ? <DVCameraLens>[DVCameraLens.screen] : isEmpty);
      expect(await headless.devices(), isEmpty);
      expect(headless.capabilities.lenses, isNot(contains(DVCameraLens.screen)));
    });
  });

  group('preview', () {
    test('opens, reports its size, and draws the picture', () async {
      final DVGStreamerCamera backend = camera();
      final List<DVCameraEvent> seen = await events(backend);
      expect(backend, isA<DVCameraSurface>());
      await backend.open(DVCameraLens.external);
      await until(() => seen.whereType<DVCameraOpened>().isNotEmpty);
      final DVCameraOpened opened = seen.whereType<DVCameraOpened>().single;
      expect((opened.lens, opened.width, opened.height),
          (DVCameraLens.external, 320, 240));
      final DVVideoFrame frame = backend.frame.value!;
      final int middle = (120 * 320 + 160) * 4;
      expect(frame.rgba[middle], lessThan(25));
      expect(frame.rgba[middle + 1], greaterThan(230));
      expect(frame.rgba[middle + 2], lessThan(25));
      await backend.close();
      await until(() => seen.whereType<DVCameraClosed>().isNotEmpty);
      expect(backend.frame.value, isNull);
    }, skip: skip);

    test('the screen lens opens the screen, not the camera', () async {
      final DVGStreamerCamera backend = camera();
      final List<DVCameraEvent> seen = await events(backend);
      await backend.open(DVCameraLens.screen);
      await until(() => seen.whereType<DVCameraOpened>().isNotEmpty);
      final DVCameraOpened opened = seen.whereType<DVCameraOpened>().single;
      expect((opened.lens, opened.width, opened.height),
          (DVCameraLens.screen, 640, 360));
    }, skip: skip);

    test('a device that does not exist fails instead of hanging', () async {
      final DVGStreamerCamera backend =
          DVGStreamerCamera(environment: const <String, String>{});
      addTearDown(backend.dispose);
      final List<DVCameraEvent> seen = await events(backend);
      await backend.open(DVCameraLens.external, device: '/dev/video99');
      await until(() => seen.whereType<DVCameraFailed>().isNotEmpty);
      expect(seen.whereType<DVCameraOpened>(), isEmpty);
    }, skip: available && DVGStreamer.hasElement('v4l2src') ? null : 'no v4l2src');

    test('refuses a device that is not a video node', () async {
      final DVGStreamerCamera backend =
          DVGStreamerCamera(environment: const <String, String>{});
      addTearDown(backend.dispose);
      final List<DVCameraEvent> seen = await events(backend);
      await backend.open(DVCameraLens.external, device: '/dev/video0 ! filesink location=/tmp/x');
      await until(() => seen.whereType<DVCameraFailed>().isNotEmpty);
      expect(seen.whereType<DVCameraFailed>().single.message, contains('not a camera'));
    }, skip: skip);
  });

  group('photo and video', () {
    test('a photo is a real JPEG of the preview size', () async {
      final DVGStreamerCamera backend = camera();
      final List<DVCameraEvent> seen = await events(backend);
      await backend.open(DVCameraLens.external);
      await until(() => seen.whereType<DVCameraOpened>().isNotEmpty);
      final String path = '${dir.path}/photo.jpg';
      File(path).createSync();
      await backend.takePhoto(path);
      await until(() => seen.whereType<DVCameraPhotoTaken>().isNotEmpty);
      final List<int> bytes = File(path).readAsBytesSync();
      expect(bytes.take(3), <int>[0xff, 0xd8, 0xff]);
      expect(bytes.length, greaterThan(500));
    }, skip: skip);

    test('records an MP4 that plays back with the recorded picture', () async {
      final DVGStreamerCamera backend = camera();
      final List<DVCameraEvent> seen = await events(backend);
      await backend.open(DVCameraLens.external);
      await until(() => seen.whereType<DVCameraOpened>().isNotEmpty);
      final String path = '${dir.path}/clip.mp4';
      File(path).createSync();
      await backend.startRecording(path, quality: DVVideoQuality.sd480);
      await until(() => seen.whereType<DVCameraRecordingStarted>().isNotEmpty);
      // The preview keeps drawing while it records.
      final DVVideoFrame before = backend.frame.value!;
      await until(() => !identical(backend.frame.value, before));
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await backend.stopRecording();
      await until(() => seen.whereType<DVCameraRecordingStopped>().isNotEmpty,
          timeout: const Duration(seconds: 15));
      final Duration length =
          seen.whereType<DVCameraRecordingStopped>().single.duration;
      expect(length.inMilliseconds, inInclusiveRange(1000, 4000));
      // Back to previewing after the file is finalised.
      final DVVideoFrame after = backend.frame.value ?? before;
      await until(() => backend.frame.value != null && !identical(backend.frame.value, after));

      // The clip decodes: a frame of it comes back green, at 480 lines.
      final DVGStreamerPlayer player = DVGStreamerPlayer(audioSink: 'fakesink');
      addTearDown(player.dispose);
      await player.open(DVMediaSource.file(path));
      await player.play();
      await until(() => player.frame.value != null);
      final DVVideoFrame frame = player.frame.value!;
      expect(frame.height, 480);
      final int middle = ((frame.height ~/ 2) * frame.width + frame.width ~/ 2) * 4;
      expect(frame.rgba[middle + 1], greaterThan(200));
      expect(frame.rgba[middle], lessThan(60));
    }, skip: skip);
  });
}

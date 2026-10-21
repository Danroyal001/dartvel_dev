import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/src/media/native_backend.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBridge implements DVNativeMediaBridge {
  final calls = <(String, List<Object?>)>[];
  String? pending;
  @override
  Object? call(String method, List<Object?> arguments) {
    calls.add((method, arguments));
    return switch (method) {
      'createCamera' || 'create' => 7,
      'cameraTextureId' || 'textureId' => 9,
      'devices' => '[{"id":"usb:2","name":"Capture","lens":"external"}]',
      'pollCamera' || 'poll' => pending,
      _ => null,
    };
  }
}

void main() {
  test(
    'opens selected camera, refuses screen without opening hardware',
    () async {
      final bridge = FakeBridge();
      final camera = DVNativeCameraBackend(
        bridge,
        engineId: 1,
        capabilities: const DVCameraCapabilities(
          lenses: {.external},
          preview: true,
        ),
      );
      expect((await camera.devices()).single.id, 'usb:2');
      await camera.open(.external, device: 'usb:2');
      expect(
        bridge.calls.singleWhere((c) => c.$1 == 'openCamera').$2,
        <Object?>[7, 'external', 'usb:2'],
      );
      final before = bridge.calls.length;
      await expectLater(camera.open(.screen), throwsUnsupportedError);
      expect(bridge.calls.length, before);
      await camera.dispose();
      expect(bridge.calls.last.$1, 'disposeCamera');
    },
  );
  test('polling decodes events; dispose releases once', () async {
    final bridge = FakeBridge();
    final camera = DVNativeCameraBackend(
      bridge,
      engineId: 1,
      capabilities: const DVCameraCapabilities(lenses: {.front}),
    );
    bridge.pending =
        '[{"type":"opened","lens":"front","width":640,"height":480}]';
    final first = camera.events.first;
    await camera.open(.front);
    expect(
      await first.timeout(const Duration(seconds: 2)),
      isA<DVCameraOpened>(),
    );
    bridge.pending = null;
    await camera.dispose();
    await camera.dispose();
    expect(bridge.calls.where((c) => c.$1 == 'disposeCamera'), hasLength(1));
    await expectLater(camera.open(.front), throwsStateError);
  });
  test('player passes seek generations and rejects unconfigured DRM', () async {
    final bridge = FakeBridge();
    final player = DVNativePlayerBackend(bridge, engineId: 1, video: true);
    await player.seek(const Duration(seconds: 4), 3);
    expect(bridge.calls.singleWhere((c) => c.$1 == 'seek').$2, <Object?>[
      7,
      4000,
      3,
    ]);
    await expectLater(
      player.open(
        DVMediaSource.url('https://example.com/a.mp4'),
        license: 'secret',
      ),
      throwsUnsupportedError,
    );
    expect(bridge.calls.where((c) => c.$1 == 'open'), isEmpty);
    await player.dispose();
    await player.dispose();
    expect(bridge.calls.where((c) => c.$1 == 'dispose'), hasLength(1));
  });
}

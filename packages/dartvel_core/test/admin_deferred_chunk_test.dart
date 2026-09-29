import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  const DVAdminMount mount =
      DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);

  test('the engine and the app entry are public: the sign-in screen needs them', () {
    for (final String path in <String>[
      '/__studio/canvaskit/canvaskit.wasm',
      '/__studio/canvaskit/chromium/canvaskit.wasm',
      '/__studio/canvaskit/skwasm.wasm',
      '/__studio/main.dart.js',
      '/__studio/main.dart.wasm',
      '/__studio/flutter_bootstrap.js',
    ]) {
      expect(dvIsDeferredLibraryChunk(mount, path), isFalse, reason: path);
    }
  });

  test('deferred library parts are protected', () {
    for (final String path in <String>[
      '/__studio/main.dart.js_1.part.js',
      '/__studio/main.dart.js_12.part.js.map',
      '/__studio/main.dart.wasm_3.part.wasm',
    ]) {
      expect(dvIsDeferredLibraryChunk(mount, path), isTrue, reason: path);
    }
  });
}

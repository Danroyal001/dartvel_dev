// Assembling an eLinux application without flutter-elinux.
//
// flutter-elinux is pinned to Flutter 3.29.3 and upstream has not committed
// since 2025-07-09. Its classes subclass flutter_tools internals, so moving it
// to Dartvel's 3.44.5 is a port across fifteen minor versions.
//
// It is also not the only way to produce an eLinux application. One is the
// embedder executable, libflutter_engine.so, the app's AOT app.so, icudtl.dat
// and the asset bundle — and every one of those comes from stock Flutter plus
// the artifacts already verified against Dartvel's engine. This describes that
// assembly so it can be asserted on without running a build.
import 'package:dartvel_cli/src/build/elinux_bundle.dart';
import 'package:test/test.dart';

void main() {
  group('bundle layout', () {
    test('a release bundle carries an AOT app.so and no kernel', () {
      final layout = elinuxBundleLayout(
        backend: ELinuxBackend.wayland,
        mode: ELinuxMode.release,
      );

      expect(layout.entries.map((ELinuxBundleEntry e) => e.target),
          contains('lib/libapp.so'));
      expect(layout.entries.map((ELinuxBundleEntry e) => e.target),
          isNot(contains('data/flutter_assets/kernel_blob.bin')),
          reason: 'a release engine cannot run kernel; shipping it would be '
              'dead weight that also implies the app is debuggable');
    });

    test('a debug bundle carries the kernel and no app.so', () {
      final layout = elinuxBundleLayout(
        backend: ELinuxBackend.wayland,
        mode: ELinuxMode.debug,
      );

      final targets = layout.entries.map((ELinuxBundleEntry e) => e.target);
      expect(targets, contains('data/flutter_assets/kernel_blob.bin'));
      expect(targets, isNot(contains('lib/libapp.so')));
    });

    test('every bundle carries the engine, the embedder and icudtl', () {
      for (final mode in ELinuxMode.values) {
        final targets = elinuxBundleLayout(
                backend: ELinuxBackend.wayland, mode: mode)
            .entries
            .map((ELinuxBundleEntry e) => e.target)
            .toList();
        expect(targets, contains('lib/libflutter_engine.so'), reason: '$mode');
        expect(targets, contains('data/icudtl.dat'), reason: '$mode');
        expect(targets.any((String t) => t.startsWith('flutter-')), isTrue,
            reason: '$mode needs the embedder executable');
      }
    });

    test('the backend decides which embedder executable is used', () {
      // Sony builds one executable per display backend, and they are not
      // interchangeable: a Wayland binary on a DRM-only device fails at
      // startup rather than at build.
      final wayland = elinuxBundleLayout(
          backend: ELinuxBackend.wayland, mode: ELinuxMode.release);
      final gbm = elinuxBundleLayout(
          backend: ELinuxBackend.drmGbm, mode: ELinuxMode.release);

      expect(wayland.embedderExecutable, 'flutter-client');
      expect(gbm.embedderExecutable, 'flutter-drm-gbm-backend');
      expect(wayland.embedderExecutable, isNot(gbm.embedderExecutable));
    });
  });

  group('AOT compilation', () {
    test('release asks gen_snapshot for a shared library, not a blob', () {
      // An eLinux release app loads libapp.so through the engine. Emitting an
      // assembly or blob snapshot instead produces files the engine will not
      // load, and the failure is at startup on the device.
      final args = genSnapshotArguments(
        kernel: '/build/app.dill',
        output: '/build/libapp.so',
      );

      expect(args, contains('--snapshot_kind=app-aot-elf'));
      expect(args, contains('--elf=/build/libapp.so'));
      expect(args.last, '/build/app.dill',
          reason: 'gen_snapshot takes the kernel as its final positional '
              'argument');
    });

    test('stripping is requested, because these ship to devices', () {
      final args = genSnapshotArguments(
        kernel: '/build/app.dill',
        output: '/build/libapp.so',
      );
      expect(args, contains('--strip'));
    });

    test('there is no architecture argument to get wrong', () {
      // gen_snapshot is downloaded per architecture, so the binary is the
      // target. Accepting an arch here would invite passing arm64 to an x64
      // binary and expecting a cross-compile.
      final args = genSnapshotArguments(
        kernel: '/build/app.dill',
        output: '/build/libapp.so',
      );
      expect(args.where((String a) => a.contains('arch')), isEmpty);
    });
  });
}

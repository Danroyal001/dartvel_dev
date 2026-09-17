// `dartvel deploy --store` refuses a dev-client shell on anything but an internal
// track (DV-DEVCLIENT-003).
//
// Decided from the artifact's content, not its name: a renamed file is still
// a shell with a dev menu in it. The marker is a string the shell's compiled
// snapshot carries, so the fixtures here put it where a real build puts that
// snapshot -- deflated, as an .aab and an .ipa store it.
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/deploy_command.dart';
import 'package:dartvel_cli/src/devclient/dev_client_artifact.dart';
import 'package:dartvel_core/dartvel.dart' show dvDevClientShellMarker;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A zip holding [entries], each deflated unless [stored].
Uint8List zip(Map<String, List<int>> entries, {bool stored = false}) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder central = BytesBuilder();
  var count = 0;
  void u16(BytesBuilder b, int v) => b.add(<int>[v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) => b.add(<int>[
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  entries.forEach((String name, List<int> data) {
    final List<int> body = stored ? data : ZLibCodec(raw: true).encode(data);
    final List<int> nameBytes = name.codeUnits;
    final int offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, stored ? 0 : 8);
    u16(out, 0);
    u16(out, 0);
    u32(out, 0); // crc, unchecked by the reader
    u32(out, body.length);
    u32(out, data.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    out.add(nameBytes);
    out.add(body);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, stored ? 0 : 8);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, body.length);
    u32(central, data.length);
    u16(central, nameBytes.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(nameBytes);
    count++;
  });
  final int centralOffset = out.length;
  final Uint8List centralBytes = central.toBytes();
  out.add(centralBytes);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, centralBytes.length);
  u32(out, centralOffset);
  u16(out, 0);
  return out.toBytes();
}

List<int> snapshot({required bool shell}) => <int>[
  ...List<int>.filled(4096, 0x2a),
  ...'runApp'.codeUnits,
  if (shell) ...dvDevClientShellMarker.codeUnits,
  ...List<int>.filled(4096, 0x11),
];

void main() {
  late Directory root;
  late List<List<String>> ran;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_store_devclient_');
    ran = <List<String>>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  String artifact(String name, Uint8List bytes) {
    final File file = File(p.join(root.path, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  void declare(String yaml) =>
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  deploy:
    stores:
${yaml.replaceAll(RegExp('^(?=.)', multiLine: true), '  ')}
''');

  Future<void> publish(List<String> arguments) async {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(
        DeployCommand(
          root: root.path,
          processRun:
              (
                String executable,
                List<String> args, {
                bool runInShell = false,
              }) async {
                ran.add(<String>[executable, ...args]);
                return ProcessResult(0, 0, '', '');
              },
        ),
      );
    await runner.run(<String>['deploy', '--store', ...arguments]);
  }

  group('recognising a shell', () {
    test('in an app bundle', () {
      final String aab = artifact(
        'a.aab',
        zip(<String, List<int>>{
          'base/manifest/AndroidManifest.xml': <int>[1, 2, 3],
          'base/lib/arm64-v8a/libapp.so': snapshot(shell: true),
        }),
      );
      expect(dvArtifactIsDevClient(aab), isTrue);
    });

    test('in an APK that stores its libraries uncompressed', () {
      final String apk = artifact(
        'a.apk',
        zip(<String, List<int>>{
          'lib/arm64-v8a/libapp.so': snapshot(shell: true),
        }, stored: true),
      );
      expect(dvArtifactIsDevClient(apk), isTrue);
    });

    test('in an IPA', () {
      final String ipa = artifact(
        'a.ipa',
        zip(<String, List<int>>{
          'Payload/Runner.app/Frameworks/App.framework/App': snapshot(
            shell: true,
          ),
        }),
      );
      expect(dvArtifactIsDevClient(ipa), isTrue);
    });

    // A development-profile build is a Flutter debug build: its Dart is a
    // JIT kernel, not an AOT snapshot, and no store track runs one.
    for (final String path in <String>[
      'assets/flutter_assets/kernel_blob.bin',
      'base/assets/flutter_assets/kernel_blob.bin',
      'Payload/Runner.app/Frameworks/App.framework/flutter_assets/kernel_blob.bin',
    ]) {
      test('in a development-profile build, by its kernel ($path)', () {
        final String built = artifact(
          'dev.zip',
          zip(<String, List<int>>{path: List<int>.filled(128, 7)}),
        );
        expect(dvArtifactIsDevClient(built), isTrue);
      });
    }

    test('not in the application itself', () {
      final String aab = artifact(
        'a.aab',
        zip(<String, List<int>>{
          'base/lib/arm64-v8a/libapp.so': snapshot(shell: false),
        }),
      );
      expect(dvArtifactIsDevClient(aab), isFalse);
    });

    test('not from a marker in a file that is not the snapshot', () {
      // An asset that merely mentions the marker -- this repository's own
      // documentation, bundled by somebody -- is not a shell.
      final String aab = artifact(
        'a.aab',
        zip(<String, List<int>>{
          'base/assets/flutter_assets/NOTES.md':
              dvDevClientShellMarker.codeUnits,
          'base/lib/arm64-v8a/libapp.so': snapshot(shell: false),
        }),
      );
      expect(dvArtifactIsDevClient(aab), isFalse);
    });

    test('a marker straddling two reads is still found', () {
      // Stored entries are read 64 KiB at a time, so a marker starting ten
      // bytes before that boundary is split across two chunks; a search that
      // looked at each chunk alone would miss it.
      const int boundary = 1 << 16;
      final List<int> data = <int>[
        ...List<int>.filled(boundary - 10, 0x2a),
        ...dvDevClientShellMarker.codeUnits,
        ...List<int>.filled(1000, 0x11),
      ];
      final String apk = artifact(
        'split.apk',
        zip(<String, List<int>>{'lib/arm64-v8a/libapp.so': data}, stored: true),
      );
      expect(dvArtifactIsDevClient(apk), isTrue);
    });

    test('a marker split across the inflater\'s chunks is still found', () {
      final List<int> big = <int>[
        for (int i = 0; i < 300000; i++) (i * 7919) & 0xff,
        ...dvDevClientShellMarker.codeUnits,
        for (int i = 0; i < 300000; i++) (i * 104729) & 0xff,
      ];
      final String aab = artifact(
        'a.aab',
        zip(<String, List<int>>{'base/lib/arm64-v8a/libapp.so': big}),
      );
      expect(dvArtifactIsDevClient(aab), isTrue);
    });
  });

  group('the command', () {
    test(
      'a shell to Play production is refused before anything runs',
      () async {
        declare('''
    play:
      track: production
      credentials: secrets/play.json
''');
        final String shell = artifact(
          'renamed-release.aab',
          zip(<String, List<int>>{
            'base/lib/arm64-v8a/libapp.so': snapshot(shell: true),
          }),
        );

        await publish(<String>['play', '--artifact', shell, '--dry-run']);

        expect(exitCode, 78);
        expect(ran, isEmpty);
        expect(
          dvDevClientStoreRefusal(store: 'play', track: 'production'),
          contains('DV-DEVCLIENT-003'),
        );
      },
    );

    test('a shell to the App Store is refused', () async {
      expect(dvDevClientStoreRefusal(store: 'appstore'), isNotNull);
      expect(dvDevClientStoreRefusal(store: 'play', track: 'beta'), isNotNull);
      expect(dvDevClientStoreRefusal(store: 'play', track: 'alpha'), isNotNull);
    });

    test('the internal tracks the section names are allowed', () {
      expect(dvDevClientStoreRefusal(store: 'play', track: 'internal'), isNull);
      expect(dvDevClientStoreRefusal(store: 'testflight'), isNull);
      expect(
        dvDevClientStoreRefusal(store: 'firebase-app-distribution'),
        isNull,
      );
    });

    test('a shell to Play internal testing goes ahead', () async {
      declare('''
    play:
      track: internal
      credentials: secrets/play.json
''');
      final String shell = artifact(
        'shell.aab',
        zip(<String, List<int>>{
          'base/lib/arm64-v8a/libapp.so': snapshot(shell: true),
        }),
      );

      await publish(<String>['play', '--artifact', shell, '--dry-run']);

      expect(exitCode, 0);
    });

    test('the application itself to production goes ahead', () async {
      declare('''
    play:
      track: production
      credentials: secrets/play.json
''');
      final String app = artifact(
        'app.aab',
        zip(<String, List<int>>{
          'base/lib/arm64-v8a/libapp.so': snapshot(shell: false),
        }),
      );

      await publish(<String>['play', '--artifact', app, '--dry-run']);

      expect(exitCode, 0);
    });
  });
}

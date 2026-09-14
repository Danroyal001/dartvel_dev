// The application key on a phone, across a restart of the process.
//
// Not a `flutter test` suite, and the reason decides the shape. `flutter test`
// uninstalls the application when it finishes, and an uninstall is exactly
// what deletes a Keystore entry and a Keychain item -- so a second run would
// start from nothing, and "the key survived a restart" could be neither shown
// nor refuted. This is an entry point instead:
//
//   flutter build apk --debug -t integration_test/app_key_custody_probe.dart
//   flutter build ios --debug --simulator -t integration_test/app_key_custody_probe.dart
//
// and tool/ci/key_custody_device.dart launches the one installed build twice,
// stopping the process in between (.github/workflows/key-custody.yml).
//
// The first launch finds no state. It plants a key where an earlier Dartvel
// kept one on these platforms -- a file under the home directory -- and lets
// the stores move it in; asks the generated runtime for its key store, which
// must be the keyring with no application change; and seals a canary under
// each key. The second launch is a new process and has to open both canaries,
// which it can only do with the same keys. Both launches scan the
// application's data directory for the keys' bytes, raw or base64, and fail
// on a hit.
//
// Each launch prints one line, `DV-KEY-CUSTODY-RESULT {json}`, and writes the
// same JSON to dv-key-custody-result-<phase>.json in the data directory; the
// host reads whichever it can reach. Nothing reported is key material: a
// canary is ciphertext, and the scan reports counts and paths.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart'
    show
        DVAppKey,
        DVAppKeyCipher,
        DVAppKeyStore,
        DVAppKeyStores,
        DVFileAppKeyStore,
        DVKeychainAppKeyStore,
        DVMigratingAppKeyStore,
        dvHostHome;
import 'package:dartvel_example/dartvel_client/dartvel_client.dart' show createDartvelRouter;
import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DVAndroidKeystoreAppKeyStore, DVWindowSharedStore, dvAndroidOpenKeyBlob, dvAppKeyStoreFor;
import 'package:flutter/material.dart';

const String _tag = 'DV-KEY-CUSTODY-RESULT';

/// What the generated runtime names the key store by: the pubspec name.
const String _wiredApp = 'dartvel_example';

/// A second application id, whose old key file is planted somewhere this
/// process can certainly write, so the move is exercised even where the home
/// directory an earlier version used is not writable.
const String _movedApp = 'dv_key_custody_moved';

const String _canary = 'dartvel key custody canary';

/// Files larger than this are the engine's own snapshots, not somewhere a key
/// is written.
const int _scanLimitBytes = 8 * 1024 * 1024;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final _Probe probe = _Probe();
  Map<String, Object?> result;
  try {
    result = await probe.run();
  } catch (error, stack) {
    result = <String, Object?>{
      'phase': probe.phase,
      'passed': false,
      'platform': Platform.operatingSystem,
      'failures': <String>[...probe.failures, 'the probe threw: $error'],
      'at': stack.toString().split('\n').take(6).join(' | '),
      'facts': probe.facts,
    };
  }
  final String line = jsonEncode(result);
  // ignore: avoid_print
  print('$_tag $line');
  try {
    File('${probe.root.path}/dv-key-custody-result-${probe.phase}.json').writeAsStringSync(line, flush: true);
  } on FileSystemException {
    // The printed line is still there for the host to read.
  }
  final bool passed = result['passed'] == true;
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(child: Text(passed ? 'key custody: passed (launch ${probe.phase})' : 'key custody: FAILED')),
    ),
  ));
}

class _Probe {
  int phase = 0;
  Directory root = Directory.systemTemp;
  final List<String> failures = <String>[];
  final Map<String, Object?> facts = <String, Object?>{};

  void check(bool ok, String failure) {
    if (!ok) failures.add(failure);
  }

  Map<String, Object?> _result() => <String, Object?>{
        'phase': phase,
        'passed': failures.isEmpty && phase > 0,
        'platform': Platform.operatingSystem,
        'failures': failures,
        'facts': facts,
      };

  Future<Map<String, Object?>> run() async {
    // The generated runtime, which points DVWindowSharedStore.defaultAppKeys
    // at dvAppKeyStoreFor('<package>'). Nothing below names a store for the
    // application: if the wiring picked the wrong one, it shows here.
    createDartvelRouter();
    final DVAppKeyStore? wired = await DVWindowSharedStore.defaultAppKeys();
    if (wired == null) {
      failures.add('the generated runtime left DVWindowSharedStore.defaultAppKeys unset');
      return _result();
    }
    facts['wired'] = DVAppKeyStores.describe(wired);
    _expectKeyring(wired, 'the store the generated runtime wired');

    root = _dataRoot(wired);
    final String? home = dvHostHome();
    facts['root'] = root.path;
    facts['home'] = home;

    final Directory state = Directory('${root.path}/dv-key-custody-probe');
    final File canaries = File('${state.path}/canaries.json');
    phase = canaries.existsSync() ? 2 : 1;
    state.createSync(recursive: true);

    final String wiredLegacy = DVAppKeyStores.legacyFilePath(app: _wiredApp, home: home ?? '.');
    final String movedLegacy = DVAppKeyStores.legacyFilePath(app: _movedApp, home: state.path);
    final DVAppKeyStore moved = await dvAppKeyStoreFor(_movedApp, home: state.path);
    _expectKeyring(moved, 'the store for a second application');

    if (phase == 1) {
      await _first(wired, moved, wiredLegacy, movedLegacy, state, canaries);
    } else {
      await _second(wired, moved, wiredLegacy, movedLegacy, state, canaries);
    }
    return _result();
  }

  Future<void> _first(DVAppKeyStore wired, DVAppKeyStore moved, String wiredLegacy, String movedLegacy,
      Directory state, File canaries) async {
    // A clean start: a key left by an earlier run on this device would turn
    // "made" into "found".
    await wired.clear();
    await moved.clear();

    // Where an earlier Dartvel kept the key, written the way it wrote it.
    final Uint8List old = DVAppKey.generate();
    _plant(movedLegacy, old);
    Uint8List? oldWired;
    try {
      final Uint8List planted = DVAppKey.generate();
      _plant(wiredLegacy, planted);
      oldWired = planted;
      facts['wiredLegacy'] = 'planted at $wiredLegacy';
    } on FileSystemException catch (error) {
      // Where the old path cannot be written, no earlier version could have
      // kept a key there either; the second application covers the move.
      facts['wiredLegacy'] = 'not writable in this process: ${error.osError?.message ?? error.message}';
    }

    final Uint8List a = await DVAppKey.ensure(wired);
    if (oldWired != null) {
      check(_same(a, oldWired), 'the wired store replaced the key at $wiredLegacy instead of moving it in');
      check(!File(wiredLegacy).existsSync(), 'the old key file $wiredLegacy was not removed after the move');
    }
    final Uint8List b = await DVAppKey.ensure(moved);
    check(_same(b, old), 'the key at $movedLegacy was replaced instead of moved in');
    check(!File(movedLegacy).existsSync(), 'the old key file $movedLegacy was not removed after the move');

    final Uint8List? fresh = await (await dvAppKeyStoreFor(_movedApp, home: state.path)).read();
    check(fresh != null && _same(fresh, b), 'a store made afresh in the same process read a different key');

    canaries.writeAsStringSync(
      jsonEncode(<String, String>{
        'wired': DVAppKeyCipher(a).encrypt(_canary),
        'moved': DVAppKeyCipher(b).encrypt(_canary),
      }),
      flush: true,
    );
    await _custody(wired);
    _scan(<Uint8List>[a, b, old, if (oldWired != null) oldWired]);
  }

  Future<void> _second(DVAppKeyStore wired, DVAppKeyStore moved, String wiredLegacy, String movedLegacy,
      Directory state, File canaries) async {
    final Map<String, dynamic> sealed = jsonDecode(canaries.readAsStringSync()) as Map<String, dynamic>;
    final Uint8List? a = await wired.read();
    final Uint8List? b = await moved.read();
    check(a != null, 'after the restart the wired store held no key');
    check(b != null, 'after the restart the second store held no key');
    if (a != null) {
      check(DVAppKeyCipher(a).decrypt(sealed['wired'] as String) == _canary,
          'after the restart the wired store gave back a different key');
    }
    if (b != null) {
      check(DVAppKeyCipher(b).decrypt(sealed['moved'] as String) == _canary,
          'after the restart the second store gave back a different key');
    }
    check(!File(wiredLegacy).existsSync() && !File(movedLegacy).existsSync(),
        'an old key file was back after the restart');
    await _custody(wired);
    _scan(<Uint8List>[if (a != null) a, if (b != null) b]);

    // Leave the device as it was found.
    await wired.clear();
    await moved.clear();
    state.deleteSync(recursive: true);
  }

  /// What the keyring itself says about the key, asked of the platform.
  Future<void> _custody(DVAppKeyStore wired) async {
    if (wired is! DVMigratingAppKeyStore) return;
    final DVAppKeyStore keyring = wired.keyring;
    if (keyring is DVKeychainAppKeyStore) {
      final Map<String, Object?>? attributes = await keyring.debugItemAttributes();
      facts['keychain$phase'] = attributes;
      check(attributes != null, 'the Keychain has no item for the key');
      check(attributes?['accessible'] == DVKeychainAppKeyStore.accessibleAfterFirstUnlockThisDeviceOnly,
          'the Keychain item is not after-first-unlock, this device only: ${attributes?['accessible']}');
      check(attributes?['synchronizable'] != true, 'the Keychain item synchronizes');
    } else if (keyring is DVAndroidKeystoreAppKeyStore) {
      final Map<String, Object?> keystore = await keyring.debugKeystoreFacts();
      facts['keystore$phase'] = keystore;
      check(keystore['entry'] == true, 'the Android Keystore holds no entry for the key');
      check(keystore['exportable'] == false, 'the Keystore key hands out its bytes');
      final String? path = keyring.sealedPath;
      final bool there = path != null && File(path).existsSync();
      check(there, 'no sealed key at $path');
      if (there) {
        check(dvAndroidOpenKeyBlob(File(path).readAsStringSync()) != null, 'the file at $path is not a sealed key');
      }
    }
  }

  void _expectKeyring(DVAppKeyStore store, String what) {
    check(store is! DVFileAppKeyStore, '$what is the file store');
    if (store is! DVMigratingAppKeyStore) {
      failures.add('$what is ${store.runtimeType}, not a keyring store');
      return;
    }
    if (Platform.isAndroid) {
      check(store.keyring is DVAndroidKeystoreAppKeyStore,
          '$what keeps its key in ${store.keyring.runtimeType}, not the Android Keystore');
    }
    if (Platform.isIOS) {
      check(store.keyring is DVKeychainAppKeyStore,
          '$what keeps its key in ${store.keyring.runtimeType}, not the Keychain');
    }
  }

  /// The application's own data directory: the container on iOS, the
  /// directory above no_backup on Android.
  Directory _dataRoot(DVAppKeyStore wired) {
    final String? home = dvHostHome();
    if (Platform.isIOS && home != null) return Directory(home);
    if (wired is DVMigratingAppKeyStore && wired.keyring is DVAndroidKeystoreAppKeyStore) {
      final String? sealed = (wired.keyring as DVAndroidKeystoreAppKeyStore).sealedPath;
      // <data>/no_backup/dartvel-keys/<app>.sealed
      if (sealed != null) return File(sealed).parent.parent.parent;
    }
    return Directory.systemTemp.parent;
  }

  static void _plant(String path, Uint8List key) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(base64Encode(key), flush: true);
  }

  void _scan(List<Uint8List> keys) {
    final List<List<int>> needles = <List<int>>[
      for (final Uint8List key in keys) ...<List<int>>[key, utf8.encode(base64Encode(key))],
    ];
    final String? home = dvHostHome();
    final List<Directory> places = <Directory>[
      root,
      if (home != null && !root.path.startsWith(home) && !home.startsWith(root.path)) Directory(home),
    ];
    int scanned = 0;
    final Set<String> found = <String>{};
    for (final Directory place in places) {
      _walk(place, (File file) {
        scanned++;
        final Uint8List bytes = file.readAsBytesSync();
        for (final List<int> needle in needles) {
          if (_contains(bytes, needle)) found.add(file.path);
        }
      });
    }
    facts['scanned$phase'] = scanned;
    check(scanned > 0, 'the scan read no files under ${root.path}, so it showed nothing');
    check(found.isEmpty, 'key material in plain files: ${found.join(', ')}');
  }

  static void _walk(Directory dir, void Function(File) visit) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entry in entries) {
      if (entry is Directory) {
        _walk(entry, visit);
      } else if (entry is File) {
        try {
          if (entry.lengthSync() <= _scanLimitBytes) visit(entry);
        } on FileSystemException {
          // Unreadable to this process, and so not somewhere it wrote.
        }
      }
    }
  }

  static bool _contains(Uint8List haystack, List<int> needle) {
    final int last = haystack.length - needle.length;
    for (int i = 0; i <= last; i++) {
      if (haystack[i] != needle[0]) continue;
      int j = 1;
      while (j < needle.length && haystack[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return true;
    }
    return false;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

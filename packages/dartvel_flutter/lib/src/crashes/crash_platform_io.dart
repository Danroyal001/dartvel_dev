/// Crash hooks and storage where there is dart:io.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../platform/device_runtime.dart';
import 'crash_directory.dart';
import 'crash_hook.dart';

/// Listens to this isolate's uncaught errors.
///
/// The listener carries text, and it arrives through a port — after the
/// fact, and only when the isolate survives the error. Flutter delivers a
/// root-zone error to `PlatformDispatcher.onError` first, synchronously;
/// this catches what gets past that, and the installation records an error
/// that arrives at both once.
void Function() dvInstallPlatformCrashHooks(DVCrashTextReceiver receive) {
  final RawReceivePort port = RawReceivePort((Object? message) {
    if (message is List && message.isNotEmpty) {
      receive(
        '${message[0]}',
        message.length > 1 && message[1] != null ? '${message[1]}' : '',
        DVCrashHook.isolate,
      );
    }
  })
    // A listener must not be the reason the process stays up.
    ..keepIsolateAlive = false;
  Isolate.current.addErrorListener(port.sendPort);
  return () {
    Isolate.current.removeErrorListener(port.sendPort);
    port.close();
  };
}

String? _directory(String appId) => dvCrashDirectoryFor(
      appId: appId,
      os: Platform.operatingSystem,
      environment: Platform.environment,
      androidStateDirectory: DVDeviceRuntime.stateDirectory,
    );

DVCrashStore? dvDefaultCrashStore(String appId) {
  final String? directory = _directory(appId);
  return directory == null ? null : DVFileCrashStore(directory);
}

/// Kept beside the crash records, so clearing the application's data resets
/// both together.
String dvInstallId(String appId) {
  final String? directory = _directory(appId);
  if (directory == null) {
    return dvInstallIdFrom(read: () => null, write: (String _) {});
  }
  final File file = File('$directory/install-id');
  return dvInstallIdFrom(
    read: () => file.existsSync() ? file.readAsStringSync() : null,
    write: (String id) {
      Directory(directory).createSync(recursive: true);
      file.writeAsStringSync(id, flush: true);
    },
  );
}

bool dvHostedByTestRunner() => Platform.environment['FLUTTER_TEST'] == 'true';

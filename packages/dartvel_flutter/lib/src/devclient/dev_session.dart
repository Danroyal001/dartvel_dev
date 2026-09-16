/// The Dart half of a development build's pairing with `dartvel dev`.
///
/// The development entrypoint calls [DVDevClientSession.start] before the
/// application's own `main`. It hands this app's Dart VM service URI to the
/// native code the build wrote -- Java on Android over JNI; Objective-C on iOS
/// and macOS, and C++ on Linux, over FFI -- which holds the pairing link and
/// runs the tunnel the dev server reaches the VM service through. The tunnel
/// is native because a hot restart kills every Dart isolate, and the restart
/// travels over it.
library;

import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:dartvel_core/dartvel.dart' show DVDevServerHost;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:jni/jni.dart';

abstract final class DVDevClientSession {
  /// The class `dartvel build android --profile development` writes, in JNI's
  /// form. The CLI's tests assert it is the same string the build uses.
  static const String androidClass = 'dev/dartvel/devclient/DartvelDevClient';

  /// The C functions `dartvel build ios|macos|linux --profile development`
  /// writes.
  /// The CLI's tests assert they are the names the build uses.
  static const String appleVmServiceSymbol = 'dartvel_dev_client_vm_service';
  static const String appleServerHostSymbol = 'dartvel_dev_client_server_host';

  /// What the last [start] found, for a dev menu or a log.
  static String? lastStatus;

  /// Registers this app's VM service with the build's tunnel.
  ///
  /// Never throws: a development build whose tunnel cannot start is still an
  /// application, and the status says why.
  static Future<String> start() async {
    final String status = await _start();
    lastStatus = status;
    debugPrint('[dartvel] dev client: $status');
    return status;
  }

  static Future<String> _start() async {
    if (kReleaseMode || kProfileMode) {
      return 'not a development build, so there is nothing to pair';
    }
    if (kIsWeb ||
        !(Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isLinux)) {
      return 'no dev client on this platform; a development build pairs on '
          'Android, iOS, macOS and Linux';
    }
    // The VM service can still be starting when main runs; waited for
    // briefly rather than reported missing.
    Uri? vmService = (await developer.Service.getInfo()).serverUri;
    for (int i = 0; vmService == null && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      vmService = (await developer.Service.getInfo()).serverUri;
    }
    if (vmService == null) {
      return 'this build is running without a Dart VM service, so dartvel dev '
          'cannot reload it';
    }
    if (!Platform.isAndroid) return _startNative(vmService);
    final JClass client;
    try {
      client = JClass.forName(androidClass);
    } on Object catch (error) {
      return 'the class $androidClass is not in this build ($error). It is '
          'written by `dartvel build android --profile development`; an APK '
          'built with plain `flutter build` does not have it.';
    }
    try {
      final JString? answer = client
          .staticMethodId('vmService', '(Ljava/lang/String;)Ljava/lang/String;')
          .callNullable(client, JString.type, <dynamic>[
            vmService.toString().toJString(),
          ]);
      final JString? host = client
          .staticMethodId('serverHost', '()Ljava/lang/String;')
          .callNullable(client, JString.type, const <dynamic>[]);
      if (host != null) {
        DVDevServerHost.current = host.toDartString(releaseOriginal: true);
      }
      return answer?.toDartString(releaseOriginal: true) ?? 'started';
    } on Object catch (error) {
      return '$androidClass is present but did not start the tunnel ($error)';
    }
  }

  static String _startNative(Uri vmService) {
    final DynamicLibrary process = DynamicLibrary.process();
    if (!process.providesSymbol(appleVmServiceSymbol)) {
      return 'the tunnel is not in this build (no $appleVmServiceSymbol). It '
          'is written by `dartvel build ios|macos|linux --profile development`; an '
          'app built with plain `flutter build` does not have it.';
    }
    final Pointer<Utf8> Function(Pointer<Utf8>) start = process
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >(appleVmServiceSymbol);
    final Pointer<Utf8> uri = vmService.toString().toNativeUtf8();
    try {
      final Pointer<Utf8> status = start(uri);
      if (process.providesSymbol(appleServerHostSymbol)) {
        final Pointer<Utf8> host = process
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              appleServerHostSymbol,
            )();
        if (host != nullptr) DVDevServerHost.current = host.toDartString();
      }
      return status == nullptr ? 'started' : status.toDartString();
    } finally {
      malloc.free(uri);
    }
  }
}

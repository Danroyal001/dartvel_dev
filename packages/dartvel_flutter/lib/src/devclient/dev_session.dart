/// The Dart half of a development build's pairing with `dartvel dev`.
///
/// The development entrypoint calls [DVDevClientSession.start] before the
/// application's own `main`. It hands this app's Dart VM service URI to the
/// Java the build wrote, which holds the pairing link and runs the tunnel the
/// dev server reaches the VM service through. The tunnel is Java because a hot
/// restart kills every Dart isolate, and the restart travels over it.
library;

import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:dartvel_core/dartvel.dart' show DVDevServerHost;
import 'package:flutter/foundation.dart';
import 'package:jni/jni.dart';

abstract final class DVDevClientSession {
  /// The class `dartvel build android --profile development` writes, in JNI's
  /// form. The CLI's tests assert it is the same string the build uses.
  static const String androidClass = 'dev/dartvel/devclient/DartvelDevClient';

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
    if (kIsWeb || !Platform.isAndroid) {
      return 'no dev client on this platform; a development build pairs on '
          'Android';
    }
    final Uri? vmService = (await developer.Service.getInfo()).serverUri;
    if (vmService == null) {
      return 'this build is running without a Dart VM service, so dartvel dev '
          'cannot reload it';
    }
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
}

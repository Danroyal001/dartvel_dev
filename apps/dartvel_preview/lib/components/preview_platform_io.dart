import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:jni/jni.dart';

/// A development build pairs on these; a profile or release build has no
/// tunnel and no Dart VM service to attach to.
bool get previewRunsCode =>
    kDebugMode &&
    (Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isIOS);

/// A native Preview has no web view: the web build opens in the browser.
bool get previewShowsWeb => false;

/// The class `dartvel build android --profile development` writes.
const String _androidClient = 'dev/dartvel/devclient/DartvelDevClient';

Future<String> previewPair(Uri pairing) async {
  final String link = pairing.toString();
  if (Platform.isAndroid) {
    // The same call the build's own link activity makes when a camera opens
    // a dartvel-dev:// link: the tunnel takes the link and dials the server.
    // No Context: the link is not kept past this run of the app.
    final JClass client = JClass.forName(_androidClient);
    client
        .staticMethodId('pair', '(Landroid/content/Context;Ljava/lang/String;)V')
        .call(client, jvoid.type, <dynamic>[null, link.toJString()]);
    return 'Pairing. When dartvel dev attaches, this app restarts into the '
        'project.';
  }
  // On a desktop the tunnel reads the link from the command line when the
  // process starts, as it does for any development build. So Preview starts
  // itself again with the link and leaves: the new process pairs, and
  // dartvel dev restarts it into the project.
  await Process.start(
    Platform.resolvedExecutable,
    <String>[link],
    mode: ProcessStartMode.detached,
  );
  exit(0);
}

Widget previewWebFrame(Uri url) => const SizedBox.shrink();

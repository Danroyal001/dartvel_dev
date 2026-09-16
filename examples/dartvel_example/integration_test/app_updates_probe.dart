// A release build that updates itself through DV.Updates.
//
// Built twice by the OTA workflow with Shorebird's engine: once as the release,
// once with [probeVersion] changed to make the patch. Launched, it checks for a
// patch and applies it; launched again, it should be the patch. Everything it
// does is printed with an OTA-PROBE prefix, which is what the device check
// reads. See tool/ci/android_ota_check.dart.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

const String probeVersion = 'OTA-PROBE-ONE';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool registered = DVShorebirdUpdates.register();
  debugPrint(
    'OTA-PROBE running $probeVersion registered=$registered'
    '${registered ? '' : ' (${DVShorebirdUpdates.lastFailure})'}',
  );
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text(probeVersion))),
    ),
  );
  if (!registered) return;
  try {
    final DVUpdateInfo update = await const DVUpdates().check();
    debugPrint(
      'OTA-PROBE check available=${update.available} ${update.metadata}',
    );
    if (update.available && update.metadata['restartRequired'] != 'true') {
      await const DVUpdates().apply(update: update);
      debugPrint('OTA-PROBE apply installed');
    }
  } on Object catch (error) {
    debugPrint('OTA-PROBE error $error');
  }
}

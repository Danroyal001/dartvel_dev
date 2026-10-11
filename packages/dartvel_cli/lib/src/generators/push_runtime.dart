/// The push wiring in the generated client runtime.
///
/// `dartvel.push` declares which targets receive push; this is the Dart the
/// runtime gets for it: the provider registered with `PushNotifications` and
/// started. Started, not prompted: the permission is the application asking
/// from a tap, never a side effect of launching.
library dartvel_cli.generators.push_runtime;

import 'package:dartvel_core/dartvel.dart' show DVPushConfig;

/// The names the generated runtime's `dartvel_flutter` import must show.
String dvPushRuntimeImports(DVPushConfig config) =>
    config.isDeclared ? ' PushNotifications, DVDevicePushProvider,' : '';

/// The statement that starts push, in the body of the runtime's startup.
String dvPushRuntimeCall(DVPushConfig config) => config.isDeclared
    ? '  // dartvel.push: this target\'s push provider, started without a prompt.\n'
        '  startDartvelPush();\n'
    : '';

/// The function the call above names; empty when nothing is declared.
String dvPushRuntimeFunction(DVPushConfig config) => dvPushRuntimeFunctionFor(
      webKey: config.web?.vapidPublicKey,
      android: config.androidFcm != null,
    );

/// As [dvPushRuntimeFunction], from the two facts it depends on.
String dvPushRuntimeFunctionFor({String? webKey, required bool android}) {
  if (webKey == null && !android) return '';
  final String condition = <String>[
    if (webKey != null) 'kIsWeb',
    if (android) '(!kIsWeb && defaultTargetPlatform == TargetPlatform.android)',
  ].join(' || ');
  final String key = webKey == null
      ? ''
      : "\n    // The public half of the VAPID key: what a browser subscribes with.\n"
          "    vapidPublicKey: ${_dartString(webKey)},";
  return '''
/// Registers this target's push provider and starts it, for the targets
/// `dartvel.push` names. Asks for no permission: `PushNotifications
/// .requestPermission()` is for the application to call from a tap, because
/// a prompt at launch is how the permission is lost for good.
void startDartvelPush() {
  if (!($condition)) return;
  PushNotifications.setProvider(DVDevicePushProvider($key
  ));
  unawaited(PushNotifications.initialize());
}

''';
}

String _dartString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

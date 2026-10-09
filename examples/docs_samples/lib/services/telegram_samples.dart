import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start telegram-status
Widget telegramStatus(BuildContext context) {
  final telegram = DV.Platform.telegram;
  if (telegram == null) return const DVText('Open in Telegram');
  final theme = telegram.theme.watch(context);
  final viewport = telegram.viewport.watch(context);
  return DVText(
    'Theme: ${theme.dark ? 'dark' : 'light'}, height: ${viewport.height}',
  );
}
// docs:end

// docs:start telegram-controls
Future<void> telegramContinue() async {
  final telegram = DV.Platform.telegram;
  if (telegram == null) return;
  await telegram.mainButton.set(text: 'Continue', visible: true);
  await telegram.haptics.impact(.light);
}
// docs:end

// docs:start telegram-auth
Future<void> telegramSignIn() async {
  await DV.Auth.signInWithProvider('telegram');
}
// docs:end

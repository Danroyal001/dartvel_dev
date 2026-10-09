import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Telegram Mini Apps',
  description: 'Build a Dartvel app for Telegram, use host controls and sign in with server-verified Telegram credentials.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsTelegramPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docstelegram,
  lead: <String>[
    'Your existing Dartvel pages run inside Telegram. The target uses the same web renderer, typed routes and accessible page shell.',
    'Telegram controls are available through DV.Platform.telegram; ordinary browsers and native apps return null.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'build',
      title: 'Build and develop',
      children: <Widget>[
        DocsShell(<String>[
          'dartvel build telegram',
          'dartvel dev telegram',
          'dartvel build web-server',
        ]),
        DocsText(
          'The Telegram target writes build/web and loads Telegram’s official SDK before Flutter starts. A web-server build loads the same SDK when dartvel.telegram is configured, serving each page at its own URL.',
        ),
        DocsShell(<String>[
          'dartvel:',
          '  telegram:',
          '    botUsername: example_bot',
          '    shortName: shop',
          '    requiredPermissions: [contact, write]',
        ]),
        DocsText(
          'DartvelConfig.telegram exposes the same values as a DVTelegramConfig. Permissions describe what your app needs; ask for consent with requestContact or requestWriteAccess from a user action.',
        ),
      ],
    ),
    DocsSection(
      id: 'botfather',
      title: 'Connect the app in BotFather',
      children: <Widget>[
        Bullets(<String>[
          'Create a bot with /newbot in @BotFather. Keep its token on your server.',
          'Use /newapp to register a named Mini App and its HTTPS URL, or configure the main Mini App under /mybots → Bot Settings → Configure Mini App.',
          'Set the menu button with /setmenubutton and your HTTPS app URL.',
          'A named app opens at https://t.me/example_bot/shop. Add ?startapp=your-value for a launch parameter.',
          'Host build/web on an HTTPS web host, or serve a web-server binary. Dartvel does not register or publish the bot for you.',
        ]),
      ],
    ),
    DocsSection(
      id: 'platform',
      title: 'Read the Telegram host',
      children: <Widget>[
        DocsCode('telegram-status'),
        DocsCode('telegram-controls'),
        DocsText(
          'The page shell calls ready and expand at startup, applies safe-area padding and updates the app’s colors when Telegram changes theme. The host BackButton follows the router’s back stack.',
        ),
        Bullets(<String>[
          'mainButton, secondaryButton, backButton and settingsButton expose show/hide and click streams. Bottom buttons also expose text, colors, progress and active state.',
          'cloudStorage, deviceStorage and secureStorage expose asynchronous get, set, delete and clear calls. Unsupported host APIs throw UnsupportedError; storage errors are reported by the host.',
          'openLink, openTelegramLink, shareMessage, shareToStory, requestContact and requestWriteAccess use Telegram’s native flows.',
          'scanQr emits qrTexts; closeQrScanner closes the scanner. openInvoice returns the final invoice status.',
          'requestFullscreen, exitFullscreen, lockOrientation, unlockOrientation, addToHomeScreen, checkHomeScreenStatus and close control the host window.',
        ]),
      ],
    ),
    DocsSection(
      id: 'auth',
      title: 'Sign in and accept Stars payments',
      children: <Widget>[
        DocsShell(<String>[
          'export TELEGRAM_BOT_TOKEN="your-server-only-bot-token"',
        ]),
        DocsCode('telegram-auth'),
        DocsText(
          'The configured generated backend verifies initData with HMAC-SHA256 and accepts credentials up to five minutes old. The existing auth endpoint issues a Dartvel session. Explicitly installed auth providers are preserved. The token belongs in the server environment or secret store, never pubspec, a dart-define or client code.',
        ),
        DocsText(
          'user and initDataUnsafe originate on the client and cannot authorize access. Sign in first. For digital goods create a Stars invoice on the backend using currency XTR, then pass its HTTPS URL to openInvoice. A paid UI status is not proof of fulfillment: verify the bot’s successful_payment update on the server before delivering goods.',
        ),
      ],
    ),
    DocsSection(
      id: 'testing',
      title: 'Test the complete flow',
      children: <Widget>[
        Bullets(<String>[
          'A normal browser has no Telegram host. Use a mocked window.Telegram.WebApp for controls, callbacks, live theme and viewport tests.',
          'Use a separate bot in Telegram’s test environment and register its test URL in the test BotFather. The test environment permits HTTP; production requires HTTPS.',
          'On iOS tap Settings ten times, then Accounts → Login to another account → Test. On Telegram Desktop use Settings, then Shift + Alt + right-click Add Account and select Test Server.',
          'Open from the bot menu or a direct Mini App link to receive signed initData. Keyboard-button and inline launches may have no initData and cannot use this sign-in flow.',
          'Check the app in Telegram on supported client versions before shipping. Mock-browser evidence does not verify live bot payments, native storage encryption or device dialogs.',
        ]),
        DocsText('Reference: https://core.telegram.org/bots/webapps'),
      ],
    ),
  ],
);

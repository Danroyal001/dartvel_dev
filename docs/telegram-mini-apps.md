# Telegram Mini Apps

> **`telegram` is a paid target** from the release after 0.11.5: `dartvel build
> telegram` and `dartvel dev telegram` come with any Dartvel Cloud plan through
> the private `dartvel_targets_pro` package (`dartvel targets add pro`). The
> runtime API below is still part of the free framework, so a web build can
> load Telegram's SDK itself; the free CLI no longer adds it.

`dartvel build telegram` compiles the application's ordinary web renderer and
writes `build/web`. `dartvel dev telegram` runs the Flutter web-server device
with the official Telegram SDK in the existing web shell. Every page retains
its typed route, selection, keyboard navigation and browser find support.

Declare public metadata in `pubspec.yaml`:

```yaml
dartvel:
  telegram:
    botUsername: example_bot
    shortName: shop
    requiredPermissions: [contact, write]
```

The generated client exports `DartvelConfig.telegram`, a `DVTelegramConfig`.
Unknown fields, including bot tokens, are refused. Required permissions are
metadata: request contact/write consent from a user action. Before the
target moved, declaring this section also put the SDK into `dartvel build web`
and `web-server` output; the free CLI no longer does, and plain web builds
never install it.

Create a bot in [BotFather](https://t.me/BotFather), then use `/newapp` to register
a named Mini App, or configure the main Mini App under `/mybots`. Set the menu
URL with `/setmenubutton`. Production URLs must use HTTPS. A named app opens at
`https://t.me/example_bot/shop`; `?startapp=value` passes a launch parameter.
Building does not register the bot, publish the app or send any messages.

## Host API

`DV.Platform.telegram` is null outside Telegram. In Telegram it exposes:

- `user`, `initData`, `platform` and `version`;
- `mainButton`, `secondaryButton`, `backButton`, `settingsButton`, with click
  streams and show/hide; bottom buttons support configuration and progress;
- `haptics.impact`, `notification` and `selectionChanged`;
- `cloudStorage`, `deviceStorage`, `secureStorage`: `get`, `set`, `delete`, `clear`;
- `openLink`, `openTelegramLink`, `shareMessage`, `shareToStory`, `requestContact`,
  `requestWriteAccess`, `scanQr`, `qrTexts`, `closeQrScanner`, `openInvoice`;
- `requestFullscreen`, `exitFullscreen`, `lockOrientation`, `unlockOrientation`,
  `addToHomeScreen`, `checkHomeScreenStatus`, `close`;
- `theme` and `viewport` signals: read `.value`, subscribe to `.changes`, or use
  `.watch(context)` to rebuild a widget automatically.

The framework calls `ready()`/`expand()` at startup. Its page shell applies
host colors to the app theme while preserving typography and layout, follows
host theme/inset events, and pads each page by the device safe area plus
Telegram's content safe area (which Telegram measures from the safe area's
edges), filling both with the host background. The Telegram back
button follows the router's push stack. Unsupported methods throw
`UnsupportedError`; asynchronous host callbacks surface errors and time out
after two minutes rather than remaining pending forever.

## Authentication and payments

Set `TELEGRAM_BOT_TOKEN` only on the backend. A server built with the
`telegram` section refuses to start without it, rather than running with a
sign-in that cannot verify anyone. A configured generated server
installs the Telegram auth provider unless the application installed its own.
Call `DV.Auth.signInWithProvider('telegram')` from the client. The existing
CSRF-protected sign-in endpoint validates raw initData with HMAC-SHA256 and a
five-minute freshness window, then issues a normal Dartvel session. It rejects
malformed/duplicate fields, tampering, wrong tokens, expired data and future
authentication dates. Telegram does not attest to an email address.

Never authorize access using the client-side `user`: verify initData first.
Keyboard-button and inline launches may provide no initData, so those launches
cannot use this sign-in flow. A custom server can install
`DVTelegramAuthProvider` from `dartvel_shelf`, configuring its validator's
freshness limit or secret source there.

For digital goods, create a Stars invoice on the backend with currency `XTR`
and open its HTTPS URL with `openInvoice`. The returned status drives the UI;
fulfillment requires the bot's verified `successful_payment` update. This
feature opens invoices; it does not implement a bot payment webhook or invoice
creation service.

## Testing and limits

Use a mocked `window.Telegram.WebApp` in a real browser to verify integration.
Use a separate test bot and the test BotFather in Telegram's test environment
for native host dialogs, storage and payments. That environment permits HTTP;
production requires HTTPS. Current setup and client-specific switching steps
are in [Telegram's testing reference](https://core.telegram.org/bots/webapps#testing-mini-apps).

Mocked browser verification does not establish native encryption, a live
payment, bot registration or behavior on every Telegram client version. See
[build target evidence](build-targets.md) for commands and inspected artifacts.

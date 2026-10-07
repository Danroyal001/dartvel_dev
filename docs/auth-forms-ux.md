# Authentication and form UX

Prebuilt email/password sign-in, sign-up and second-factor pages use the application's Material theme. At 720 logical pixels and above they show a brand panel beside the form. Smaller windows use a scrolling form, including watch-sized windows. Account pages use the same frame.

Configure identity in `pubspec.yaml`:

```yaml
dartvel:
  pwa:
    name: Harvest
    icon: assets/harvest.png
  auth:
    tagline: Good food, together.
    heroImage: assets/garden.png
    brandPanelColor: '#21664B'
```

Images are Flutter assets: include them in `flutter.assets`. The panel color accepts six-digit RGB hex; omitted colors and typography come from the app theme. `auth.pages` continues to configure or disable account routes. Generated sign-in and sign-up links follow those configured routes and preserve the `from` query. Both pages validate the return destination as an internal path.

For a custom panel, import your generated `dartvel_client/dartvel_client.dart` barrel and set `DV.Auth.appearance` before constructing the app:

```dart
DV.Auth.appearance = DVAuthAppearance(
  name: 'Harvest',
  brandPanelBuilder: (context) => const HarvestWelcomePanel(),
);
```

An application-supplied appearance wins over generated defaults. The custom panel is used at wide sizes; its name is also shown on compact screens.

Email fields use email keyboards and autofill hints. Passwords distinguish current and new passwords, with a reveal control. Next moves through the fields; Done submits the last field. Multiline data-model fields keep Enter as a newline.

`Article.Form()` creates; `article.Form()` edits. Both save automatically. The shared form awaits asynchronous saves, shows progress, prevents another submission or reset while pending, keeps edits after a failure, and announces the error. Auth requests likewise show disabled pending buttons and live error messages; provider exceptions are not displayed verbatim.

There is no public forgot-password/reset endpoint in the current framework. The security page lets a signed-in person change their password; that is not account recovery.

## Current server-rendering limitation

The existing shared renderer captures semantics into a fallback document. It does not yet capture interactive form actions or the full Material layout. These runtime UX changes do **not** establish Enter submission before Flutter loads, themed server/Flutter visual parity, or a flash-free handoff. Those requirements need changes to the shared rendering contract and browser verification. Do not describe this slice as production-ready until that work is verified.

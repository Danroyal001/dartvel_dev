# dartvel_meta_pixel

Meta (Facebook) Pixel for [Dartvel](https://dartvel.dev) applications: page
views and events in the browser, the same events through your backend to the
Conversions API, counted once.

A first-party Dartvel module. It lives in
[`modules/`](https://github.com/Danroyal001/dartvel_dev/tree/main/modules) of
the Dartvel repository and is released with the framework.

## Add it

```bash
dartvel add meta-pixel
```

That writes the dependency and the mount. Give it your pixel id:

```yaml
dartvel:
  modules:
    metaPixel:
      package: dartvel_meta_pixel
      backendPolicy: public
      config:
        pixelId: "1234567890"
```

and, for the Conversions API, the access token in the **server's**
environment (`.env` in development, your host's secrets in production):

```
META_CONVERSIONS_API_TOKEN=...
```

The token is never a setting. A mount's `config:` is compiled into the
client, so `accessToken:` there is refused by name.

## What it does without being called

- **Page views.** The first page and every route change send `PageView`.
  The page shell reports them; no page calls anything.
- **Purchases**, when a store module such as `dartvel_woocommerce` is
  mounted: the store publishes a purchase when the payment is confirmed, and
  this module reports `Purchase` from the backend, and from the buyer's
  browser when it learns the order is paid, both with the event id
  `purchase.<order id>`.

## Events

```dart
DV.Modules.metaPixel.viewContent(contentName: 'Pricing');
DV.Modules.metaPixel.lead(contentName: 'Callback form');
DV.Modules.metaPixel.contact();
DV.Modules.metaPixel.initiateCheckout(value: 45000, currency: 'NGN', numItems: 1);
DV.Modules.metaPixel.purchase(value: 45000, currency: 'NGN', eventId: 'order-981');
DV.Modules.metaPixel.trackCustom('BookedDemo', data: {'plan': 'pro'});
DV.Modules.metaPixel.track(MetaPixelEvent('Schedule'));
```

A tap that leaves the application, such as a WhatsApp button:

```dart
.onTap(() {
  DV.Modules.metaPixel.outboundClick(whatsApp);   // a Contact
  openLink(whatsApp);   // however the application opens a link
})
```

A WhatsApp link, a phone number or an email address is a `Contact`. Pass
`event: MetaPixelEvent.lead()` to report it as a `Lead` instead. Any other
link is a custom `OutboundClick` with the destination, without its query.

Every call is safe anywhere: with no pixel id, before consent, with the
pixel's script blocked or the network down, it does nothing and does not
throw.

## Where an event goes

| Called from | Browser pixel (`fbq`) | Conversions API |
|---|---|---|
| A browser | yes | yes, through your backend, same `event_id` |
| A device (Android, iOS, desktop, TV) | no | yes, through your backend |
| Your backend | no | yes, directly |

Meta counts a browser event and a server event once when their name and id
match, so an in-app browser that blocks the pixel still reports through the
server. A client's event reaches your backend at
`<apiBasePath>/_dv/modules/metaPixel/collect`, which is why the mount names a
`backendPolicy`. That route accepts an event name, a web address, up to 4 KB
of parameters and the `_fbp`/`_fbc` cookies, and nothing else; the backend
adds the caller's address and user agent from the request.

On the backend there is no page, so say who and where:

```dart
await DV.Modules.metaPixel.track(
  MetaPixelEvent.lead(),
  user: MetaUserData(email: lead.email, phone: lead.phone),
  sourceUrl: Uri.parse('https://example.com/contact'),
);
```

`MetaUserData` normalises and SHA-256 hashes the email, phone, names, city,
country and postcode as Meta requires, and sends the address, user agent,
`fbp` and `fbc` unhashed, as Meta requires.

## Consent

The application decides whether consent is required, by declaring a policy:

```yaml
dartvel:
  analytics:
    consent:
      version: "2026-11-01"
      categories:
        essential: { required: true }
        marketing: { default: denied, tracking: true }
```

- **With a policy**, nothing is loaded or sent until the module's category
  is granted: not the pixel's script, not a server event. The category is
  `marketing` unless `config.consent` names another. A category the policy
  does not declare is never granted, and the module says so once in the log.
  When consent is withdrawn the pixel is told (`fbq('consent', 'revoke')`)
  and events stop.
- **With no policy**, the application has not asked for consent to be
  required and the module sends from the first page. This is the default.

A Global Privacy Control signal is honoured for a `tracking: true` category
by the framework, and by the backend route for a client that sent the event
anyway.

## Content-Security-Policy

Nothing to edit. The module declares the origins the pixel needs and the
build adds them to your `dartvel.security.pageCsp`: `script-src
https://connect.facebook.net`, and `connect-src` and `img-src
https://www.facebook.com`. The pixel's base code is served from your own
origin as a file, so no `'unsafe-inline'` is needed. With no page policy
declared, none is sent and nothing is added.

## Settings

Under `dartvel.modules.metaPixel.config`, or as `MetaPixelConfig` passed to
`DV.Modules.metaPixel.configure(...)`:

| Setting | Default | |
|---|---|---|
| `pixelId` | none | The pixel's id. Without it the module does nothing. The server also reads `META_PIXEL_ID`. |
| `consent` | `marketing` | The consent category to wait for. |
| `serverEvents` | `true` | Send a client's events through the backend to the Conversions API. |
| `accessTokenSecret` | `META_CONVERSIONS_API_TOKEN` | The name of the environment variable holding the token. |
| `apiVersion` | `v27.0` | The Graph API version. |
| `testEventCode` | none | Events Manager's test code; unset it in production. |
| `excludePaths` | `[/__studio]` | Paths that are not page views. |

## Not covered

- App install attribution and SKAdNetwork: a device's events are sent with
  `action_source: other`, since Meta's `app` source needs app data this
  module does not collect. Use Meta's SDK for those.
- A visitor with JavaScript off sends no page view: there is no
  `<noscript>` image.

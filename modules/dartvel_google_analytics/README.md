# dartvel_google_analytics

Google Analytics 4 for [Dartvel](https://dartvel.dev) applications: Google's
tag in the browser, the Measurement Protocol from your backend and from
devices.

A first-party Dartvel module. It lives in
[`modules/`](https://github.com/Danroyal001/dartvel_dev/tree/main/modules) of
the Dartvel repository and is released with the framework.

## Add it

```bash
dartvel add google-analytics
```

That writes the dependency and the mount. Give it your measurement id:

```yaml
dartvel:
  modules:
    googleAnalytics:
      package: dartvel_google_analytics
      backendPolicy: public
      config:
        measurementId: G-XXXXXXXXXX
```

and, for the Measurement Protocol, the API secret in the **server's**
environment (Admin > Data streams > your stream > Measurement Protocol API
secrets):

```
GA4_API_SECRET=...
```

The secret is never a setting. A mount's `config:` is compiled into the
client, so `apiSecret:` there is refused by name.

**One setting in Google Analytics itself.** The module sends a `page_view`
for each route change. Turn off *Page changes based on browser history
events* under the web stream's Enhanced Measurement, or each route change is
counted twice. Or set `pageViews: automatic` and let Google's tag count them.

## What it does without being called

- **Page views.** The first page and every route change send `page_view`
  with `page_location` and `page_title`.
- **Purchases**, when a store module such as `dartvel_woocommerce` is
  mounted: the store publishes a purchase when the payment is confirmed, and
  this module reports `purchase` from the backend with the buyer's client
  and session ids, so it lands in the session they were in.

## Events

Google's recommended events, with its parameter names:

```dart
DV.Modules.googleAnalytics.generateLead(leadSource: 'contact form');
DV.Modules.googleAnalytics.beginCheckout(
  value: 45000,
  currency: 'NGN',
  items: [GoogleAnalyticsItem(itemId: 'SKU-1', itemName: 'Website audit', price: 45000, quantity: 1)],
);
DV.Modules.googleAnalytics.viewItem(items: [GoogleAnalyticsItem(itemName: 'Pro plan')]);
DV.Modules.googleAnalytics.signUp(method: 'email');
DV.Modules.googleAnalytics.login(method: 'google');
DV.Modules.googleAnalytics.track(GoogleAnalyticsEvent('booked_demo', params: {'plan': 'pro'}));
```

An event Google Analytics would silently drop is refused when it is made: a
reserved name or prefix, a name over 40 characters, more than 25 parameters.

Every call is safe anywhere: with no measurement id, before consent, with
Google's tag blocked or the network down, it does nothing and does not
throw.

## Where an event goes

| Called from | Google's tag (`gtag`) | Measurement Protocol |
|---|---|---|
| A browser | yes | no |
| A device (Android, iOS, desktop, TV) | no | yes, through your backend |
| Your backend | no | yes, directly |

One route only, because Google Analytics has no way to count an event sent
twice as one. A device's event reaches your backend at
`<apiBasePath>/_dv/modules/googleAnalytics/collect`, which is why the mount
names a `backendPolicy`; the route accepts an event Google Analytics would
accept, a client id and a session id, and nothing else.

On the backend an event needs the visitor's client id:

```dart
await DV.Modules.googleAnalytics.generateLead(clientId: lead.analyticsClientId);
```

A device has no tag to give it a client id, so each launch is a new visitor
unless the application supplies one it keeps:

```dart
DV.Modules.googleAnalytics.identify(clientId: installId, userId: user?.id);
```

`GoogleAnalyticsMeasurementProtocol(config).validate(...)` asks Google's
validation server what is wrong with an event; the Measurement Protocol
itself answers 2xx to a malformed one.

## Consent

The application decides whether consent is required, by declaring a policy
under `dartvel.analytics.consent`.

- **With a policy**, nothing is loaded or sent until the module's category
  is granted: not Google's tag, not a server event. The category is
  `product` unless `config.consent` names another. A category the policy
  does not declare is never granted, and the module says so once in the log.
  When consent is withdrawn the tag is told
  (`gtag('consent', 'update', {analytics_storage: 'denied'})`) and events
  stop.
- **With no policy**, the application has not asked for consent to be
  required and the module sends from the first page. This is the default.

## Content-Security-Policy

Nothing to edit. The module declares what Google's CSP guide lists for
Google Analytics without Ads features, and the build adds it to your
`dartvel.security.pageCsp`: `script-src https://www.googletagmanager.com`;
`img-src https://www.googletagmanager.com https://*.google-analytics.com`;
`connect-src https://www.googletagmanager.com https://*.google-analytics.com
https://*.google.com`. The two lines that define `gtag` are served from your
own origin as a file, so no `'unsafe-inline'` is needed. With no page policy
declared, none is sent and nothing is added.

## Settings

Under `dartvel.modules.googleAnalytics.config`, or as `GoogleAnalyticsConfig`
passed to `DV.Modules.googleAnalytics.configure(...)`:

| Setting | Default | |
|---|---|---|
| `measurementId` | none | The web stream's `G-` id. Without it the module does nothing. The server also reads `GA4_MEASUREMENT_ID`. |
| `consent` | `product` | The consent category to wait for. |
| `pageViews` | `manual` | `manual` (the module sends them), `automatic` (Google's tag does) or `off`. |
| `apiSecretName` | `GA4_API_SECRET` | The name of the environment variable holding the API secret. |
| `collectInEu` | `false` | Send Measurement Protocol events to `region1.google-analytics.com`. |
| `origin` | `app://app` | The address a device's pages are reported under, such as `https://example.com`. |
| `excludePaths` | `[/__studio]` | Paths that are not page views. |

## Not covered

- Google Ads features: the declared origins are the ones for Google
  Analytics alone.
- Firebase app streams: events go to a web stream's measurement id.

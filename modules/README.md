# First-party Dartvel modules

The modules Dartvel maintains itself. Each folder here is one module: a
normal Dart package with a `dartvel: module:` block, published to pub.dev
with every Dartvel release and added to an application like any other
module.

| Module | `dartvel add` | Reached as | What it is |
|---|---|---|---|
| [`dartvel_meta_pixel`](dartvel_meta_pixel/README.md) | `meta-pixel` | `DV.Modules.metaPixel` | Meta (Facebook) Pixel: page views and events in the browser, the Conversions API from the backend, counted once. |
| [`dartvel_google_analytics`](dartvel_google_analytics/README.md) | `google-analytics` | `DV.Modules.googleAnalytics` | Google Analytics 4: gtag in the browser, the Measurement Protocol from the backend and devices. |
| [`dartvel_woocommerce`](dartvel_woocommerce/README.md) | `woocommerce` | `DV.Modules.woocommerce` | WooCommerce: a typed REST API v3 client, and checkout through the store's own payment gateways. |

```bash
dartvel add meta-pixel
dartvel add google-analytics
dartvel add woocommerce
```

`dartvel add <name>` writes the dependency and the mount; each module's
README lists its settings and the secrets the server's environment supplies.

## What a first-party module is

A first-party module has no privileged status. It uses what any module may
use, all of it declared in its own `pubspec.yaml`:

- **`surface:`** the class `DV.Modules.<id>` is an instance of.
- **`start:`** a function called with the registered module, in the client
  and in the server, so a module that listens for something starts listening
  without the application calling it.
- **`csp:`** the third-party origins its scripts need, added to the page
  policy the application declares (`dartvel.security.pageCsp`). Origins
  only: a module cannot ask for `'unsafe-inline'`.
- **`operations:`** what each call does on a device, in a browser and on
  the backend. One declared `{ compat: backend }` is carried to the
  application's backend, behind the `backendPolicy` the application names.
- **`config:`** at the mount, the settings the application gives it. They
  are compiled into the client, so never a secret: a module reads secrets
  from the server's environment by name.

Modules that do not depend on each other talk through topics on the
registry: `DV.Modules.publish('commerce.purchase', payload)` and
`DV.Modules.subscribe('commerce.purchase', listener)`. That is how a
purchase WooCommerce confirms is reported by whichever analytics modules an
application mounted.

## Rules for a module in this folder

- It works on every target Dartvel builds for. Where a capability cannot
  run in the calling environment it is carried to the backend, not refused.
- It does nothing, and throws nothing, when it is not configured.
- A third party's script or endpoint failing never fails a page, a tap or
  an order.
- Where the application declares a consent policy, nothing is sent before
  the module's category is granted.
- A secret is read from the server's environment and appears in no client
  bundle, no address it can avoid, no log line and no error message.
- Every vendor endpoint, parameter and signature is checked against the
  vendor's current documentation, and the test that asserts it says so.

## Adding one

1. Create `modules/<package>/` with its `pubspec.yaml`, `README.md`,
   `CHANGELOG.md`, `LICENSE`, `lib/` and `test/`.
2. Add it to the catalogue in
   `packages/dartvel_cli/lib/src/modules/first_party.dart`, so
   `dartvel add <name>` finds it. A test fails when the folder and the
   catalogue disagree.
3. Add it to the release lists in `tool/bump_version.dart` and
   `tool/publish.sh`, and to `tool/pubspec_platforms_check.dart`.
4. List it in this file, in the root README and on the site's Modules page.

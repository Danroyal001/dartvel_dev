## Unreleased

- One page_view per page: Google's tag counts the page it loads on (it ignores `send_page_view: false` when *Ignore duplicate instances of on-page configuration* is on, the default), the module each route change after it, with `page_location` the page's own address rather than the address bar's.

## 3.47.6 — 2026-11-18

- Ad conversions: `DV.Analytics.track(DVPurchase(...))` and the other recommended events go to Google Analytics through gtag as they are tracked; the landing page view carries the campaign (`campaign_*`).
- `page_view` carries `page_path`; with a consent policy the tag starts under Consent Mode v2 defaults and `analytics_storage` follows the visitor's choice.
- The module loads after the visitor accepts, even when it starts before `DV.Analytics`.
- Declares its `capabilities:` (`GA4_MEASUREMENT_ID`, `GA4_API_SECRET`, `www.google-analytics.com`, `region1.google-analytics.com`), so an app that mounts it passes the build's declaration check. The `apiSecretName` setting is gone: the secret is read by its fixed name.
- README: the Google tag setting that counts the landing page twice, and how to turn it off.

## 3.47.5 — 2026-11-17

- Version aligned with dartvel_core 3.47.5.

## 3.47.4 — 2026-11-16

- Version aligned with dartvel_core 3.47.4.

## 3.47.3 — 2026-11-16

- Version aligned with dartvel_core 3.47.3.

## 3.47.2 — 2026-11-15

- First release.

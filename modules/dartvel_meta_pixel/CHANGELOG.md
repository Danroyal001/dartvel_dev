## 3.47.6 — 2026-11-18

- Ad conversions: `DV.Analytics.track(DVPurchase(...))` and the other recommended events go out as the Meta standard event (`ViewContent`, `AddToCart`, `InitiateCheckout`, `Purchase`, `CompleteRegistration`, `Lead`) in the browser and through the Conversions API with one event id.
- The kept click id is written to the `_fbc` cookie when the pixel loads, so a visitor who accepts on their second page is still attributed to the ad; the landing page view carries `utm_*`.
- The module loads after the visitor accepts, even when it starts before `DV.Analytics`.
- Declares its `capabilities:` (`META_PIXEL_ID`, `META_CONVERSIONS_API_TOKEN`, `graph.facebook.com`), so an app that mounts it passes the build's declaration check. The `accessTokenSecret` setting is gone: the token is read by its fixed name.

## 3.47.5 — 2026-11-17

- Version aligned with dartvel_core 3.47.5.

## 3.47.4 — 2026-11-16

- Version aligned with dartvel_core 3.47.4.

## 3.47.3 — 2026-11-16

- Version aligned with dartvel_core 3.47.3.

## 3.47.2 — 2026-11-15

- First release.

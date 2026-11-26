## 3.47.18 — 2026-11-26

- Switched off by `DARTVEL_OFF=analytics` or `module:<id>`: no script loaded, nothing forwarded.

## 3.47.17 — 2026-11-26

- Version aligned with dartvel_flutter 3.47.17.

## 3.47.16 — 2026-11-26

- Version aligned with dartvel_flutter 3.47.16.

## 3.47.15 — 2026-11-26

- Version aligned with dartvel_flutter 3.47.15.

## 3.47.14 — 2026-11-26

- Version aligned with dartvel_flutter 3.47.14.

## 3.47.13 — 2026-11-26

- Version aligned with dartvel_flutter 3.47.13.

## 3.47.12 — 2026-11-26

- Version aligned with dartvel_core 3.47.12.

## 3.47.10 — 2026-11-25

- Meta Pixel turns on from the server's secrets alone. With `pixelId` left empty the backend read `META_PIXEL_ID`, but a browser has no environment, so the client never saw an id and the pixel never loaded. The client now asks its backend which pixel to load (a new internal `settings` operation that answers the server's id and nothing else), once per page load and only after consent; setting `META_PIXEL_ID` and `META_CONVERSIONS_API_TOKEN` turns the pixel on with no rebuild.
- Meta Pixel counts each route change once. Meta's `fbevents.js` sends a `PageView` of its own, with no event id, on every `history.pushState`, which in a Dartvel app is every route change, while the module sends that view itself with the event id its Conversions API twin carries: with the pixel on, every route change after the first page counted twice and could not be de-duplicated. `fbevents.js` also drops every `PageView` after the first of a page load, so the module's own browser views of later routes never left the page. The module now sets `fbq.disablePushState` and `fbq.allowDuplicatePageViews` before `init`; each `PageView`, `ViewContent`, `Lead`, `InitiateCheckout` and `Purchase` goes out once from the browser and once to the Conversions API with the same event id.

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


# Web & Cross-Platform Features — dartvel v0.1

**Implemented (v0.1):**
- Cross-platform transitions via `dartvel.transitions` (page override via `DartvelPage.transition`)
- Cross-platform router redirects via `dartvel.routingRedirects`
- Cross-platform i18n via `dartvel.i18n` (query strategy: `?lang=en-US`)
- Web SEO defaults via `dartvel.webSeoDefaults` and per-page `buildWebSeo(...)`

**Planned (reserved keys; not yet in generator):**
- `webHead` (meta/link/script injection at build-time)
- `webPrerender` (SSG/ISR-like JSON alongside Flutter web)
- `webPwa` (manifest & service worker generator)
- `webImage` (image proxy & helpers)
- `webAnalytics` / `webVitals`
- `webRobots` / `webSitemap`

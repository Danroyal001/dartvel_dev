
# dartvel Config Reference (v2.2)

All configuration lives under the **`dartvel:`** key in your app's `pubspec.yaml`.

| Key | Type | Default | Required | Description | Status |
|-----|------|---------|----------|-------------|--------|
| `backendHost` | string | `0.0.0.0` | no | Bind address for the Shelf backend (your server process). | ✅ Implemented |
| `backendPort` | int | `3000` | no | Bind port for the backend. | ✅ Implemented |
| `devBackendHost` | string | `http://localhost:{backendPort}` | no | Base URL the Flutter app calls during **development**. | ✅ Implemented |
| `prodBackendHost` | string | — | **yes** (for `build`) | Base URL the Flutter app uses in **release** builds. | ✅ Implemented |
| `pagesDir` | string | `lib/pages` | no | Directory for your page files `*.page.dart`. | ✅ Implemented |
| `backendDir` | string | `lib/backend` | no | Directory for backend code (e.g., `functions/`). | ✅ Implemented |
| `apiBasePath` | string | `/api` | no | API base path prefix for backend endpoints. | ✅ Implemented |
| `transitions.default` | enum | `fade` | no | Global default transition: `none`\|`fade`\|`slideLeft`\|`slideUp`\|`scale`\|`sharedAxis`. | ✅ Implemented |
| `transitions.durationMs` | int | `220` | no | Default transition duration in ms. | ✅ Implemented |
| `transitions.curve` | enum | `easeInOut` | no | Default curve: `linear`\|`easeIn`\|`easeOut`\|`easeInOut`\|`decelerate`. | ✅ Implemented |
| `routingRedirects` | list | `[]` | no | Cross-platform in-app redirects (pattern `:id` supported). | ✅ Implemented |
| `i18n.strategy` | string | `query` | no | Strategy. Currently only `query` is supported. | ✅ Implemented |
| `i18n.param` | string | `lang` | no | Query parameter name used for locale (e.g., `?lang=en-US`). | ✅ Implemented |
| `i18n.defaultLocale` | string | `''` | no | Default locale tag when the query is absent/invalid. | ✅ Implemented |
| `i18n.locales` | list | `[]` | no | Allowed locale tags (case-insensitive). Empty list = accept any. | ✅ Implemented |
| `webSeoDefaults.siteName` | string | `''` | no | Default OpenGraph site name (web only). | ✅ Implemented |
| `webSeoDefaults.defaultTitle` | string | `''` | no | Default `<title>` for pages without overrides (web). | ✅ Implemented |
| `webSeoDefaults.defaultDescription` | string | `''` | no | Default meta description (web). | ✅ Implemented |
| `webSeoDefaults.defaultImage` | string | `''` | no | Default OG/Twitter image URL (web). | ✅ Implemented |
| `webSeoDefaults.twitterHandle` | string | `''` | no | Default Twitter handle (e.g., `@myapp`) (web). | ✅ Implemented |

## Deprecated Keys
| Old | New |
|-----|-----|
| `webTransitions` | `transitions` |
| `webRedirects` | `routingRedirects` |
| `webI18n` | `i18n` |
| `seoDefaults` | `webSeoDefaults` |
| `DartvelPage.buildSeo()` | `DartvelPage.buildWebSeo()` |

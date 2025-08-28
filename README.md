
# dartvel (v2.2)

Flutter-first file-system routing with cross-platform transitions, redirects, and query-based i18n; plus web SEO injection.

- 📚 **Docs:** see [`/docs/`](./docs)
- 🧪 **Example app:** [`/example/dartvel_example`](./example/dartvel_example)
- 🧩 Packages:
  - `packages/dartvel_core`
  - `packages/dartvel_flutter`
  - `packages/dartvel_cli`

## TL;DR
1) Add `dartvel:` to your app's `pubspec.yaml`.
2) Create pages in `lib/pages/**/*.page.dart` (extend `DartvelPage`).
3) Run `dart run dartvel_cli:routes` to generate router/configs.
4) Use `MaterialApp.router(routerConfig: createDartvelRouter())`.

### Sample `dartvel:` config
```yaml
dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.example.com

  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api

  transitions:
    default: fade
    durationMs: 220
    curve: easeInOut

  routingRedirects:
    - { from: "/old", to: "/" }

  i18n:
    strategy: query
    param: lang
    defaultLocale: en-US
    locales: [en-US, fr-FR]

  webSeoDefaults:
    siteName: MyApp
    defaultTitle: MyApp
    defaultDescription: A beautiful app built with dartvel.
    defaultImage: assets/og_default.png
    twitterHandle: "@myapp"
```

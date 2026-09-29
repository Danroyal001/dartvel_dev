# `dartvel.docs` — Documentation site options

The documentation site is a compiled Flutter application (`DVDocsApp`) that reads the project's own graph (`docs.json` and `graph.json`). It is **OFF by default** for every application.

Configuration lives under the `dartvel:` section of `pubspec.yaml`:

```yaml
dartvel:
  docs:
    enabled: true        # false by default; set to true to include the site
    path: /docs          # default mount; must begin with "/" and cannot be "/"
    access: studio       # default when enabled; "studio" or "public"
```

- `enabled` (bool): When omitted or `false`, the build produces no docs site (`DVDocsMount(enabled: false)`). Only `true` includes it.
- `path` (string): The mount under which the site is served. Default `/docs`. Refused if missing a leading `/`, equal to `/`, or parameterised (`/docs/:id`, `/docs/*`).
- `access` (string): `studio` (default when enabled) requires Studio authentication (`DVDocsAccess.studio`); `public` serves without authentication (`DVDocsAccess.public`).

## Access control

- `studio`: Signed-out callers get a `302` redirect to Studio sign-in (`<adminMount.path>/login?from=...`). The docs data (`docs.json`, `graph.json`) answers `404` without a Studio grant. Authorized callers receive the docs app and its data.
- `public`: Any caller can access the site and its data without authentication.

## Route collision refusal

A mount path that collides with an application page route is refused at build time with a clear error naming both the page file and the docs mount. The build exits non-zero (`DV-...`) so the collision is caught before deployment.

## Build targets

Both `dartvel build web` and `dartvel build web-server` integrate the docs site at its mount when enabled. The web-server binary carries the docs site outside the `web` section (behind authentication when `access: studio`) and serves it through `DVDocsServer`.

## Local development

`dartvel docs --serve` keeps working as today: it serves the compiled site on loopback (`http://localhost:4180` by default) and rebuilds it when the project changes.

# Dartvel Project Structure Guide

This document captures the current expectations for a Dartvel application layout. It
has been prepared as part of the structured project organisation backlog item and
will evolve as we automate more scaffolding in the CLI.

## Top-Level Layout

```
<project_root>
├── lib/
│   ├── pages/                 # File-based routing surface for Flutter UI pages
│   │   ├── index.page.dart
│   │   ├── _layout.page.dart
│   │   └── ...
│   ├── backend/               # Backend runtime implemented as functions
│   │   └── functions/
│   │       ├── hello.get.dart
│   │       └── ...
│   ├── dartvel_client/        # Generated client runtime (router, env, dio helpers)
│   └── dartvel_config.dart    # (Optional) manual overrides
├── .dart_tool/
│   └── dartvel_backend*.g.dart  # Generated backend router/config files
├── Backlog/                   # Planning artefacts (not required for apps)
├── docs/                      # Developer documentation
├── pubspec.yaml               # Flutter application manifest + dartvel section
├── analysis_options.yaml      # Linting configuration
└── README.md
```

## `pubspec.yaml` Requirements

Every Dartvel app declares a `dartvel` section. At minimum:

```yaml
name: awesome_app
flutter:
  uses-material-design: true

dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  apiBasePath: /api
  pagesDir: lib/pages
  backendDir: lib/backend
```

Additional keys (`envFiles`, `routingRedirects`, i18n, transitions) enable optional
features such as localisation and page transitions.

## Generated Assets

Running `dartvel routes`, `dartvel dev`, or `dartvel build` generates:

- `lib/dartvel_client/*`: Flutter router/configuration helpers.
- `.dart_tool/dartvel_backend*.g.dart`: backend router + config.
- `.dart_tool/dartvel_dev_server.dart`: entrypoint used by `dartvel dev`.

These files should be **ignored** from source control unless the project wants to
commit client artefacts (the CLI inserts ignore rules automatically).

## Backend Functions

Backends live under `lib/backend/functions`. File names map to HTTP routes:

- `hello.get.dart` → `GET /api/hello`
- `[id].get.dart` → `GET /api/<id>` with dynamic param.
- `group/[...slug].post.dart` → `POST /api/group/<slug>` catch-all.

Functions can export either:

- A top-level function whose name matches the file stem (sanitised).
- A `handler(...)` function returning a Dartvel `Response`.

The CLI inspects parameter names to wire request params/body/query automatically.

## Pages and Layouts

The file-based router mimics frameworks like Next.js:

- `lib/pages/index.page.dart` → `/`.
- Nested directories map to nested routes.
- `_layout.page.dart` files wrap descendant pages.
- Optional `.loading.dart` / `.error.dart` provide skeletons.

Guards can be defined with `_guard.dart` next to page directories (execution
model TBD; see backlog item #9).

## Pending Improvements

- Introduce a `dartvel new` command to scaffold this structure automatically.
- Extend docs with opinionated environment separation (`dev`, `staging`, `prod`).
- Link to forthcoming architecture decision records.

Feedback welcome via issues or PRs.

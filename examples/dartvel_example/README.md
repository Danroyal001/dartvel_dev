
# dartvel_example

A minimal Flutter app using **dartvel v0.1** (web SEO, transitions, file-system routing).

## Run (Web)

```bash
# 1) Get packages for the framework and the example
dart pub get --directory ../packages/dartvel_core
dart pub get --directory ../packages/dartvel_flutter
dart pub get --directory ../packages/dartvel_cli
flutter pub get

# 2) Generate dartvel artifacts (router + client/backend configs + backend routes)
dart run dartvel_cli:dartvel routes
# Optional: watch for changes and regenerate automatically
# dart run dartvel_cli:watch

# 3) Run Flutter (web)
flutter run -d chrome

# Or use dartvel dev/run to orchestrate backend + Flutter
# Prompts for device if not specified
dart run dartvel_cli:run

# (Optional) Start your backend server (example provided)
# From this directory:
#   dart run bin/server.dart
```

Routes:
- `/` from `lib/pages/index.page.dart`
- `/blog/:id` from `lib/pages/blog/[id].page.dart`

Notes:
- Backend function filenames without a method suffix (e.g., `lib/backend/functions/blog/last_viewed_date_[date].dart`) default to POST.

## Extra backend features showcased

- Streaming (SSE): `GET /api/stream/ticks` emits 10 ticks
- Polling: `GET /api/poll/now` → `{ now, changed }` (compare with `?last=`)
- In-memory collection (todos):
  - `GET /api/db/todos`
  - `POST /api/db/todos?title=Buy%20milk`
  - `PUT /api/db/todos/:id?title=New%20title`
  - `DELETE /api/db/todos/:id`
- Remote file storage (local demo):
  - `PUT /api/storage/file/foo.bin` with raw body
  - `GET /api/storage/file/foo.bin`

Buttons in the home page trigger many of these endpoints for quick testing.

The client artifacts are generated under `lib/dartvel_client/` (router, functions, config).
You can re-generate anytime with `dart run dartvel_cli:dartvel routes`.

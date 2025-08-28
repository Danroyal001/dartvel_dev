
# dartvel_example

A minimal Flutter app using **dartvel v2.1** (web SEO, transitions, file-system routing).

## Run (Web)

```bash
# 1) Get packages for the framework and the example
dart pub get --directory ../packages/dartvel_core
dart pub get --directory ../packages/dartvel_flutter
dart pub get --directory ../packages/dartvel_cli
flutter pub get

# 2) Generate dartvel artifacts (router + client/backend configs)
dart run dartvel_cli:dartvel routes

# 3) Run Flutter (web)
flutter run -d chrome

# (Optional) Start your backend server separately; example only shows API stub code.
```

Routes:
- `/` from `lib/pages/index.page.dart`
- `/blog/:id` from `lib/pages/blog/[id].page.dart`

The router is **pre-generated** under `.dart_tool/dartvel_client/` so it can run out-of-the-box.
You can re-generate anytime with `dart run dartvel_cli:dartvel routes`.

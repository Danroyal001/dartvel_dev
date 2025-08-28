
# Routing (File-System) — dartvel v0.1

- Pages live under **`lib/pages`** (configurable via `pagesDir`).
- Each file must be named **`*.page.dart`** and define a **class ending with `Page`** that **extends `DartvelPage`**.
- File path → URL path mapping:

| File | Route |
|------|-------|
| `lib/pages/index.page.dart` | `/` |
| `lib/pages/about.page.dart` | `/about` |
| `lib/pages/blog/[id].page.dart` | `/blog/:id` |
| `lib/pages/(auth)/login.page.dart` | `/login` (group folders are stripped) |
| `lib/pages/docs/[...slug].page.dart` | `/docs/*slug` (catch-all) |

> **Route Groups**: A folder wrapped with parentheses (e.g., `(auth)`) is **not** part of the URL.

## Accessing Params & Query
```dart
import 'package:dartvel_flutter/dartvel_flutter.dart';

@override
Widget build(BuildContext context) {
  final id = context.dvParams['id'];       // from /blog/:id
  final q  = context.dvQuery['q'];         // from ?q=...
  ...
}
```

## 404 Handling
- To redirect unknown routes, set `notFoundRedirect` in your `dartvel:` config (e.g., `/`).
- Trailing slash normalization is enabled by default (`/path/` → `/path`); disable via `routingNormalizeTrailingSlash: false`.

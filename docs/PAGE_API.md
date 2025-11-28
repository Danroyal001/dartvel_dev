
# Page API — `DartvelPage` (v0.1)

Pages are **Flutter widgets** extending `DartvelPage`.

```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(title: 'Home', description: 'Welcome');

  @override
  PageTransitionSpec get transition =>
      const PageTransitionSpec(type: DvTransition.fade, duration: Duration(milliseconds: 180));

  @override
  Widget build(BuildContext context) {
    final params = context.dvParams;
    final query  = context.dvQuery;
    final lang   = DvI18nScope.of(context).localeTag; // current locale tag from query
    return Scaffold(...);
  }
}
```

## i18n (query-param strategy; cross-platform)
- Configure in `pubspec.yaml -> dartvel.i18n`.
- Router wraps each page into a `DvI18nScope(localeTag: ...)` with the normalized query param value.
- Change language in-app (preserving path & query):
```dart
ElevatedButton(
  onPressed: () => DvI18n.updateLang(context, 'lang', 'fr-FR'),
  child: const Text('Français'),
);
```

## SEO (web-only)
- Implement `buildWebSeo(params, query)` to set title/description/canonical/OG/Twitter tags on web at runtime.
- Project defaults are taken from `pubspec.yaml -> dartvel.webSeoDefaults` and merged with your page’s override.

## Transitions (cross-platform)
- Override `transition` per page.
- Global defaults in `pubspec.yaml -> dartvel.transitions`.
- Available types: `none`, `fade`, `slideLeft`, `slideUp`, `scale`, `sharedAxis`.

## Layouts (root and per-segment)
- Root: create `lib/pages/_layout.dart` exporting a class that extends `DartvelLayout` and takes a required `child`:
```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}
```
- The generator wraps every page with the root layout.
- Per-segment: add `_layout.dart` inside any folder under `lib/pages/**` (including group folders like `(admin)`); pages under that folder are wrapped by that layout in addition to the root.
- Data Loading (per page)
- Override `loadData(params, query)` in your `DartvelPage` to fetch data before rendering. The router wraps your page in a `DvDataLoader` and exposes the result via `DvDataScope`:
```dart
class BlogIdPage extends DartvelPage {
  const BlogIdPage({super.key});

  @override
  Future<Object?> loadData(Map<String, String> params, Map<String, String> query) async {
    final id = params['id'];
    // fetch from your backend, e.g., using Dio
    // return await api.getPost(id);
    return {'id': id, 'title': 'Hello $id'};
  }

  @override
  Widget build(BuildContext context) {
    final data = DvDataScope.of(context).data as Map?;
    return Scaffold(body: Center(child: Text('Post: \\${data?['title']}')));
  }
}
```

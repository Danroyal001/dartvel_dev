
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

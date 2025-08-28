
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(title: 'Home • Dartvel Demo', description: 'Welcome to the Dartvel demo!');

  @override
  Widget build(BuildContext context) {
    final currentLangScope = DvI18nScope.of(context).localeTag;
    final currentLang = currentLangScope.isEmpty ? 'system' : currentLangScope;

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hello from Dartvel! (lang: $currentLang)'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => DvI18n.updateLang(context, 'lang', 'en-US'),
                  child: const Text('EN-US'),
                ),
                FilledButton(
                  onPressed: () => DvI18n.updateLang(context, 'lang', 'fr-FR'),
                  child: const Text('FR-FR'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed('/blog/42'),
              child: const Text('Go to /blog/42'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed('/old'),
              child: const Text('Try redirect: /old -> /'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/dartvel_client/functions.g.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';

class IndexPage extends DartvelPage {
  @Preview()
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(
          title: 'Home • Dartvel Demo',
          description: 'Welcome to the Dartvel demo!');

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
              onPressed: () => context.push('/blog/42'),
              child: const Text('Go to /blog/42'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.push('/old'),
              child: const Text('Try redirect: /old -> /'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final data = await getHelloApi(name: 'Dartvel');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hello API: ${data.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('Call /api/hello?name=Dartvel'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final data = await getBlogByIdApi(id: '42');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Blog API: ${data.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('Call /api/blog/42'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final data =
                      await postBlogLastViewedDateByDateApi(date: '2025-08-29');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('Last viewed (POST): ${data.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('POST /api/blog/last_viewed_date_:date'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final data = await postEchoApi(msg: 'Hello Dartvel');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Echo: ${data.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('POST /api/echo'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final sum = await postSumApi(a: 2, b: 3);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sum: $sum')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('POST /api/sum (2+3)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await putUserByIdApi(id: 'u1', name: 'Alice');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PUT user: ${res.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('PUT /api/user/u1?name=Alice'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await deleteUserByIdApi(id: 'u1');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('DELETE user: $res')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('DELETE /api/user/u1'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final res = await getSearchApi(q: 'hello', tags: ['a', 'b']);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Search: ${res.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('GET /api/search?q=hello&tags=a,b'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final r = await headPing();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('HEAD /api/ping → ${r.statusCode}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('HEAD /api/ping'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  final data =
                      await postBlogLastViewedDateByDateApi(date: '2025-08-29');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('Last viewed API (POST): ${data.toString()}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('API error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('POST /api/blog/last_viewed_date_:date'),
            ),
          ],
        ),
      ),
    );
  }
}

//

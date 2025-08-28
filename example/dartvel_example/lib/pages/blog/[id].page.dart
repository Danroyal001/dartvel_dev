
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class BlogIdPage extends DartvelPage {
  const BlogIdPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) {
    final id = params['id'] ?? 'unknown';
    return SeoProps(
      title: 'Blog $id • Dartvel Demo',
      description: 'Reading blog post $id.',
      canonicalUrl: 'https://example.com/blog/$id',
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = context.dvParams['id']!;
    return Scaffold(
      appBar: AppBar(title: Text('Blog $id')),
      body: Center(child: Text('Viewing blog post $id')),
    );
  }
}

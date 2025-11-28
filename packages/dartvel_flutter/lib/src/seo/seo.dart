import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:seo/seo.dart';

export 'package:seo/seo.dart';

/// SEO Metadata
class SeoMetadata {
  final String title;
  final String description;
  final String? image;
  final String? url;
  final String? type;
  final String? siteName;
  final String? twitterHandle;

  const SeoMetadata({
    required this.title,
    required this.description,
    this.image,
    this.url,
    this.type = 'website',
    this.siteName,
    this.twitterHandle,
  });
}

/// Root widget to enable SEO (wraps SeoController)
class DartvelSeoRoot extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const DartvelSeoRoot({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return SeoController(
      enabled: enabled,
      tree: WidgetTree(context: context),
      child: child,
    );
  }
}

/// SEO Widget for Head Metadata
class SeoHead extends StatelessWidget {
  final SeoMetadata metadata;
  final Widget child;

  const SeoHead({
    super.key,
    required this.metadata,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // In a real implementation, this would update the DOM head
      // using dart:js_interop or package:web
      // For now, we rely on the prerenderer to pick this up from the widget tree
      // or we could use a library like `meta_seo` or just vanilla JS interop here.
    }
    return child;
  }
}

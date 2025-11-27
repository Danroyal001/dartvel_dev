import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

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

/// SEO Widget
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
    }
    return child;
  }
}

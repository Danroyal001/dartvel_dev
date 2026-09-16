// docs:start routing-nested-layout
// lib/pages/blog/_layout.dart wraps the pages under /blog,
// inside the root layout.
import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

class BlogLayout extends DartvelLayout {
  const BlogLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) => DVBox.row(<Widget>[
        const DVText('Blog'),
        Expanded(child: child),
      ], spacing: 24);
}
// docs:end

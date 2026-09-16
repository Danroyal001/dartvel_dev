import 'package:flutter/material.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

/// Brew guides read as articles: nothing around them but the page.
class BlogLayout extends DartvelLayout {
  const BlogLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) => child;
}

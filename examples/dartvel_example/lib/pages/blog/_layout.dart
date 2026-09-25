import 'package:flutter/material.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

/// Brew guides read as articles: nothing around them but the page.
class const BlogLayout({super.key, required super.child})
    extends DartvelLayout {
  @override
  Widget build(BuildContext context) => child;
}

import 'package:flutter/material.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

class BlogLayout extends DartvelLayout {
  const BlogLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.deepPurple.shade200, width: 3)),
      ),
      child: child,
    );
  }
}

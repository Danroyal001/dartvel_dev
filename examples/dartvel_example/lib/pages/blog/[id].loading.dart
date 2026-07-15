import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

class BlogIdPageLoading extends StatelessWidget {
  const BlogIdPageLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox(
      SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class BlogIdPageError extends StatelessWidget {
  const BlogIdPageError({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox.list([
      Icon(Icons.error_outline, color: Colors.redAccent),
      DVText('Failed to load blog post'),
    ]).modifier(
      const DVModifier().align(Alignment.center),
    );
  }
}

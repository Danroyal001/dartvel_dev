import 'package:flutter/material.dart';

class BlogIdPageLoading extends StatelessWidget {
  const BlogIdPageLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class BlogIdPageError extends StatelessWidget {
  const BlogIdPageError({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blog')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            Text('Failed to load blog post', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}


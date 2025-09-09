import 'package:flutter/material.dart';

class IndexPageLoading extends StatelessWidget {
  const IndexPageLoading({super.key});

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

class IndexPageError extends StatelessWidget {
  const IndexPageError({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            Text('Failed to load page', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';

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


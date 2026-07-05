import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:dartvel_core/dartvel.dart';

@DVPage()
@DVFunctionalWidget()
Widget indexPage(BuildContext context) {
  final data = DvDataScope.of(context).data as Map?;

  return Scaffold(
    appBar: AppBar(
      title: const Text('Welcome to Dartvel'),
      centerTitle: true,
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              'Your Dartvel app is ready!',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Loaded at: ${data?['timestamp'] ?? 'N/A'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.book),
                  label: const Text('Docs'),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.code),
                  label: const Text('GitHub'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

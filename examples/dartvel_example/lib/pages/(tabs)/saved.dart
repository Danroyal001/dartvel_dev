import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Saved')
@pragma('vm:entry-point')
Widget _savedPage(BuildContext context) => (() {
      // Kept while the Library tab is on screen: each tab's pages stay built.
      final saves = context.signal(0);
      return DVBox.list([
        const DVText('Saved')
            .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
        DVText('Saved ${saves.value} times'),
        TextButton(
          key: const Key('save-button'),
          onPressed: () => saves.value = saves.value + 1,
          child: const Text('Save'),
        ),
      ], spacing: 12)
          .modifier(const DVModifier().padding(24));
    })();

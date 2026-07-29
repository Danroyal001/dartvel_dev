import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(
  title: 'Blog',
  showAppBar: true,
)
@pragma('vm:entry-point')
Widget _blogIdPage(BuildContext context) => DVBox.list([
      DVText('Blog ${context.dvParams['id'] ?? 'unknown'}'),
      DVBox(
        DVText('Viewing blog post ${context.dvParams['id'] ?? 'unknown'}'),
        const DVModifier().align(Alignment.center),
      ),
    ]);

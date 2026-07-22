import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(
  title: 'Blog',
  showAppBar: true,
)
@DVFunctionalWidget()
Widget blogIdPage(BuildContext context) {
  final id = context.dvParams['id'] ?? 'unknown';
  return DVBox.list([
    DVText('Blog $id'),
    DVBox(
      DVText('Viewing blog post $id'),
      const DVModifier().align(Alignment.center),
    ),
  ]);
}

import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_core/dartvel.dart';

@DVPage()
@DVFunctionalWidget()
Widget blogIdPage(BuildContext context) {
  final id = context.dvParams['id'] ?? 'unknown';
  return Scaffold(
    appBar: AppBar(title: Text('Blog $id')),
    body: Center(child: Text('Viewing blog post $id')),
  );
}

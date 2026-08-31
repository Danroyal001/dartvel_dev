// GENERATED – do not edit.
import 'dart:convert';
import 'dart:io';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/pages/about.page.dart' deferred as p0;
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:dartvel_example/pages/blog/[id].page.dart' deferred as p1;
import 'package:dartvel_example/pages/index.page.dart' deferred as p2;
import 'package:dartvel_example/pages/pricing.dart' deferred as p3;
import 'package:flutter/widgets.dart';
void main() async {
  final outDir = Directory('build/web/_ssg');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  stdout.writeln('Generating SSG data...');
  // /about
  // Skipped functional widget page: /about
  // /blog/:id
  // Skipped functional widget page: /blog/:id
  // /
  // Skipped functional widget page: /
  // /pricing
  // Skipped functional widget page: /pricing
  stdout.writeln('SSG generation complete.');
}

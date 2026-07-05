// GENERATED – do not edit.
import 'dart:convert';
import 'dart:io';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/pages/about.page.dart' as p0;
import 'package:dartvel_example/pages/blog/[id].page.dart' as p1;
import 'package:dartvel_example/pages/blog/[id].loading.dart' as pl1;
import 'package:dartvel_example/pages/blog/[id].error.dart' as pe1;
import 'package:dartvel_example/pages/index.page.dart' as p2;
import 'package:dartvel_example/pages/index.loading.dart' as pl2;
import 'package:dartvel_example/pages/index.error.dart' as pe2;
void main() async {
  final outDir = Directory('build/web/_ssg');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  print('Generating SSG data...');
  // /about
  try {
    final page = const p0.AboutPage();
    final data = await page.loadData({}, {});
    if (data != null) {
      final key = "/about";
      final bytes = utf8.encode(key);
      final filename = base64Url.encode(bytes);
      File("${outDir.path}/$filename.json").writeAsStringSync(jsonEncode(data));
    }
  } catch (e) {
  }
  // /blog/:id
  // Skipped functional widget page: /blog/:id
  // /
  // Skipped functional widget page: /
  print('SSG generation complete.');
}

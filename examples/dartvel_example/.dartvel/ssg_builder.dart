// GENERATED – do not edit.
import 'dart:convert';
import 'dart:io';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/pages/about.page.dart' deferred as p0;
import 'package:dartvel_example/pages/blog/[id].page.dart' deferred as p2;
import 'package:dartvel_example/pages/index.page.dart' deferred as p4;
void main() async {
  final outDir = Directory('build/web/_ssg');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  stdout.writeln('Generating SSG data...');
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
  stdout.writeln('SSG generation complete.');
}

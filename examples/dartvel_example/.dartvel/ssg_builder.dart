// GENERATED – do not edit.
import 'dart:convert';
import 'dart:io';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/pages/blog/[id].page.dart' as p0;
import 'package:dartvel_example/pages/blog/[id].loading.dart' as pl0;
import 'package:dartvel_example/pages/blog/[id].error.dart' as pe0;
import 'package:dartvel_example/pages/index.page.dart' as p1;
import 'package:dartvel_example/pages/index.loading.dart' as pl1;
import 'package:dartvel_example/pages/index.error.dart' as pe1;
void main() async {
  final outDir = Directory('build/web/_ssg');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  print('Generating SSG data...');
  // /blog/:id
  try {
    final page = const p0.BlogIdPage();
    final paths = await page.staticPaths;
    for (final params in paths) {
      final data = await page.loadData(params, {});
      if (data != null) {
        var key = "/blog/:id";
        params.forEach((k, v) => key = key.replaceAll(":$k", v));
        final bytes = utf8.encode(key);
        final filename = base64Url.encode(bytes);
        File("${outDir.path}/$filename.json").writeAsStringSync(jsonEncode(data));
      }
    }
  } catch (e) {
  }
  // /
  try {
    final page = const p1.IndexPage();
    final data = await page.loadData({}, {});
    if (data != null) {
      final key = "/";
      final bytes = utf8.encode(key);
      final filename = base64Url.encode(bytes);
      File("${outDir.path}/$filename.json").writeAsStringSync(jsonEncode(data));
    }
  } catch (e) {
  }
  print('SSG generation complete.');
}

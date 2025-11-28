import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/logger.dart';

class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description = 'Check your project for common issues.';

  @override
  Future<void> run() async {
    // Config keys
    final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
    final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();
    final devBackendHost = (dv['devBackendHost'] ?? '').toString();
    final prodBackendHost = (dv['prodBackendHost'] ?? '').toString();
    // Env files
    final envFiles = <String>[];
    if (dv['envFiles'] is List) {
      for (final f in (dv['envFiles'] as List)) {
        if (f != null) envFiles.add(f.toString());
      }
    } else {
      envFiles.addAll(['.env', '.env.local']);
    }

    // Paths
    final pagesPath = p.join(root, pagesDir);
    final backendPath = p.join(root, backendDir);
    final pagesExists = Directory(pagesPath).existsSync();
    final backendExists = Directory(backendPath).existsSync();

    Logger.log('• pagesDir: $pagesDir${pagesExists ? ' (ok)' : ' (missing)'}');
    if (!pagesExists) warn('pagesDir does not exist: $pagesDir');
    Logger.log(
        '• backendDir: $backendDir${backendExists ? ' (ok)' : ' (missing)'}');
    if (!backendExists) warn('backendDir does not exist: $backendDir');

    // Pages presence
    if (pagesExists) {
      final glob = Glob(p.join(pagesDir, '**.page.dart'));
      final fs = const LocalFileSystem();
      final list = glob.listFileSystemSync(fs, root: root, followLinks: false);
      final count = list.length;
      Logger.log('• pages found: $count');
      if (count == 0) {
        warn('No pages found under $pagesDir (need *.page.dart)');
      }

      // Detect route conflicts
      String routeFor(String rel) {
        var path = rel
            .replaceFirst(RegExp('^$pagesDir/?'), '')
            .replaceAll('\\\\', '/');
        path = path.replaceFirst(RegExp(r'\.page\.dart$'), '');
        if (path == 'index') return '/';
        path = path.replaceAllMapped(RegExp(r'\(([^)]+)\)/'), (m) => '');
        path = path.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
          final seg = m.group(1)!;
          if (seg.startsWith('...')) return '*${seg.substring(3)}';
          return ':$seg';
        });
        path = path.replaceFirst(RegExp(r'/index$'), '');
        if (path.isEmpty) return '/';
        return '/$path';
      }

      final routeMap = <String, List<String>>{};
      for (final ent in list) {
        final abs = ent.path;
        final rel = p.relative(abs, from: root).replaceAll('\\\\', '/');
        if (p.basename(rel) == '_layout.page.dart') continue;
        final r = routeFor(rel);
        (routeMap[r] ??= <String>[]).add(rel);
      }
      final conflicts = routeMap.entries.where((e) => e.value.length > 1);
      if (conflicts.isNotEmpty) {
        for (final c in conflicts) {
          warn('Route conflict for "${c.key}" from:');
          for (final f in c.value) {
            Logger.log('   - $f');
          }
        }
      }
    }

    // Backend functions
    final fnGlob = Glob(p.join(backendDir, 'functions/**.dart'));
    final fs = const LocalFileSystem();
    final methodSet = {
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'head',
      'options'
    };
    int fnCount = 0;
    for (final e
        in fnGlob.listFileSystemSync(fs, root: root, followLinks: false)) {
      final rel = p.relative(e.path, from: root).replaceAll('\\\\', '/');
      final base = p.basenameWithoutExtension(rel);
      final dot = base.lastIndexOf('.');
      final method = (dot != -1) ? base.substring(dot + 1).toLowerCase() : '';
      // Count functions even without explicit method suffix (defaults to GET)
      if (method.isEmpty || methodSet.contains(method)) fnCount++;
    }
    Logger.log('• backend functions: $fnCount');
    if (fnCount == 0) {
      warn('No backend functions found under $backendDir/functions');
    }

    // prodBackendHost
    if (prodBackendHost.isEmpty) {
      warn('prodBackendHost is empty (required for build)');
    } else {
      Logger.log('• devBackendHost: $devBackendHost');
      Logger.log('• prodBackendHost: $prodBackendHost');
    }

    // Env file checks
    final foundEnv = <String>[];
    final publicKeys = <String>{};
    for (final f in envFiles) {
      final file = File(p.join(root, f));
      if (!file.existsSync()) {
        warn('Env file missing: $f');
        continue;
      }
      foundEnv.add(f);
      try {
        for (final line in file.readAsLinesSync()) {
          final t = line.trim();
          if (t.isEmpty || t.startsWith('#')) continue;
          final i = t.indexOf('=');
          if (i <= 0) continue;
          final key = t.substring(0, i).trim();
          if (key.startsWith('PUBLIC_')) publicKeys.add(key);
        }
      } catch (_) {}
    }
    if (foundEnv.isEmpty) {
      warn('No env files found (checked: ${envFiles.join(', ')})');
    } else {
      Logger.log('• env files: ${foundEnv.join(', ')}');
    }
    if (publicKeys.isEmpty) {
      warn('No PUBLIC_* keys found in env files (env.g.dart will be empty)');
    } else {
      Logger.log('• PUBLIC_* keys: ${publicKeys.length}');
    }

    // Shorebird check
    Logger.log('');
    Logger.log('Running Shorebird doctor...');
    try {
      final sbCheck = await Process.run('shorebird', ['--version']);
      if (sbCheck.exitCode == 0) {
        Logger.log(
            '• Shorebird: installed (version: ${(sbCheck.stdout as String).trim()})');
        final sbDoctor = await Process.start(
          'shorebird',
          ['doctor'],
          mode: ProcessStartMode.inheritStdio,
        );
        await sbDoctor.exitCode;
      } else {
        warn(
            'Shorebird not found (required for OTA updates). Install via https://shorebird.dev');
      }
    } catch (_) {
      warn(
          'Shorebird not found (required for OTA updates). Install via https://shorebird.dev');
    }

    // Flutter check
    Logger.log('');
    Logger.log('Running Flutter doctor...');
    try {
      final flutterCheck = await Process.run('flutter', ['--version']);
      if (flutterCheck.exitCode == 0) {
        final flutterDoctor = await Process.start(
          'flutter',
          ['doctor'],
          mode: ProcessStartMode.inheritStdio,
        );
        await flutterDoctor.exitCode;
      } else {
        warn('Flutter not found. Please install Flutter SDK.');
      }
    } catch (_) {
      warn('Flutter not found. Please install Flutter SDK.');
    }

    Logger.log('');
    Logger.log(warnings == 0
        ? 'Dartvel doctor finished with no issues.'
        : 'Dartvel doctor finished with $warnings warning(s).');
  }
}

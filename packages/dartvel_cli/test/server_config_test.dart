// The server configuration path URLs require, which nothing wrote.
//
// `dartvel build web` switches the app off Flutter's hash strategy so every
// route has a real URL -- and a real URL has to be served. The generated
// router's own comment says "it needs the server to serve index.html for
// unknown paths, which is what the .htaccess and dartvel deploy configuration
// do", and no .htaccess existed. A build uploaded to Apache answered the
// host's 404 page for anything the build had not prerendered.
import 'dart:io';

import 'package:dartvel_cli/src/build/server_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('the Apache configuration', () {
    final String config = dvApacheConfig();

    test('apple-app-site-association is served as JSON', () {
      // It has no extension, so AddType cannot reach it, and iOS refuses the
      // document as anything but JSON: every Universal Link opens Safari.
      expect(config, contains('<Files "apple-app-site-association">'));
      expect(config, contains('ForceType application/json'));
    });

    test('an existing file is served as itself', () {
      // Without this the rewrite swallows main.dart.js and every asset, and
      // the page loads index.html as its own JavaScript.
      expect(config, contains('RewriteCond %{REQUEST_FILENAME} -f'));
      expect(config, contains('RewriteCond %{REQUEST_FILENAME} -d'));
    });

    test('anything else falls back to the application', () {
      expect(config, contains('RewriteRule . /index.html [L]'));
    });

    test('it does nothing where mod_rewrite is absent', () {
      // A bare RewriteEngine on a host without the module is a 500, which is
      // a worse failure than the one being fixed.
      expect(config, contains('<IfModule mod_rewrite.c>'));
    });

    test('wasm is served as wasm', () {
      // Flutter loads CanvasKit's wasm with fetch and instantiateStreaming,
      // which refuses anything not served as application/wasm.
      expect(config, contains('application/wasm'));
    });

    test('the entry point is not cached', () {
      // index.html names the hashed bundles. A cached one keeps pointing at
      // the previous deploy's files, which is the deploy that appears to have
      // done nothing.
      expect(config, contains('index.html'));
      expect(config, contains('no-cache'));
    });
  });

  group('what may be cached forever', () {
    // Dots are escaped for the regex, so `main\.dart\.js` is what is
    // written. Matching filenames against the raw text would be matching the
    // escaping rather than the rule.
    final String config = dvApacheConfig().replaceAll(r'\.', '.');

    test('the entry bundles are not', () {
      // Flutter does not content-hash these: main.dart.js is called
      // main.dart.js in every build there has ever been. Marking them
      // immutable for a year means a returning visitor never sees a deploy
      // again -- the site is simply frozen for them, with no error and no
      // way for them to know.
      for (final String never in <String>[
        'main.dart.js',
        'flutter_bootstrap.js',
        'flutter_service_worker.js',
        'version.json',
      ]) {
        expect(config, contains(never),
            reason: '\$never has to be named somewhere that stops it being '
                'cached immutably');
      }
      expect(config, isNot(contains(r'\.(js|wasm|woff2|png|jpg|svg)\$')),
          reason: 'a blanket rule over .js catches main.dart.js');
    });

    test('what Flutter does hash still is', () {
      // canvaskit and the asset bundle carry a version in the path, so they
      // are safe to keep -- and they are the large ones.
      expect(config, contains('canvaskit'));
      expect(config, contains('assets/'));
      expect(config, contains('immutable'));
    });

    test('the service worker is never cached', () {
      // A cached service worker cannot replace itself, which is the one
      // failure with no way out from the visitor's side.
      final int swAt = config.indexOf('flutter_service_worker.js');
      expect(swAt, greaterThan(-1));
      expect(config.substring(swAt).contains('no-cache'), isTrue);
    });
  });

  // The header said "Edits are kept: this file is only created when it is
  // absent", and every build overwrote it, so an edit made on the strength of
  // that comment was lost on the next deploy without a word. The build keeps
  // any .htaccess it did not write, and the header says exactly what happens.
  group('writing the .htaccess into a build', () {
    late Directory root;
    late Directory web;
    late File output;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_htaccess_');
      web = Directory(p.join(root.path, 'build', 'web'))
        ..createSync(recursive: true);
      output = File(p.join(web.path, '.htaccess'));
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('the header says what the build does with the file', () {
      final String header = dvApacheConfig().split('\n<IfModule').first;
      expect(header.split('\n').first, startsWith(dvApacheConfigMarker));
      expect(header, isNot(contains('only created when')));
      expect(header, contains('every build'));
      expect(header, contains('web/.htaccess'));
    });

    test('it is written when the build has none', () {
      expect(dvWriteApacheConfig(web, projectRoot: root.path), isTrue);
      expect(output.readAsStringSync(), dvApacheConfig());
    });

    test('a copy Dartvel wrote is brought up to date', () {
      // A fix to the generated rules has to reach a project that has built
      // before -- that is how a bad cache rule survived being fixed.
      output.writeAsStringSync('$dvApacheConfigMarker stale\nold rules\n');
      expect(dvWriteApacheConfig(web, projectRoot: root.path), isTrue);
      expect(output.readAsStringSync(), dvApacheConfig());
    });

    test('a copy written in an earlier release is brought up to date', () {
      // The header before the marker existed; it is still Dartvel's.
      output.writeAsStringSync('# Written by dartvel build web. Edits are '
          'kept: this file is only created when it is\n# absent.\n');
      expect(dvWriteApacheConfig(web, projectRoot: root.path), isTrue);
      expect(output.readAsStringSync(), dvApacheConfig());
    });

    test('an edited copy without the marker line is left alone', () {
      const String mine = '# my host\nRewriteEngine On\n';
      output.writeAsStringSync(mine);
      expect(dvWriteApacheConfig(web, projectRoot: root.path), isFalse);
      expect(output.readAsStringSync(), mine);
    });

    test("the project's own web/.htaccess wins", () {
      Directory(p.join(root.path, 'web')).createSync();
      File(p.join(root.path, 'web', '.htaccess'))
          .writeAsStringSync('# the project\'s\n');
      // Flutter copied it into the build before this runs.
      output.writeAsStringSync('# the project\'s\n');
      expect(dvWriteApacheConfig(web, projectRoot: root.path), isFalse);
      expect(output.readAsStringSync(), '# the project\'s\n');
    });
  });
}

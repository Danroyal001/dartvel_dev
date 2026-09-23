// Everything `dartvel build web` and `dartvel build web-server` leave in
// build/web is minified, because nobody ships the indentation.
//
// The tests that matter here are the ones where a wrong answer still looks
// like HTML, CSS or JavaScript: a descendant selector whose space was taken,
// a `calc()` whose operator lost the spaces it needs, a `//` inside a string
// read as a comment, two statements joined across the newline a semicolon was
// never written for. Each of those produces a file that parses and behaves
// differently, which is worth more test effort than one that throws.
import 'dart:io';

import 'package:args/args.dart';
import 'package:dartvel_cli/src/build/minify.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('the flag', () {
    test('a build minifies unless it is told not to', () {
      // The owner's ask is that this needs no flag to happen. --no-minify is
      // the escape for a build somebody is about to read.
      final Option? option = BuildCommand().argParser.options['minify'];
      expect(option, isNotNull);
      expect(option!.defaultsTo, isTrue);
      expect(option.negatable, isTrue);
    });
  });

  group('HTML', () {
    test('drops comments and the whitespace between tags', () {
      final String out = dvMinifyHtml('''
<!DOCTYPE html>
<html>
  <head>
    <!-- the renderer, preloaded -->
    <title>Home</title>
  </head>
  <body>
    <div>
      <span>Hi</span>
    </div>
  </body>
</html>
''');
      expect(out, contains('<title>Home</title>'));
      expect(out, isNot(contains('<!--')));
      expect(out, isNot(contains('\n  ')));
      expect(out, contains('<div><span>Hi</span></div>'));
    });

    test('keeps one space where text had whitespace', () {
      // "one   two" collapsing to "onetwo" is the silent failure: the page
      // still renders, with two words run together.
      final String out = dvMinifyHtml('<p>one\n   two</p>');
      expect(out, '<p>one two</p>');
    });

    test('keeps the space between a tag and the word beside it', () {
      final String out = dvMinifyHtml('<p>Read <a href="/x">this</a> now</p>');
      expect(out, '<p>Read <a href="/x">this</a> now</p>');
    });

    test('leaves pre and textarea exactly as written', () {
      const String source = '<pre>  a\n    b</pre><textarea>\n  keep </textarea>';
      expect(dvMinifyHtml(source), source);
    });

    test('minifies an inline style block', () {
      final String out = dvMinifyHtml('''
<style>
  /* the shell */
  body {
    margin: 0;
  }
</style>
''');
      expect(out, contains('<style>body{margin:0}</style>'));
    });

    test('minifies an inline script without joining its lines', () {
      final String out = dvMinifyHtml('''
<script>
  // start
  const a = 1
  const b = 2
</script>
''');
      expect(out, isNot(contains('// start')));
      expect(out, contains('const a = 1\nconst b = 2'));
    });

    test('leaves JSON-LD parseable', () {
      final String out = dvMinifyHtml(
          '<script type="application/ld+json">{\n  "@type": "Article"\n}</script>');
      expect(out,
          contains('<script type="application/ld+json">{"@type":"Article"}</script>'));
    });

    test('keeps a conditional comment, which is markup and not a note', () {
      const String source = '<!--[if IE]><p>old</p><![endif]-->';
      expect(dvMinifyHtml(source), contains('<!--[if IE]>'));
    });

    test('never touches the text inside an attribute', () {
      final String out =
          dvMinifyHtml('<meta name="description" content="one  two   three">');
      expect(out, contains('content="one  two   three"'));
    });
  });

  group('CSS', () {
    test('drops comments and the space around punctuation', () {
      expect(dvMinifyCss('''
/* a note */
.card {
  color: red;
  padding: 0 1px;
}
'''), '.card{color:red;padding:0 1px}');
    });

    test('keeps the space that makes a descendant selector', () {
      // `nav a` and `nava` select different things, and only one of them
      // selects anything at all.
      expect(dvMinifyCss('nav a { color: red }'), 'nav a{color:red}');
    });

    test('keeps the spaces calc() needs around its operators', () {
      // `calc(100%-2px)` is invalid and the declaration is dropped, so the
      // page lays out at some other width rather than failing.
      expect(dvMinifyCss('.a { width: calc(100% - 2px) }'),
          '.a{width:calc(100% - 2px)}');
    });

    test('keeps a string as written', () {
      expect(dvMinifyCss('.a::after { content: "  /* not a comment */  " }'),
          '.a::after{content:"  /* not a comment */  "}');
    });

    test('keeps an at-rule and the block it opens', () {
      expect(dvMinifyCss('@media (min-width: 40rem) { .a { color: red } }'),
          '@media (min-width:40rem){.a{color:red}}');
    });
  });

  group('JavaScript', () {
    test('drops comments and indentation', () {
      expect(dvMinifyJs('''
// a note
const a = 1;
  /* block */
const b = 2;
'''), 'const a = 1;\nconst b = 2;');
    });

    test('keeps // inside a string, which is a URL and not a comment', () {
      expect(dvMinifyJs("const u = 'https://dartvel.dev/x';"),
          "const u = 'https://dartvel.dev/x';");
    });

    test('keeps what a template literal spans', () {
      const String source = 'const t = `a\n  b`;';
      expect(dvMinifyJs(source), source);
    });

    test('keeps a regex literal that contains a slash', () {
      expect(dvMinifyJs(r'const r = /a\/\/b/g; // note'),
          r'const r = /a\/\/b/g;');
    });

    test('a division is not the start of a regular expression', () {
      // The one way this minifier can eat working code: read `/` as opening a
      // pattern and swallow everything to the next one, comments and all.
      // What decides it is the token before the slash.
      expect(dvMinifyJs('const a = b / c;\nconst d = e[0] / f() / 2;'),
          'const a = b / c;\nconst d = e[0] / f() / 2;');
      expect(dvMinifyJs('let x = 1;\nx /= 2;'), 'let x = 1;\nx /= 2;');
    });

    test('a slash that opens nothing closes on its own line', () {
      // Wrong either way, and the damage is bounded to the line: a pattern
      // that does not terminate before the newline was a division.
      expect(dvMinifyJs('const a = (b) / c;\nconst d = 2;'),
          'const a = (b) / c;\nconst d = 2;');
    });

    test('never joins two lines, because a semicolon may be missing', () {
      // `const a = 1 const b = 2` is a syntax error, and joining lines that
      // relied on automatic semicolon insertion is how a minifier produces
      // one out of a file that worked.
      expect(dvMinifyJs('const a = 1\nconst b = 2'), 'const a = 1\nconst b = 2');
    });
  });

  group('the pass over a built web output', () {
    late Directory web;

    setUp(() {
      web = Directory.systemTemp.createTempSync('dv_minify_');
    });

    tearDown(() {
      if (web.existsSync()) web.deleteSync(recursive: true);
    });

    void write(String path, String contents) {
      final File file = File(p.join(web.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    test('minifies the HTML, CSS and JS it wrote', () {
      write('index.html', '<html>\n  <body>\n    <p>hi</p>\n  </body>\n</html>');
      write('styles.css', '.a {\n  color: red;\n}\n');
      write('app.js', '// note\nconst a = 1;\n');

      final DVMinifyReport report = dvMinifyWebOutput(web);

      expect(File(p.join(web.path, 'index.html')).readAsStringSync(),
          isNot(contains('\n  ')));
      expect(File(p.join(web.path, 'styles.css')).readAsStringSync(),
          '.a{color:red}');
      expect(File(p.join(web.path, 'app.js')).readAsStringSync(), 'const a = 1;');
      expect(report.files, 3);
      expect(report.saved, greaterThan(0));
    });

    test('leaves the compiler\'s own output alone', () {
      // dart2js already minified it, and a second pass over a megabyte of
      // generated JavaScript can only cost time or correctness.
      const String compiled = '// dart2js\nself.window = self;\n';
      write('main.dart.js', compiled);
      write('flutter_bootstrap.js', compiled);
      write('canvaskit/canvaskit.js', compiled);

      dvMinifyWebOutput(web);

      expect(File(p.join(web.path, 'main.dart.js')).readAsStringSync(), compiled);
      expect(File(p.join(web.path, 'flutter_bootstrap.js')).readAsStringSync(),
          compiled);
      expect(File(p.join(web.path, 'canvaskit', 'canvaskit.js')).readAsStringSync(),
          compiled);
    });

    test('minifies the service worker, which the build wrote itself', () {
      // Named flutter_service_worker.js because that is the name index.html
      // registers, but Dartvel writes it: a build's own precache list, and
      // the largest file the pass has any business touching.
      write('flutter_service_worker.js', '// dartvel\nconst CACHE = "v1";\n');

      dvMinifyWebOutput(web);

      expect(File(p.join(web.path, 'flutter_service_worker.js')).readAsStringSync(),
          'const CACHE = "v1";');
    });

    test('leaves the application\'s bundled assets alone', () {
      // An asset is the application's own file, whatever its extension. It is
      // read back by the app, not served as the page's own script.
      const String asset = '/* a bundled sample */\n.a { color: red; }\n';
      write('assets/samples/theme.css', asset);

      dvMinifyWebOutput(web);

      expect(File(p.join(web.path, 'assets', 'samples', 'theme.css'))
          .readAsStringSync(), asset);
    });

    test('keeps the original when minifying would not make it smaller', () {
      const String already = '.a{color:red}';
      write('small.css', already);

      final DVMinifyReport report = dvMinifyWebOutput(web);

      expect(File(p.join(web.path, 'small.css')).readAsStringSync(), already);
      expect(report.files, 0);
    });

    test('the build step runs over build/web and says what it saved', () {
      final Directory root = Directory.systemTemp.createTempSync('dv_build_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'build', 'web', 'index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<html>\n  <body>\n    <p>hi</p>\n  </body>\n</html>');

      final DVMinifyReport report = dvMinifyBuildOutput(root.path);

      expect(File(p.join(root.path, 'build', 'web', 'index.html')).readAsStringSync(),
          '<html><body><p>hi</p></body></html>');
      expect(dvMinifySummary(report), contains('1 file'));
    });

    test('a build told not to minify is left as it was', () {
      final Directory root = Directory.systemTemp.createTempSync('dv_build_');
      addTearDown(() => root.deleteSync(recursive: true));
      const String page = '<html>\n  <body>\n    <p>hi</p>\n  </body>\n</html>';
      File(p.join(root.path, 'build', 'web', 'index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(page);

      final DVMinifyReport report = dvMinifyBuildOutput(root.path, enabled: false);

      expect(File(p.join(root.path, 'build', 'web', 'index.html')).readAsStringSync(),
          page);
      expect(report.files, 0);
    });

    test('a build with no web output is not an error', () {
      final Directory root = Directory.systemTemp.createTempSync('dv_build_');
      addTearDown(() => root.deleteSync(recursive: true));

      expect(dvMinifyBuildOutput(root.path).files, 0);
    });

    test('a file it cannot read as text is left where it is', () {
      final File binary = File(p.join(web.path, 'broken.css'));
      binary.writeAsBytesSync(<int>[0xff, 0xfe, 0x00, 0x01]);

      expect(() => dvMinifyWebOutput(web), returnsNormally);
      expect(binary.readAsBytesSync(), <int>[0xff, 0xfe, 0x00, 0x01]);
    });
  });
}

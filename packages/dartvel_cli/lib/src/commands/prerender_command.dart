import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import '../utils/logger.dart';

class PrerenderCommand extends Command<void> {
  @override
  final String name = 'prerender';

  @override
  final String description = 'Prerender routes to static HTML for SEO.';

  PrerenderCommand() {
    argParser.addOption('port',
        abbr: 'p', defaultsTo: '8080', help: 'Port the app is serving on');
    argParser.addOption('output',
        abbr: 'o', defaultsTo: 'build/web', help: 'Output directory');
    argParser.addOption('base-url',
        defaultsTo: 'http://localhost:8080',
        help: 'Canonical base URL for sitemap.xml and robots.txt');
  }

  @override
  Future<void> run() async {
    final port = int.parse(argResults?['port'] as String);
    final outputDir = argResults?['output'] as String;
    final baseUrl = (argResults?['base-url'] as String).replaceAll(
      RegExp(r'/$'),
      '',
    );
    final root = Directory.current.path;
    final buildDir = Directory(p.join(root, outputDir));

    if (!buildDir.existsSync()) {
      Logger.log('❌ Build directory not found: $outputDir');
      Logger.log('Run `dartvel build` first.');
      exit(1);
    }

    Logger.log('🕷️  Starting prerender crawler on http://localhost:$port...');

    // Launch headless browser
    final browser = await puppeteer.launch(
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    );

    try {
      // We assume the app is already running or served.
      // For a robust implementation, we might want to start a server here if not running.
      // But for now, let's assume the user ran `dartvel preview` or similar, or we start a temp server.
      // Actually, let's start a temp server to be safe.
      final server = await _startTempServer(buildDir.path, port);

      try {
        final routes = await _discoverRoutes(browser, port);
        Logger.log('Found ${routes.length} routes to prerender.');

        for (final route in routes) {
          await _prerenderRoute(browser, port, route, buildDir);
        }

        await _generateSitemap(routes, buildDir, baseUrl);
        await _generateRobotsTxt(buildDir, baseUrl);

        Logger.log('✅ Prerendering complete!');
      } finally {
        await server.close();
      }
    } catch (e) {
      Logger.log('❌ Prerendering failed: $e', isError: true);
      rethrow;
    } finally {
      await browser.close();
    }
  }

  Future<HttpServer> _startTempServer(String path, int port) async {
    // Simple static file server
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    Logger.log('Started temp server on port $port');

    server.listen((request) async {
      final response = request.response;
      var filePath = request.uri.path;
      if (filePath == '/') filePath = '/index.html';

      final file = File(p.join(path, filePath.substring(1)));
      if (await file.exists()) {
        await file.openRead().pipe(response);
      } else {
        // SPA fallback
        final index = File(p.join(path, 'index.html'));
        if (await index.exists()) {
          await index.openRead().pipe(response);
        } else {
          response.statusCode = HttpStatus.notFound;
          unawaited(response.close());
        }
      }
    });
    return server;
  }

  Future<List<String>> _discoverRoutes(Browser browser, int port) async {
    // In a real app, we might parse the router config or crawl links.
    // For now, let's crawl from root and find all internal links.
    final page = await browser.newPage();
    await page.goto('http://localhost:$port/', wait: Until.networkIdle);

    // Extract links
    final links = await page.evaluate<List<Object?>>('''() => {
      return Array.from(document.querySelectorAll('a'))
        .map(a => a.getAttribute('href'))
        .filter(href => href && href.startsWith('/'));
    }''');

    final routes = {'/'};
    for (final link in links) {
      routes.add(link as String);
    }

    await page.close();
    return routes.toList();
  }

  Future<void> _prerenderRoute(
      Browser browser, int port, String route, Directory outDir) async {
    Logger.log('Rendering $route...');
    final page = await browser.newPage();
    await page.goto('http://localhost:$port$route', wait: Until.networkIdle);

    // The page's semantics tree, as structure rather than as Flutter's DOM.
    //
    // The first version of this took flt-semantics-host's innerHTML whole,
    // which is Flutter's internals: <flt-semantics> elements carrying inline
    // transforms and pixel sizes. Injecting that into a page gives a crawler
    // a wall of positioned divs, not a document.
    //
    // What comes out here is role, heading level, label, destination and
    // children -- the structure the application declared, which is the same
    // one a screen reader is given. dvSemanticHtml turns it into headings,
    // anchors and landmarks.
    final String semanticTree = await page.evaluate<String>(r"""() => {
      const host = document.querySelector('flt-semantics-host');
      if (!host) return '[]';

      const labelOf = (el) => {
        const aria = el.getAttribute('aria-label');
        if (aria) return aria;
        // This element's own text, not its descendants': Flutter puts a
        // label in a span, or directly inside an anchor.
        let text = '';
        for (const child of el.childNodes) {
          if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
          else if (child.tagName === 'SPAN') text += child.textContent;
        }
        return text.trim();
      };

      const walk = (el) => {
        const out = [];
        for (const child of el.children) {
          const tag = child.tagName.toLowerCase();
          if (tag === 'flt-semantics-scroll-overflow') continue;
          // Flutter emits a heading as a real h1..h6 element rather than as
          // role="heading", so the tag carries the level.
          const heading = /^h([1-6])$/.exec(tag);
          if (tag !== 'a' && tag !== 'flt-semantics' && !heading) continue;
          const aria = child.getAttribute('aria-level');
          const node = {
            role: child.getAttribute('role') || (tag === 'a' ? 'link' : null),
            level: heading ? parseInt(heading[1], 10)
                           : (aria ? parseInt(aria, 10) : null),
            label: labelOf(child),
            href: child.getAttribute('href'),
            children: walk(child),
          };
          // Nothing to say, nowhere to go, nothing inside.
          if (!node.label && !node.href && node.children.length === 0) continue;
          out.push(node);
        }
        return out;
      };

      return JSON.stringify(walk(host));
    }""");

    final title = await page.title;

    // Save to file
    // We create a directory structure: /about -> /about/index.html (or a separate prerender cache)
    // We'll save it as .html.prerender to be injected by the server

    final cleanRoute = route == '/' ? 'index' : route.substring(1);
    final saveDir = Directory(p.join(outDir.path, 'prerender', cleanRoute));
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);

    final meta = <String, Object?>{
      'title': title,
      'route': route,
    };

    File(p.join(saveDir.path, 'meta.json')).writeAsStringSync(jsonEncode(meta));

    // Where `dartvel build web` looks for it, so the crawler-visible HTML is
    // rebuilt from the tree rather than from string literals in the source.
    final semanticsDir =
        Directory(p.join(Directory.current.path, '.dart_tool', 'dartvel_semantics'));
    semanticsDir.createSync(recursive: true);
    final name = route == '/'
        ? 'index'
        : route.replaceAll(RegExp(r'^/|/$'), '').replaceAll('/', '_');
    File(p.join(semanticsDir.path, '$name.json'))
        .writeAsStringSync(semanticTree);

    final nodes = (jsonDecode(semanticTree) as List<Object?>).length;
    Logger.log('   $route: $nodes top-level semantic nodes');

    await page.close();
  }

  Future<void> _generateSitemap(
    List<String> routes,
    Directory outDir,
    String baseUrl,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');

    for (final route in routes) {
      buffer.writeln('  <url>');
      buffer.writeln('    <loc>$baseUrl$route</loc>');
      buffer.writeln('    <changefreq>weekly</changefreq>');
      buffer.writeln('  </url>');
    }

    buffer.writeln('</urlset>');
    File(p.join(outDir.path, 'sitemap.xml'))
        .writeAsStringSync(buffer.toString());
  }

  Future<void> _generateRobotsTxt(Directory outDir, String baseUrl) async {
    final content = '''
User-agent: *
Allow: /
Sitemap: $baseUrl/sitemap.xml
''';
    File(p.join(outDir.path, 'robots.txt')).writeAsStringSync(content);
  }
}

import 'dart:io';
import 'dart:convert';
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
  }

  @override
  Future<void> run() async {
    final port = int.parse(argResults?['port'] as String);
    final outputDir = argResults?['output'] as String;
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

        await _generateSitemap(routes, buildDir);
        await _generateRobotsTxt(buildDir);

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
          response.close();
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
    final links = await page.evaluate<List<dynamic>>('''() => {
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

    // Wait for semantics or some indicator
    // Flutter web semantics can be enabled via flag, but we might need to trigger it.
    // For now, let's assume we just want to scrape the accessibility tree if available,
    // or just take a screenshot.

    // Enable semantics if not already
    await page.evaluate('''() => {
      // Trigger semantics update if possible in Flutter Web
      // This is tricky without explicit app support, but let's try to find semantics nodes
      // flt-semantics-host is usually the tag
    }''');

    // Extract semantic content (simplified)
    // Extract semantic content
    final semanticHtml = await page.evaluate<String>('''() => {
      // 1. Try flt-semantics-host (Flutter's built-in semantics)
      const host = document.querySelector('flt-semantics-host');
      if (host && host.innerText.trim().length > 0) return host.innerHTML;

      // 2. Try to extract structured content (e.g. from package:seo)
      // We clone body and remove known non-content elements
      const clone = document.body.cloneNode(true);
      
      // Remove scripts, styles, and Flutter engine internals that don't contain content
      const toRemove = clone.querySelectorAll('script, style, noscript, flt-glass-pane, .flt-text-editing-host');
      toRemove.forEach(el => el.remove());
      
      // If we have remaining content that looks like HTML tags, return it
      if (clone.innerHTML.trim().length > 0) {
        // Optional: Clean up empty divs or spans if needed
        return clone.innerHTML;
      }

      // 3. Fallback: text content
      return document.body.innerText;
    }''');

    final title = await page.title;

    // Save to file
    // We create a directory structure: /about -> /about/index.html (or a separate prerender cache)
    // We'll save it as .html.prerender to be injected by the server

    final cleanRoute = route == '/' ? 'index' : route.substring(1);
    final saveDir = Directory(p.join(outDir.path, 'prerender', cleanRoute));
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);

    final meta = {
      'title': title,
      'content': semanticHtml,
      'route': route,
    };

    File(p.join(saveDir.path, 'meta.json')).writeAsStringSync(jsonEncode(meta));

    await page.close();
  }

  Future<void> _generateSitemap(List<String> routes, Directory outDir) async {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');

    for (final route in routes) {
      buffer.writeln('  <url>');
      buffer.writeln(
          '    <loc>https://example.com$route</loc>'); // TODO: Configurable host
      buffer.writeln('    <changefreq>weekly</changefreq>');
      buffer.writeln('  </url>');
    }

    buffer.writeln('</urlset>');
    File(p.join(outDir.path, 'sitemap.xml'))
        .writeAsStringSync(buffer.toString());
  }

  Future<void> _generateRobotsTxt(Directory outDir) async {
    final content = '''
User-agent: *
Allow: /
Sitemap: https://example.com/sitemap.xml
''';
    File(p.join(outDir.path, 'robots.txt')).writeAsStringSync(content);
  }
}

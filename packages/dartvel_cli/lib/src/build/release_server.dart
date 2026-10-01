import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:yaml/yaml.dart';

import 'package:dartvel_core/dartvel.dart'
    show
        DVAdminMount,
        DVAdminServer,
        DVDatabaseAdapter,
        DVModelDataApi,
        DVPublishedPages,
        DVStudioDevGrant;

import '../build/dev_studio.dart';
import '../build/studio_parts.dart'
    show dvReadStudioParts, dvStudioDataDirectory, dvStudioPartsDirectory;
import '../build/web_server.dart';

import '../utils/logger.dart';

/// Serve an existing production build through the shared web renderer.
Future<void> dvServeRelease({
  required String root,
  required String host,
  required int port,
}) async {
  final buildDir = Directory(p.join(root, 'build', 'web'));

  if (!buildDir.existsSync()) {
    Logger.log('❌ No build found. Run: dartvel build');
    exit(1);
  }

  Logger.log('📦 Serving build/web on http://$host:$port');
  Logger.log('Press Ctrl+C to stop');

  // `dartvel build web-server` writes dartvel_routes.json instead of
  // prerendering a file per route, and deletes the static pages an earlier
  // static build left behind so they cannot shadow the live ones. Serving
  // that build as plain files therefore hands back one shell for every URL,
  // with no per-route title, canonical or crawler-visible text -- which is
  // the whole difference between the two targets.
  final manifest = File(p.join(buildDir.path, 'dartvel_routes.json'));
  final serverRendered = manifest.existsSync();

  try {
    final HttpServer server;
    if (serverRendered) {
      Logger.log(
        '   Rendering each route on request '
        '(dartvel_routes.json present).',
      );
      // The admin, where the project asked for one. Release serving is a
      // development server, so the mount is read with release: false --
      // which is what makes a new project's dashboard work with no
      // configuration, and what makes a deployed one have to ask.
      final DVAdminMount admin = dvDevStudioMount(_dartvelSection(root));
      // Studio's data as well as its files, over the project's database,
      // for the browser that opens the development grant's link.
      final DVDatabaseAdapter? database = dvDevStudioDatabase(
        root,
        Platform.environment,
      );
      final DVStudioDevGrant grant = DVStudioDevGrant.generate();
      if (admin.enabled) {
        Logger.log(
          '   Studio at ${admin.path}, for the browser that opens '
          '${grant.link('http://localhost:$port', admin)} '
          '(dartvel.admin.path moves it, dartvel.admin.enabled turns it off).',
        );
        if (database == null) {
          Logger.log(
            '   Studio has no database to read: set DATABASE_URL '
            'for the dartvel.database this project uses.',
          );
        }
      }
      server = await shelf_io.serve(
        dvWebServerHandler(
          webRoot: buildDir.path,
          admin: admin,
          // Studio as the binary serves it: pages of the application
          // rendered from its shell, its data from what the build kept
          // for it, and its code handed out from memory.
          adminServer: admin.enabled
              ? DVAdminServer(
                  mount: admin,
                  root: p.join(root, dvStudioDataDirectory),
                  webRoot: buildDir.path,
                  title: 'Studio · ${_appName(root)}',
                  studioParts: <String, Uint8List>{
                    for (final MapEntry<String, List<int>> part
                        in dvReadStudioParts(
                          p.join(root, dvStudioPartsDirectory),
                        ).entries)
                      part.key: Uint8List.fromList(part.value),
                  },
                  devGrant: grant,
                  models: dvDevStudioModels(root),
                  database: database,
                )
              : null,
          publishedPages: DVPublishedPages(database: () => database),
          modelData: DVModelDataApi(database: () => database),
        ),
        host,
        port,
      );
    } else {
      server = await shelf_io.serve(
        createStaticHandler(
          buildDir.path,
          defaultDocument: 'index.html',
          listDirectories: false,
        ),
        host,
        port,
      );
    }

    Logger.log('✅ Server started successfully on http://$host:${server.port}');
    Logger.log('');

    // Keep server running
    await ProcessSignal.sigint.watch().first;

    Logger.log('\n🛑 Shutting down server...');
    await server.close(force: true);
  } catch (e) {
    Logger.log('❌ Failed to start server: $e');
    exit(1);
  }
}

/// The project's name, as its pubspec gives it.
String _appName(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  try {
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? name = document is Map ? document['name'] : null;
    return name is String && name.trim().isNotEmpty
        ? name.trim()
        : 'Dartvel application';
  } on Object {
    return 'Dartvel application';
  }
}

/// The `dartvel:` section of the project's pubspec, or null.
///
/// Read here rather than taken from the build manifest because the mount is
/// a property of the project, not of the artifact: moving the admin should
/// not need a rebuild before `dartvel dev --release` honours it.
Object? _dartvelSection(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  try {
    final Object? document = loadYaml(pubspec.readAsStringSync());
    return document is Map ? document['dartvel'] : null;
  } on Object {
    // A pubspec this cannot parse is a problem the build reports properly.
    // Refusing to serve it would be this command reporting somebody
    // else's error, worse.
    return null;
  }
}

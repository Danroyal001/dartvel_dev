/// Every page the application answers, as Studio lists them.
///
/// Studio's Pages listed what its own table held -- the pages somebody had
/// published from Studio -- so a site made of fifty compiled pages opened on
/// "0 pages". The pages a build compiled are in the project graph the build
/// writes beside Studio, and the ones Studio stored are in `dartvel_pages`;
/// this is the two together, each marked for what it is, which is the list
/// the Pages section and the Site map both show.
library;

import 'dart:convert';
import 'dart:io';

/// What kind of page a route is.
enum DVStudioPageKind {
  /// Compiled from the project's source.
  code,

  /// Published from Studio, at a route no compiled page answers.
  stored,

  /// Published from Studio at a compiled page's route, which it takes over
  /// until it is deleted.
  override,
}

/// One route of the site.
class DVStudioSitePage {
  const DVStudioSitePage({
    required this.path,
    required this.kind,
    this.page,
    this.source,
    this.title,
    this.module,
    this.pageKind,
    this.structure = false,
  });

  final String path;
  final DVStudioPageKind kind;

  /// The compiled page's function, and the file and line it is declared at.
  final String? page;
  final String? source;

  /// The stored document's title.
  final String? title;

  /// The mounted module a compiled page comes from.
  final String? module;

  /// How the graph describes a compiled page: `page`, `account page`,
  /// `module page`.
  final String? pageKind;

  /// Whether the build captured the compiled page's structure, which Studio
  /// opens it with.
  final bool structure;

  /// A page from [toJson]'s output.
  factory DVStudioSitePage.fromJson(Map<Object?, Object?> json) {
    String? text(String key) => json[key] is String ? json[key]! as String : null;
    return DVStudioSitePage(
      path: '${json['path']}',
      kind: DVStudioPageKind.values.firstWhere(
        (DVStudioPageKind kind) => kind.name == json['kind'],
        orElse: () => DVStudioPageKind.code,
      ),
      page: text('page'),
      source: text('source'),
      title: text('title'),
      module: text('module'),
      pageKind: text('pageKind'),
      structure: json['structure'] == true,
    );
  }

  /// Whether a stored document serves this route.
  bool get isStored => kind != DVStudioPageKind.code;

  /// Whether a compiled page answers this route, stored over or not.
  bool get isCompiled => kind != DVStudioPageKind.stored;

  /// Whether the route is a pattern with parameters rather than one page.
  bool get isDynamic => params.isNotEmpty;

  /// The path's parameters: `/articles/:slug` has `slug`.
  List<String> get params => dvStudioRouteParams(path);

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'kind': kind.name,
    'page': ?page,
    'source': ?source,
    'title': ?title,
    'module': ?module,
    'pageKind': ?pageKind,
    'params': params,
    if (structure) 'structure': true,
  };
}

/// The parameters a route pattern names, in order: `:slug`, `{slug}` and
/// `[slug]` all name `slug`.
List<String> dvStudioRouteParams(String path) => <String>[
  for (final RegExpMatch m
      in RegExp(r':([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\}|\[([A-Za-z_][A-Za-z0-9_]*)\]')
          .allMatches(path))
    m.group(1) ?? m.group(2) ?? m.group(3)!,
];

/// The file name a route's captured structure is kept under, as the build's
/// semantics capture names it: `/` is `index`, `/docs/cli` is `docs_cli`.
/// Null for a route that could name a file outside the directory.
String? dvStudioStructureName(String route) {
  if (!route.startsWith('/') || route.contains('..') || route.contains(r'\')) {
    return null;
  }
  final String name = route == '/'
      ? 'index'
      : route.replaceAll(RegExp(r'^/|/$'), '').replaceAll('/', '_');
  if (name.isEmpty || !RegExp(r'^[A-Za-z0-9_\-.:\[\]{}]+$').hasMatch(name)) {
    return null;
  }
  return name;
}

/// The directory under the admin root the build copies each route's
/// captured structure into.
const String dvStudioStructureDirectory = 'structure';

/// The routes the project graph in [root] lists, or none when there is no
/// graph to read.
List<Map<String, Object?>> dvStudioGraphRoutes(String? root) {
  if (root == null) return const <Map<String, Object?>>[];
  final File graph = File('$root${Platform.pathSeparator}graph.json');
  try {
    final Object? decoded = jsonDecode(graph.readAsStringSync());
    final Object? routes = decoded is Map ? decoded['routes'] : null;
    return <Map<String, Object?>>[
      if (routes is List)
        for (final Object? route in routes)
          if (route is Map && route['path'] is String)
            route.cast<String, Object?>(),
    ];
  } on Object {
    return const <Map<String, Object?>>[];
  }
}

/// The structure captured for [route] in [directory], or null.
Object? dvStudioStructureIn(String? directory, String route) {
  final String? name = dvStudioStructureName(route);
  if (directory == null || name == null) return null;
  final File file = File('$directory${Platform.pathSeparator}$name.json');
  try {
    return jsonDecode(file.readAsStringSync());
  } on Object {
    return null;
  }
}

/// The structure captured for [route] in [directory], without the layout
/// around it: every part that at least half of the captured pages share,
/// identically, is the site's header, navigation or footer rather than this
/// page's own content, and an override of the page would otherwise draw it a
/// second time inside the layout that already does. Null when nothing was
/// captured for [route].
Object? dvStudioPageContentIn(String? directory, String route) {
  final Object? tree = dvStudioStructureIn(directory, route);
  if (tree is! List || directory == null) return tree;
  final List<Object?> pages = <Object?>[];
  try {
    for (final FileSystemEntity entity in Directory(directory).listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('.images.json')) continue;
      try {
        pages.add(jsonDecode(entity.readAsStringSync()));
      } on FormatException {
        // Skipped: one unreadable capture does not decide what is shared.
      }
    }
  } on FileSystemException {
    return tree;
  }
  // Too few pages to tell a layout from a coincidence.
  if (pages.length < 3) return tree;
  final Map<String, int> shared = <String, int>{};
  for (final Object? page in pages) {
    final Set<String> seen = <String>{};
    void count(Object? node) {
      if (node is! Map) return;
      final String signature = jsonEncode(node);
      if (seen.add(signature)) shared[signature] = (shared[signature] ?? 0) + 1;
      for (final Object? child in (node['children'] as List?) ?? const <Object?>[]) {
        count(child);
      }
    }

    if (page is List) page.forEach(count);
  }
  final int threshold = (pages.length / 2).ceil();
  Object? strip(Object? node) {
    if (node is! Map) return node;
    return <String, Object?>{
      ...node.cast<String, Object?>(),
      'children': <Object?>[
        for (final Object? child in (node['children'] as List?) ?? const <Object?>[])
          if (child is! Map || (shared[jsonEncode(child)] ?? 0) < threshold)
            strip(child),
      ],
    };
  }

  return <Object?>[
    for (final Object? node in tree)
      if (node is! Map || (shared[jsonEncode(node)] ?? 0) < threshold)
        strip(node),
  ];
}

/// Whether a structure was captured for [route] in [directory].
bool dvStudioHasStructure(String? directory, String route) {
  final String? name = dvStudioStructureName(route);
  if (directory == null || name == null) return false;
  return File('$directory${Platform.pathSeparator}$name.json').existsSync();
}

/// Where Dartvel keeps documents that are not pages: under it, Studio's
/// components (at [dvStudioComponentsPrefix]). Nothing is served as a page
/// at an address here, listed as one, or put in a sitemap.
const String dvStudioReservedPrefix = '/_dartvel/';

/// Where a component made in Studio is stored: `<prefix><Name>`.
const String dvStudioComponentsPrefix = '/_dartvel/components/';

/// Whether [route] is Dartvel's rather than a page's.
bool dvStudioIsReservedRoute(String route) =>
    route.startsWith(dvStudioReservedPrefix);

/// Every route of the site: each compiled one, marked as overridden when
/// [stored] has a document at its path, then the stored routes no compiled
/// page answers. Sorted by path.
///
/// [compiled] is the application's own route list, however it was learned:
/// the project graph a build wrote beside Studio, or the route manifest
/// compiled into the application Studio runs in. Each entry carries `path`,
/// and may carry `page`, `source`, `kind` and `module`. [stored] maps a
/// stored document's route to its title. Nothing here knows any one
/// project's routes.
List<DVStudioSitePage> dvStudioSitePages({
  required Iterable<Map<String, Object?>> compiled,
  required Map<String, String?> stored,
  bool Function(String path)? hasStructure,
}) {
  final List<DVStudioSitePage> pages = <DVStudioSitePage>[];
  final Set<String> seen = <String>{};
  for (final Map<String, Object?> route in compiled) {
    final Object? path = route['path'];
    if (path is! String || !seen.add(path)) continue;
    String? text(String key) =>
        route[key] is String && '${route[key]}'.isNotEmpty
            ? route[key]! as String
            : null;
    pages.add(
      DVStudioSitePage(
        path: path,
        kind: stored.containsKey(path)
            ? DVStudioPageKind.override
            : DVStudioPageKind.code,
        page: text('page'),
        source: text('source'),
        module: text('module'),
        pageKind: text('kind'),
        title: stored[path],
        structure: hasStructure?.call(path) ?? false,
      ),
    );
  }
  for (final MapEntry<String, String?> page in stored.entries) {
    if (seen.contains(page.key) || dvStudioIsReservedRoute(page.key)) continue;
    pages.add(
      DVStudioSitePage(
        path: page.key,
        kind: DVStudioPageKind.stored,
        title: page.value,
      ),
    );
  }
  pages.sort(
    (DVStudioSitePage a, DVStudioSitePage b) => a.path.compareTo(b.path),
  );
  return pages;
}

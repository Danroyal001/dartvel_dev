import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVDiagnostic, DVDiagnostics;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/backend_generator.dart';
import '../generators/page_policy.dart';
import '../generators/policy_classes.dart';
import '../generators/static_paths_generator.dart';
import '../graph/module_mounts.dart';
import '../graph/project_graph.dart';
import '../module_trust/capabilities.dart';
import '../module_trust/module_trust.dart';
import 'docs_document.dart';

export 'docs_document.dart';

/// The node kinds a decision record can name, as `` `kind:target` ``.
const List<String> dvDocsReferenceKinds = <String>[
  'model',
  'field',
  'route',
  'function',
  'job',
  'schedule',
  'policy',
  'module',
];

/// The file the documentation build leaves in its output directory, so a
/// later build knows the directory is its own to clear.
const String dvDocsMarker = '.dartvel-docs';

/// The documentation for one application: a second reading of the project
/// graph, the same graph `dartvel inspect` and `dartvel mcp` answer from, plus
/// what the generators already read beside it.
///
/// Nothing is authored here. A description is the doc comment above the
/// declaration, read through the node's source mapping; a node whose mapping
/// no longer resolves is rendered without one and reported, rather than
/// rendered with something plausible.
///
/// What this is not is the site. `dartvel docs` compiles `DVDocsApp` and
/// writes this beside it, and the application draws every page from it -- so
/// what the build produces here is the content, and the site itself is code
/// like every other page in the framework.
class DVDocsSite {
  const DVDocsSite({required this.document, required this.graph});

  /// Every page of the site, as data.
  final DVDocsDocument document;

  /// The graph the document was rendered from, published beside it.
  final DartvelProjectGraph graph;

  /// Sorted by code, then source. What `--fatal-warnings` decides on, and
  /// what the application shows as drift.
  List<DVDocsFinding> get findings => document.findings;

  /// The artifacts this build writes, by name.
  ///
  /// Two files rather than the nine pages this used to write: the pages are in
  /// [document], and the application is what turns them into pages. Byte
  /// deterministic for a given project -- nothing here reads a clock, an
  /// absolute path or an unsorted listing.
  Map<String, String> get files => <String, String>{
    dvDocsGraphFile: graphJson,
    dvDocsPayloadFile: payload,
  };

  /// The document, as the application reads it.
  String get payload =>
      '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n';

  /// The raw graph, so a reader can diff it against a commit.
  String get graphJson =>
      '${const JsonEncoder.withIndent('  ').convert(graph.toJson())}\n';

  /// One of [files] by name.
  String file(String name) => files[name]!;

  /// Builds the site for the project at [root].
  ///
  /// [graph] is the graph to render, built from [root] when omitted. Passing
  /// one is how a caller holding an older graph renders it; its mappings are
  /// still checked against the files as they are now.
  static Future<DVDocsSite> build({
    required String root,
    DartvelProjectGraph? graph,
  }) async {
    final String pkgName = _packageName(root);
    final _Builder builder = _Builder(
      root: root,
      pkgName: pkgName,
      graph:
          graph ??
          await DartvelProjectGraph.build(root: root, pkgName: pkgName),
    );
    await builder.collect();
    return builder.render();
  }

  /// Writes the artifacts into [directory], removing anything an earlier build
  /// wrote that this one does not produce.
  ///
  /// Refuses a non-empty directory that an earlier documentation build did
  /// not write: clearing what the site does not produce from `--output lib`
  /// would delete the application.
  void writeTo(String directory) {
    final Directory out = Directory(directory);
    final File marker = File(p.join(out.path, dvDocsMarker));
    if (out.existsSync() && !marker.existsSync() && out.listSync().isNotEmpty) {
      throw StateError(
        '$directory is not empty and was not written by dartvel docs, so '
        'nothing in it will be removed. Choose an empty or new directory '
        'with --output.',
      );
    }
    out.createSync(recursive: true);
    for (final FileSystemEntity entity in out.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String relative = p
          .relative(entity.path, from: out.path)
          .replaceAll(r'\', '/');
      if (relative == dvDocsMarker) continue;
      if (!files.containsKey(relative)) entity.deleteSync();
    }
    // Directories emptied by the removals above, deepest first.
    final List<Directory> directories =
        out
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort(
            (Directory a, Directory b) =>
                b.path.length.compareTo(a.path.length),
          );
    for (final Directory d in directories) {
      if (d.listSync().isEmpty) d.deleteSync();
    }
    files.forEach((String relative, String contents) {
      final File file = File(
        p.joinAll(<String>[out.path, ...relative.split('/')]),
      );
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.readAsStringSync() == contents) return;
      file.writeAsStringSync(contents);
    });
    marker.writeAsStringSync(
      'Written by dartvel docs. Files here that the build does not produce '
      'are removed on the next build.\n',
    );
  }

  static String _packageName(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return 'app';
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      if (loaded is YamlMap && loaded['name'] is String) {
        return loaded['name'] as String;
      }
    } on Object {
      // The build reports a pubspec that does not parse; the site still
      // renders what the graph found.
    }
    return 'app';
  }
}

/// A resolved `path:line` source mapping.
class _Mapping {
  const _Mapping(this.file, this.line, this.lines);

  final String file;

  /// 1-based.
  final int line;
  final List<String> lines;

  String get source => '$file:$line';
}

class _Policy {
  const _Policy(this.declaration, this.source);

  final DVPolicyClass declaration;
  final String source;
}

class _Decision {
  _Decision(this.file, this.id, this.title);

  /// Relative to the project.
  final String file;

  /// What a link names this record by, and what the application routes it at.
  final String id;

  final String title;

  /// The record's own heading, its source, and its body.
  late List<DVDocsBlock> blocks;

  DVDocsTarget get target => DVDocsTarget.page(id);
}

class _Route {
  _Route({
    required this.path,
    required this.kind,
    this.page,
    this.source,
    this.mapping,
    this.model,
    this.module,
    this.location,
    this.policy,
    this.middleware = const <String>[],
    this.unmapped = false,
  });

  final String path;

  /// `page`, `account page`, `model page` or `module page`.
  final String kind;
  final String? page;
  final String? source;
  final _Mapping? mapping;
  final String? model;
  final String? module;
  final String? location;
  final String? policy;
  final List<String> middleware;
  final bool unmapped;
}

typedef _Schedule = ({
  String name,
  String cron,
  bool client,
  String file,
  bool? catchUp,
});

class _Builder {
  _Builder({required this.root, required this.pkgName, required this.graph});

  final String root;
  final String pkgName;
  final DartvelProjectGraph graph;

  final List<DVDocsFinding> findings = <DVDocsFinding>[];
  final Map<String, List<String>?> _sources = <String, List<String>?>{};

  final List<_Policy> policies = <_Policy>[];
  List<_Schedule> schedules = <_Schedule>[];
  List<DVModuleMount> mounts = <DVModuleMount>[];
  List<StaticPathsProvider> providers = <StaticPathsProvider>[];
  final List<_Route> routes = <_Route>[];
  final List<_Decision> decisions = <_Decision>[];

  /// `kind:target` to the page and anchor it is rendered at.
  ///
  /// A target and not an href: the app routes a page from its id, so a link
  /// that names a page id and an anchor cannot break by pointing at a file
  /// that moved.
  final Map<String, DVDocsTarget> nodes = <String, DVDocsTarget>{};

  /// `kind:target` to the decisions naming it, in decision order.
  final Map<String, List<_Decision>> backlinks = <String, List<_Decision>>{};

  // ---------------------------------------------------------------- collect

  Future<void> collect() async {
    for (final File file in _dartFiles()) {
      final String rel = _rel(file.path);
      final String source = file.readAsStringSync();
      for (final DVPolicyClass c in dvPolicyClassesIn(source, rel)) {
        final int at = source.indexOf(
          RegExp('class\\s+(?:const\\s+)?${c.className}\\b'),
        );
        policies.add(_Policy(c, '$rel:${_lineOf(source, at < 0 ? 0 : at)}'));
      }
    }
    policies.sort((_Policy a, _Policy b) {
      final int byResource = a.declaration.resource.compareTo(
        b.declaration.resource,
      );
      return byResource != 0
          ? byResource
          : a.declaration.className.compareTo(b.declaration.className);
    });

    schedules =
        (await BackendGenerator.cronSchedules(root: root, pkgName: pkgName))
          ..sort((_Schedule a, _Schedule b) {
            final int byName = a.name.compareTo(b.name);
            return byName != 0 ? byName : a.file.compareTo(b.file);
          });

    mounts = dvDiscoverModuleMounts(root);
    // A copy: discovery answers a constant empty list for a project with no
    // lib directory, and sorting that in place threw.
    providers =
        List<StaticPathsProvider>.of(
          StaticPathsGenerator.discover(root: root, pkgName: pkgName),
        )..sort(
          (StaticPathsProvider a, StaticPathsProvider b) =>
              (a.className ?? '').compareTo(b.className ?? ''),
        );

    _collectRoutes();
    _indexNodes();
    _collectDecisions();
  }

  void _collectRoutes() {
    for (final DVGraphRoute r in graph.routes) {
      // A mounted module's routes are rendered from the mounts below, which
      // carry the module and its deployment.
      if (r.kind == 'module page') continue;
      if (r.kind == 'account page') {
        // Generated by the router from dartvel.auth.pages: there is no
        // declaration in this project to map to, and that is not drift.
        routes.add(
          _Route(path: r.path, kind: r.kind, page: r.page, source: r.source),
        );
        continue;
      }
      final _Mapping? mapping = _resolve(r.source, RegExp(r'@DVPage\b'));
      if (mapping == null) _unmapped('route ${r.path}', r.source);
      final String? file = mapping?.lines.join('\n');
      routes.add(
        _Route(
          path: r.path,
          kind: 'page',
          page: r.page,
          source: r.source,
          mapping: mapping,
          policy: file == null ? null : dvPagePolicyFromSource(file),
          middleware: file == null
              ? const <String>[]
              : dvMiddlewareKeysFromSource(file),
          unmapped: mapping == null,
        ),
      );
    }
    for (final StaticPathsProvider provider in providers) {
      if (!provider.generatesPage || provider.route == null) continue;
      final DVGraphModel? model = _model(provider.className);
      routes.add(
        _Route(
          path: provider.route!,
          kind: 'model page',
          page: '${provider.className}.Page',
          source: model?.source,
          model: provider.className,
        ),
      );
    }
    for (final DVModuleMount mount in mounts) {
      for (final DVModuleRoute r in mount.routes) {
        if (mount.deployment == DVModuleDeployment.federated) {
          // Rendered from the verified manifest, which is the only
          // description of a module deployed elsewhere; there is no source
          // in this project to map to, and that is the design rather than
          // drift.
          routes.add(
            _Route(
              path: r.mounted,
              kind: 'module page',
              module: mount.id,
              location: mount.location,
            ),
          );
          continue;
        }
        final String file = p.posix.normalize(
          p.posix.join(mount.sourcePath, r.file),
        );
        final List<String>? lines = _lines(file);
        final int index = lines == null
            ? -1
            : lines.indexWhere((String l) => l.contains(RegExp(r'@DVPage\b')));
        final String source = '$file:${index + 1}';
        final _Mapping? mapping = index < 0
            ? null
            : _Mapping(file, index + 1, lines!);
        if (mapping == null) _unmapped('route ${r.mounted}', source);
        routes.add(
          _Route(
            path: r.mounted,
            kind: 'module page',
            page: r.widget,
            module: mount.id,
            source: source,
            mapping: mapping,
            unmapped: mapping == null,
          ),
        );
      }
    }
    routes.sort((_Route a, _Route b) {
      final int byPath = a.path.compareTo(b.path);
      return byPath != 0 ? byPath : a.kind.compareTo(b.kind);
    });
  }

  void _indexNodes() {
    for (final DVGraphModel m in graph.models) {
      nodes['model:${m.name}'] = DVDocsTarget.page(
        'models',
        anchor: 'model-${m.name}',
      );
      for (final DVGraphField f in m.fields) {
        nodes['field:${m.name}.${f.name}'] = DVDocsTarget.page(
          'models',
          anchor: 'field-${m.name}-${f.name}',
        );
      }
    }
    for (final _Route r in routes) {
      nodes.putIfAbsent(
        'route:${r.path}',
        () => DVDocsTarget.page('routes', anchor: 'route-${r.path}'),
      );
    }
    for (final DVGraphFunction f in graph.functions) {
      nodes['function:${f.name}'] = DVDocsTarget.page(
        'functions',
        anchor: 'function-${f.name}',
      );
    }
    for (final DVGraphJob j in graph.jobs) {
      nodes['job:${j.name}'] = DVDocsTarget.page(
        'jobs',
        anchor: 'job-${j.name}',
      );
    }
    for (final _Schedule s in schedules) {
      nodes['schedule:${s.name}'] = DVDocsTarget.page(
        'jobs',
        anchor: 'schedule-${s.name}',
      );
    }
    for (final _Policy policy in policies) {
      nodes['policy:${policy.declaration.className}'] = DVDocsTarget.page(
        'policies',
        anchor: 'policy-${policy.declaration.resource}',
      );
    }
    for (final DVModuleMount m in mounts) {
      nodes['module:${m.id}'] = DVDocsTarget.page(
        'modules',
        anchor: 'module-${m.id}',
      );
    }
  }

  void _collectDecisions() {
    final Directory dir = Directory(p.join(root, _decisionsDir()));
    if (!dir.existsSync()) return;
    final List<File> records =
        dir
            .listSync(followLinks: false)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.md'))
            .toList()
          ..sort(
            (File a, File b) =>
                p.basename(a.path).compareTo(p.basename(b.path)),
          );
    final RegExp reference = RegExp(
      '^(${dvDocsReferenceKinds.join('|')}):(\\S.*)\$',
    );
    for (final File record in records) {
      final String rel = _rel(record.path);
      final String text = record.readAsStringSync();
      final String name = p.basenameWithoutExtension(record.path);
      final _Decision decision = _Decision(
        rel,
        'decision:$name',
        dvDocsMarkdownTitle(text) ?? name,
      );
      final List<DVDocsBlock> body = dvDocsProse(
        text,
        code: (String code, int line) {
          final RegExpMatch? m = reference.firstMatch(code.trim());
          if (m == null) return DVDocsSpan.code(code);
          final String key = '${m.group(1)}:${m.group(2)}';
          final DVDocsTarget? target = nodes[key];
          if (target == null) {
            findings.add(
              DVDocsFinding(
                code: 'DV-DOCS-001',
                source: '$rel:$line',
                message: 'names `$key`, which is not in the project graph',
              ),
            );
            return DVDocsSpan.gone(key);
          }
          final List<_Decision> named = backlinks.putIfAbsent(
            key,
            () => <_Decision>[],
          );
          if (!named.contains(decision)) named.add(decision);
          return DVDocsSpan.link(key, target);
        },
      );
      // The record's own `# heading` is this page's title, drawn by the app
      // above the content. Left in the body it would be a second one, and it
      // would cut the page in half for anything that follows a link to it.
      if (body.isNotEmpty &&
          body.first is DVDocsHeading &&
          (body.first as DVDocsHeading).level == 1) {
        body.removeAt(0);
      }
      decision.blocks = <DVDocsBlock>[
        DVDocsHeading(1, dvDocsInline(decision.title), anchor: name),
        DVDocsParagraph(<DVDocsSpan>[
          const DVDocsSpan.text('Source: '),
          DVDocsSpan.note(rel),
        ]),
        ...body,
      ];
      decisions.add(decision);
    }
  }

  String _decisionsDir() {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      final Object? docs = loaded is YamlMap && loaded['dartvel'] is YamlMap
          ? (loaded['dartvel'] as YamlMap)['docs']
          : null;
      if (docs is YamlMap && docs['decisions'] is String) {
        return docs['decisions'] as String;
      }
    } on Object {
      // Falls through to the default.
    }
    return 'docs/decisions';
  }

  // ----------------------------------------------------------------- render

  DVDocsSite render() {
    // Every page but the overview first, because rendering one is what finds
    // drift: a node whose source mapping no longer resolves is reported as
    // the page is built, so the overview -- which lists the drift -- has to be
    // rendered after them all or it lists what the earlier pages had found
    // so far.
    final Map<String, List<DVDocsBlock>> blocks = <String, List<DVDocsBlock>>{
      for (final (String id, String _) in dvDocsNavigation)
        if (id != 'index') id: _render(id),
    };
    final List<DVDocsFinding> sorted = List<DVDocsFinding>.of(findings)
      ..sort((DVDocsFinding a, DVDocsFinding b) {
        final int byCode = a.code.compareTo(b.code);
        if (byCode != 0) return byCode;
        final int bySource = a.source.compareTo(b.source);
        return bySource != 0 ? bySource : a.message.compareTo(b.message);
      });
    blocks['index'] = _index(sorted);
    return DVDocsSite(
      document: DVDocsDocument(
        application: pkgName,
        graphVersion: graph.graphVersion,
        navigation: dvDocsNavigation,
        pages: <DVDocsPage>[
          for (final (String id, String label) in dvDocsNavigation)
            DVDocsPage(id: id, title: label, blocks: blocks[id]!),
          // The decision records are not in the navigation, and they are the
          // only pages the build produced that a reader did not ask for by
          // name: each is reached from the node it explains.
          for (final _Decision d in decisions)
            DVDocsPage(id: d.id, title: d.title, source: d.file, blocks: d.blocks),
        ],
        findings: List<DVDocsFinding>.unmodifiable(sorted),
      ),
      graph: graph,
    );
  }

  List<DVDocsBlock> _render(String id) => switch (id) {
    'models' => _models(),
    'functions' => _functions(),
    'routes' => _routes(),
    'jobs' => _jobs(),
    'policies' => _policies(),
    'modules' => _modules(),
    'diagnostics' => _diagnostics(),
    _ => const <DVDocsBlock>[],
  };

  List<DVDocsBlock> _index(List<DVDocsFinding> sorted) {
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('Rendered from the project graph. Descriptions are '),
        DVDocsSpan.text('doc comments read from the source; nothing here is '),
        DVDocsSpan.text('written twice.'),
      ]),
      DVDocsTable(
        <DVDocsColumn>[
          const DVDocsColumn('Page'),
          const DVDocsColumn('Count'),
        ],
        <DVDocsRow>[
          _linkRow('Models', 'models', graph.models.length),
          _linkRow('Functions', 'functions', graph.functions.length),
          _linkRow('Routes', 'routes', routes.length),
          _linkRow('Jobs', 'jobs', graph.jobs.length),
          _linkRow('Schedules', 'jobs', schedules.length),
          _linkRow('Policies', 'policies', policies.length),
          _linkRow('Modules', 'modules', mounts.length),
          DVDocsRow(<List<DVDocsSpan>>[
            <DVDocsSpan>[
              const DVDocsSpan.link(dvDocsGraphFile, DVDocsTarget.external(dvDocsGraphFile)),
            ],
            <DVDocsSpan>[
              const DVDocsSpan.text('graphVersion '),
              DVDocsSpan.note('${graph.graphVersion}'),
            ],
          ]),
        ],
      ),
      const DVDocsHeading(2, <DVDocsSpan>[DVDocsSpan.text('Decisions')]),
    ];
    if (decisions.isEmpty) {
      out.add(
        DVDocsParagraph(<DVDocsSpan>[
          const DVDocsSpan.text('No decision records under '),
          DVDocsSpan.code(_decisionsDir()),
          const DVDocsSpan.text('.'),
        ]),
      );
    } else {
      out.add(
        DVDocsList(false, <DVDocsListItem>[
          for (final _Decision d in decisions)
            DVDocsListItem(<DVDocsSpan>[DVDocsSpan.link(d.title, d.target)]),
        ]),
      );
    }
    if (sorted.isNotEmpty) {
      out
        ..add(
          const DVDocsHeading(2, <DVDocsSpan>[DVDocsSpan.text('Drift')]),
        )
        ..add(
          DVDocsList(false, <DVDocsListItem>[
            for (final DVDocsFinding f in sorted)
              DVDocsListItem(<DVDocsSpan>[
                DVDocsSpan.link(f.code, DVDocsTarget.page('diagnostics', anchor: f.code)),
                const DVDocsSpan.text(' '),
                DVDocsSpan.note(f.source),
                const DVDocsSpan.text(' '),
                ...dvDocsInline(f.message),
              ]),
          ]),
        );
    }
    return out;
  }

  static DVDocsRow _linkRow(String label, String page, int count) =>
      DVDocsRow(<List<DVDocsSpan>>[
        <DVDocsSpan>[DVDocsSpan.link(label, DVDocsTarget.page(page))],
        <DVDocsSpan>[DVDocsSpan.note('$count')],
      ]);

  List<DVDocsBlock> _models() {
    final Set<String> names = <String>{
      for (final DVGraphModel m in graph.models) m.name,
    };
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('Example data is generated from each field\'s '),
        DVDocsSpan.text('type, never read from a database. A sensitive '),
        DVDocsSpan.text('field is named and never valued.'),
      ]),
    ];
    if (graph.models.isEmpty) {
      out.add(
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No '),
          DVDocsSpan.code('@DVModel'),
          DVDocsSpan.text(' inputs.'),
        ]),
      );
      return out;
    }
    for (final DVGraphModel m in graph.models) {
      final _Mapping? mapping = _resolve(m.source, RegExp(r'@DVModel\s*\('));
      if (mapping == null) _unmapped('model ${m.name}', m.source);
      final Map<String, String> fieldDocs = mapping == null
          ? const <String, String>{}
          : _fieldDocs(mapping, m);

      out.add(
        DVDocsHeading(2, <DVDocsSpan>[DVDocsSpan.text(m.name)], anchor: 'model-${m.name}'),
      );
      out.addAll(_description(mapping, m.source));
      out.add(
        DVDocsTable(
          <DVDocsColumn>[
            const DVDocsColumn('Field', 'name'),
            const DVDocsColumn('Type', 'type'),
            const DVDocsColumn('', 'flags'),
            const DVDocsColumn('Description', 'description'),
          ],
          <DVDocsRow>[
            for (final DVGraphField f in m.fields)
              DVDocsRow(
                <List<DVDocsSpan>>[
                  <DVDocsSpan>[DVDocsSpan.code(f.name)],
                  _typeSpans(f.type, names),
                  <DVDocsSpan>[
                    if (f.sensitive) const DVDocsSpan.badge('sensitive'),
                  ],
                  dvDocsInline(fieldDocs[f.name] ?? ''),
                ],
                'field-${m.name}-${f.name}',
              ),
          ],
        ),
      );

      final List<DVGraphField> relations = <DVGraphField>[
        for (final DVGraphField f in m.fields)
          if (_modelsIn(f.type, names).isNotEmpty) f,
      ];
      if (relations.isNotEmpty) {
        out
          ..add(
            const DVDocsHeading(
              3,
              <DVDocsSpan>[DVDocsSpan.text('Relations')],
            ),
          )
          ..add(
            DVDocsList(false, <DVDocsListItem>[
              for (final DVGraphField f in relations)
                DVDocsListItem(<DVDocsSpan>[
                  DVDocsSpan.code(f.name),
                  const DVDocsSpan.text(' → '),
                  for (final (int i, String target) in _modelsIn(
                    f.type,
                    names,
                  ).indexed)
                    ...<DVDocsSpan>[
                      if (i > 0) const DVDocsSpan.text(', '),
                      DVDocsSpan.link(
                        target,
                        DVDocsTarget.page('models', anchor: 'model-$target'),
                      ),
                    ],
                ]),
            ]),
          );
      }

      final List<_Policy> own = <_Policy>[
        for (final _Policy policy in policies)
          if (policy.declaration.resource == m.name) policy,
      ];
      out.add(
        const DVDocsHeading(3, <DVDocsSpan>[DVDocsSpan.text('Policies')]),
      );
      if (own.isEmpty) {
        out.add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('No '),
            DVDocsSpan.code('@DVPolicy(${m.name})'),
            const DVDocsSpan.text(' class: every action on it is denied.'),
          ]),
        );
      } else {
        out.add(
          DVDocsList(false, <DVDocsListItem>[
            for (final _Policy policy in own)
              DVDocsListItem(<DVDocsSpan>[
                DVDocsSpan.link(
                  policy.declaration.className,
                  DVDocsTarget.page(
                    'policies',
                    anchor: 'policy-${m.name}',
                  ),
                ),
                const DVDocsSpan.text(': '),
                DVDocsSpan.text(
                  policy.declaration.methods.isEmpty
                      ? 'no actions'
                      : policy.declaration.methods
                            .map((DVPolicyMethod x) => x.action)
                            .join(', '),
                ),
              ]),
          ]),
        );
      }

      final List<DVDocsListItem> generated = <DVDocsListItem>[
        for (final String surface in const <String>[
          'Form',
          'List',
          'Table',
          'Card',
          'PageBody',
          'Page',
        ])
          DVDocsListItem(<DVDocsSpan>[
            DVDocsSpan.code('${m.name}.$surface'),
          ]),
        for (final StaticPathsProvider provider in providers)
          if (provider.className == m.name && provider.route != null)
            DVDocsListItem(<DVDocsSpan>[
              if (provider.generatesPage)
                const DVDocsSpan.text('public page at ')
              else
                const DVDocsSpan.text('static paths for '),
              if (provider.generatesPage)
                DVDocsSpan.link(
                  provider.route!,
                  DVDocsTarget.page('routes', anchor: 'route-${provider.route!}'),
                )
              else ...<DVDocsSpan>[
                DVDocsSpan.code(provider.route!),
                const DVDocsSpan.text(' from '),
                DVDocsSpan.code(provider.resolveExpression),
              ],
            ]),
      ];
      out
        ..add(
          const DVDocsHeading(
            3,
            <DVDocsSpan>[DVDocsSpan.text('Generated')],
          ),
        )
        ..add(DVDocsList(false, generated))
        ..add(
          const DVDocsHeading(3, <DVDocsSpan>[DVDocsSpan.text('Example')]),
        )
        ..add(DVDocsCode(_example(m, names)))
        ..addAll(_backlinks('model:${m.name}'));
    }
    return out;
  }

  List<DVDocsBlock> _functions() {
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('Each function lists the stages a request passes '),
        DVDocsSpan.text('through before and around it, in the order the '),
        DVDocsSpan.text('generated backend runs them.'),
      ]),
    ];
    if (graph.functions.isEmpty) {
      out.add(
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No backend functions under '),
          DVDocsSpan.code('lib/backend/functions'),
          DVDocsSpan.text('.'),
        ]),
      );
      return out;
    }
    for (final DVGraphFunction f in graph.functions) {
      final _Mapping? mapping = _resolve(
        f.source,
        f.annotated ? RegExp(r'@DVBackendFunction\b') : null,
      );
      if (mapping == null) _unmapped('function ${f.name}', f.source);
      out
        ..add(
          DVDocsHeading(
            2,
            <DVDocsSpan>[DVDocsSpan.code(f.name)],
            anchor: 'function-${f.name}',
          ),
        )
        ..add(
          DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.strong(f.method),
            const DVDocsSpan.text(' '),
            DVDocsSpan.code(f.path),
          ]),
        );
      if (mapping == null) {
        out
          ..addAll(_unmappedParagraph(f.source))
          ..addAll(_backlinks('function:${f.name}'));
        continue;
      }
      final String file = mapping.lines.join('\n');
      final ({int line, bool typed})? declaration = _declaration(mapping, f);
      final String? signature = declaration == null
          ? null
          : _signature(mapping.lines, declaration.line, f);
      final String? policy = dvBackendPolicyFromSource(file);
      out.addAll(
        declaration == null
            ? const <DVDocsBlock>[]
            : dvDocsProse(_docAbove(mapping.lines, declaration.line)),
      );
      if (signature != null) {
        out.add(DVDocsCode(signature, signature: true));
      }
      out
        ..add(
          const DVDocsHeading(
            3,
            <DVDocsSpan>[DVDocsSpan.text('Request lifecycle')],
          ),
        )
        ..add(
          DVDocsList(true, <DVDocsListItem>[
            for (final (String id, List<DVDocsSpan> spans) in _stages(
              method: f.method,
              middleware: dvMiddlewareKeysFromSource(file),
              policy: policy,
              typed: declaration?.typed ?? false,
              context:
                  signature != null &&
                  RegExp(r'\(\s*(?:final\s+)?DVContext\s+\w+').hasMatch(signature),
            ))
              DVDocsListItem(spans, id),
          ]),
        )
        ..addAll(_sourceParagraph(f.source))
        ..addAll(_backlinks('function:${f.name}'));
    }
    return out;
  }

  /// The stages the generated backend runs a request through, in order.
  ///
  /// This mirrors the order `BackendGenerator` emits, and a test generates a
  /// real backend and checks the two agree, because a list that drifted from
  /// the handler would still read as a perfectly plausible lifecycle.
  static List<(String, List<DVDocsSpan>)> _stages({
    required String method,
    required List<String> middleware,
    required String? policy,
    required bool typed,
    required bool context,
  }) {
    final String m = method.toUpperCase();
    final bool readsBody = typed && m != 'GET' && m != 'HEAD';
    final bool limited =
        middleware.contains('bodyLimit') || middleware.contains('uploadLimit');
    return <(String, List<DVDocsSpan>)>[
      (
        'tenant',
        const <DVDocsSpan>[
          DVDocsSpan.text('Tenant scope: the tenant this request names is '),
          DVDocsSpan.text('current for everything below.'),
        ],
      ),
      (
        'privacy',
        const <DVDocsSpan>[
          DVDocsSpan.text('Privacy scope: a '),
          DVDocsSpan.code('Sec-GPC: 1'),
          DVDocsSpan.text(' header is in force for everything below, and '),
          DVDocsSpan.text('denies every consent category declared as '),
          DVDocsSpan.text('tracking.'),
        ],
      ),
      if (middleware.contains('tracing'))
        (
          'tracing',
          const <DVDocsSpan>[
            DVDocsSpan.text('Tracing span around everything below, refused '),
            DVDocsSpan.text('requests included.'),
          ],
        ),
      for (final String key in middleware)
        if (key != 'tracing')
          (
            'middleware:$key',
            <DVDocsSpan>[
              const DVDocsSpan.text('Middleware '),
              DVDocsSpan.code(key),
              const DVDocsSpan.text(', in declared order.'),
            ],
          ),
      if (readsBody)
        (
          'body',
          limited
              ? const <DVDocsSpan>[
                  DVDocsSpan.text(
                    'Body read, refused past the declared limit before it '
                    'is buffered.',
                  ),
                ]
              : const <DVDocsSpan>[DVDocsSpan.text('Body read and decoded.')],
        ),
      if (typed) ('csrf', const <DVDocsSpan>[DVDocsSpan.text('CSRF check.')]),
      if (policy != null)
        (
          'policy',
          <DVDocsSpan>[
            const DVDocsSpan.text('Policy gate '),
            DVDocsSpan.code(policy),
            const DVDocsSpan.text(': refused with 403 before the function '),
            const DVDocsSpan.text('runs.'),
          ],
        ),
      if (context)
        (
          'context',
          const <DVDocsSpan>[
            DVDocsSpan.text('A '),
            DVDocsSpan.code('DVContext'),
            DVDocsSpan.text(' is built and passed first; it is not a client '),
            DVDocsSpan.text('argument.'),
          ],
        ),
      (
        'function',
        <DVDocsSpan>[
          if (typed)
            const DVDocsSpan.text('The function.')
          else
            const DVDocsSpan.text('The raw handler, which owns the request.'),
        ],
      ),
    ];
  }

  List<DVDocsBlock> _routes() {
    if (routes.isEmpty) {
      return const <DVDocsBlock>[
        DVDocsParagraph(<DVDocsSpan>[DVDocsSpan.text('No routes.')]),
      ];
    }
    final List<DVDocsBlock> out = <DVDocsBlock>[];
    for (final _Route r in routes) {
      out
        ..add(
          DVDocsHeading(
            2,
            <DVDocsSpan>[DVDocsSpan.code(r.path)],
            anchor: 'route-${r.path}',
          ),
        )
        ..add(
          DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.text(r.kind),
            if (r.page != null) ...<DVDocsSpan>[
              const DVDocsSpan.text(' · '),
              DVDocsSpan.code(r.page!),
            ],
            if (r.module != null) ...<DVDocsSpan>[
              const DVDocsSpan.text(' · module '),
              DVDocsSpan.link(
                r.module!,
                DVDocsTarget.page('modules', anchor: 'module-${r.module}'),
              ),
            ],
          ]),
        );
      if (r.model != null) {
        out.add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('Generated from '),
            DVDocsSpan.link(
              r.model!,
              DVDocsTarget.page('models', anchor: 'model-${r.model}'),
            ),
            const DVDocsSpan.text('.'),
          ]),
        );
      }
      if (r.location != null) {
        out.add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('Served by the module\'s own deployment '),
            const DVDocsSpan.text('at '),
            DVDocsSpan.code(r.location!),
            const DVDocsSpan.text(', from its verified manifest.'),
          ]),
        );
      }
      if (r.unmapped) {
        out.addAll(_unmappedParagraph(r.source ?? ''));
      } else if (r.mapping != null) {
        out.addAll(
          dvDocsProse(_docAbove(r.mapping!.lines, r.mapping!.line)),
        );
      }
      if (r.policy != null) {
        out.add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('Guarded by '),
            DVDocsSpan.code(r.policy!),
            const DVDocsSpan.text('.'),
          ]),
        );
      }
      if (r.middleware.isNotEmpty) {
        out.add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('Middleware: '),
            for (final (int i, String key) in r.middleware.indexed) ...<DVDocsSpan>[
              if (i > 0) const DVDocsSpan.text(', '),
              DVDocsSpan.code(key),
            ],
          ]),
        );
      }
      if (r.source != null && !r.unmapped) {
        out.addAll(_sourceParagraph(r.source!));
      }
      out.addAll(_backlinks('route:${r.path}'));
    }
    return out;
  }

  List<DVDocsBlock> _jobs() {
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsHeading(
        2,
        <DVDocsSpan>[DVDocsSpan.text('Jobs')],
        anchor: 'jobs',
      ),
      if (graph.jobs.isEmpty)
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No '),
          DVDocsSpan.code('@DVJob'),
          DVDocsSpan.text(' inputs.'),
        ]),
      const DVDocsHeading(
        2,
        <DVDocsSpan>[DVDocsSpan.text('Schedules')],
        anchor: 'schedules',
      ),
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('A backend schedule runs on the server from a '),
        DVDocsSpan.text('periodic timer. A client schedule is a request, '),
        DVDocsSpan.text('not a guarantee: it ticks while the application is '),
        DVDocsSpan.text('showing a page, and each platform decides how often '),
        DVDocsSpan.text('a backgrounded or closed application runs it.'),
      ]),
      if (schedules.isEmpty)
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No '),
          DVDocsSpan.code('@DVBackendCron'),
          DVDocsSpan.text(' or '),
          DVDocsSpan.code('@DVClientCron'),
          DVDocsSpan.text(' functions.'),
        ]),
    ];
    for (final DVGraphJob j in graph.jobs) {
      final _Mapping? mapping = _resolve(j.source, RegExp(r'@DVJob\b'));
      if (mapping == null) _unmapped('job ${j.name}', j.source);
      out
        ..add(
          DVDocsHeading(
            3,
            <DVDocsSpan>[DVDocsSpan.text(j.name)],
            anchor: 'job-${j.name}',
          ),
        )
        ..add(
          DVDocsParagraph(<DVDocsSpan>[
            const DVDocsSpan.text('Queue '),
            DVDocsSpan.code(j.queue),
          ]),
        )
        ..addAll(_description(mapping, j.source))
        ..addAll(_backlinks('job:${j.name}'));
    }
    for (final _Schedule s in schedules) {
      final List<String>? lines = _lines(s.file);
      final String annotation = s.client ? 'DVClientCron' : 'DVBackendCron';
      int line = 0;
      if (lines != null) {
        final String text = lines.join('\n');
        final RegExpMatch? m = RegExp(
          '@$annotation\\s*\\((?:[^()]|\\([^()]*\\))*\\)[^;{=]*?\\b'
          '${RegExp.escape(s.name)}\\s*\\(',
        ).firstMatch(text);
        if (m != null) line = _lineOf(text, m.start);
      }
      final String source = '${s.file}:$line';
      final _Mapping? mapping = line == 0
          ? null
          : _Mapping(s.file, line, lines!);
      if (mapping == null) _unmapped('schedule ${s.name}', source);
      out
        ..add(
          DVDocsHeading(
            3,
            <DVDocsSpan>[DVDocsSpan.code(s.name)],
            anchor: 'schedule-${s.name}',
          ),
        )
        ..add(
          DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.code(s.cron),
            DVDocsSpan.text(
              ' on the ${s.client ? 'client' : 'backend'}'
              '${s.catchUp == null ? '' : ' · catch-up ${s.catchUp! ? 'on' : 'off'}'}',
            ),
          ]),
        );
      if (s.client) {
        out.add(
          const DVDocsParagraph(<DVDocsSpan>[
            DVDocsSpan.text('A request, not a guarantee: runs while the '),
            DVDocsSpan.text('application is showing a page; how often it runs '),
            DVDocsSpan.text('in the background is the platform\'s decision.'),
          ]),
        );
      }
      out
        ..addAll(_description(mapping, source))
        ..addAll(_backlinks('schedule:${s.name}'));
    }
    return out;
  }

  List<DVDocsBlock> _policies() {
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('An action no policy method answers is denied: '),
        DVDocsSpan.code('DV.Auth.authorization'),
        DVDocsSpan.text(' is default-deny. Who a method allows is decided '),
        DVDocsSpan.text('in its body, which the source link opens.'),
      ]),
      if (policies.isEmpty)
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No '),
          DVDocsSpan.code('@DVPolicy'),
          DVDocsSpan.text(' classes.'),
        ]),
    ];
    final List<String> resources = <String>{
      for (final _Policy policy in policies) policy.declaration.resource,
    }.toList();
    for (final String resource in resources) {
      out
        ..add(
          DVDocsHeading(
            2,
            _typeSpans(
              resource,
              <String>{for (final DVGraphModel m in graph.models) m.name},
            ),
            anchor: 'policy-$resource',
          ),
        )
        ..add(
          DVDocsTable(
            <DVDocsColumn>[
              const DVDocsColumn('Policy', 'policy'),
              for (final String action in dvPolicyActions)
                DVDocsColumn(action, action),
            ],
            <DVDocsRow>[
              for (final _Policy policy in policies)
                if (policy.declaration.resource == resource)
                  DVDocsRow(
                    <List<DVDocsSpan>>[
                      <DVDocsSpan>[
                        DVDocsSpan.code(policy.declaration.className),
                        const DVDocsSpan.text(' '),
                        DVDocsSpan.note(policy.source),
                      ],
                      for (final String action in dvPolicyActions)
                        <DVDocsSpan>[
                          if (policy.declaration.methods.any(
                            (DVPolicyMethod x) => x.action == action,
                          ))
                            DVDocsSpan.code(
                              '${policy.declaration.className}.$action',
                            )
                          else
                            const DVDocsSpan.denied(),
                        ],
                    ],
                    'policy-${policy.declaration.className}',
                  ),
            ],
          ),
        );
      for (final _Policy policy in policies) {
        if (policy.declaration.resource != resource) continue;
        out.addAll(_backlinks('policy:${policy.declaration.className}'));
      }
    }

    final List<(String, String, DVDocsTarget)> guarded =
        <(String, String, DVDocsTarget)>[
          for (final _Route r in routes)
            if (r.policy != null)
              (
                r.policy!,
                r.path,
                DVDocsTarget.page('routes', anchor: 'route-${r.path}'),
              ),
          for (final DVGraphFunction f in graph.functions)
            if (_functionPolicy(f) case final String policy)
              (
                policy,
                '${f.method} ${f.path}',
                DVDocsTarget.page('functions', anchor: 'function-${f.name}'),
              ),
        ]..sort(((String, String, DVDocsTarget) a, (String, String, DVDocsTarget) b) {
          final int byPolicy = a.$1.compareTo(b.$1);
          return byPolicy != 0 ? byPolicy : a.$2.compareTo(b.$2);
        });
    out.add(
      const DVDocsHeading(
        2,
        <DVDocsSpan>[DVDocsSpan.text('What each policy guards')],
        anchor: 'guarded',
      ),
    );
    if (guarded.isEmpty) {
      out.add(
        const DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No page or backend function declares a policy.'),
        ]),
      );
    } else {
      out.add(
        DVDocsTable(
          const <DVDocsColumn>[
            DVDocsColumn('Policy'),
            DVDocsColumn('Surface'),
          ],
          <DVDocsRow>[
            for (final (String policy, String surface, DVDocsTarget target)
                in guarded)
              DVDocsRow(<List<DVDocsSpan>>[
                <DVDocsSpan>[DVDocsSpan.code(policy)],
                <DVDocsSpan>[DVDocsSpan.link(surface, target)],
              ]),
          ],
        ),
      );
    }
    return out;
  }

  String? _functionPolicy(DVGraphFunction f) {
    final _Mapping? mapping = _resolve(
      f.source,
      f.annotated ? RegExp(r'@DVBackendFunction\b') : null,
    );
    return mapping == null
        ? null
        : dvBackendPolicyFromSource(mapping.lines.join('\n'));
  }

  List<DVDocsBlock> _modules() {
    if (mounts.isEmpty) {
      return const <DVDocsBlock>[
        DVDocsParagraph(<DVDocsSpan>[
          DVDocsSpan.text('No modules are mounted: '),
          DVDocsSpan.code('dartvel.modules'),
          DVDocsSpan.text(' is empty.'),
        ]),
      ];
    }
    final List<DVDocsBlock> out = <DVDocsBlock>[];
    for (final DVModuleMount m in mounts) {
      List<DVDocsSpan> list(List<String> values) => values.isEmpty
          ? const <DVDocsSpan>[DVDocsSpan.text('none')]
          : <DVDocsSpan>[
              for (final (int i, String v) in values.indexed) ...<DVDocsSpan>[
                if (i > 0) const DVDocsSpan.text(', '),
                DVDocsSpan.code(v),
              ],
            ];
      out
        ..add(
          DVDocsHeading(
            2,
            <DVDocsSpan>[DVDocsSpan.code('DV.Modules.${m.id}')],
            anchor: 'module-${m.id}',
          ),
        )
        ..add(
          DVDocsTable(
            const <DVDocsColumn>[
              DVDocsColumn('Property'),
              DVDocsColumn('Value'),
            ],
            <DVDocsRow>[
              _row('Mount', <DVDocsSpan>[DVDocsSpan.code(m.mount)]),
              _row('Deployment', <DVDocsSpan>[
                DVDocsSpan.text(m.deployment.name),
                if (!m.mounted) const DVDocsSpan.text(' (not mounted)'),
              ]),
              _row('Package', <DVDocsSpan>[
                DVDocsSpan.code(m.packageName),
                if (m.version != null) DVDocsSpan.text(' ${m.version}'),
              ]),
              _row('Modes', <DVDocsSpan>[
                DVDocsSpan.code('shell="${m.shell}"'),
                const DVDocsSpan.text(' '),
                DVDocsSpan.code('auth="${m.auth}"'),
                const DVDocsSpan.text(' '),
                DVDocsSpan.code('theme="${m.theme}"'),
                const DVDocsSpan.text(' '),
                DVDocsSpan.code('data="${m.data}"'),
              ]),
              _row('Requires', list(m.requires)),
              _row('Shares pages', <DVDocsSpan>[
                DVDocsSpan.text(m.exportsPages ? 'yes' : 'no'),
              ]),
              _row('Shares functions', <DVDocsSpan>[
                DVDocsSpan.text(m.exportsFunctions ? 'yes' : 'no'),
              ]),
              _row('Exported globals', list(m.exportedGlobals)),
              _row('Inherited globals', list(m.inheritedGlobals)),
              // What the parent grants, and what Module Distribution and Trust
              // says of it. Showing only what a module was declared to need
              // left a reader unable to tell a granted module from one the
              // build refuses.
              _row('Grant', list(_grant(m.id))),
              _row('Trust', _trust(m)),
              if (m.backend != null)
                _row('Backend', <DVDocsSpan>[DVDocsSpan.code(m.backend!)]),
              if (m.location != null)
                _row('Location', <DVDocsSpan>[DVDocsSpan.code(m.location!)]),
              _row('Routes', <DVDocsSpan>[
                if (m.routes.isEmpty)
                  const DVDocsSpan.text('none')
                else
                  for (final (int i, DVModuleRoute r) in m.routes.indexed) ...<DVDocsSpan>[
                    if (i > 0) const DVDocsSpan.text(', '),
                    DVDocsSpan.link(
                      r.mounted,
                      DVDocsTarget.page(
                        'routes',
                        anchor: 'route-${r.mounted}',
                      ),
                    ),
                  ],
              ]),
            ],
          ),
        );
      if (m.problems.isNotEmpty) {
        out.add(
          DVDocsList(false, <DVDocsListItem>[
            for (final String problem in m.problems)
              DVDocsListItem(<DVDocsSpan>[DVDocsSpan.finding(problem)]),
          ]),
        );
      }
      out.addAll(_backlinks('module:${m.id}'));
    }
    return out;
  }

  static DVDocsRow _row(String label, List<DVDocsSpan> value) =>
      DVDocsRow(<List<DVDocsSpan>>[
        <DVDocsSpan>[DVDocsSpan.strong(label)],
        value,
      ]);

  /// What the parent grants this module, as the grant block reads it.
  List<String> _grant(String id) {
    Object? declared;
    try {
      final Object? doc = loadYaml(
        File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
      );
      final Object? dartvel = doc is Map ? doc['dartvel'] : null;
      final Object? modules = dartvel is Map ? dartvel['modules'] : null;
      declared = modules is Map ? modules[id] : null;
    } on Object {
      declared = null;
    }
    final Object? grant = declared is Map ? declared['grant'] : null;
    return dvParseModuleCapabilities(
      grant,
      where: 'grant',
    ).capabilities.items();
  }

  /// What the trust evaluation says of this module.
  List<DVDocsSpan> _trust(DVModuleMount m) {
    if (m.deployment == DVModuleDeployment.federated) {
      return const <DVDocsSpan>[
        DVDocsSpan.text('deployed elsewhere and trusted through its signed '),
        DVDocsSpan.text('manifest'),
      ];
    }
    final List<DVModuleTrustFinding> found = dvEvaluateModuleTrust(
      root,
    ).findings.where((DVModuleTrustFinding f) => f.module == m.id).toList();
    if (found.isEmpty) {
      return const <DVDocsSpan>[
        DVDocsSpan.text('verifies against its pin where it has one, and uses '),
        DVDocsSpan.text('only what it is granted'),
      ];
    }
    return <DVDocsSpan>[
      for (final (int i, DVModuleTrustFinding f) in found.indexed) ...<DVDocsSpan>[
        if (i > 0) const DVDocsSpan.text(' '),
        if (f.code != null) DVDocsSpan.code(f.code!),
        if (f.code != null) const DVDocsSpan.text(' '),
        if (!f.isError) const DVDocsSpan.text('(warning) '),
        DVDocsSpan.text(f.message),
      ],
    ];
  }

  List<DVDocsBlock> _diagnostics() {
    final List<DVDocsBlock> out = <DVDocsBlock>[
      const DVDocsParagraph(<DVDocsSpan>[
        DVDocsSpan.text('The registry '),
        DVDocsSpan.code('dartvel explain'),
        DVDocsSpan.text(' reads.'),
      ]),
    ];
    for (final String family in DVDiagnostics.families()) {
      out
        ..add(
          DVDocsHeading(
            2,
            <DVDocsSpan>[DVDocsSpan.text(family)],
            anchor: 'family-$family',
          ),
        )
        ..add(
          DVDocsTable(
            const <DVDocsColumn>[
              DVDocsColumn('Code'),
              DVDocsColumn('Level'),
              DVDocsColumn('Reason'),
            ],
            <DVDocsRow>[
              for (final DVDiagnostic d in DVDiagnostics.family(family))
                DVDocsRow(
                  <List<DVDocsSpan>>[
                    <DVDocsSpan>[DVDocsSpan.code(d.code)],
                    <DVDocsSpan>[DVDocsSpan.text(d.level)],
                    dvDocsInline(d.reason),
                  ],
                  d.code,
                ),
            ],
          ),
        );
    }
    return out;
  }

  // ---------------------------------------------------------------- helpers

  /// The decisions naming [key], as a block, or nothing.
  List<DVDocsBlock> _backlinks(String key) {
    final List<_Decision>? named = backlinks[key];
    if (named == null || named.isEmpty) return const <DVDocsBlock>[];
    return <DVDocsBlock>[
      DVDocsParagraph(<DVDocsSpan>[
        const DVDocsSpan.text('Decisions: '),
        for (final (int i, _Decision d) in named.indexed) ...<DVDocsSpan>[
          if (i > 0) const DVDocsSpan.text(', '),
          DVDocsSpan.link(d.title, d.target),
        ],
      ]),
    ];
  }

  /// A node's doc comment, and where it was read from.
  List<DVDocsBlock> _description(_Mapping? mapping, String source) =>
      mapping == null
      ? _unmappedParagraph(source)
      : <DVDocsBlock>[
          ...dvDocsProse(_docAbove(mapping.lines, mapping.line)),
          ..._sourceParagraph(mapping.source),
        ];

  List<DVDocsBlock> _sourceParagraph(String source) => <DVDocsBlock>[
        DVDocsParagraph(<DVDocsSpan>[
          const DVDocsSpan.text('Source: '),
          DVDocsSpan.note(source),
        ]),
      ];

  /// Said, not invented around. A node the build cannot read still appears in
  /// the page with its path on it, because a reference that has silently
  /// vanished is harder to notice than one that admits itself.
  List<DVDocsBlock> _unmappedParagraph(String source) => <DVDocsBlock>[
        DVDocsParagraph(<DVDocsSpan>[
          const DVDocsSpan.text('no source to render from: '),
          DVDocsSpan.note(source),
        ]),
      ];

  void _unmapped(String node, String source) {
    findings.add(
      DVDocsFinding(
        code: 'DV-DOCS-002',
        source: source,
        message:
            '$node is documented from a source mapping that does not '
            'resolve to its declaration',
      ),
    );
  }

  /// [source] as `path:line`, if that file exists and the line holds
  /// [declaration]. A null [declaration] needs only the file.
  _Mapping? _resolve(String source, RegExp? declaration) {
    final int colon = source.lastIndexOf(':');
    if (colon <= 0) return null;
    final String file = source.substring(0, colon);
    final int? line = int.tryParse(source.substring(colon + 1));
    final List<String>? lines = _lines(file);
    if (line == null || lines == null || line < 1 || line > lines.length) {
      return null;
    }
    if (declaration != null && !declaration.hasMatch(lines[line - 1])) {
      return null;
    }
    return _Mapping(file, line, lines);
  }

  List<String>? _lines(String relative) => _sources.putIfAbsent(relative, () {
    if (p.isAbsolute(relative) || relative.split('/').contains('..')) {
      return null;
    }
    final File file = File(p.joinAll(<String>[root, ...relative.split('/')]));
    if (!file.existsSync()) return null;
    return file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
  });

  /// The `///` comment directly above the declaration starting at [line],
  /// stepping over the annotations stacked on it.
  static String _docAbove(List<String> lines, int line) {
    final List<String> doc = <String>[];
    for (int i = line - 2; i >= 0; i--) {
      final String t = lines[i].trim();
      if (t.startsWith('///')) {
        doc.insert(
          0,
          t.length > 3 && t[3] == ' ' ? t.substring(4) : t.substring(3),
        );
        continue;
      }
      if (t.startsWith('@')) continue;
      break;
    }
    return doc.join('\n').trim();
  }

  /// Each field's doc comment, found inside the model's own body.
  static Map<String, String> _fieldDocs(_Mapping mapping, DVGraphModel model) {
    final String text = mapping.lines.join('\n');
    int offset = 0;
    for (int i = 0; i < mapping.line - 1; i++) {
      offset += mapping.lines[i].length + 1;
    }
    // From the class keyword rather than the body's brace: a primary
    // constructor declares its fields in the header, `class _User(
    // /// Where receipts are sent.
    // final String email)`, and its first brace may be the named
    // parameters' rather than the body's.
    final int classAt = text.indexOf(RegExp(r'\bclass\b'), offset);
    final int open = classAt < 0 ? text.indexOf('{', offset) : classAt;
    if (open < 0) return const <String, String>{};
    int end = open;
    final int paren = text.indexOf('(', open);
    final int brace = text.indexOf('{', open);
    if (classAt >= 0 && paren >= 0 && (brace < 0 || paren < brace)) {
      end = _matching(text, paren, '(', ')');
    }
    final int bodyOpen = text.indexOf('{', end);
    final int semicolon = text.indexOf(';', end);
    final int close = bodyOpen < 0 || (semicolon >= 0 && semicolon < bodyOpen)
        ? semicolon
        : _matching(text, bodyOpen, '{', '}');
    if (close < 0) return const <String, String>{};
    final String body = text.substring(open, close);
    final int bodyLine = _lineOf(text, open);
    final Map<String, String> docs = <String, String>{};
    for (final DVGraphField f in model.fields) {
      final RegExpMatch? m = RegExp(
        '(?:final|var)\\s+[^;,(){}]*?\\b${RegExp.escape(f.name)}\\s*[;,)}=]',
      ).firstMatch(body);
      if (m == null) continue;
      final int line = bodyLine + _lineOf(body, m.start) - 1;
      final String doc = _docAbove(mapping.lines, line);
      if (doc.isNotEmpty) docs[f.name] = doc;
    }
    return docs;
  }

  /// Where the function the generated backend calls is declared, and whether
  /// it is typed, decided the way `BackendGenerator` decides it: an annotated
  /// private function, then a function named after the file, then a raw
  /// `handler`, then the first top-level function.
  ///
  /// Not by whether `@DVBackendFunction` is present. Most functions carry no
  /// annotation -- seventeen of twenty in the repository's own example -- and
  /// going by the annotation listed every one of those as a raw handler with
  /// no body read and no CSRF check, which is a lifecycle that reads as
  /// entirely plausible and is not the one they run.
  static ({int line, bool typed})? _declaration(
    _Mapping mapping,
    DVGraphFunction f,
  ) {
    if (f.annotated) return (line: mapping.line, typed: true);
    final String text = mapping.lines.join('\n');
    int lineAt(int offset) {
      final int start = text.indexOf(RegExp(r'\S'), offset);
      return _lineOf(text, start < 0 ? offset : start);
    }

    const String head = r'^\s*(?:[A-Za-z_][\w<>, ?]*\s+)?';
    const String tail = r'\s*\(([^)]*)\)\s*(?:async\*?|sync\*)?\s*(?:=>|\{)';
    final String base = p.basenameWithoutExtension(mapping.file);
    final String candidate =
        (base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base)
            .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (candidate.isNotEmpty) {
      final RegExpMatch? named = RegExp(
        head + RegExp.escape(candidate) + tail,
        multiLine: true,
      ).firstMatch(text);
      if (named != null) return (line: lineAt(named.start), typed: true);
    }
    final RegExpMatch? handler = RegExp(
      '${head}handler$tail',
      multiLine: true,
    ).firstMatch(text);
    if (handler != null) return (line: lineAt(handler.start), typed: false);
    const Set<String> reserved = <String>{
      'if',
      'for',
      'while',
      'switch',
      'case',
      'default',
      'return',
      'try',
      'catch',
      'on',
      'do',
      'else',
    };
    for (final RegExpMatch m in RegExp(
      '$head([A-Za-z_]\\w*)$tail',
      multiLine: true,
    ).allMatches(text)) {
      if (reserved.contains(m.group(1))) continue;
      return (line: lineAt(m.start), typed: true);
    }
    return null;
  }

  /// The signature declared at [line] as written, with the public name.
  static String? _signature(List<String> lines, int line, DVGraphFunction f) {
    final String rest = _skipAnnotations(lines.sublist(line - 1).join('\n'));
    final int open = rest.indexOf('(');
    if (open < 0) return null;
    final int close = _matching(rest, open, '(', ')');
    if (close >= rest.length) return null;
    return rest
        .substring(0, close + 1)
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r',\s*\)$'), ')')
        .replaceAll('( ', '(')
        .replaceFirstMapped(
          RegExp('(^|\\s)_(${RegExp.escape(f.name)})\\s*\\('),
          (Match m) => '${m.group(1)}${m.group(2)}(',
        )
        .trim();
  }

  static String _skipAnnotations(String text) {
    String rest = text;
    while (true) {
      rest = rest.trimLeft();
      final RegExpMatch? name = RegExp(r'^@[A-Za-z_][\w.]*').firstMatch(rest);
      if (name == null) return rest;
      rest = rest.substring(name.end);
      final String after = rest.trimLeft();
      if (after.startsWith('(')) {
        final int open = rest.indexOf('(');
        rest = rest.substring(_matching(rest, open, '(', ')') + 1);
      }
    }
  }

  /// The index of the bracket closing the one at [open], or the length.
  static int _matching(String text, int open, String opening, String closing) {
    int depth = 0;
    String? quote;
    for (int i = open; i < text.length; i++) {
      final String c = text[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == opening) {
        depth++;
      } else if (c == closing) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return text.length;
  }

  /// Example JSON for [model], from field types alone.
  static String _example(DVGraphModel model, Set<String> models) {
    Object? valueFor(String type) {
      final String t = type.replaceAll('?', '').trim();
      if (t == 'String') return 'text';
      if (t == 'int') return 0;
      if (t == 'double' || t == 'num') return 0.0;
      if (t == 'bool') return false;
      if (t == 'DateTime') return '1970-01-01T00:00:00.000Z';
      if (t.startsWith('List<') ||
          t.startsWith('Set<') ||
          t.startsWith('Iterable<')) {
        return <Object?>[];
      }
      if (t.startsWith('Map<')) return <String, Object?>{};
      if (models.contains(t)) return <String, Object?>{};
      return null;
    }

    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      for (final DVGraphField f in model.fields)
        f.name: f.sensitive ? '[sensitive]' : valueFor(f.type),
    });
  }

  static List<String> _modelsIn(String type, Set<String> models) => <String>[
    for (final Match m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(type))
      if (models.contains(m.group(0))) m.group(0)!,
  ];

  /// A type as spans: the names in it that are models link to those models,
  /// and the rest is the type as written.
  static List<DVDocsSpan> _typeSpans(String type, Set<String> models) {
    final List<DVDocsSpan> out = <DVDocsSpan>[];
    int at = 0;
    for (final Match m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(type)) {
      if (m.start > at) {
        out.add(DVDocsSpan.text(type.substring(at, m.start)));
      }
      final String name = m.group(0)!;
      out.add(
        models.contains(name)
            ? DVDocsSpan.link(
                name,
                DVDocsTarget.page('models', anchor: 'model-$name'),
              )
            : DVDocsSpan.code(name),
      );
      at = m.end;
    }
    if (at < type.length) out.add(DVDocsSpan.text(type.substring(at)));
    return out.isEmpty ? <DVDocsSpan>[DVDocsSpan.text(type)] : out;
  }

  DVGraphModel? _model(String? name) {
    for (final DVGraphModel m in graph.models) {
      if (m.name == name) return m;
    }
    return null;
  }

  List<File> _dartFiles() {
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return const <File>[];
    return lib
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !_rel(f.path).startsWith('lib/dartvel_client/'))
        .where((File f) => !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
  }

  String _rel(String path) =>
      p.relative(path, from: root).replaceAll(r'\', '/');

  static int _lineOf(String source, int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;
}

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
import 'docs_html.dart';

/// Something the documentation build found wrong with what it was asked to
/// render. Both codes are drift -- see `DV-DOCS` in the diagnostics registry.
/// A generated site cannot be out of date with the code; what it can be is
/// pointed at something that is gone.
class DVDocsFinding {
  const DVDocsFinding({
    required this.code,
    required this.message,
    required this.source,
  });

  /// `DV-DOCS-001` or `DV-DOCS-002`.
  final String code;

  final String message;

  /// Where to look, as `path:line` relative to the project.
  final String source;

  @override
  String toString() => '$code  $source  $message';
}

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

/// The documentation site for one application: a second rendering of the
/// project graph, the same graph `dartvel inspect` and `dartvel mcp` answer
/// from, plus what the generators already read beside it.
///
/// Nothing is authored here. A description is the doc comment above the
/// declaration, read through the node's source mapping; a node whose mapping
/// no longer resolves is rendered without one and reported, rather than
/// rendered with something plausible.
class DVDocsSite {
  const DVDocsSite({required this.files, required this.findings});

  /// Every page, by forward-slash path relative to the site root, in sorted
  /// order. Byte-deterministic for a given project: nothing here reads a
  /// clock, an absolute path or an unsorted listing.
  final Map<String, String> files;

  /// Sorted by code, then source.
  final List<DVDocsFinding> findings;

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

  /// Writes the site into [directory], removing any page an earlier build
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
  _Decision(this.file, this.page, this.title);

  /// Relative to the project.
  final String file;

  /// Relative to the site root.
  final String page;
  final String title;
  String html = '';
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

  /// `kind:target` to the page and fragment it renders at.
  final Map<String, String> nodes = <String, String>{};

  /// `kind:target` to the decisions naming it, in decision order.
  final Map<String, List<_Decision>> backlinks = <String, List<_Decision>>{};

  // ---------------------------------------------------------------- collect

  Future<void> collect() async {
    for (final File file in _dartFiles()) {
      final String rel = _rel(file.path);
      final String source = file.readAsStringSync();
      for (final DVPolicyClass c in dvPolicyClassesIn(source, rel)) {
        final int at = source.indexOf(RegExp('class\\s+${c.className}\\b'));
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
      nodes['model:${m.name}'] = 'models.html#model-${m.name}';
      for (final DVGraphField f in m.fields) {
        nodes['field:${m.name}.${f.name}'] =
            'models.html#field-${m.name}-${f.name}';
      }
    }
    for (final _Route r in routes) {
      nodes.putIfAbsent('route:${r.path}', () => 'routes.html#route-${r.path}');
    }
    for (final DVGraphFunction f in graph.functions) {
      nodes['function:${f.name}'] = 'functions.html#function-${f.name}';
    }
    for (final DVGraphJob j in graph.jobs) {
      nodes['job:${j.name}'] = 'jobs.html#job-${j.name}';
    }
    for (final _Schedule s in schedules) {
      nodes['schedule:${s.name}'] = 'jobs.html#schedule-${s.name}';
    }
    for (final _Policy policy in policies) {
      nodes['policy:${policy.declaration.className}'] =
          'policies.html#policy-${policy.declaration.resource}';
    }
    for (final DVModuleMount m in mounts) {
      nodes['module:${m.id}'] = 'modules.html#module-${m.id}';
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
        'decisions/$name.html',
        dvDocsMarkdownTitle(text) ?? name,
      );
      decision.html = dvDocsMarkdown(
        text,
        code: (String code, int line) {
          final RegExpMatch? m = reference.firstMatch(code.trim());
          if (m == null) return '<code>${dvDocsText(code)}</code>';
          final String key = '${m.group(1)}:${m.group(2)}';
          final String? href = nodes[key];
          if (href == null) {
            findings.add(
              DVDocsFinding(
                code: 'DV-DOCS-001',
                source: '$rel:$line',
                message: 'names `$key`, which is not in the project graph',
              ),
            );
            return '<code class="gone" title="no longer exists">'
                '${dvDocsText(key)}</code>';
          }
          final List<_Decision> named = backlinks.putIfAbsent(
            key,
            () => <_Decision>[],
          );
          if (!named.contains(decision)) named.add(decision);
          return '<a href="../${dvDocsAttr(href)}"><code>${dvDocsText(key)}</code></a>';
        },
      );
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
    final Map<String, String> pages = <String, String>{
      'graph.json':
          '${const JsonEncoder.withIndent('  ').convert(graph.toJson())}\n',
      'models.html': _page('Models', _models()),
      'functions.html': _page('Functions', _functions()),
      'routes.html': _page('Routes', _routes()),
      'jobs.html': _page('Jobs and cron', _jobs()),
      'policies.html': _page('Policies', _policies()),
      'modules.html': _page('Modules', _modules()),
      'diagnostics.html': _page('Diagnostics', _diagnostics()),
      for (final _Decision d in decisions)
        d.page: dvDocsPage(
          title: d.title,
          application: pkgName,
          depth: 1,
          body:
              '<p class="source">Source: <code>${dvDocsText(d.file)}</code></p>\n'
              '${d.html}',
        ),
    };
    final List<DVDocsFinding> sorted = List<DVDocsFinding>.of(findings)
      ..sort((DVDocsFinding a, DVDocsFinding b) {
        final int byCode = a.code.compareTo(b.code);
        if (byCode != 0) return byCode;
        final int bySource = a.source.compareTo(b.source);
        return bySource != 0 ? bySource : a.message.compareTo(b.message);
      });
    pages['index.html'] = _page('Overview', _index(sorted));
    final List<String> keys = pages.keys.toList()..sort();
    return DVDocsSite(
      files: <String, String>{for (final String k in keys) k: pages[k]!},
      findings: List<DVDocsFinding>.unmodifiable(sorted),
    );
  }

  String _page(String title, String body) =>
      dvDocsPage(title: title, application: pkgName, body: body);

  String _index(List<DVDocsFinding> sorted) {
    final StringBuffer b = StringBuffer()
      ..writeln(
        '<p>Rendered from the project graph. Descriptions are doc '
        'comments read from the source; nothing here is written twice.</p>',
      )
      ..writeln('<table><tbody>')
      ..writeln(
        '<tr><td><a href="models.html">Models</a></td><td>${graph.models.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="functions.html">Functions</a></td><td>${graph.functions.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="routes.html">Routes</a></td><td>${routes.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="jobs.html">Jobs</a></td><td>${graph.jobs.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="jobs.html#schedules">Schedules</a></td><td>${schedules.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="policies.html">Policies</a></td><td>${policies.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="modules.html">Modules</a></td><td>${mounts.length}</td></tr>',
      )
      ..writeln(
        '<tr><td><a href="graph.json">graph.json</a></td><td>graphVersion ${graph.graphVersion}</td></tr>',
      )
      ..writeln('</tbody></table>')
      ..writeln('<h2>Decisions</h2>');
    if (decisions.isEmpty) {
      b.writeln(
        '<p>No decision records under <code>${dvDocsText(_decisionsDir())}</code>.</p>',
      );
    } else {
      b.writeln('<ul>');
      for (final _Decision d in decisions) {
        b.writeln(
          '<li><a href="${dvDocsAttr(d.page)}">${dvDocsInline(d.title)}</a></li>',
        );
      }
      b.writeln('</ul>');
    }
    if (sorted.isNotEmpty) {
      b
        ..writeln('<h2>Drift</h2>')
        ..writeln('<ul>');
      for (final DVDocsFinding f in sorted) {
        b.writeln(
          '<li class="finding"><a href="diagnostics.html#${f.code}">'
          '${f.code}</a> <code>${dvDocsText(f.source)}</code> '
          '${dvDocsInline(f.message)}</li>',
        );
      }
      b.writeln('</ul>');
    }
    return b.toString();
  }

  String _models() {
    if (graph.models.isEmpty) {
      return '<p>No <code>@DVModel</code> inputs.</p>\n';
    }
    final Set<String> names = <String>{
      for (final DVGraphModel m in graph.models) m.name,
    };
    final StringBuffer b = StringBuffer()
      ..writeln(
        '<p>Example data is generated from each field\'s type, never '
        'read from a database. A sensitive field is named and never '
        'valued.</p>',
      );
    for (final DVGraphModel m in graph.models) {
      final _Mapping? mapping = _resolve(m.source, RegExp(r'@DVModel\s*\('));
      if (mapping == null) _unmapped('model ${m.name}', m.source);
      final Map<String, String> fieldDocs = mapping == null
          ? const <String, String>{}
          : _fieldDocs(mapping, m);

      b
        ..writeln('<section id="model-${dvDocsAttr(m.name)}">')
        ..writeln('<h2>${dvDocsText(m.name)}</h2>')
        ..write(_description(mapping, m.source))
        ..writeln(
          '<table class="fields"><thead><tr><th>Field</th><th>Type</th>'
          '<th></th><th>Description</th></tr></thead><tbody>',
        );
      for (final DVGraphField f in m.fields) {
        b.writeln(
          '<tr id="field-${dvDocsAttr(m.name)}-${dvDocsAttr(f.name)}"'
          '${f.sensitive ? ' class="sensitive"' : ''}>'
          '<td><code>${dvDocsText(f.name)}</code></td>'
          '<td><code>${_typeHtml(f.type, names)}</code></td>'
          '<td>${f.sensitive ? '<span class="badge">sensitive</span>' : ''}</td>'
          '<td>${dvDocsInline(fieldDocs[f.name] ?? '')}</td></tr>',
        );
      }
      b.writeln('</tbody></table>');

      final List<DVGraphField> relations = <DVGraphField>[
        for (final DVGraphField f in m.fields)
          if (_modelsIn(f.type, names).isNotEmpty) f,
      ];
      if (relations.isNotEmpty) {
        b.writeln('<h3>Relations</h3><ul>');
        for (final DVGraphField f in relations) {
          final String targets = _modelsIn(f.type, names)
              .map(
                (String t) =>
                    '<a href="#model-${dvDocsAttr(t)}">${dvDocsText(t)}</a>',
              )
              .join(', ');
          b.writeln('<li><code>${dvDocsText(f.name)}</code> → $targets</li>');
        }
        b.writeln('</ul>');
      }

      final List<_Policy> own = <_Policy>[
        for (final _Policy policy in policies)
          if (policy.declaration.resource == m.name) policy,
      ];
      b.writeln('<h3>Policies</h3>');
      if (own.isEmpty) {
        b.writeln(
          '<p>No <code>@DVPolicy(${dvDocsText(m.name)})</code> class: '
          'every action on it is denied.</p>',
        );
      } else {
        b.writeln('<ul>');
        for (final _Policy policy in own) {
          final String actions = policy.declaration.methods
              .map((DVPolicyMethod x) => x.action)
              .join(', ');
          b.writeln(
            '<li><a href="policies.html#policy-${dvDocsAttr(m.name)}">'
            '<code>${dvDocsText(policy.declaration.className)}</code></a>: '
            '${actions.isEmpty ? 'no actions' : dvDocsText(actions)}</li>',
          );
        }
        b.writeln('</ul>');
      }

      b
        ..writeln('<h3>Generated</h3><ul>')
        ..writeln(
          <String>['Form', 'List', 'Table', 'Card', 'PageBody', 'Page']
              .map(
                (String s) => '<li><code>${dvDocsText(m.name)}.$s</code></li>',
              )
              .join('\n'),
        );
      for (final StaticPathsProvider provider in providers) {
        if (provider.className != m.name || provider.route == null) continue;
        b.writeln(
          provider.generatesPage
              ? '<li>public page at <a href="routes.html#route-${dvDocsAttr(provider.route!)}">'
                    '<code>${dvDocsText(provider.route!)}</code></a></li>'
              : '<li>static paths for <code>${dvDocsText(provider.route!)}</code> '
                    'from <code>${dvDocsText(provider.resolveExpression)}</code></li>',
        );
      }
      b
        ..writeln('</ul>')
        ..writeln('<h3>Example</h3>')
        ..writeln('<pre><code>${dvDocsText(_example(m, names))}</code></pre>')
        ..write(_backlinks('model:${m.name}'))
        ..writeln('</section>');
    }
    return b.toString();
  }

  String _functions() {
    if (graph.functions.isEmpty) {
      return '<p>No backend functions under <code>lib/backend/functions</code>.</p>\n';
    }
    final StringBuffer b = StringBuffer()
      ..writeln(
        '<p>Each function lists the stages a request passes through '
        'before and around it, in the order the generated backend runs '
        'them.</p>',
      );
    for (final DVGraphFunction f in graph.functions) {
      final _Mapping? mapping = _resolve(
        f.source,
        f.annotated ? RegExp(r'@DVBackendFunction\b') : null,
      );
      if (mapping == null) _unmapped('function ${f.name}', f.source);
      b
        ..writeln('<section id="function-${dvDocsAttr(f.name)}">')
        ..writeln('<h2><code>${dvDocsText(f.name)}</code></h2>')
        ..writeln(
          '<p><strong>${dvDocsText(f.method)}</strong> '
          '<code>${dvDocsText(f.path)}</code></p>',
        );
      if (mapping == null) {
        b
          ..writeln(
            '<p class="unmapped">no source to render from: '
            '<code>${dvDocsText(f.source)}</code></p>',
          )
          ..write(_backlinks('function:${f.name}'))
          ..writeln('</section>');
        continue;
      }
      final String file = mapping.lines.join('\n');
      final ({int line, bool typed})? declaration = _declaration(mapping, f);
      final String? signature = declaration == null
          ? null
          : _signature(mapping.lines, declaration.line, f);
      final String? policy = dvBackendPolicyFromSource(file);
      b.write(
        _docHtml(
          declaration == null ? '' : _docAbove(mapping.lines, declaration.line),
        ),
      );
      if (signature != null) {
        b.writeln(
          '<pre class="signature"><code>${dvDocsText(signature)}</code></pre>',
        );
      }
      b
        ..writeln('<h3>Request lifecycle</h3>')
        ..writeln('<ol class="stages">');
      for (final (String id, String text) in _stages(
        method: f.method,
        middleware: dvMiddlewareKeysFromSource(file),
        policy: policy,
        typed: declaration?.typed ?? false,
        context:
            signature != null &&
            RegExp(r'\(\s*(?:final\s+)?DVContext\s+\w+').hasMatch(signature),
      )) {
        b.writeln(
          '<li class="stage" data-stage="${dvDocsAttr(id)}">$text</li>',
        );
      }
      b
        ..writeln('</ol>')
        ..writeln(
          '<p class="source">Source: <code>${dvDocsText(f.source)}</code></p>',
        )
        ..write(_backlinks('function:${f.name}'))
        ..writeln('</section>');
    }
    return b.toString();
  }

  /// The stages the generated backend runs a request through, in order.
  ///
  /// This mirrors the order `BackendGenerator` emits, and a test generates a
  /// real backend and checks the two agree, because a list that drifted from
  /// the handler would still read as a perfectly plausible lifecycle.
  static List<(String, String)> _stages({
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
    return <(String, String)>[
      (
        'tenant',
        'Tenant scope: the tenant this request names is current for '
            'everything below.',
      ),
      (
        'privacy',
        'Privacy scope: a <code>Sec-GPC: 1</code> header is in force for '
            'everything below, and denies every consent category declared '
            'as tracking.',
      ),
      if (middleware.contains('tracing'))
        (
          'tracing',
          'Tracing span around everything below, refused requests '
              'included.',
        ),
      for (final String key in middleware)
        if (key != 'tracing')
          (
            'middleware:$key',
            'Middleware <code>${dvDocsText(key)}</code>, in '
                'declared order.',
          ),
      if (readsBody)
        (
          'body',
          limited
              ? 'Body read, refused past the declared limit before it is buffered.'
              : 'Body read and decoded.',
        ),
      if (typed) ('csrf', 'CSRF check.'),
      if (policy != null)
        (
          'policy',
          'Policy gate <code>${dvDocsText(policy)}</code>: refused '
              'with 403 before the function runs.',
        ),
      if (context)
        (
          'context',
          'A <code>DVContext</code> is built and passed first; it is '
              'not a client argument.',
        ),
      (
        'function',
        typed ? 'The function.' : 'The raw handler, which owns the request.',
      ),
    ];
  }

  String _routes() {
    if (routes.isEmpty) return '<p>No routes.</p>\n';
    final StringBuffer b = StringBuffer();
    for (final _Route r in routes) {
      b
        ..writeln('<section id="route-${dvDocsAttr(r.path)}">')
        ..writeln('<h2><code>${dvDocsText(r.path)}</code></h2>')
        ..writeln(
          '<p>${dvDocsText(r.kind)}'
          '${r.page == null ? '' : ' · <code>${dvDocsText(r.page!)}</code>'}'
          '${r.module == null ? '' : ' · module <a href="modules.html#module-${dvDocsAttr(r.module!)}"><code>${dvDocsText(r.module!)}</code></a>'}'
          '</p>',
        );
      if (r.model != null) {
        b.writeln(
          '<p>Generated from <a href="models.html#model-${dvDocsAttr(r.model!)}">'
          '${dvDocsText(r.model!)}</a>.</p>',
        );
      }
      if (r.location != null) {
        b.writeln(
          '<p>Served by the module\'s own deployment at '
          '<code>${dvDocsText(r.location!)}</code>, from its verified manifest.</p>',
        );
      }
      if (r.unmapped) {
        b.writeln(
          '<p class="unmapped">no source to render from: '
          '<code>${dvDocsText(r.source ?? '')}</code></p>',
        );
      } else if (r.mapping != null) {
        b.write(_docHtml(_docAbove(r.mapping!.lines, r.mapping!.line)));
      }
      if (r.policy != null) {
        b.writeln('<p>Guarded by <code>${dvDocsText(r.policy!)}</code>.</p>');
      }
      if (r.middleware.isNotEmpty) {
        b.writeln(
          '<p>Middleware: ${r.middleware.map((String k) => '<code>${dvDocsText(k)}</code>').join(', ')}</p>',
        );
      }
      if (r.source != null && !r.unmapped) {
        b.writeln(
          '<p class="source">Source: <code>${dvDocsText(r.source!)}</code></p>',
        );
      }
      b
        ..write(_backlinks('route:${r.path}'))
        ..writeln('</section>');
    }
    return b.toString();
  }

  String _jobs() {
    final StringBuffer b = StringBuffer();
    b.writeln('<h2 id="jobs">Jobs</h2>');
    if (graph.jobs.isEmpty) b.writeln('<p>No <code>@DVJob</code> inputs.</p>');
    b
      ..writeln('<h2 id="schedules">Schedules</h2>')
      ..writeln(
        '<p>A backend schedule runs on the server from a periodic '
        'timer. A client schedule is a request, not a guarantee: it ticks '
        'while the application is showing a page, and each platform decides '
        'how often a backgrounded or closed application runs it.</p>',
      );
    if (schedules.isEmpty) {
      b.writeln(
        '<p>No <code>@DVBackendCron</code> or <code>@DVClientCron</code> '
        'functions.</p>',
      );
    }
    for (final DVGraphJob j in graph.jobs) {
      final _Mapping? mapping = _resolve(j.source, RegExp(r'@DVJob\b'));
      if (mapping == null) _unmapped('job ${j.name}', j.source);
      b
        ..writeln('<section id="job-${dvDocsAttr(j.name)}">')
        ..writeln('<h3>${dvDocsText(j.name)}</h3>')
        ..writeln('<p>Queue <code>${dvDocsText(j.queue)}</code></p>')
        ..write(_description(mapping, j.source))
        ..write(_backlinks('job:${j.name}'))
        ..writeln('</section>');
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
      b
        ..writeln('<section id="schedule-${dvDocsAttr(s.name)}">')
        ..writeln('<h3><code>${dvDocsText(s.name)}</code></h3>')
        ..writeln(
          '<p><code>${dvDocsText(s.cron)}</code> on the '
          '${s.client ? 'client' : 'backend'}'
          '${s.catchUp == null ? '' : ' · catch-up ${s.catchUp! ? 'on' : 'off'}'}</p>',
        );
      if (s.client) {
        b.writeln(
          '<p>A request, not a guarantee: runs while the application '
          'is showing a page; how often it runs in the background is the '
          'platform\'s decision.</p>',
        );
      }
      b
        ..write(_description(mapping, source))
        ..write(_backlinks('schedule:${s.name}'))
        ..writeln('</section>');
    }
    return b.toString();
  }

  String _policies() {
    final StringBuffer b = StringBuffer()
      ..writeln(
        '<p>An action no policy method answers is denied: '
        '<code>DV.Auth.authorization</code> is default-deny. Who a method '
        'allows is decided in its body, which the source link opens.</p>',
      );
    if (policies.isEmpty) {
      b.writeln('<p>No <code>@DVPolicy</code> classes.</p>');
    }
    final List<String> resources = <String>{
      for (final _Policy policy in policies) policy.declaration.resource,
    }.toList();
    for (final String resource in resources) {
      b
        ..writeln('<section id="policy-${dvDocsAttr(resource)}">')
        ..writeln(
          '<h2>${_typeHtml(resource, <String>{for (final DVGraphModel m in graph.models) m.name}, fromPolicies: true)}</h2>',
        )
        ..writeln(
          '<table><thead><tr><th>Policy</th>'
          '${dvPolicyActions.map((String a) => '<th>$a</th>').join()}</tr></thead><tbody>',
        );
      for (final _Policy policy in policies) {
        if (policy.declaration.resource != resource) continue;
        final Set<String> defined = <String>{
          for (final DVPolicyMethod m in policy.declaration.methods) m.action,
        };
        final String name = dvDocsText(policy.declaration.className);
        b.writeln(
          '<tr><td><code>$name</code><br>'
          '<span class="source">${dvDocsText(policy.source)}</span></td>'
          '${dvPolicyActions.map((String a) => '<td data-action="$a">${defined.contains(a) ? '<code>$name.$a</code>' : 'denied'}</td>').join()}'
          '</tr>',
        );
      }
      b
        ..writeln('</tbody></table>')
        ..write(
          <String>[
            for (final _Policy policy in policies)
              if (policy.declaration.resource == resource)
                _backlinks('policy:${policy.declaration.className}'),
          ].join(),
        )
        ..writeln('</section>');
    }

    final List<(String, String, String)> guarded =
        <(String, String, String)>[
          for (final _Route r in routes)
            if (r.policy != null)
              (r.policy!, r.path, 'routes.html#route-${r.path}'),
          for (final DVGraphFunction f in graph.functions)
            if (_functionPolicy(f) case final String policy)
              (
                policy,
                '${f.method} ${f.path}',
                'functions.html#function-${f.name}',
              ),
        ]..sort(((String, String, String) a, (String, String, String) b) {
          final int byPolicy = a.$1.compareTo(b.$1);
          return byPolicy != 0 ? byPolicy : a.$2.compareTo(b.$2);
        });
    b
      ..writeln('<section id="guarded">')
      ..writeln('<h2>What each policy guards</h2>');
    if (guarded.isEmpty) {
      b.writeln('<p>No page or backend function declares a policy.</p>');
    } else {
      b.writeln(
        '<table><thead><tr><th>Policy</th><th>Surface</th></tr></thead><tbody>',
      );
      for (final (String policy, String surface, String href) in guarded) {
        b.writeln(
          '<tr><td><code>${dvDocsText(policy)}</code></td>'
          '<td><a href="${dvDocsAttr(href)}"><code>${dvDocsText(surface)}</code></a></td></tr>',
        );
      }
      b.writeln('</tbody></table>');
    }
    b.writeln('</section>');
    return b.toString();
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

  String _modules() {
    if (mounts.isEmpty) {
      return '<p>No modules are mounted: <code>dartvel.modules</code> is empty.</p>\n';
    }
    final StringBuffer b = StringBuffer();
    String list(List<String> values) => values.isEmpty
        ? 'none'
        : values.map((String v) => '<code>${dvDocsText(v)}</code>').join(', ');
    for (final DVModuleMount m in mounts) {
      b
        ..writeln('<section id="module-${dvDocsAttr(m.id)}">')
        ..writeln('<h2><code>DV.Modules.${dvDocsText(m.id)}</code></h2>')
        ..writeln('<table><tbody>')
        ..writeln(
          '<tr><th>Mount</th><td><code>${dvDocsText(m.mount)}</code></td></tr>',
        )
        ..writeln(
          '<tr><th>Deployment</th><td>${dvDocsText(m.deployment.name)}'
          '${m.mounted ? '' : ' (not mounted)'}</td></tr>',
        )
        ..writeln(
          '<tr><th>Package</th><td><code>${dvDocsText(m.packageName)}</code>'
          '${m.version == null ? '' : ' ${dvDocsText(m.version!)}'}</td></tr>',
        )
        ..writeln(
          '<tr><th>Modes</th><td>'
          '<code>shell="${dvDocsText(m.shell)}"</code> '
          '<code>auth="${dvDocsText(m.auth)}"</code> '
          '<code>theme="${dvDocsText(m.theme)}"</code> '
          '<code>data="${dvDocsText(m.data)}"</code></td></tr>',
        )
        ..writeln('<tr><th>Requires</th><td>${list(m.requires)}</td></tr>')
        ..writeln(
          '<tr><th>Shares pages</th><td>${m.exportsPages ? 'yes' : 'no'}</td></tr>',
        )
        ..writeln(
          '<tr><th>Shares functions</th><td>${m.exportsFunctions ? 'yes' : 'no'}</td></tr>',
        )
        ..writeln(
          '<tr><th>Exported globals</th><td>${list(m.exportedGlobals)}</td></tr>',
        )
        ..writeln(
          '<tr><th>Inherited globals</th><td>${list(m.inheritedGlobals)}</td></tr>',
        );
      // What the parent grants, and what Module Distribution and Trust says
      // of it. Showing only what a module was declared to need left a reader
      // unable to tell a granted module from one the build refuses.
      Object? declaredBody;
      try {
        final Object? doc = loadYaml(
          File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
        );
        final Object? dartvel = doc is Map ? doc['dartvel'] : null;
        final Object? modules = dartvel is Map ? dartvel['modules'] : null;
        declaredBody = modules is Map ? modules[m.id] : null;
      } on Object {
        declaredBody = null;
      }
      final Object? grant = declaredBody is Map ? declaredBody['grant'] : null;
      b.writeln(
        '<tr><th>Grant</th><td>${list(dvParseModuleCapabilities(grant, where: 'grant').capabilities.items())}</td></tr>',
      );
      final String trust;
      if (m.deployment == DVModuleDeployment.federated) {
        trust = 'deployed elsewhere and trusted through its signed manifest';
      } else {
        final List<DVModuleTrustFinding> found = dvEvaluateModuleTrust(
          root,
        ).findings.where((DVModuleTrustFinding f) => f.module == m.id).toList();
        trust = found.isEmpty
            ? 'verifies against its pin where it has one, and uses only what '
                  'it is granted'
            : found
                  .map(
                    (DVModuleTrustFinding f) =>
                        '${f.code == null ? '' : '<code>${dvDocsText(f.code!)}</code> '}'
                        '${f.isError ? '' : '(warning) '}${dvDocsText(f.message)}',
                  )
                  .join('<br>');
      }
      b.writeln('<tr><th>Trust</th><td>$trust</td></tr>');
      if (m.backend != null) {
        b.writeln(
          '<tr><th>Backend</th><td><code>${dvDocsText(m.backend!)}</code></td></tr>',
        );
      }
      if (m.location != null) {
        b.writeln(
          '<tr><th>Location</th><td><code>${dvDocsText(m.location!)}</code></td></tr>',
        );
      }
      b
        ..writeln(
          '<tr><th>Routes</th><td>${m.routes.isEmpty ? 'none' : m.routes.map((DVModuleRoute r) => '<a href="routes.html#route-${dvDocsAttr(r.mounted)}"><code>${dvDocsText(r.mounted)}</code></a>').join(', ')}</td></tr>',
        )
        ..writeln('</tbody></table>');
      if (m.problems.isNotEmpty) {
        b.writeln('<ul>');
        for (final String problem in m.problems) {
          b.writeln('<li class="finding">${dvDocsText(problem)}</li>');
        }
        b.writeln('</ul>');
      }
      b
        ..write(_backlinks('module:${m.id}'))
        ..writeln('</section>');
    }
    return b.toString();
  }

  String _diagnostics() {
    final StringBuffer b = StringBuffer()
      ..writeln('<p>The registry <code>dartvel explain</code> reads.</p>');
    for (final String family in DVDiagnostics.families()) {
      b
        ..writeln('<section id="family-${dvDocsAttr(family)}">')
        ..writeln('<h2>${dvDocsText(family)}</h2>')
        ..writeln(
          '<table><thead><tr><th>Code</th><th>Level</th><th>Reason</th></tr></thead><tbody>',
        );
      for (final DVDiagnostic d in DVDiagnostics.family(family)) {
        b.writeln(
          '<tr class="diagnostic" id="${dvDocsAttr(d.code)}">'
          '<td><code>${dvDocsText(d.code)}</code></td>'
          '<td>${dvDocsText(d.level)}</td>'
          '<td>${dvDocsInline(d.reason)}</td></tr>',
        );
      }
      b
        ..writeln('</tbody></table>')
        ..writeln('</section>');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------- helpers

  String _backlinks(String key) {
    final List<_Decision>? named = backlinks[key];
    if (named == null || named.isEmpty) return '';
    return '<p>Decisions: ${named.map((_Decision d) => '<a href="${dvDocsAttr(d.page)}">${dvDocsInline(d.title)}</a>').join(', ')}</p>\n';
  }

  String _description(_Mapping? mapping, String source) {
    if (mapping == null) {
      return '<p class="unmapped">no source to render from: '
          '<code>${dvDocsText(source)}</code></p>\n';
    }
    return '${_docHtml(_docAbove(mapping.lines, mapping.line))}'
        '<p class="source">Source: <code>${dvDocsText(mapping.source)}</code></p>\n';
  }

  String _docHtml(String doc) =>
      doc.isEmpty ? '' : '<div class="doc">${dvDocsMarkdown(doc)}</div>\n';

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
    final int open = text.indexOf('{', offset);
    if (open < 0) return const <String, String>{};
    final int close = _matching(text, open, '{', '}');
    final String body = text.substring(open, close);
    final int bodyLine = _lineOf(text, open);
    final Map<String, String> docs = <String, String>{};
    for (final DVGraphField f in model.fields) {
      final RegExpMatch? m = RegExp(
        'final\\s+[^;]*?\\b${RegExp.escape(f.name)}\\s*;',
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

  static String _typeHtml(
    String type,
    Set<String> models, {
    bool fromPolicies = false,
  }) {
    final String prefix = fromPolicies ? 'models.html' : '';
    return dvDocsText(type).replaceAllMapped(
      RegExp(r'[A-Za-z_][A-Za-z0-9_]*'),
      (Match m) => models.contains(m.group(0))
          ? '<a href="$prefix#model-${m.group(0)}">${m.group(0)}</a>'
          : m.group(0)!,
    );
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

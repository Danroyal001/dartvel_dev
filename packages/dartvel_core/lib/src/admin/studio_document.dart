/// Every Studio screen, and everything in it, as a document of its own.
///
/// Studio used to be served as the application's shell with nothing in it:
/// an empty `<body>` that the Flutter app painted over once it booted. That
/// left three things broken at once. A printer got a blank sheet, because a
/// canvas prints as one bitmap. A reader whose browser will not run the app
/// got nothing at all. And Ctrl+F had no text to match, so find over Studio
/// -- the screen a person spends their day in -- found nothing at all.
///
/// So a Studio page is rendered like every other page of the application, by
/// the same `dvRenderRoutePage`, from the same data Studio's own API reads:
/// the project's graph and its models. This file is the document model, the
/// screens it knows, and the markup.
///
/// Two things it deliberately does not carry.
///
/// Record values. A model document names the model and its fields and says
/// how many records it has; the values themselves are fetched by Studio's API
/// on demand and stay out of the document, which sits in the page source
/// where anything that can see the screen can read it and Ctrl+F's
/// `hidden` cannot keep it from a "view source". A field marked
/// `@DVModel.sensitiveField()` is named and typed like any other: a schema is
/// not anybody's secret, and a reader who needs the values has Studio.
///
/// Anything about who may open Studio. The rail lists the Team screen, and
/// the document says what it is for; the grants behind it are the API's to
/// answer, to the caller the grant admits.
library;

import 'dart:convert';
import 'dart:io';

import 'studio_api.dart' show DVStudioFieldSpec, DVStudioModelSpec;
import 'studio_site.dart' show DVStudioPageKind, DVStudioSitePage;

/// One of Studio's screens: the id it is addressed by, the name a person
/// reads, and what it is for.
///
/// Named `Spec` and not `DVStudioScreen` because the Studio screen itself is
/// a Flutter widget in `dartvel_flutter`, and an application that imports
/// both barrels has to be able to name both.
class DVStudioScreenSpec {
  const DVStudioScreenSpec({
    required this.id,
    required this.label,
    required this.summary,
  });

  /// The id Studio's own rail uses for this screen, and the last segment of
  /// the URL that opens it.
  final String id;

  /// What the rail calls it, and what the document's `<h1>` says.
  final String label;

  /// One sentence, for somebody reading the document and not the app: a
  /// printer, a crawler, a reader with scripting off. Written as what the
  /// screen is rather than as what it is called.
  final String summary;

  /// The URL of this screen under [mount].
  String path(String mount) => '$mount/$id';

  @override
  String toString() => 'DVStudioScreenSpec($id)';
}

/// Every screen free Studio has, in the order its rail puts them.
///
/// The ids are the ones `dartvel_flutter`'s `dvStudioServerSections` and
/// `DVStudioScreenSpec` use, and the two are held to each other by a test: a
/// screen this list names that the rail does not have would be a link to
/// nowhere, and a screen the rail has that this list does not is a screen a
/// crawler, a printer and a reader with scripting off never hear about.
///
/// Two screens are deliberately missing, because they exist only for a
/// project that declared something: `flags`, for an application with feature
/// flags, and `operations`, for one with alerting or incidents. A server
/// cannot know either -- they are wired at run time -- so printing a link to
/// them on a project that has none would be printing a dead link. Their URLs
/// still work on a project that has them, because the client is what knows.
///
/// `pages` is the mount itself: `<mount>` and `<mount>/pages` are the same
/// screen, so the first address a person is given is not a special case.
const List<DVStudioScreenSpec> dvStudioScreens = <DVStudioScreenSpec>[
  DVStudioScreenSpec(
    id: 'pages',
    label: 'Pages',
    summary:
        'Every page this application answers, and the canvas that draws '
        'one of them.',
  ),
  DVStudioScreenSpec(
    id: 'components',
    label: 'Components',
    summary:
        'Parts of a page designed once and put on any page of this '
        'application.',
  ),
  DVStudioScreenSpec(
    id: 'shortcuts',
    label: 'Shortcuts',
    summary: 'The keys this application answers, set without code.',
  ),
  DVStudioScreenSpec(
    id: 'models',
    label: 'Data',
    summary:
        'Every data model in this application, its fields, and its '
        'records.',
  ),
  DVStudioScreenSpec(
    id: 'routes',
    label: 'Site map',
    summary:
        'Every route this application answers, compiled from source and '
        'stored here.',
  ),
  DVStudioScreenSpec(
    id: 'frontend',
    label: 'Frontend',
    summary: 'The functions the pages of this application call.',
  ),
  DVStudioScreenSpec(
    id: 'functions',
    label: 'Backend',
    summary:
        'The functions this application answers for, and the steps each '
        'one runs.',
  ),
  DVStudioScreenSpec(
    id: 'modules',
    label: 'Modules',
    summary: 'The modules this application mounts, and what each one adds.',
  ),
  DVStudioScreenSpec(
    id: 'jobs',
    label: 'Tasks',
    summary:
        'The background tasks this application runs, and where each '
        'one is declared.',
  ),
  DVStudioScreenSpec(
    id: 'queues',
    label: 'Queue',
    summary: 'The queues those tasks run on.',
  ),
  DVStudioScreenSpec(
    id: 'cache',
    label: 'Cache',
    summary: 'What this application keeps in its cache, and for how long.',
  ),
  DVStudioScreenSpec(
    id: 'repository',
    label: 'GitHub',
    summary:
        "This application's studio folder, as a diff, a pull request or a "
        'push.',
  ),
  DVStudioScreenSpec(
    id: 'access',
    label: 'Team',
    summary: 'Who may open Studio for this application.',
  ),
];

/// The screen [id] names, or null when it names none.
const Map<String, String> dvStudioScreenAliases = <String, String>{
  'data': 'models',
  'sitemap': 'routes',
  'team': 'access',
};

DVStudioScreenSpec? dvStudioScreenFor(String id) {
  id = dvStudioScreenAliases[id] ?? id;
  for (final DVStudioScreenSpec screen in dvStudioScreens) {
    if (screen.id == id) return screen;
  }
  return null;
}

/// The two pages a caller who may not see the rest of Studio still gets.
///
/// Not screens: they are in [dvStudioScreens]'s sense the exceptions to it,
/// and are written by name where they are served rather than listed in a rail
/// neither of them draws. A signed-out visitor is told what Studio is and
/// nothing about what is behind it -- a document that listed the project's
/// screens and their names would describe the project to the one person who
/// is not allowed to see it.
const DVStudioScreenSpec dvStudioSignInScreen = DVStudioScreenSpec(
  id: 'login',
  label: 'Sign in to Studio',
  summary:
      "Studio is this application's own editor: its pages, its data, its "
      'backend and who may reach them.',
);

/// The first run: the owner has a printed password and no account yet.
const DVStudioScreenSpec dvStudioSetupScreen = DVStudioScreenSpec(
  id: 'setup',
  label: 'Set up Studio',
  summary:
      'Studio needs an owner before anybody can open it. This is where that '
      'account is made.',
);

/// A path under [mount], resolved: the screen it names and the object in it.
///
/// `<mount>` and `<mount>/pages` are the same screen with no object, so the
/// first address a person is given is not a special case. An object is every
/// segment after the screen's own, which is what lets a page be addressed by
/// the route it answers -- `/__studio/pages/products/:slug` -- without a
/// second scheme for paths.
class DVStudioTarget {
  const DVStudioTarget({required this.screen, this.object = const <String>[]});

  final DVStudioScreenSpec screen;

  /// The segments naming what is open inside [screen], empty for the screen
  /// itself.
  final List<String> object;

  /// The URL this target is at, under [mount].
  String path(String mount) => object.isEmpty
      ? screen.path(mount)
      : '$mount/${screen.id}/${object.join('/')}';

  /// What was asked for, as one name: a model, a route, a function.
  String get objectName => object.join('/');
}

/// The screen and object [route] under [mount] names, or null when it names
/// neither -- a path nobody has, a file, an API call. Null rather than a
/// guess, so a scanner walking the mount gets the application's own answer
/// instead of a Studio page for every path it tries.
DVStudioTarget? dvStudioTargetFor(String route, {required String mount}) {
  if (route == mount || route == '$mount/') {
    return DVStudioTarget(screen: dvStudioScreens.first);
  }
  final String prefix = '$mount/';
  if (!route.startsWith(prefix)) return null;
  final List<String> segments = <String>[
    for (final String raw in route.substring(prefix.length).split('/'))
      if (raw.isNotEmpty) Uri.decodeComponent(raw),
  ];
  if (segments.isEmpty) return null;
  final DVStudioScreenSpec? screen = dvStudioScreenFor(segments.first);
  if (screen == null) return null;
  return DVStudioTarget(screen: screen, object: segments.sublist(1));
}

/// One thing a document lists, and the URL that opens it.
class DVStudioRow {
  const DVStudioRow({
    required this.label,
    required this.href,
    this.detail,
    this.extra,
    this.head = false,
  });

  /// What a person reads.
  final String label;

  /// Where it is, as a Studio URL.
  final String href;

  /// What else is known about it, in a second column.
  final String? detail;

  /// A third column, for a screen that has three things to say about a row.
  final String? extra;

  /// Whether this row is the screen's own heading rather than a list entry:
  /// what a model's field is, when the document is about one model.
  final bool head;
}

/// A column of a table in a Studio document.
class DVStudioColumn {
  const DVStudioColumn(this.label);
  final String label;
}

/// What a server knows about the project, for the documents it writes.
///
/// Read from the graph the build writes beside Studio and from the models the
/// backend compiled, which are the two places a server knows any of this from.
/// Everything is optional: a graph missing, unreadable or empty leaves the
/// document shorter rather than failing the request.
class DVStudioProjectData {
  const DVStudioProjectData({
    this.compiled = const <Map<String, Object?>>[],
    this.pages = const <DVStudioSitePage>[],
    this.models = const <DVStudioModelSpec>[],
    this.functions = const <String>[],
    this.jobs = const <String>[],
    this.queues = const <String>[],
    this.modules = const <String>[],
  });

  /// The routes a build compiled, as the graph writes them.
  ///
  /// Kept in the graph's own shape rather than resolved here, because the
  /// pages stored beside them are in the database and the two are composed
  /// into [pages] by whoever holds both.
  final List<Map<String, Object?>> compiled;

  /// Every page the application answers, compiled and stored.
  final List<DVStudioSitePage> pages;

  /// Every data model, compiled or designed here.
  final List<DVStudioModelSpec> models;

  /// The names of the functions the application answers for.
  final List<String> functions;

  /// The names of its background tasks.
  final List<String> jobs;

  /// The queues its tasks run on.
  final List<String> queues;

  /// The modules it mounts.
  final List<String> modules;

  /// The project data the build's [root] graph describes, read fresh so a
  /// build that ran while the server was up is what the documents say.
  ///
  /// A graph that is missing, unreadable or not an object is no data rather
  /// than an exception: a Studio page that threw would answer an operator's
  /// screen with a 500 for a file the build writes. [pages] is left empty
  /// here, because composing it needs the stored documents too and that is
  /// the caller's to ask for.
  static DVStudioProjectData fromGraph(String root) {
    Object? decoded;
    try {
      decoded = jsonDecode(
        File('$root${Platform.pathSeparator}graph.json').readAsStringSync(),
      );
    } on Object {
      return const DVStudioProjectData();
    }
    if (decoded is! Map) return const DVStudioProjectData();
    List<Map<String, Object?>> maps(String key) => <Map<String, Object?>>[
      for (final Object? entry
          in ((decoded as Map)[key] as List?) ?? const <Object?>[])
        if (entry is Map) entry.cast<String, Object?>(),
    ];
    List<String> named(String key, String field) => <String>[
      for (final Map<String, Object?> entry in maps(key))
        '${entry[field] ?? ''}',
    ].where((String name) => name.isNotEmpty).toList();
    return DVStudioProjectData(
      compiled: maps('routes'),
      functions: named('functions', 'name'),
      jobs: named('jobs', 'name'),
      queues: <String>{
        for (final Map<String, Object?> job in maps('jobs'))
          if (job['queue'] is String) '${job['queue']}',
      }.where((String queue) => queue.isNotEmpty).toList(),
      modules: <String>[
        for (final Map<String, Object?> module in maps('modules'))
          '${module['name'] ?? module['id'] ?? ''}',
      ].where((String name) => name.isNotEmpty).toList(),
    );
  }
}

/// A Studio document: the markup a screen is served with, and the plain
/// lines it is made of.
///
/// [html] is what the page is rendered from. [text] is the same content with
/// the markup taken off, which is what the route's own metadata carries and
/// what a tool with neither reads.
class DVStudioDocument {
  const DVStudioDocument({
    required this.heading,
    required this.html,
    required this.text,
  });

  /// What the document's `<h1>` says: the screen's own name, or the object's
  /// when one is open. It is also the tab's title, so a person with eleven
  /// Studio tabs open can tell them apart.
  final String heading;

  final String html;
  final List<String> text;
}

const HtmlEscape _escape = HtmlEscape(HtmlEscapeMode.element);

/// The document for [target]: the object it names where the project has one,
/// and its screen otherwise.
///
/// An object nobody has is not an error. A link somebody wrote by hand, or a
/// list that has changed since it was printed, opens the screen rather than
/// answering "no such thing" -- the screen is a real page and a 404 for a
/// name Studio cannot resolve makes a stale bookmark look like a broken
/// Studio.
DVStudioDocument dvStudioDocumentFor(
  DVStudioTarget target, {
  required String mount,
  required DVStudioProjectData data,
  List<DVStudioModelSpec> models = const <DVStudioModelSpec>[],
  bool navigation = true,
}) {
  final DVStudioDocument? object = target.object.isEmpty
      ? null
      : _objectDocument(
          target,
          mount: mount,
          data: data,
          models: models,
          navigation: navigation,
        );
  return object ??
      _screenDocument(target, mount: mount, data: data, navigation: navigation);
}

/// The screen itself: what it is for, and everything the server knows is in
/// it, each with its own URL.
DVStudioDocument _screenDocument(
  DVStudioTarget target, {
  required String mount,
  required DVStudioProjectData data,
  required bool navigation,
}) {
  final DVStudioScreenSpec screen = target.screen;
  final StringBuffer html = StringBuffer()
    ..writeln(navigation ? _rail(target, mount) : '')
    ..writeln('<h1>${_escape.convert(screen.label)}</h1>')
    ..writeln('<p>${_escape.convert(screen.summary)}</p>');
  final List<String> text = <String>[screen.label, screen.summary];

  // What the server knows is inside this screen, as a table with a header
  // row: the one shape a screen reader reads a set of named values
  // correctly, and the one that prints.
  void table(
    String caption,
    List<DVStudioColumn> columns,
    List<DVStudioRow> rows,
  ) {
    html..writeln('<h2>${_escape.convert(caption)}</h2>');
    if (rows.isEmpty) {
      html.writeln('<p>Nothing here yet.</p>');
      text
        ..add(caption)
        ..add('Nothing here yet.');
      return;
    }
    html.writeln('<table>');
    html.writeln('<caption>${_escape.convert(caption)}</caption>');
    html.writeln('<thead><tr>');
    for (final DVStudioColumn column in columns) {
      html.writeln('<th scope="col">${_escape.convert(column.label)}</th>');
    }
    html.writeln('</tr></thead>');
    html.writeln('<tbody>');
    for (final DVStudioRow row in rows) {
      html.writeln('<tr>');
      final String name = row.href.isEmpty
          ? _escape.convert(row.label)
          : '<a href="${_escape.convert(row.href)}">'
                '${_escape.convert(row.label)}</a>';
      // A row's own name is its row header, so a reader saying "Product"
      // reaches the row it is in rather than a list of words.
      html.write(row.head ? '<th scope="row">$name</th>' : '<td>$name</td>');
      for (int i = 0; i < columns.length - 1; i++) {
        html.writeln(
          '<td>${_escape.convert(switch (i) {
            0 => row.detail ?? '',
            1 => row.extra ?? '',
            _ => '',
          })}</td>',
        );
      }
      html.writeln('</tr>');
      text
        ..add(row.label)
        ..add(row.detail ?? '')
        ..add(row.extra ?? '');
    }
    html
      ..writeln('</tbody>')
      ..writeln('</table>');
  }

  const DVStudioColumn name = DVStudioColumn('Name');
  switch (screen.id) {
    case 'pages':
    case 'routes':
      final String child = screen.id;
      table(
        screen.id == 'pages' ? 'Pages' : 'Routes',
        <DVStudioColumn>[
          const DVStudioColumn('Route'),
          const DVStudioColumn('Page'),
          const DVStudioColumn('Kind'),
        ],
        <DVStudioRow>[
          for (final DVStudioSitePage page in data.pages)
            DVStudioRow(
              // The URL a page is at is the URL that opens it in Studio:
              // the page's own route is an object's name, not an escape.
              label: page.path,
              href: page.path == '/'
                  ? '$mount/$child'
                  : '$mount/$child/${Uri.encodeComponent(page.path.substring(1))}',
              // The route is what names a row, so it is the row's header:
              // a reader saying "/products/:slug" lands in that row rather
              // than on a word in a line of words.
              head: true,
              // Whatever the source called the page, which is not always a
              // person-facing title and never markup.
              detail: page.title ?? page.page,
              extra: _kind(page.kind),
            ),
        ],
      );
    case 'models':
      table(
        'Models',
        <DVStudioColumn>[name, const DVStudioColumn('Fields')],
        <DVStudioRow>[
          for (final DVStudioModelSpec model in data.models)
            DVStudioRow(
              label: model.id,
              href: '$mount/models/${Uri.encodeComponent(model.id)}',
              detail: '${model.fields.length} fields',
            ),
        ],
      );
    case 'functions':
    case 'frontend':
      table(
        screen.label,
        <DVStudioColumn>[name],
        <DVStudioRow>[
          for (final String function in data.functions)
            if (screen.id == 'functions')
              DVStudioRow(
                label: function,
                href: '$mount/functions/${Uri.encodeComponent(function)}',
              )
            else
              DVStudioRow(label: function, href: ''),
        ],
      );
    case 'jobs':
      table(
        'Tasks',
        <DVStudioColumn>[name],
        <DVStudioRow>[
          for (final String job in data.jobs)
            DVStudioRow(
              label: job,
              href: '$mount/jobs/${Uri.encodeComponent(job)}',
            ),
        ],
      );
    case 'queues':
      table(
        'Queues',
        <DVStudioColumn>[name],
        <DVStudioRow>[
          for (final String queue in data.queues)
            DVStudioRow(
              label: queue,
              href: '$mount/queues/${Uri.encodeComponent(queue)}',
            ),
        ],
      );
    case 'modules':
      table(
        'Modules',
        <DVStudioColumn>[name],
        <DVStudioRow>[
          for (final String module in data.modules)
            DVStudioRow(
              label: module,
              href: '$mount/modules/${Uri.encodeComponent(module)}',
            ),
        ],
      );
    default:
      // A screen holding what the running application decided rather than
      // what the build wrote: the components, the shortcut keys, the cache,
      // the repository and the team. The document says what the screen is for
      // and says plainly that what is in it is not here, rather than printing
      // an empty list it would have had to invent.
      html.writeln('<p>${_escape.convert(_decidedAtRuntime)}</p>');
      text.add(_decidedAtRuntime);
  }

  return DVStudioDocument(
    heading: screen.label,
    html: html.toString(),
    text: text,
  );
}

/// The document for the object [target] names, or null when the project has
/// no such object, so the caller can answer the screen instead.
DVStudioDocument? _objectDocument(
  DVStudioTarget target, {
  required String mount,
  required DVStudioProjectData data,
  required List<DVStudioModelSpec> models,
  required bool navigation,
}) {
  final DVStudioScreenSpec screen = target.screen;
  final String name = target.objectName;
  final String parent = '$mount/${screen.id}';
  final String crumb =
      '<p><a href="${_escape.convert(parent)}">${_escape.convert(screen.label)}</a></p>';
  final StringBuffer html = StringBuffer()
    ..writeln(navigation ? _rail(target, mount) : '')
    ..writeln(crumb);

  switch (screen.id) {
    case 'models':
      final DVStudioModelSpec? model = <DVStudioModelSpec>[
        ...models,
        ...data.models,
      ].where((DVStudioModelSpec m) => m.id == name).firstOrNull;
      if (model == null) return null;
      html
        ..writeln('<h1>${_escape.convert(model.id)}</h1>')
        ..writeln(
          '<p>A data model of this application, with '
          '${model.fields.length} fields and its records in '
          '${_escape.convert(model.table)}.</p>',
        )
        ..writeln('<h2>Fields</h2>')
        ..writeln('<table>')
        ..writeln('<caption>Fields of ${_escape.convert(model.id)}</caption>')
        ..writeln(
          '<thead><tr><th scope="col">Field</th><th scope="col">Type</th>'
          '<th scope="col">Notes</th></tr></thead>',
        )
        ..writeln('<tbody>');
      for (final DVStudioFieldSpec field in model.fields) {
        html..writeln(
          '<tr><th scope="row">${_escape.convert(field.name)}</th>'
          '<td>${_escape.convert(field.type)}</td>'
          '<td>${_escape.convert(_fieldNotes(field))}</td></tr>',
        );
      }
      html
        ..writeln('</tbody>')
        ..writeln('</table>');
      return DVStudioDocument(
        heading: model.id,
        html: html.toString(),
        text: <String>[
          model.id,
          'A data model of this application, with ${model.fields.length} '
              'fields and its records in ${model.table}.',
          'Fields',
          for (final DVStudioFieldSpec field in model.fields)
            '${field.name} ${field.type}${_fieldNotes(field).isEmpty ? '' : ' — ${_fieldNotes(field)}'}',
        ],
      );
    case 'pages':
    case 'routes':
      final DVStudioSitePage? page = data.pages
          .where((DVStudioSitePage p) => p.path == '/$name')
          .firstOrNull;
      if (page == null) return null;
      final String self = page.path == '/'
          ? parent
          : '$parent/${Uri.encodeComponent(name)}';
      html
        ..writeln('<h1>${_escape.convert(page.title ?? page.path)}</h1>')
        ..writeln(
          '<p>${_escape.convert('${_kind(page.kind)} page at $self.')}</p>',
        )
        ..writeln('<dl>')
        ..writeln(
          '<dt>Route</dt><dd><code>${_escape.convert(page.path)}</code></dd>',
        );
      if (page.page != null) {
        html.writeln(
          '<dt>Page</dt><dd><code>${_escape.convert(page.page!)}</code></dd>',
        );
      }
      if (page.source != null) {
        html.writeln(
          '<dt>Source</dt><dd><code>${_escape.convert(page.source!)}</code></dd>',
        );
      }
      if (page.params.isNotEmpty) {
        html.writeln(
          '<dt>Parameters</dt><dd>${_escape.convert(page.params.join(', '))}</dd>',
        );
      }
      html
        ..writeln('</dl>')
        ..writeln(
          '<p>Open it in the canvas at <a href="${_escape.convert(self)}">${_escape.convert(self)}</a>.</p>',
        );
      return DVStudioDocument(
        heading: page.title ?? page.path,
        html: html.toString(),
        text: <String>[
          page.title ?? page.path,
          '${_kind(page.kind)} page at $self.',
          'Route ${page.path}',
          if (page.page != null) 'Page ${page.page}',
          if (page.source != null) 'Source ${page.source}',
          if (page.params.isNotEmpty) 'Parameters ${page.params.join(', ')}',
        ],
      );
    case 'functions':
      if (!data.functions.contains(name)) return null;
      html
        ..writeln('<h1>${_escape.convert(name)}</h1>')
        ..writeln(
          '<p>A backend function of this application. Its steps, runs and '
          'variables are Studio\'s to show.</p>',
        );
      return DVStudioDocument(
        heading: name,
        html: html.toString(),
        text: <String>[name, 'A backend function of this application.'],
      );
    case 'jobs':
      if (!data.jobs.contains(name)) return null;
      html
        ..writeln('<h1>${_escape.convert(name)}</h1>')
        ..writeln('<p>A background task of this application.</p>');
      return DVStudioDocument(
        heading: name,
        html: html.toString(),
        text: <String>[name, 'A background task of this application.'],
      );
    case 'queues':
      if (!data.queues.contains(name)) return null;
      html
        ..writeln('<h1>${_escape.convert(name)}</h1>')
        ..writeln('<p>A queue this application\'s tasks run on.</p>');
      return DVStudioDocument(
        heading: name,
        html: html.toString(),
        text: <String>[name, 'A queue this application\'s tasks run on.'],
      );
    case 'modules':
      if (!data.modules.contains(name)) return null;
      html
        ..writeln('<h1>${_escape.convert(name)}</h1>')
        ..writeln('<p>A module this application mounts.</p>');
      return DVStudioDocument(
        heading: name,
        html: html.toString(),
        text: <String>[name, 'A module this application mounts.'],
      );
    default:
      return null;
  }
}

/// The rail: every screen, at its own URL, with this one marked.
///
/// `aria-current="page"` on the screen being read, because a reader has to
/// be told where they are from the document alone, and a link that is only a
/// link is a link they have to follow to find out.
String _rail(DVStudioTarget target, String mount) {
  final StringBuffer out = StringBuffer()
    ..writeln('<nav aria-label="Studio sections">')
    ..writeln('<ul>');
  for (final DVStudioScreenSpec screen in dvStudioScreens) {
    final bool here = screen.id == target.screen.id;
    out.writeln(
      '<li><a href="${_escape.convert(screen.path(mount))}"'
      '${here ? ' aria-current="page"' : ''}>'
      '${_escape.convert(screen.label)}</a></li>',
    );
  }
  out
    ..writeln('</ul>')
    ..writeln('</nav>');
  return out.toString();
}

/// What a screen holds that no document can know, said the same way for each
/// one: the running application decides it, and this document is what the
/// build wrote.
const String _decidedAtRuntime =
    'What is in this screen is the running application\'s own, decided at '
    'runtime. This document carries what the build wrote.';

/// How a page's kind is named to a person, rather than the enum's word.
String _kind(DVStudioPageKind kind) => switch (kind) {
  DVStudioPageKind.code => 'Compiled',
  DVStudioPageKind.stored => 'Stored',
  DVStudioPageKind.override => 'Overrides a compiled page',
};

/// What is known about a field beyond its name and type, in words.
String _fieldNotes(DVStudioFieldSpec field) => <String>[
  if (field.sensitive) 'sensitive',
  if (field.unique) 'unique',
  if (field.relation != null) 'relates to ${field.relation}',
].join(', ');

/// Studio served by the application's own backend.
///
/// A web-server binary carries Studio and serves it at the admin mount, to
/// the people granted it. What it served was a static manifest -- a model's
/// name and no record of it, and no page builder. This is the real Studio in
/// that place: [DVStudioScreen], with a page store that publishes to the
/// server, and sections for the records of every model, the build's routes,
/// functions and jobs, and who may open Studio.
///
/// Everything goes through a [DVStudioTransport], so the screens have no idea
/// they are in a browser. The browser's transport sends paths relative to the
/// page, which is served at the mount: `api/models` is `<mount>/api/models`
/// wherever the project mounted its admin.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart' as core
    show DVDatabase, DVStudioApi, DVStudioModelSpec, Headers, Request, Response;
import 'package:dartvel_core/dartvel.dart'
    show
        DVAccess,
        DVModelAccess,
        DVStudioFieldSpec,
        DVStudioIndexSpec,
        DVStudioModelOrigin;
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart';
import 'studio_first_run.dart';
import 'studio_server_transport_stub.dart'
    if (dart.library.js_interop) 'studio_server_transport_web.dart' as transport;
import 'studio_sign_in.dart';

part 'studio_model_designer.dart';

/// What the backend answered: a status and the decoded JSON body.
class DVStudioReply {
  const DVStudioReply(this.status, this.body);

  final int status;
  final Object? body;
}

/// Sends one request to the backend Studio is served by. [path] is relative
/// to the mount, with no leading slash.
typedef DVStudioTransport = Future<DVStudioReply> Function(
  String method,
  String path, {
  Object? body,
});

/// The browser's transport: same-origin, with the session cookie, and the
/// CSRF header every write needs.
///
/// [base] goes before every path: `<mount>/` for Studio in the application,
/// whose pages are at the application's base rather than the mount's.
DVStudioTransport dvStudioBrowserTransport({String base = ''}) {
  final math.Random random = math.Random.secure();
  const String alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final String csrf = String.fromCharCodes(<int>[
    for (int i = 0; i < 32; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
  return (String method, String path, {Object? body}) =>
      transport.dvStudioSend(method, '$base$path', body: body, csrf: csrf);
}

/// The page documents published on the server that served this page, from
/// its `/_dartvel/pages`. Empty when it answers anything else.
Future<List<DVPageDocument>> dvPublishedPagesFromServer() async {
  final DVStudioReply reply =
      await transport.dvStudioSend('GET', '/_dartvel/pages', csrf: '');
  final Object? body = reply.body;
  if (reply.status != 200 || body is! Map || body['pages'] is! List) {
    return const <DVPageDocument>[];
  }
  return <DVPageDocument>[
    for (final Object? page in body['pages']! as List)
      if (page is Map && page['document'] is Map)
        DVPageDocument.fromJson(
            (page['document']! as Map).cast<String, Object?>()),
  ];
}

/// A request the backend refused, with what it said.
class DVStudioRemoteError implements Exception {
  const DVStudioRemoteError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// A page was changed in code since Studio last saved it -- on a
/// development server, where each page is also a file of the project -- and
/// Studio did not write over it.
class DVStudioChangedInCode extends DVStudioRemoteError {
  const DVStudioChangedInCode(this.path, this.inCode, String message)
      : super(409, 'changed_in_code', message);

  /// The file, relative to the project.
  final String path;

  /// The page as the file has it now.
  final DVPageDocument? inCode;
}

/// One field of a model, as the backend describes it.
class DVStudioField {
  const DVStudioField({
    required this.name,
    required this.type,
    this.sensitive = false,
    this.options,
    this.relation,
    DVStudioFieldSpec? spec,
  }) : _spec = spec;

  final DVStudioFieldSpec? _spec;

  /// The field as the backend describes it, rules included: the same
  /// description a compiled model and a designed one both have.
  DVStudioFieldSpec get spec =>
      _spec ??
      DVStudioFieldSpec(
        name: name,
        type: type,
        sensitive: sensitive,
        options: options,
        relation: relation,
      );

  factory DVStudioField.fromJson(Map<String, Object?> json) => DVStudioField(
        spec: DVStudioFieldSpec.fromJson(json),
        name: '${json['name']}',
        type: '${json['type']}',
        sensitive: json['sensitive'] == true,
        options: json['options'] is List
            ? <String>[
                for (final Object? option in json['options']! as List)
                  '$option',
              ]
            : null,
        relation: json['relation'] is String ? json['relation']! as String : null,
      );

  final String name;
  final String type;
  final bool sensitive;

  /// An enum's values, when the field is one.
  final List<String>? options;

  /// The model whose key this field holds, when it holds one.
  final String? relation;

  bool get nullable => type.endsWith('?');

  /// The type with no `?`.
  String get baseType => type.replaceAll('?', '').trim();

  /// Whether the value is a list, set or map, edited as JSON.
  bool get isCollection =>
      baseType.startsWith('List') ||
      baseType.startsWith('Set') ||
      baseType.startsWith('Map');

  /// Whether the field can be set here but never read back: a sensitive text
  /// field, drawn like a password field. Its value is never sent to Studio,
  /// so the input starts empty, and leaving it empty keeps what is stored.
  bool get writeOnly =>
      sensitive && options == null && relation == null && baseType == 'String';

  /// Whether Studio has a control for this type. Anything else is shown and
  /// left as it is.
  bool get editable =>
      !sensitive &&
      (options != null ||
          relation != null ||
          isCollection ||
          const <String>{'String', 'int', 'double', 'num', 'bool', 'DateTime'}
              .contains(baseType));
}

/// A model, as the backend describes it.
class DVStudioModel {
  const DVStudioModel({
    required this.model,
    required this.key,
    required this.fields,
    this.versioned = true,
    this.module,
    this.origin = DVStudioModelOrigin.code,
    this.softDelete = false,
    this.indexes = const <DVStudioIndexSpec>[],
    this.access,
  });

  factory DVStudioModel.fromJson(Map<String, Object?> json) => DVStudioModel(
        model: '${json['model']}',
        module: json['module'] is String ? json['module']! as String : null,
        key: '${json['key']}',
        versioned: json['versioned'] != false,
        softDelete: json['softDelete'] == true,
        origin: json['origin'] == DVStudioModelOrigin.studio.name
            ? DVStudioModelOrigin.studio
            : DVStudioModelOrigin.code,
        fields: <DVStudioField>[
          for (final Object? field in (json['fields'] as List?) ?? const <Object?>[])
            DVStudioField.fromJson((field! as Map).cast<String, Object?>()),
        ],
        indexes: <DVStudioIndexSpec>[
          for (final Object? index in (json['indexes'] as List?) ?? const <Object?>[])
            if (index is Map) DVStudioIndexSpec.fromJson(index),
        ],
        access: json['access'] is Map
            ? DVModelAccess.fromJson(json['access']! as Map)
            : null,
      );

  /// Where the model is defined: in code, or designed in Studio.
  final DVStudioModelOrigin origin;

  /// Whether deleting a record marks it rather than removing it.
  final bool softDelete;

  /// The indexes the model asks its database for.
  final List<DVStudioIndexSpec> indexes;

  /// Who may do what through the model's data API, or null for a model
  /// whose policies are written in code.
  final DVModelAccess? access;

  /// Whether Studio designs this model, rather than showing one written in
  /// code.
  bool get designed => origin == DVStudioModelOrigin.studio;

  /// The model as its designer sends it back: key, fields with their rules,
  /// indexes and access.
  Map<String, Object?> get definition => <String, Object?>{
        'key': key,
        'fields': <Object?>[
          for (final DVStudioField field in fields) field.spec.toJson(),
        ],
        'versioned': versioned,
        'softDelete': softDelete,
        if (indexes.isNotEmpty)
          'indexes': <Object?>[
            for (final DVStudioIndexSpec index in indexes) index.toJson(),
          ],
        if (access != null) 'access': access!.toJson(),
      };

  /// The name the backend addresses the model by: `notes.Memo` for a
  /// mounted module's.
  final String model;

  /// The mounted module the model belongs to, or null.
  final String? module;
  final String key;
  final List<DVStudioField> fields;
  final bool versioned;

  /// The fields Studio shows: every one that is not sensitive.
  List<DVStudioField> get visibleFields => <DVStudioField>[
        for (final DVStudioField field in fields)
          if (!field.sensitive) field,
      ];

  /// The fields a record's form has a control for: the visible ones, and
  /// each sensitive one that can be written without being read.
  List<DVStudioField> get formFields => <DVStudioField>[
        for (final DVStudioField field in fields)
          if (!field.sensitive || field.writeOnly) field,
      ];
}

/// One stored record, at the version it was read.
class DVStudioRecordData {
  const DVStudioRecordData({
    required this.key,
    required this.version,
    required this.values,
  });

  factory DVStudioRecordData.fromJson(Map<String, Object?> json) =>
      DVStudioRecordData(
        key: '${json['key']}',
        version: (json['version'] as num?)?.toInt() ?? 0,
        values: ((json['values'] as Map?) ?? const <String, Object?>{})
            .cast<String, Object?>(),
      );

  final String key;
  final int version;
  final Map<String, Object?> values;
}

/// Studio's calls to the backend it is served by.
class DVStudioClient {
  const DVStudioClient(this.transport);

  final DVStudioTransport transport;

  /// The signed-in account, `{userId, email}`.
  Future<Map<String, Object?>> me() async => _map(await _send('GET', 'api/me'));

  /// Ends this session on the server and clears its cookie.
  Future<void> signOut() async {
    await transport('POST', 'api/auth/sign-out');
  }

  /// Whether this caller has a granted session to open Studio.
  Future<bool> access() async {
    try {
      final DVStudioReply reply = await transport('GET', 'api/access');
      final Object? body = reply.body;
      return reply.status == 200 && body is Map && body['granted'] == true;
    } on Object {
      return false;
    }
  }

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final DVStudioReply reply = await transport(method, path, body: body);
    if (reply.status >= 200 && reply.status < 300) return reply.body;
    final Object? json = reply.body;
    final Map<Object?, Object?> error =
        json is Map ? json : const <Object?, Object?>{};
    String message =
        '${error['message'] ?? 'The server answered ${reply.status}.'}';
    if (_isMarkupOrDump(message)) {
      message = 'The server answered ${reply.status}.';
    }
    if (error['error'] == 'changed_in_code') {
      final Object? inCode = error['inCode'];
      throw DVStudioChangedInCode(
        '${error['path'] ?? ''}',
        inCode is Map
            ? DVPageDocument.fromJson(inCode.cast<String, Object?>())
            : null,
        message,
      );
    }
    throw DVStudioRemoteError(
      reply.status,
      '${error['error'] ?? 'http_${reply.status}'}',
      message,
    );
  }

  static bool _isMarkupOrDump(String text) {
    final String trimmed = text.trim();
    return trimmed.startsWith('<') ||
        trimmed.contains('<!DOCTYPE') ||
        trimmed.contains('<!doctype') ||
        trimmed.contains('<html') ||
        trimmed.contains('<body') ||
        trimmed.length > 200;
  }

  Map<String, Object?> _map(Object? json) =>
      json is Map ? json.cast<String, Object?>() : const <String, Object?>{};

  List<Map<String, Object?>> _list(Object? json, String key) =>
      <Map<String, Object?>>[
        for (final Object? item in (_map(json)[key] as List?) ?? const <Object?>[])
          if (item is Map) item.cast<String, Object?>(),
      ];

  static String _segment(String value) => Uri.encodeComponent(value);

  Future<List<DVStudioModel>> models() async =>
      (await modelCatalog()).models;

  /// Every data model, and whether one designed here can also be written to
  /// the project's source -- true only on a development server.
  Future<({List<DVStudioModel> models, bool sourceWritable})>
      modelCatalog() async {
    final Map<String, Object?> body = _map(await _send('GET', 'api/models'));
    return (
      models: <DVStudioModel>[
        for (final Map<String, Object?> model in _list(body, 'models'))
          DVStudioModel.fromJson(model),
      ],
      sourceWritable: body['sourceWritable'] == true,
    );
  }

  /// Stores [definition] as the model [name], designed in Studio: its key,
  /// fields and their rules, indexes and access. Answers the model as it
  /// was stored.
  Future<DVStudioModel> saveModel(
    String name,
    Map<String, Object?> definition,
  ) async =>
      DVStudioModel.fromJson(_map(await _send(
        'PUT',
        'api/models/${_segment(name)}',
        body: <String, Object?>{'definition': definition},
      )));

  /// Removes the model [name] designed in Studio. Its records are kept.
  Future<void> deleteModel(String name) =>
      _send('DELETE', 'api/models/${_segment(name)}');

  /// Writes the model [name] to the project's source, and answers the file.
  Future<String> writeModelSource(String name) async => '${_map(await _send(
        'POST',
        'api/models/${_segment(name)}/source',
      ))['source']}';

  /// Every route the site answers, compiled and stored, each marked.
  Future<List<DVStudioSitePage>> site() async => <DVStudioSitePage>[
        for (final Map<String, Object?> page
            in _list(await _send('GET', 'api/site'), 'pages'))
          DVStudioSitePage.fromJson(page),
      ];

  /// The structure the build captured for the compiled page at [route], or
  /// null when it captured none.
  Future<Object?> structure(String route) async {
    try {
      return _map(await _send(
        'GET',
        'api/site/structure?route=${Uri.encodeQueryComponent(route)}',
      ))['structure'];
    } on DVStudioRemoteError catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<List<DVStudioRecordData>> records(String model) async =>
      <DVStudioRecordData>[
        for (final Map<String, Object?> record in _list(
            await _send('GET', 'api/models/${_segment(model)}/records'),
            'records'))
          DVStudioRecordData.fromJson(record),
      ];

  Future<DVStudioRecordData> create(
          String model, Map<String, Object?> values) async =>
      DVStudioRecordData.fromJson(_map(await _send(
        'POST',
        'api/models/${_segment(model)}/records',
        body: <String, Object?>{'values': values},
      )));

  /// Stores [values] over [read], refused when the record has moved since.
  Future<DVStudioRecordData> update(String model, DVStudioRecordData read,
          Map<String, Object?> values) async =>
      DVStudioRecordData.fromJson(_map(await _send(
        'PUT',
        'api/models/${_segment(model)}/records/${_segment(read.key)}',
        body: <String, Object?>{'version': read.version, 'values': values},
      )));

  Future<void> delete(String model, DVStudioRecordData read) => _send(
        'DELETE',
        'api/models/${_segment(model)}/records/${_segment(read.key)}'
            '?version=${read.version}',
      );

  Future<List<DVPageDocument>> pages() async => <DVPageDocument>[
        for (final Map<String, Object?> page
            in _list(await _send('GET', 'api/pages'), 'pages'))
          if (page['document'] is Map)
            DVPageDocument.fromJson(
                (page['document']! as Map).cast<String, Object?>()),
      ];

  /// Saves [document]. On a development server, where the page is also a
  /// file of the project, a file changed in code since Studio last saved it
  /// is not written over: [DVStudioChangedInCode], unless [force].
  Future<void> savePage(DVPageDocument document, {bool force = false}) => _send(
        'PUT',
        'api/pages',
        body: <String, Object?>{
          'document': document.toJson(),
          if (force) 'force': true,
        },
      );

  Future<void> deletePage(String route) =>
      _send('DELETE', 'api/pages?route=${Uri.encodeQueryComponent(route)}');

  /// Every function built in Studio, as `{name, document}`.
  Future<List<Map<String, Object?>>> functions() async =>
      _list(await _send('GET', 'api/functions'), 'functions');

  Future<void> saveFunction(Map<String, Object?> document) => _send(
        'PUT',
        'api/functions',
        body: <String, Object?>{'document': document},
      );

  Future<void> deleteFunction(String name) => _send(
      'DELETE', 'api/functions?name=${Uri.encodeQueryComponent(name)}');

  Future<List<Map<String, Object?>>> grants() async =>
      _list(await _send('GET', 'api/grants'), 'grants');

  /// Lets [account], an address or an account id, open Studio.
  Future<void> grant(String account) =>
      _send('POST', 'api/grants', body: <String, Object?>{'account': account});

  /// Takes [userId]'s grant on [tenant] away. The server refuses the
  /// caller's own grant and the last one on a tenant with a 409 unless
  /// [confirm] says the person meant it.
  Future<void> revoke(String userId,
          {required String tenant, bool confirm = false}) =>
      _send(
        'DELETE',
        'api/grants?userId=${Uri.encodeQueryComponent(userId)}'
            '&tenant=${Uri.encodeQueryComponent(tenant)}'
            '${confirm ? '&confirm=true' : ''}',
      );

  /// Every queue the build declares, with its pending jobs and dead letters.
  Future<List<Map<String, Object?>>> queues() async =>
      _list(await _send('GET', 'api/queues'), 'queues');

  /// Puts a dead-lettered job back on its queue.
  Future<void> retryJob(String id) =>
      _send('POST', 'api/queues/jobs/${_segment(id)}/retry');

  /// Drops a dead-lettered job for good.
  Future<void> discardJob(String id) =>
      _send('POST', 'api/queues/jobs/${_segment(id)}/discard');

  /// Every cache tag, with the keys under it.
  Future<List<Map<String, Object?>>> cacheTags() async =>
      _list(await _send('GET', 'api/cache/tags'), 'tags');

  /// Drops every key under [tag], and returns the keys dropped.
  Future<List<String>> revalidateTag(String tag) async => <String>[
        for (final Object? key in (_map(await _send(
                    'POST', 'api/cache/tags/${_segment(tag)}/revalidate'))[
                'dropped'] as List?) ??
            const <Object?>[])
          '$key',
      ];

  /// The project graph the build wrote beside Studio: models, routes,
  /// functions and jobs, with the file each is declared in.
  Future<Map<String, Object?>> manifest() async =>
      _map(await _send('GET', 'api/graph'));
}

/// A page store kept on the server Studio is served by.
///
/// Saving is still publishing: the document is written to the server's
/// `dartvel_pages`, the table the local [DVPageStore] reads.
class DVStudioRemotePageStore extends DVPageStore {
  const DVStudioRemotePageStore(this.client);

  final DVStudioClient client;

  @override
  Future<void> save(DVPageDocument document) => client.savePage(document);

  /// Saves [document] over a version code changed, which [save] refuses.
  Future<void> saveOverCode(DVPageDocument document) =>
      client.savePage(document, force: true);

  @override
  Future<DVPageDocument?> load(String route) async {
    for (final DVPageDocument document in await client.pages()) {
      if (document.route == route) return document;
    }
    return null;
  }

  @override
  Future<List<String>> routes() async => <String>[
        for (final DVPageDocument document in await client.pages())
          document.route,
      ]..sort();

  @override
  Future<void> delete(String route) => client.deletePage(route);
}

/// The whole of Studio, as a web-server binary serves it.
class DVStudioApp extends StatefulWidget {
  const DVStudioApp({
    super.key,
    required this.client,
    this.title = 'Studio',
    this.mount,
    this.screen,
    this.object,
    this.location,
    this.open,
    this.onSelect,
  });

  final DVStudioClient client;
  final String title;

  /// The mount Studio is served at, `/__studio`, with no trailing slash.
  ///
  /// The address alone no longer says where the mount ends: `<mount>` and
  /// `<mount>/<screen>` and `<mount>/<screen>/<object>` are all Studio,
  /// and only the route knows which part of the path the mount is. Worked
  /// out from the address when the caller does not say, which is what a
  /// build served on its own under a directory has to do.
  final String? mount;

  /// The screen the address names. Null for a caller that keeps the
  /// selection in the app rather than in the address.
  final String? screen;

  /// What the address names inside [screen]: a page's route, a model's name,
  /// a function's.
  final String? object;

  /// The address the app was opened at; the browser's by default. At
  /// `<mount>/login` the app is Studio's sign-in.
  final Uri? location;

  /// Loads a path from the server as a page; a full navigation by default.
  final void Function(String path)? open;

  /// Called when the person chooses another screen or another object, so
  /// that the address can follow them.
  final void Function(String screen, String? object)? onSelect;

  @override
  State<DVStudioApp> createState() => _DVStudioAppState();
}

class _DVStudioAppState extends State<DVStudioApp> {
  Uri get _here => widget.location ?? Uri.base;

  bool get _signingIn =>
      _here.path.endsWith('/login') || _here.path.endsWith('/login/');

  /// The first-run setup, at `<mount>/setup`: the server serves it only while
  /// the setup is pending, and it carries no data, so it needs no session.
  bool get _settingUp =>
      _here.path.endsWith('/setup') || _here.path.endsWith('/setup/');

  /// The mount: the route's, or worked out from the address of its sign-in,
  /// its setup or a page, which is what a build served on its own has.
  /// `/__studio/login` and `/__studio/setup` are both `/__studio`.
  String get _mount => widget.mount ?? _mountFromAddress(_here.path);

  static String _mountFromAddress(String path) {
    for (final String page in const <String>[
      '/login',
      '/login/',
      '/setup',
      '/setup/',
    ]) {
      if (path.endsWith(page)) {
        return path.substring(0, path.length - page.length);
      }
    }
    if (path.endsWith('/index.html')) {
      return path.substring(0, path.length - '/index.html'.length);
    }
    if (path.endsWith('/index.html/')) {
      return path.substring(0, path.length - '/index.html/'.length);
    }
    if (path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  bool? _granted;

  @override
  void initState() {
    super.initState();
    if (_signingIn || _settingUp) {
      _granted = false;
    } else {
      _checkSession();
    }
  }

  @override
  void didUpdateWidget(DVStudioApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.location != widget.location) {
      if (_signingIn || _settingUp) {
        _granted = false;
      } else {
        _checkSession();
      }
    }
  }

  Future<void> _checkSession() async {
    final bool granted = await widget.client.access();
    if (mounted) {
      setState(() => _granted = granted);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The application Studio is a route of: its page views and its look,
    // so the canvas draws a page as the site does.
    final DVStudioHost? host = DVStudioHost.maybeOf(context);
    return DVStudioFrame(
      title: widget.title,
      home: _settingUp
          ? DVStudioFirstRunScreen(
              client: widget.client,
              mount: _mount,
              title: widget.title,
              open: widget.open ?? dvOpenUrl,
            )
          : _granted == null
          // The application's splash while the grant is asked, carrying
          // on from the one the route showed while the code loaded.
          ? (host?.splash == null
              ? const Scaffold(
                  backgroundColor: DVStudioStyle.canvas,
                  body: SizedBox.shrink(),
                )
              : DVStudioSplashView(host!.splash!))
          : (_granted == true
              ? Material(
                  child: DVStudioScreen(
                    store: DVStudioRemotePageStore(widget.client),
                    site: DVStudioSiteSource(
                      pages: widget.client.site,
                      structure: widget.client.structure,
                      view: host?.view,
                      look: host?.look,
                    ),
                    sections: dvStudioServerSections(widget.client),
                    account: DVStudioAccount(
                      client: widget.client,
                      mount: _mount,
                      open: widget.open ?? dvOpenUrl,
                    ),
                    selected: widget.screen,
                    object: widget.object,
                    onSelect: widget.onSelect,
                  ),
                )
              : DVStudioSignInScreen(
                  client: widget.client,
                  mount: _mount,
                  from: _here.queryParameters['from'] ??
                      (_signingIn ? null : _here.path),
                  title: widget.title,
                  open: widget.open ?? dvOpenUrl,
                )),
    );
  }
}

/// Who is signed in to Studio, and the control that signs them out: at the
/// foot of Studio's rail, always in sight.
///
/// Signing out ends the session on the server -- not only in this browser --
/// and then loads Studio's sign-in as a page, so nothing of Studio stays on
/// screen for whoever sits down next.
class DVStudioAccount extends StatefulWidget {
  const DVStudioAccount({
    super.key,
    required this.client,
    required this.mount,
    required this.open,
  });

  final DVStudioClient client;

  /// The admin mount, with no trailing slash.
  final String mount;

  /// Loads a path from the server as a page.
  final void Function(String path) open;

  @override
  State<DVStudioAccount> createState() => _DVStudioAccountState();
}

class _DVStudioAccountState extends State<DVStudioAccount> {
  String? _email;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.client.me().then((Map<String, Object?> me) {
      if (!mounted) return;
      final Object? email = me['email'] ?? me['userId'];
      setState(() => _email = email is String ? email : null);
    }, onError: (Object _) {});
  }

  Future<void> _signOut() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await widget.client.signOut();
    } on Object {
      // Away to the sign-in regardless: the server refuses Studio to a
      // session it no longer has, and one it still has is asked again there.
    }
    widget.open('${widget.mount}/login');
  }

  @override
  Widget build(BuildContext context) {
    final String who = _email ?? '';
    final String initial = who.isEmpty ? '?' : who.substring(0, 1).toUpperCase();
    return Semantics(
      container: true,
      label: who.isEmpty ? 'Signed in' : 'Signed in as $who',
      child: Container(
        key: const ValueKey<String>('dv-studio-account'),
        width: 72,
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Tooltip(
              message: who.isEmpty ? 'Signed in' : 'Signed in as $who',
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: DVStudioStyle.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(initial,
                    style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 4),
            if (who.isNotEmpty)
              Text(
                who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: DVStudioStyle.railInk),
              ),
            const SizedBox(height: 4),
            Semantics(
              button: true,
              label: 'Sign out',
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey<String>('dv-studio-sign-out'),
                behavior: HitTestBehavior.opaque,
                onTap: _leaving ? null : _signOut,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.logout, size: 18, color: DVStudioStyle.railInk),
                        const SizedBox(height: 2),
                        Text(_leaving ? 'Signing out' : 'Sign out',
                            style: const TextStyle(
                                fontSize: 11, color: DVStudioStyle.railInk)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The functions built in Studio, kept on the server that served it.
///
/// The builder runs in a browser, which has no database of its own, and a
/// function belongs to the project rather than to the browser that built it.
class DVStudioRemoteFunctionStore implements DVFunctionStore {
  const DVStudioRemoteFunctionStore(this.client);

  final DVStudioClient client;

  Future<List<DVWorkflowDocument>> _all() async => <DVWorkflowDocument>[
        for (final Map<String, Object?> row in await client.functions())
          if (row['document'] is Map)
            DVWorkflowDocument.fromJson(
                (row['document']! as Map).cast<String, Object?>()),
      ];

  @override
  Future<List<String>> names({DVWorkflowSide? side}) async => <String>[
        for (final DVWorkflowDocument document in await _all())
          if (side == null || document.side == side) document.name,
      ]..sort();

  @override
  Future<DVWorkflowDocument?> load(String name) async {
    for (final DVWorkflowDocument document in await _all()) {
      if (document.name == name) return document;
    }
    return null;
  }

  @override
  Future<void> save(DVWorkflowDocument document) =>
      client.saveFunction(document.toJson());

  @override
  Future<void> delete(String name) => client.deleteFunction(name);
}

/// The sections Studio has on a server, named for someone who has never
/// written code: the app's data, its site map, its backend logic, background
/// tasks and their queue, the modules it mounts, the cache, and the team who
/// may open Studio.
List<DVStudioSection> dvStudioServerSections(DVStudioClient client) =>
    <DVStudioSection>[
      dvStudioDataSection(client),
      dvStudioSiteMapSection(client),
      // The builders, not a list: a page is of little use if a button
      // cannot be made to do anything. A backend function written in code
      // is in the site map's own listing.
      ...dvFunctionStudioSections(
        store: DVStudioRemoteFunctionStore(client),
        written: () async {
          final Map<String, Object?> graph = await client.manifest();
          return <Map<String, Object?>>[
            for (final Object? entry
                in (graph['functions'] as List?) ?? const <Object?>[])
              if (entry is Map) entry.cast<String, Object?>(),
          ];
        },
      ),
      DVStudioSection.opening(
        id: 'modules',
        label: 'Modules',
        icon: Icons.extension_outlined,
        build: (BuildContext context, DVStudioSelection selection) =>
            DVStudioModulesSection(
          manifest: client.manifest,
          module: selection.object,
          onSelect: (String id) => selection.select?.call(id),
        ),
      ),
      DVStudioSection.opening(
        id: 'jobs',
        label: 'Tasks',
        icon: Icons.work_history_outlined,
        build: (BuildContext context, DVStudioSelection selection) =>
            _DVStudioManifestSection(
          client: client,
          kind: 'jobs',
          name: 'job',
          title: 'Background tasks',
          columns: const <List<String>>[
            <String>['name', 'Task'],
            <String>['queue', 'Queue'],
            <String>['source', 'File'],
          ],
          object: selection.object,
          onSelect: (String name) => selection.select?.call(name),
        ),
      ),
      DVStudioSection.opening(
        id: 'queues',
        label: 'Queue',
        icon: Icons.inbox_outlined,
        build: (BuildContext context, DVStudioSelection selection) =>
            _DVStudioQueuesSection(
          client: client,
          queue: selection.object,
          onSelect: (String name) => selection.select?.call(name),
        ),
      ),
      DVStudioSection(
        id: 'cache',
        label: 'Cache',
        icon: Icons.bolt_outlined,
        build: (BuildContext context) => _DVStudioCacheSection(client: client),
      ),
      DVStudioSection(
        id: 'repository',
        label: 'GitHub',
        icon: Icons.cloud_upload_outlined,
        build: (BuildContext context) =>
            DVStudioRepositorySection(client: client),
      ),
      DVStudioSection(
        id: 'access',
        label: 'Team',
        icon: Icons.admin_panel_settings_outlined,
        build: (BuildContext context) => _DVStudioAccessSection(client: client),
      ),
    ];

/// Data: every data model, compiled or designed in Studio, its records, and
/// the designer that makes and changes one.
DVStudioSection dvStudioDataSection(DVStudioClient client) =>
    DVStudioSection.opening(
      id: 'models',
      label: 'Data',
      icon: Icons.table_chart_outlined,
      build: (BuildContext context, DVStudioSelection selection) =>
          DVStudioModelsSection(
        client: client,
        model: selection.object?.split('/').first,
        record: selection.object?.contains('/') == true
            ? selection.object!.substring(selection.object!.indexOf('/') + 1)
            : null,
        onSelect: (String model) => selection.select?.call(model),
      ),
    );

/// Site map: every route the site answers, compiled and stored -- the list
/// Pages opens them from.
DVStudioSection dvStudioSiteMapSection(DVStudioClient client) =>
    DVStudioSection(
      id: 'routes',
      label: 'Site map',
      icon: Icons.alt_route,
      build: (BuildContext context) => _DVStudioSiteMapSection(client: client),
    );

/// A transport that answers from a [core.DVStudioApi] in this process: the
/// Studio an application carries inside itself, on a phone, a desktop, a TV
/// or the web, reading and writing its own database through the same API a
/// server answers Studio with.
DVStudioTransport dvStudioInProcessTransport(core.DVStudioApi api) {
  const String csrf = 'in-process-studio-request';
  return (String method, String path, {Object? body}) async {
    final Uri uri = Uri.parse('http://studio.invalid/$path');
    if (!uri.path.startsWith('/api/')) {
      return const DVStudioReply(404, <String, Object?>{
        'error': 'not_found',
        'message': 'This Studio runs inside the application, which has no '
            'build manifest beside it.',
      });
    }
    final core.Response response = await api.respond(
      core.Request(
        method: method,
        url: uri,
        headers: core.Headers(<String, String>{
          'x-dartvel-csrf-token': csrf,
          if (body != null) 'content-type': 'application/json',
        }),
        bodyStream: body == null
            ? const Stream<List<int>>.empty()
            : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      ),
      uri.path.substring('/api/'.length),
    );
    final List<int> bytes = await response.body?.bytes() ?? const <int>[];
    Object? decoded;
    try {
      decoded = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on FormatException {
      decoded = null;
    }
    return DVStudioReply(response.status, decoded);
  };
}

/// Studio inside the application it manages, on whatever it runs on.
///
/// `dartvel admin generate` opens this behind the `viewAdmin` policy. The
/// pages are the application's own: [routes] is the generated route
/// manifest, so every compiled page is listed and a page added later is
/// listed the next build, and [preview] draws a compiled page as its route
/// draws it. The data models are [models], the generated specs, with any
/// model designed in Studio beside them. Both are read through
/// [core.DVStudioApi] in this process over `DV.Database`, the same API and
/// the same merge a server answers Studio with -- only where things are
/// stored differs.
class DVStudioInApp extends StatelessWidget {
  const DVStudioInApp({
    super.key,
    this.routes = const <DVRouteInfo>[],
    this.models = const <core.DVStudioModelSpec>[],
    this.store = const DVPageStore(),
    this.preview,
  });

  /// The generated route manifest, `dartvelRouteManifest`.
  final List<DVRouteInfo> routes;

  /// The generated model specs, `dartvelStudioModels`.
  final List<core.DVStudioModelSpec> models;

  /// Where page documents are read from and published to.
  final DVPageStore store;

  /// A compiled page as its route builds it, `dartvelPagePreview`.
  final Widget? Function(String path)? preview;

  @override
  Widget build(BuildContext context) {
    final core.DVStudioApi api = core.DVStudioApi(
      models: models,
      // Null when the application configured none: Pages still lists every
      // compiled route, and Data says there is nothing to read.
      database: const core.DVDatabase().configuredAdapter,
      compiledRoutes: () => <Map<String, Object?>>[
        for (final DVRouteInfo route in routes)
          if (route.isLocal) dvStudioRouteInfoJson(route),
      ],
    );
    final DVStudioClient client =
        DVStudioClient(dvStudioInProcessTransport(api));
    return DVStudioScreen(
      store: store,
      site: DVStudioSiteSource(
        pages: client.site,
        structure: client.structure,
        preview: preview,
        // Studio here is a page of the application, so the look in force
        // is the application's.
        look: DVStudioAppLook.capture(context),
      ),
      sections: <DVStudioSection>[
        dvStudioDataSection(client),
        dvStudioSiteMapSection(client),
      ],
    );
  }
}

/// Something loaded from the server, drawn when it arrives.
Widget _loading<T>(
  Future<T> future,
  Widget Function(T value) build, {
  String waiting = 'Loading…',
}) {
  return FutureBuilder<T>(
    future: future,
    builder: (BuildContext context, AsyncSnapshot<T> snapshot) {
      if (snapshot.hasError) {
        return DVStudioStyle.emptyState(
          icon: Icons.cloud_off_outlined,
          title: 'The server did not answer',
          message: '${snapshot.error}',
        );
      }
      if (!snapshot.hasData) return DVStudioStyle.placeholder(waiting);
      return build(snapshot.data as T);
    },
  );
}

/// A cell's text: a value as the table shows it.
/// `joinedAt` → `Joined at`: a field as someone editing the record reads it.
String _fieldLabel(String name) {
  if (name.isEmpty) return name;
  final String spaced = name.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (Match m) => '${m[1]} ${(m[2] ?? '').toLowerCase()}',
  );
  return spaced[0].toUpperCase() + spaced.substring(1);
}

String _cell(Object? value) => value == null ? '—' : '$value';

/// A field's value as the table shows it: a moment as a date, whether the
/// model keeps it as a `DateTime` or, as most do, as epoch milliseconds in an
/// `int` named for a moment.
String _cellText(DVStudioField field, Object? value) {
  if (value is List || value is Map) return jsonEncode(value);
  final DateTime? moment = _moment(field, value);
  return moment == null ? _cell(value) : _formatMoment(moment);
}

/// The moment [value] holds, or null when [field] is not one.
DateTime? _moment(DVStudioField field, Object? value) {
  if (value == null) return null;
  if (field.baseType == 'DateTime') {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return DateTime.tryParse('$value')?.toUtc();
  }
  if (field.baseType != 'int' && field.baseType != 'num') return null;
  // By name as well as size: a price in cents is never 13 digits, but a
  // counter could be, and one named for a moment is the model saying so.
  if (!_momentName.hasMatch(field.name)) return null;
  final num? number = value is num ? value : num.tryParse('$value');
  // Milliseconds between 1973 and 5138.
  if (number == null || number < 1e11 || number > 1e14) return null;
  return DateTime.fromMillisecondsSinceEpoch(number.toInt(), isUtc: true);
}

final RegExp _momentName =
    RegExp(r'(At|On|Date|Time|Timestamp)$|^(date|time|timestamp)$');

/// `2026-09-17 13:00 UTC`.
String _formatMoment(DateTime moment) {
  final DateTime utc = moment.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)} UTC';
}

/// A plain table in Studio's style.
class _DVStudioTable extends StatelessWidget {
  const _DVStudioTable({
    required this.headers,
    required this.rows,
    this.rowKeys,
    this.onTap,
    this.selected,
    this.trailing,
  });

  final List<String> headers;
  final List<List<String>> rows;

  /// A widget at the end of each row, such as the row's action.
  final List<Widget>? trailing;

  static const double trailingWidth = 40;
  final List<Key>? rowKeys;
  final void Function(int index)? onTap;
  final int? selected;

  /// The narrowest a column is drawn. Below it the table scrolls sideways
  /// rather than squeezing a heading until it breaks mid-word.
  static const double minColumnWidth = 112;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double needed = headers.length * minColumnWidth;
        if (!box.maxWidth.isFinite || box.maxWidth >= needed) {
          return _table();
        }
        return _DVStudioSidewaysScroll(
          child: SizedBox(width: needed, child: _table()),
        );
      },
    );
  }

  Widget _table() {
    Widget cell(String text, {bool header = false}) => Padding(
          padding: const .symmetric(
              horizontal: DVStudioStyle.space3, vertical: 9),
          // One line, both kinds: a heading that wraps breaks a word in two.
          child: Text(
            header ? text.toUpperCase() : text,
            maxLines: 1,
            softWrap: false,
            overflow: .ellipsis,
            style: header
                ? const TextStyle(
                    fontSize: 11,
                    color: DVStudioStyle.muted,
                    fontWeight: .w600,
                  )
                : const TextStyle(fontSize: 13, color: DVStudioStyle.ink),
          ),
        );
    return DVStudioStyle.card(
      padding: .zero,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              color: DVStudioStyle.canvas,
              border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
            ),
            child: Row(children: <Widget>[
              for (final String header in headers)
                Expanded(child: cell(header, header: true)),
              // The trailing column is a fixed width in the header and the
              // rows alike, so the headings sit over their cells.
              if (trailing != null)
                const SizedBox(width: trailingWidth + DVStudioStyle.space2),
            ]),
          ),
          for (int i = 0; i < rows.length; i++)
            MouseRegion(
              cursor: onTap == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: GestureDetector(
                key: rowKeys?[i],
                behavior: .opaque,
                onTap: onTap == null ? null : () => onTap!(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected == i ? DVStudioStyle.selected : null,
                    border: i == rows.length - 1
                        ? null
                        : const Border(
                            bottom: BorderSide(color: DVStudioStyle.line)),
                  ),
                  child: Row(children: <Widget>[
                    for (final String value in rows[i])
                      Expanded(child: cell(value)),
                    if (trailing != null)
                      Padding(
                        padding: const .only(
                            right: DVStudioStyle.space2),
                        child: SizedBox(
                          width: trailingWidth,
                          child: Center(child: trailing![i]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Every model the backend declares, a model's records, and a record's form.
class DVStudioModelsSection extends StatefulWidget {
  const DVStudioModelsSection({
    super.key,
    required this.client,
    this.model,
    this.onSelect,
    this.record,
  });

  final DVStudioClient client;

  /// The model the address names, opened once the catalog is read: a model
  /// cannot be found before the list of them is known.
  final String? model;

  /// The record named by a deep link, opened after its model is loaded.
  final String? record;

  /// Called with the model a person chose, so the address can follow.
  final void Function(String model)? onSelect;

  @override
  State<DVStudioModelsSection> createState() => _DVStudioModelsSectionState();
}

class _DVStudioModelsSectionState extends State<DVStudioModelsSection> {
  List<DVStudioModel>? _models;
  DVStudioModel? _model;
  List<DVStudioRecordData>? _records;
  Object? _error;

  /// Whether a model designed here can also be written to the project's
  /// source: only on a development server.
  bool _sourceWritable = false;

  /// The designer is open: on [_model], or on a new model when that is
  /// null.
  bool _designing = false;

  /// The record open in the form, or null. A record with an empty key is a
  /// new one.
  DVStudioRecordData? _editing;

  @override
  void initState() {
    super.initState();
    unawaited(_loadModels(select: widget.model));
  }

  @override
  void didUpdateWidget(DVStudioModelsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The address moved to another model. Read again rather than opening
    // from the list already held: a model published since this section was
    // built is not in it, and the address is not the thing to argue with.
    if (widget.model != oldWidget.model || widget.record != oldWidget.record) {
      unawaited(_loadModels(select: widget.model));
    }
  }

  /// [select] is the model to open once the catalog is read: named by the
  /// address, or the one already open. A name the catalog does not have
  /// falls back to the first model there is, which is what a person who
  /// asked for a model this project does not have is shown.
  Future<void> _loadModels({String? select}) async {
    try {
      final ({List<DVStudioModel> models, bool sourceWritable}) catalog =
          await widget.client.modelCatalog();
      if (!mounted) return;
      final List<DVStudioModel> models = catalog.models;
      setState(() {
        _models = models;
        _sourceWritable = catalog.sourceWritable;
      });
      final DVStudioModel? chosen = models
              .where((DVStudioModel m) => m.model == (select ?? _model?.model))
              .firstOrNull ??
          (select == null ? models.firstOrNull : null);
      if (chosen == null && select != null) {
        setState(() {
          _model = null;
          _editing = null;
          _error = 'Data model not found.';
        });
      }
      if (chosen != null) await _open(chosen);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _design({required bool fresh}) => setState(() {
        _designing = true;
        _phoneDetail = true;
        _editing = null;
        if (fresh) _model = null;
      });

  Future<void> _open(DVStudioModel model, {bool userChose = false}) async {
    if (userChose) widget.onSelect?.call(model.model);
    setState(() {
      _model = model;
      _records = null;
      _editing = null;
      _error = null;
      _designing = false;
      _query = '';
    });
    if (userChose) setState(() => _phoneDetail = true);
    try {
      final List<DVStudioRecordData> records =
          await widget.client.records(model.model);
      if (mounted && _model == model) {
        setState(() {
          _records = records;
          _editing = records.where((r) => r.key == widget.record).firstOrNull;
          if (widget.model != null) _phoneDetail = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DVStudioModel>? models = _models;
    if (models == null) {
      return _error == null
          ? DVStudioStyle.placeholder('Loading models…')
          : DVStudioStyle.emptyState(
              icon: Icons.cloud_off_outlined,
              title: 'The server did not answer',
              message: '$_error',
            );
    }
    if (models.isEmpty && !_designing) {
      return Column(
        mainAxisAlignment: .center,
        children: <Widget>[
          DVStudioStyle.emptyState(
            icon: Icons.table_chart_outlined,
            title: 'No data models yet',
            message: 'A data model is a kind of record: articles, products, '
                'bookings. Make one here, with its fields and rules, and add '
                'records to it straight away.',
          ),
          const SizedBox(height: DVStudioStyle.space4),
          DVStudioControl(
            key: const ValueKey<String>('dv-studio-model-new'),
            label: 'New data model',
            enabled: true,
            onTap: () => _design(fresh: true),
            primary: true,
            icon: Icons.add,
          ),
        ],
      );
    }
    final Widget list = Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
            title: 'Data',
            subtitle: '${models.length}',
            actions: <Widget>[
              DVStudioIconButton(
                key: const ValueKey<String>('dv-studio-model-new'),
                icon: Icons.add,
                tooltip: 'New data model',
                onTap: () => _design(fresh: true),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          for (final DVStudioModel model in models)
            DVStudioListRow(
              key: ValueKey<String>('dv-studio-model-${model.model}'),
              title: model.model,
              subtitle: model.module == null
                  ? '${model.visibleFields.length} fields'
                  : '${model.module} module · '
                      '${model.visibleFields.length} fields',
              icon: Icons.table_rows_outlined,
              selected: model == _model && !(_designing && _model == null),
              trailing: DVStudioStyle.badge(
                model.designed ? 'Studio' : 'Code',
                tone: model.designed
                    ? DVStudioStyle.success
                    : DVStudioStyle.muted,
              ),
              onTap: () => unawaited(_open(model, userChose: true)),
            ),
        ],
      );
    final Widget detail = _designing
          ? _DVStudioModelDesigner(
              key: ValueKey<String>('dv-studio-designer-${_model?.model}'),
              client: widget.client,
              model: _model,
              models: models,
              sourceWritable: _sourceWritable,
              onClose: () => setState(() => _designing = false),
              onSaved: (DVStudioModel saved) =>
                  unawaited(_loadModels(select: saved.model)),
              onDeleted: (String name) {
                setState(() => _model = null);
                unawaited(_loadModels());
              },
            )
          : _detail();
    // On a phone the list beside the records left them a strip too narrow
    // to read, so the section shows one at a time: the models, then the one
    // chosen, with the way back above it.
    final bool phone =
        (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < dvStudioPhoneWidth;
    if (phone) {
      if (!_phoneDetail) return SingleChildScrollView(child: list);
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioListRow(
            key: const ValueKey<String>('dv-studio-models-back'),
            title: 'All data models',
            icon: Icons.arrow_back,
            onTap: () => setState(() {
              _phoneDetail = false;
              _designing = false;
            }),
          ),
          Expanded(child: detail),
        ],
      );
    }
    return DVStudioStyle.panes(listWidth: 220, list: list, detail: detail);
  }

  /// On a phone, whether the chosen model is on screen rather than the list.
  bool _phoneDetail = false;

  /// What the records are searched for.
  String _query = '';

  Widget _detail() {
    final DVStudioModel? model = _model;
    if (model == null) {
      return DVStudioStyle.placeholder(_error?.toString() ?? 'Choose a model.');
    }
    final List<DVStudioRecordData>? records = _records;
    final DVStudioRecordData? editing = _editing;
    final List<DVStudioField> fields = model.visibleFields;
    final bool phone =
        (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < dvStudioPhoneWidth;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (widget.record != null && records != null && editing == null)
          DVStudioStyle.body('Record not found.'),
        DVStudioStyle.panelHeader(
          title: model.model,
          subtitle: records == null
              ? null
              : records.length == 1
                  ? '1 record'
                  : '${records.length} records',
          actions: <Widget>[
            DVStudioControl(
              key: const ValueKey<String>('dv-studio-model-design'),
              label: model.designed ? 'Design' : 'Fields',
              enabled: true,
              onTap: () => _design(fresh: false),
              icon: Icons.schema_outlined,
            ),
            const SizedBox(width: DVStudioStyle.space2),
            DVStudioControl(
              key: const ValueKey<String>('dv-studio-record-new'),
              label: 'New record',
              enabled: true,
              onTap: () => setState(() => _editing = const DVStudioRecordData(
                  key: '', version: 0, values: <String, Object?>{})),
              primary: true,
              icon: Icons.add,
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              // On a phone the form takes the width the table had.
              if (editing == null || !phone)
              Expanded(
                child: records == null
                    ? (_error == null
                        ? DVStudioStyle.placeholder('Loading records…')
                        : DVStudioStyle.emptyState(
                            icon: Icons.error_outline,
                            title: 'Records could not be read',
                            message: '$_error',
                          ))
                    : records.isEmpty
                        ? DVStudioStyle.emptyState(
                            icon: Icons.inbox_outlined,
                            title: 'No ${model.model} records yet',
                            message: 'New record adds the first one.',
                          )
                        : SingleChildScrollView(
                            padding: const .all(DVStudioStyle.space5),
                            child: Builder(builder: (BuildContext context) {
                              // The records any of whose values contain what
                              // is typed in the search, as the table shows
                              // them.
                              final String query = _query.trim().toLowerCase();
                              final List<DVStudioRecordData> shown =
                                  <DVStudioRecordData>[
                                for (final DVStudioRecordData record in records)
                                  if (query.isEmpty ||
                                      fields.any((DVStudioField f) =>
                                          _cellText(f, record.values[f.name])
                                              .toLowerCase()
                                              .contains(query)))
                                    record,
                              ];
                              return Column(
                                crossAxisAlignment: .stretch,
                                children: <Widget>[
                                  if (records.length > 1) ...<Widget>[
                                    DVStudioTextInput(
                                      key: const ValueKey<String>(
                                          'dv-studio-records-search'),
                                      value: _query,
                                      placeholder:
                                          'Search ${records.length} records',
                                      icon: Icons.search,
                                      onChanged: (String value) =>
                                          setState(() => _query = value),
                                    ),
                                    const SizedBox(height: DVStudioStyle.space3),
                                  ],
                                  _DVStudioTable(
                                    headers: <String>[
                                      for (final DVStudioField f in fields)
                                        _fieldLabel(f.name),
                                    ],
                                    rows: <List<String>>[
                                      for (final DVStudioRecordData record
                                          in shown)
                                        <String>[
                                          for (final DVStudioField f in fields)
                                            _cellText(f, record.values[f.name]),
                                        ],
                                    ],
                                    rowKeys: <Key>[
                                      for (final DVStudioRecordData record
                                          in shown)
                                        ValueKey<String>(
                                            'dv-studio-record-${record.key}'),
                                    ],
                                    selected: editing == null
                                        ? null
                                        : shown.indexWhere(
                                            (DVStudioRecordData r) =>
                                                r.key == editing.key),
                                    onTap: (int index) {
                                      setState(() => _editing = shown[index]);
                                      widget.onSelect?.call(
                                          '${model.model}/${shown[index].key}');
                                    },
                                  ),
                                ],
                              );
                            }),
                          ),
              ),
              if (editing != null)
                Container(
                  width: phone ? MediaQuery.sizeOf(context).width : 360,
                  decoration: const BoxDecoration(
                    color: DVStudioStyle.surface,
                    border:
                        Border(left: BorderSide(color: DVStudioStyle.line)),
                  ),
                  child: _DVStudioRecordForm(
                    key: ValueKey<String>(
                        'dv-studio-form-${model.model}-${editing.key}-${editing.version}'),
                    client: widget.client,
                    model: model,
                    record: editing,
                    onClose: () {
                      setState(() => _editing = null);
                      widget.onSelect?.call(model.model);
                    },
                    onSaved: (DVStudioRecordData saved) {
                      setState(() {
                        final List<DVStudioRecordData> next =
                            <DVStudioRecordData>[...?_records];
                        final int at = next.indexWhere(
                            (DVStudioRecordData r) => r.key == saved.key);
                        if (at == -1) {
                          next.add(saved);
                        } else {
                          next[at] = saved;
                        }
                        _records = next;
                        _editing = saved;
                      });
                      widget.onSelect?.call('${model.model}/${saved.key}');
                    },
                    onDeleted: (String key) {
                      setState(() {
                      _records = <DVStudioRecordData>[
                        for (final DVStudioRecordData r in _records ?? const <DVStudioRecordData>[])
                          if (r.key != key) r,
                      ];
                      _editing = null;
                      });
                      widget.onSelect?.call(model.model);
                    },
                    onReload: () => unawaited(_open(model)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The form for one record: a control per field the backend can store.
class _DVStudioRecordForm extends StatefulWidget {
  const _DVStudioRecordForm({
    super.key,
    required this.client,
    required this.model,
    required this.record,
    required this.onClose,
    required this.onSaved,
    required this.onDeleted,
    required this.onReload,
  });

  final DVStudioClient client;
  final DVStudioModel model;
  final DVStudioRecordData record;
  final VoidCallback onClose;
  final ValueChanged<DVStudioRecordData> onSaved;
  final ValueChanged<String> onDeleted;
  final VoidCallback onReload;

  @override
  State<_DVStudioRecordForm> createState() => _DVStudioRecordFormState();
}

class _DVStudioRecordFormState extends State<_DVStudioRecordForm> {
  /// What the form holds, as typed: text for a text control, a bool for a
  /// switch, JSON text for a list or map, a value for a choice.
  late final Map<String, Object?> _draft = <String, Object?>{
    for (final DVStudioField field in widget.model.formFields)
      // A write-only field starts empty whatever the record holds.
      field.name: field.writeOnly
          ? ''
          : _initial(field, widget.record.values[field.name]),
  };

  /// The nullable fields set to empty, whatever their control holds.
  late final Set<String> _empty = <String>{
    if (!_isNew)
      for (final DVStudioField field in widget.model.visibleFields)
        if (field.nullable &&
            field.baseType != 'bool' &&
            widget.record.values.containsKey(field.name) &&
            widget.record.values[field.name] == null)
          field.name,
  };

  bool _saving = false;
  String? _error;
  bool _conflict = false;

  bool get _isNew => widget.record.key.isEmpty;

  static Object? _initial(DVStudioField field, Object? value) {
    if (field.baseType == 'bool') return value == true;
    if (value == null) return field.isCollection ? '' : null;
    if (field.isCollection) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return '$value';
  }

  /// The draft as values the backend stores, only for fields that changed
  /// -- or every filled field, for a new record.
  Map<String, Object?> _changes() {
    final Map<String, Object?> changes = <String, Object?>{};
    for (final DVStudioField field in widget.model.formFields) {
      if (field.writeOnly) {
        // Sent only when something was typed: empty keeps what is stored.
        final String typed = '${_draft[field.name] ?? ''}';
        if (typed.isNotEmpty) changes[field.name] = typed;
        continue;
      }
      if (!field.editable) continue;
      if (!_isNew && field.name == widget.model.key) continue;
      final Object? typed = _typed(field, _draft[field.name]);
      final Object? before = widget.record.values[field.name];
      if (_isNew) {
        if (typed != null) changes[field.name] = typed;
      } else if (jsonEncode(typed) != jsonEncode(before) &&
          '$typed' != '$before') {
        changes[field.name] = typed;
      }
    }
    return changes;
  }

  Object? _typed(DVStudioField field, Object? draft) {
    if (_empty.contains(field.name)) return null;
    if (field.baseType == 'bool') return draft == true;
    final String text = '${draft ?? ''}'.trim();
    if (field.isCollection) {
      if (text.isEmpty) return field.nullable ? null : (field.baseType.startsWith('Map') ? <String, Object?>{} : <Object?>[]);
      try {
        return jsonDecode(text);
      } on FormatException {
        throw _DVStudioFormProblem('${field.name} is not valid JSON.');
      }
    }
    if (text.isEmpty) return field.baseType == 'String' && !field.nullable ? '' : null;
    switch (field.baseType) {
      case 'int':
        return int.tryParse(text) ?? text;
      case 'double':
      case 'num':
        return num.tryParse(text) ?? text;
    }
    return '${draft ?? ''}';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _conflict = false;
    });
    try {
      final DVStudioRecordData saved = _isNew
          ? await widget.client.create(widget.model.model, _changes())
          : await widget.client
              .update(widget.model.model, widget.record, _changes());
      widget.onSaved(saved);
    } on _DVStudioFormProblem catch (problem) {
      // Caught before anything is sent: a value the form cannot read is not
      // the server's to refuse.
      if (mounted) setState(() => _error = problem.message);
    } on DVStudioRemoteError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _conflict = error.status == 409;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    try {
      await widget.client.delete(widget.model.model, widget.record);
      widget.onDeleted(widget.record.key);
    } on DVStudioRemoteError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _conflict = error.status == 409;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: _isNew ? 'New ${widget.model.model}' : widget.record.key,
          subtitle: _isNew ? null : 'version ${widget.record.version}',
          actions: <Widget>[
            DVStudioIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: widget.onClose,
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const .all(DVStudioStyle.space4),
            children: <Widget>[
              for (final DVStudioField field in widget.model.formFields)
                Padding(
                  padding: const .only(bottom: DVStudioStyle.space3),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: DVStudioStyle.overline(_fieldLabel(field.name))),
                        if (field.nullable &&
                            field.editable &&
                            field.baseType != 'bool' &&
                            !(!_isNew && field.name == widget.model.key)) ...<Widget>[
                          GestureDetector(
                            key: ValueKey<String>(
                                'dv-studio-field-${field.name}-empty'),
                            onTap: () => setState(() {
                              if (!_empty.remove(field.name)) {
                                _empty.add(field.name);
                              }
                            }),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Row(children: <Widget>[
                                Icon(
                                  _empty.contains(field.name)
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 14,
                                  color: _empty.contains(field.name)
                                      ? DVStudioStyle.accent
                                      : DVStudioStyle.faint,
                                ),
                                const SizedBox(width: 3),
                                DVStudioStyle.caption('Empty',
                                    color: DVStudioStyle.muted),
                              ]),
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                        ],
                        Flexible(
                          child: Text(
                            // What the field holds, as the designer names it:
                            // Text, Whole number, Choice. A person who never
                            // wrote a type reads "String?" as a typo.
                            _dvStudioFieldCaption(field),
                            maxLines: 1,
                            softWrap: false,
                            overflow: .ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: DVStudioStyle.faint),
                          ),
                        ),
                      ]),
                      const SizedBox(height: DVStudioStyle.space1),
                      _control(field),
                    ],
                  ),
                ),
              if (widget.model.fields
                  .any((DVStudioField f) => f.sensitive && !f.writeOnly))
                DVStudioStyle.caption(
                  'Some sensitive fields are not shown or written here.',
                  color: DVStudioStyle.faint,
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DVStudioStyle.space3),
                DVStudioStyle.body(_error!, color: DVStudioStyle.danger),
                if (_conflict)
                  Padding(
                    padding: const .only(top: DVStudioStyle.space2),
                    child: DVStudioControl(
                      label: 'Reload records',
                      enabled: true,
                      onTap: widget.onReload,
                      icon: Icons.refresh,
                    ),
                  ),
              ],
            ],
          ),
        ),
        Container(
          padding: const .all(DVStudioStyle.space3),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              if (!_isNew)
                DVStudioControl(
                  key: const ValueKey<String>('dv-studio-record-delete'),
                  label: 'Delete',
                  enabled: true,
                  onTap: () => unawaited(_delete()),
                  icon: Icons.delete_outline,
                ),
              const Spacer(),
              DVStudioControl(
                key: const ValueKey<String>('dv-studio-record-save'),
                label: _saving ? 'Saving…' : (_isNew ? 'Create' : 'Save'),
                enabled: !_saving,
                onTap: _saving ? null : () => unawaited(_save()),
                primary: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _control(DVStudioField field) {
    final Key key = ValueKey<String>('dv-studio-field-${field.name}');
    if (field.writeOnly) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          KeyedSubtree(
            key: key,
            child: DVStudioTextInput(
              obscureText: true,
              onChanged: (String value) => _draft[field.name] = value,
            ),
          ),
          if (!_isNew) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioStyle.caption('Leave empty to keep the current value',
                color: DVStudioStyle.faint),
          ],
        ],
      );
    }
    final bool locked =
        !field.editable || (!_isNew && field.name == widget.model.key);
    if (!locked && _empty.contains(field.name)) {
      return _readOnly(key, 'empty');
    }
    if (field.baseType == 'bool' && !locked) {
      return Align(
        alignment: .centerLeft,
        child: Switch(
          key: key,
          value: _draft[field.name] == true,
          activeThumbColor: DVStudioStyle.accent,
          onChanged: (bool value) =>
              setState(() => _draft[field.name] = value),
        ),
      );
    }
    if (locked) {
      return _readOnly(
          key, _cellText(field, widget.record.values[field.name]));
    }
    final List<String>? options = field.options;
    if (options != null) {
      return _DVStudioSelect(
        key: key,
        value: _draft[field.name] as String?,
        options: options,
        onChanged: (String value) =>
            setState(() => _draft[field.name] = value),
      );
    }
    final String? relation = field.relation;
    if (relation != null) {
      return _DVStudioRelationSelect(
        key: key,
        client: widget.client,
        model: widget.model.module == null
            ? relation
            : '${widget.model.module}.$relation',
        fallbackModel: relation,
        value: _draft[field.name] as String?,
        onChanged: (String value) =>
            setState(() => _draft[field.name] = value),
      );
    }
    if (field.isCollection) {
      return KeyedSubtree(
        key: key,
        child: TextFormField(
          initialValue: '${_draft[field.name] ?? ''}',
          minLines: 3,
          maxLines: 10,
          style: const TextStyle(
              fontSize: 12, fontFamily: 'monospace', color: DVStudioStyle.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: field.baseType.startsWith('Map') ? '{ }' : '[ ]',
            contentPadding: const .all(10),
            border: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radiusSmall),
              borderSide: const BorderSide(color: DVStudioStyle.lineStrong),
            ),
          ),
          onChanged: (String value) => _draft[field.name] = value,
        ),
      );
    }
    return KeyedSubtree(
      key: key,
      child: DVStudioTextInput(
        value: '${_draft[field.name] ?? ''}',
        placeholder: field.baseType == 'DateTime'
            ? '2026-09-17T10:00:00Z'
            : field.nullable
                ? 'empty'
                : null,
        onChanged: (String value) => _draft[field.name] = value,
      ),
    );
  }

  Widget _readOnly(Key key, String text) => Container(
        key: key,
        height: 32,
        alignment: .centerLeft,
        padding: const .symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: DVStudioStyle.canvas,
          border: Border.all(color: DVStudioStyle.line),
          borderRadius: .circular(DVStudioStyle.radiusSmall),
        ),
        child: DVStudioStyle.body(text, color: DVStudioStyle.muted),
      );
}

/// What [field] holds, in the words the designer offers it in, and
/// whether it may be left empty.
String _dvStudioFieldCaption(DVStudioField field) {
  final String kind = field.options != null
      ? 'Choice'
      : field.relation != null
          ? 'Refers to ${field.relation}'
          : _dvStudioKindLabel(field.baseType);
  return field.nullable ? '$kind, optional' : kind;
}

/// A value the form could not turn into what the field holds.
class _DVStudioFormProblem implements Exception {
  const _DVStudioFormProblem(this.message);

  final String message;
}

/// A value chosen from a list, in a menu.
class _DVStudioSelect extends StatelessWidget {
  const _DVStudioSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = 'Choose…',
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String placeholder;

  Future<void> _open(BuildContext context) async {
    final RenderObject? box = context.findRenderObject();
    final OverlayState? overlay = Overlay.maybeOf(context);
    final RenderObject? overlayBox = overlay?.context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox) return;
    final Offset origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final String? picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        origin & box.size,
        Offset.zero & overlayBox.size,
      ),
      items: <PopupMenuItem<String>>[
        for (final String option in options)
          PopupMenuItem<String>(value: option, child: Text(option)),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(_open(context)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 32,
          padding: const .symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border.all(color: DVStudioStyle.lineStrong),
            borderRadius: .circular(DVStudioStyle.radiusSmall),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DVStudioStyle.body(
                  value ?? placeholder,
                  color: value == null ? DVStudioStyle.faint : DVStudioStyle.ink,
                ),
              ),
              const Icon(Icons.expand_more,
                  size: 16, color: DVStudioStyle.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A reference, chosen from the keys of the related model's records.
class _DVStudioRelationSelect extends StatefulWidget {
  const _DVStudioRelationSelect({
    super.key,
    required this.client,
    required this.model,
    required this.fallbackModel,
    required this.value,
    required this.onChanged,
  });

  final DVStudioClient client;

  /// The related model as a module's model names it, then as the
  /// application's.
  final String model;
  final String fallbackModel;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  State<_DVStudioRelationSelect> createState() =>
      _DVStudioRelationSelectState();
}

class _DVStudioRelationSelectState extends State<_DVStudioRelationSelect> {
  List<String>? _keys;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<DVStudioRecordData> records;
    try {
      records = await widget.client.records(widget.model);
    } on DVStudioRemoteError {
      try {
        records = await widget.client.records(widget.fallbackModel);
      } on DVStudioRemoteError {
        records = const <DVStudioRecordData>[];
      }
    }
    if (mounted) {
      setState(() => _keys = <String>[
            for (final DVStudioRecordData record in records) record.key,
          ]..sort());
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> keys = _keys ?? const <String>[];
    return _DVStudioSelect(
      value: widget.value,
      options: <String>[
        if (widget.value != null && !keys.contains(widget.value)) widget.value!,
        ...keys,
      ],
      placeholder: _keys == null ? 'Loading…' : 'Choose a ${widget.fallbackModel}',
      onChanged: widget.onChanged,
    );
  }
}

/// One kind of node from the build's project graph, as a table.
class _DVStudioManifestSection extends StatefulWidget {
  const _DVStudioManifestSection({
    required this.client,
    required this.kind,
    required this.name,
    required this.title,
    required this.columns,
    this.object,
    this.onSelect,
  });

  final DVStudioClient client;
  final String kind;
  final String title;

  /// What a row of this screen is called in a URL: `<mount>/jobs/<name>` and
  /// `<mount>/queues/<name>` both name the thing, so a row's key and the
  /// address are the same word. Read off the first column, which is its name.
  final String name;

  /// Each column's key in the graph and its heading.
  final List<List<String>> columns;

  /// The row the address names, marked in the list.
  final String? object;

  /// Called with the row a person chose, so the address can follow.
  final void Function(String name)? onSelect;

  @override
  State<_DVStudioManifestSection> createState() =>
      _DVStudioManifestSectionState();
}

class _DVStudioManifestSectionState extends State<_DVStudioManifestSection> {
  late final Future<Map<String, Object?>> _manifest = widget.client.manifest();

  @override
  Widget build(BuildContext context) {
    return _loading<Map<String, Object?>>(_manifest,
        (Map<String, Object?> graph) {
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        for (final Object? row
            in (graph[widget.kind] as List?) ?? const <Object?>[])
          if (row is Map) row.cast<String, Object?>(),
      ];
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
            title: widget.title,
            subtitle: '${rows.length} in this build',
          ),
          Expanded(
            child: rows.isEmpty
                ? DVStudioStyle.emptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No ${widget.title.toLowerCase()} in this build',
                  )
                : SingleChildScrollView(
                    padding: const .all(DVStudioStyle.space5),
                    child: _DVStudioTable(
                      headers: <String>[
                        for (final List<String> c in widget.columns) c[1],
                      ],
                      rows: <List<String>>[
                        for (final Map<String, Object?> row in rows)
                          <String>[
                            for (final List<String> c in widget.columns)
                              _cell(row[c[0]]),
                          ],
                      ],
                      rowKeys: <Key>[
                        for (final Map<String, Object?> row in rows)
                          ValueKey<String>(
                            'dv-studio-${widget.name}-${row['name']}'),
                      ],
                      // A row the address names is marked, and every row can
                      // be tapped to put itself in the address, so a task is
                      // linkable the same way a page and a model are.
                      selected: widget.object == null
                          ? null
                          : rows.indexWhere(
                              (Map<String, Object?> row) =>
                                  row['name'] == widget.object),
                      onTap: widget.onSelect == null
                          ? null
                          : (int index) => widget.onSelect!(
                              '${rows[index]['name']}'),
                    ),
                  ),
          ),
        ],
      );
    }, waiting: 'Loading the build manifest…');
  }
}

/// Every route the site answers, compiled and stored, as a table.
class _DVStudioSiteMapSection extends StatefulWidget {
  const _DVStudioSiteMapSection({required this.client});

  final DVStudioClient client;

  @override
  State<_DVStudioSiteMapSection> createState() =>
      _DVStudioSiteMapSectionState();
}

class _DVStudioSiteMapSectionState extends State<_DVStudioSiteMapSection> {
  late final Future<List<DVStudioSitePage>> _site = widget.client.site();

  @override
  Widget build(BuildContext context) {
    return _loading<List<DVStudioSitePage>>(_site,
        (List<DVStudioSitePage> pages) {
      final int compiled =
          pages.where((DVStudioSitePage p) => p.isCompiled).length;
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
            title: 'Site map',
            subtitle: pages.length == 1
                ? '1 page'
                : '${pages.length} pages · $compiled in code',
          ),
          Expanded(
            child: pages.isEmpty
                ? DVStudioStyle.emptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No pages yet',
                    message: 'A page written in lib/pages, or one made in '
                        'Pages, is listed here.',
                  )
                : SingleChildScrollView(
                    padding: const .all(DVStudioStyle.space5),
                    child: _DVStudioTable(
                      headers: const <String>[
                        'Address',
                        'Kind',
                        'Page',
                        'File',
                      ],
                      rowKeys: <Key>[
                        for (final DVStudioSitePage page in pages)
                          ValueKey<String>('dv-studio-sitemap-${page.path}'),
                      ],
                      rows: <List<String>>[
                        for (final DVStudioSitePage page in pages)
                          <String>[
                            page.path,
                            dvStudioPageKindLabel(page),
                            page.title ?? page.page ?? '—',
                            page.source ?? 'Stored in Studio',
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      );
    }, waiting: 'Loading the site…');
  }
}

/// The build's queues: what waits, what died and why, and the two things an
/// operator can do about a dead letter.
class _DVStudioQueuesSection extends StatefulWidget {
  const _DVStudioQueuesSection({
    required this.client,
    this.queue,
    this.onSelect,
  });

  final DVStudioClient client;

  /// The queue the address names, opened once the list is read.
  final String? queue;

  /// Called with the queue a person chose, so the address can follow.
  final void Function(String name)? onSelect;

  @override
  State<_DVStudioQueuesSection> createState() => _DVStudioQueuesSectionState();
}

class _DVStudioQueuesSectionState extends State<_DVStudioQueuesSection> {
  List<Map<String, Object?>>? _queues;
  String? _open;
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_DVStudioQueuesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The address moved to another queue: open it rather than keep the one
    // the person was already reading.
    if (widget.queue != oldWidget.queue && widget.queue != null) {
      _open = widget.queue;
    }
  }

  Future<void> _load() async {
    try {
      final List<Map<String, Object?>> queues = await widget.client.queues();
      if (!mounted) return;
      setState(() {
        _queues = queues;
        _error = null;
        // The queue the address names, or the first queue with something
        // dead in it, which is what somebody opening this is most likely here
        // for. A queue this build has no list of yet still keeps its address:
        // the detail pane says it is not here rather than the screen changing.
        final Map<String, Object?>? named = widget.queue == null
            ? null
            : queues
                .where((Map<String, Object?> q) => q['name'] == widget.queue)
                .firstOrNull;
        final String? here = named == null ? null : '${named['name']}';
        _open ??= here ??
            (queues.firstWhere(
              (Map<String, Object?> q) => _jobs(q, 'deadLetters').isNotEmpty,
              orElse: () => queues.isEmpty
                  ? const <String, Object?>{}
                  : queues.first,
            )['name'] as String?);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  static List<Map<String, Object?>> _jobs(Map<String, Object?> queue, String kind) =>
      <Map<String, Object?>>[
        for (final Object? job in (queue[kind] as List?) ?? const <Object?>[])
          if (job is Map) job.cast<String, Object?>(),
      ];

  Future<void> _act(String id, {required bool retry}) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (retry) {
        await widget.client.retryJob(id);
      } else {
        await widget.client.discardJob(id);
      }
      if (mounted) {
        setState(() => _notice = retry
            ? 'Job $id is back on its queue.'
            : 'Job $id was discarded.');
      }
      await _load();
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, Object?>>? queues = _queues;
    if (queues == null) {
      return _error == null
          ? DVStudioStyle.placeholder('Loading queues…')
          : DVStudioStyle.emptyState(
              icon: Icons.cloud_off_outlined,
              title: 'The server did not answer',
              message: '$_error',
            );
    }
    final Map<String, Object?>? open = queues
        .where((Map<String, Object?> q) => q['name'] == _open)
        .firstOrNull;
    return DVStudioStyle.panes(
      listWidth: 220,
      list: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
              title: 'Queue', subtitle: '${queues.length}'),
          const SizedBox(height: DVStudioStyle.space2),
          for (final Map<String, Object?> queue in queues)
            DVStudioListRow(
              key: ValueKey<String>('dv-studio-queue-${queue['name']}'),
              title: '${queue['name']}',
              subtitle: '${_jobs(queue, 'pending').length} waiting · '
                  '${_jobs(queue, 'deadLetters').length} failed',
              icon: Icons.inbox_outlined,
              selected: queue['name'] == _open,
              trailing: _jobs(queue, 'deadLetters').isEmpty
                  ? null
                  : DVStudioStyle.dot(DVStudioStyle.danger),
              onTap: () {
                setState(() => _open = '${queue['name']}');
                widget.onSelect?.call('${queue['name']}');
              },
            ),
        ],
      ),
      detail: open == null
          ? DVStudioStyle.placeholder('Choose a queue.')
          : _detail(open),
    );
  }

  Widget _detail(Map<String, Object?> queue) {
    final List<Map<String, Object?>> pending = _jobs(queue, 'pending');
    final List<Map<String, Object?>> dead = _jobs(queue, 'deadLetters');
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: '${queue['name']}',
          subtitle: '${pending.length} waiting, ${dead.length} failed',
          actions: <Widget>[
            DVStudioIconButton(
              key: const ValueKey<String>('dv-studio-queues-refresh'),
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: () => unawaited(_load()),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const .all(DVStudioStyle.space5),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                if (queue['unreadable'] != null) ...<Widget>[
                  DVStudioStyle.body(
                      'This queue\'s broker cannot list its jobs: '
                      '${queue['unreadable']}',
                      color: DVStudioStyle.warning),
                  const SizedBox(height: DVStudioStyle.space4),
                ],
                if (_notice != null) ...<Widget>[
                  DVStudioStyle.body(_notice!, color: DVStudioStyle.muted),
                  const SizedBox(height: DVStudioStyle.space4),
                ],
                DVStudioStyle.overline('Failed'),
                const SizedBox(height: DVStudioStyle.space2),
                if (dead.isEmpty)
                  DVStudioStyle.caption('No failed jobs.')
                else
                  for (final Map<String, Object?> job in dead)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: DVStudioStyle.space3),
                      child: _deadLetter(job),
                    ),
                const SizedBox(height: DVStudioStyle.space5),
                DVStudioStyle.overline('Waiting'),
                const SizedBox(height: DVStudioStyle.space2),
                if (pending.isEmpty)
                  DVStudioStyle.caption('Nothing waiting.')
                else
                  _DVStudioTable(
                    headers: const <String>[
                      'Job',
                      'Type',
                      'Attempts',
                      'Queued',
                    ],
                    rows: <List<String>>[
                      for (final Map<String, Object?> job in pending)
                        <String>[
                          _cell(job['id']),
                          _cell(job['type']),
                          '${job['attempts']}/${job['maxAttempts']}',
                          _momentText(job['createdAt']),
                        ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _deadLetter(Map<String, Object?> job) {
    final String id = '${job['id']}';
    return DVStudioStyle.card(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.error_outline,
                  size: 16, color: DVStudioStyle.danger),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    DVStudioStyle.body(id),
                    DVStudioStyle.caption(
                      '${_cell(job['type'])} · gave up after '
                      '${job['attempts']} of ${job['maxAttempts']} · '
                      '${_momentText(job['createdAt'])}',
                    ),
                  ],
                ),
              ),
              DVStudioControl(
                key: ValueKey<String>('dv-studio-job-discard-$id'),
                label: 'Discard',
                enabled: !_busy,
                onTap: _busy ? null : () => unawaited(_act(id, retry: false)),
                icon: Icons.delete_outline,
              ),
              const SizedBox(width: DVStudioStyle.space2),
              DVStudioControl(
                key: ValueKey<String>('dv-studio-job-retry-$id'),
                label: 'Retry',
                enabled: !_busy,
                onTap: _busy ? null : () => unawaited(_act(id, retry: true)),
                primary: true,
                icon: Icons.replay,
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          // Why it died is why anybody is here: retrying blind is guessing.
          DVStudioStyle.body(
            '${job['lastError'] ?? 'Failed with no recorded error.'}',
            color: DVStudioStyle.danger,
          ),
        ],
      ),
    );
  }
}

/// A moment the server sent as ISO 8601, as tables show one.
String _momentText(Object? value) {
  final DateTime? at = DateTime.tryParse('${value ?? ''}');
  return at == null ? _cell(value) : _formatMoment(at);
}

/// The cache tags the backend holds, what each covers, and revalidation.
class _DVStudioCacheSection extends StatefulWidget {
  const _DVStudioCacheSection({required this.client});

  final DVStudioClient client;

  @override
  State<_DVStudioCacheSection> createState() => _DVStudioCacheSectionState();
}

class _DVStudioCacheSectionState extends State<_DVStudioCacheSection> {
  List<Map<String, Object?>>? _tags;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<Map<String, Object?>> tags = await widget.client.cacheTags();
      if (mounted) {
        setState(() {
          _tags = tags;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _revalidate(String tag) async {
    try {
      final List<String> dropped = await widget.client.revalidateTag(tag);
      if (!mounted) return;
      // The count is the point: revalidating a tag that covered nothing looks
      // the same as one that cleared a hundred entries.
      setState(() => _notice = 'Revalidated $tag: ${dropped.length} '
          '${dropped.length == 1 ? 'key' : 'keys'} dropped.');
      await _load();
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _notice = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, Object?>>? tags = _tags;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Cache tags',
          subtitle: tags == null ? null : '${tags.length} on this server',
          actions: <Widget>[
            DVStudioIconButton(
              key: const ValueKey<String>('dv-studio-cache-refresh'),
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: () => unawaited(_load()),
            ),
          ],
        ),
        Expanded(
          child: tags == null
              ? (_error == null
                  ? DVStudioStyle.placeholder('Loading cache tags…')
                  : DVStudioStyle.emptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'The server did not answer',
                      message: '$_error',
                    ))
              : SingleChildScrollView(
                  padding: const .all(DVStudioStyle.space5),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      if (_notice != null) ...<Widget>[
                        DVStudioStyle.body(_notice!,
                            color: DVStudioStyle.success),
                        const SizedBox(height: DVStudioStyle.space4),
                      ],
                      if (tags.isEmpty)
                        DVStudioStyle.body('Nothing is kept in the cache under '
                            'a tag right now. When the app keeps something in '
                            'its cache under a tag, the tag is listed here, '
                            'and clearing it makes the app work it out afresh.')
                      else
                        _DVStudioTable(
                          headers: const <String>['Tag', 'Keys', 'Covers'],
                          rows: <List<String>>[
                            for (final Map<String, Object?> tag in tags)
                              <String>[
                                _cell(tag['tag']),
                                '${((tag['keys'] as List?) ?? const <Object?>[]).length}',
                                ((tag['keys'] as List?) ?? const <Object?>[])
                                    .join(', '),
                              ],
                          ],
                          trailing: <Widget>[
                            for (final Map<String, Object?> tag in tags)
                              DVStudioIconButton(
                                key: ValueKey<String>(
                                    'dv-studio-cache-revalidate-${tag['tag']}'),
                                icon: Icons.refresh,
                                tooltip: 'Revalidate',
                                onTap: () =>
                                    unawaited(_revalidate('${tag['tag']}')),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Who may open Studio, and how that changes.
class _DVStudioAccessSection extends StatefulWidget {
  const _DVStudioAccessSection({required this.client});

  final DVStudioClient client;

  @override
  State<_DVStudioAccessSection> createState() => _DVStudioAccessSectionState();
}

class _DVStudioAccessSectionState extends State<_DVStudioAccessSection> {
  late Future<List<Map<String, Object?>>> _grants = widget.client.grants();
  String _account = '';
  int _field = 0;
  bool _busy = false;
  String? _error;

  /// The grant waiting for a yes, with the server's reason for asking.
  ({String userId, String tenant, String message})? _confirming;

  void _reload() {
    setState(() {
      _grants = widget.client.grants();
    });
  }

  Future<void> _grant() async {
    final String account = _account.trim();
    if (account.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.grant(account);
      if (!mounted) return;
      setState(() {
        _account = '';
        // A fresh field, so the address granted does not stay typed in it.
        _field += 1;
      });
      _reload();
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(String userId, String tenant,
      {bool confirm = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.revoke(userId, tenant: tenant, confirm: confirm);
      if (!mounted) return;
      setState(() => _confirming = null);
      _reload();
    } on DVStudioRemoteError catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.status == 409 && !confirm) {
          _confirming =
              (userId: userId, tenant: tenant, message: error.message);
        } else {
          _error = error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({String userId, String tenant, String message})? confirming =
        _confirming;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Team',
          subtitle: 'Who may open Studio',
        ),
        Expanded(
          child: _loading<List<Map<String, Object?>>>(_grants,
              (List<Map<String, Object?>> grants) {
            return SingleChildScrollView(
              padding: const .all(DVStudioStyle.space5),
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  DVStudioStyle.overline('Grant access'),
                  const SizedBox(height: DVStudioStyle.space2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: KeyedSubtree(
                          key: const ValueKey<String>(
                              'dv-studio-grant-account'),
                          child: DVStudioTextInput(
                            key: ValueKey<int>(_field),
                            placeholder: 'Their sign-in address, or account id',
                            icon: Icons.person_add_alt_1_outlined,
                            onChanged: (String value) => _account = value,
                            onSubmitted: (_) => unawaited(_grant()),
                          ),
                        ),
                      ),
                      const SizedBox(width: DVStudioStyle.space2),
                      DVStudioControl(
                        key: const ValueKey<String>('dv-studio-grant'),
                        label: 'Grant',
                        enabled: !_busy,
                        onTap: _busy ? null : () => unawaited(_grant()),
                        primary: true,
                        icon: Icons.add,
                      ),
                    ],
                  ),
                  const SizedBox(height: DVStudioStyle.space2),
                  DVStudioStyle.caption(
                    'The person signs up to the application first. A grant '
                    'lets them open Studio; it gives them nothing else.',
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: DVStudioStyle.space3),
                    DVStudioStyle.body(_error!, color: DVStudioStyle.danger),
                  ],
                  if (confirming != null) ...<Widget>[
                    const SizedBox(height: DVStudioStyle.space4),
                    Container(
                      padding: const .all(DVStudioStyle.space3),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          DVStudioStyle.warning.withValues(alpha: 0.1),
                          DVStudioStyle.surface,
                        ),
                        border: Border.all(
                            color:
                                DVStudioStyle.warning.withValues(alpha: 0.4)),
                        borderRadius:
                            BorderRadius.circular(DVStudioStyle.radiusSmall),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.warning_amber_rounded,
                              size: 18, color: DVStudioStyle.warning),
                          const SizedBox(width: DVStudioStyle.space2),
                          Expanded(
                              child: DVStudioStyle.body(confirming.message)),
                          const SizedBox(width: DVStudioStyle.space2),
                          DVStudioControl(
                            key: const ValueKey<String>(
                                'dv-studio-revoke-cancel'),
                            label: 'Keep it',
                            enabled: true,
                            onTap: () => setState(() => _confirming = null),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                          DVStudioControl(
                            key: const ValueKey<String>(
                                'dv-studio-revoke-confirm'),
                            label: 'Revoke anyway',
                            enabled: !_busy,
                            onTap: _busy
                                ? null
                                : () => unawaited(_revoke(
                                    confirming.userId, confirming.tenant,
                                    confirm: true)),
                            primary: true,
                            icon: Icons.remove_circle_outline,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: DVStudioStyle.space5),
                  if (grants.isEmpty)
                    DVStudioStyle.body('Nobody holds a grant. This Studio is '
                        'open because the application answers Studio.access '
                        'itself, or because this is a development build.')
                  else
                    _DVStudioTable(
                      headers: const <String>[
                        'Email',
                        'Account',
                        'Tenant',
                        'Granted',
                      ],
                      rows: <List<String>>[
                        for (final Map<String, Object?> grant in grants)
                          <String>[
                            _cell(grant['email']),
                            _cell(grant['userId']),
                            _cell(grant['tenant']),
                            _grantedAt(grant['grantedAt']),
                          ],
                      ],
                      // The caller's own grant, highlighted: the one to
                      // think twice about.
                      selected: grants.indexWhere(
                          (Map<String, Object?> g) => g['you'] == true),
                      trailing: <Widget>[
                        for (final Map<String, Object?> grant in grants)
                          DVStudioIconButton(
                            key: ValueKey<String>(
                                'dv-studio-revoke-${grant['userId']}'),
                            icon: Icons.person_remove_outlined,
                            tooltip: 'Revoke',
                            onTap: _busy
                                ? null
                                : () => unawaited(_revoke(
                                    '${grant['userId']}',
                                    '${grant['tenant'] ?? 'default'}')),
                          ),
                      ],
                    ),
                  const SizedBox(height: DVStudioStyle.space4),
                  DVStudioStyle.caption(
                    'On the server, dartvel admin grant <user-id> and '
                    'dartvel admin revoke <user-id> do the same, pointed at '
                    'this deployment\'s database with --database.',
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  static String _grantedAt(Object? value) {
    final DateTime? at = DateTime.tryParse('${value ?? ''}');
    return at == null ? _cell(value) : _formatMoment(at);
  }
}

/// A table too wide for its space, scrolled sideways with a scrollbar that
/// knows which scroll view it belongs to.
///
/// The scrollbar had no controller of its own, and a sideways scroll view is
/// never the primary one, so the first narrow table -- the model table beside
/// an open record -- failed an assertion: "A ScrollController is required
/// when the scrollbar is interactive".
class _DVStudioSidewaysScroll extends StatefulWidget {
  const _DVStudioSidewaysScroll({required this.child});

  final Widget child;

  @override
  State<_DVStudioSidewaysScroll> createState() => _DVStudioSidewaysScrollState();
}

class _DVStudioSidewaysScrollState extends State<_DVStudioSidewaysScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: .horizontal,
          child: widget.child,
        ),
      );
}

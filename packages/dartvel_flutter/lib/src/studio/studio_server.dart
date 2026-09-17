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

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart';
import 'studio_server_transport_stub.dart'
    if (dart.library.js_interop) 'studio_server_transport_web.dart' as transport;

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
DVStudioTransport dvStudioBrowserTransport() {
  final math.Random random = math.Random.secure();
  const String alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final String csrf = String.fromCharCodes(<int>[
    for (int i = 0; i < 32; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
  return (String method, String path, {Object? body}) =>
      transport.dvStudioSend(method, path, body: body, csrf: csrf);
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

/// One field of a model, as the backend describes it.
class DVStudioField {
  const DVStudioField({
    required this.name,
    required this.type,
    this.sensitive = false,
    this.options,
    this.relation,
  });

  factory DVStudioField.fromJson(Map<String, Object?> json) => DVStudioField(
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
  });

  factory DVStudioModel.fromJson(Map<String, Object?> json) => DVStudioModel(
        model: '${json['model']}',
        module: json['module'] is String ? json['module']! as String : null,
        key: '${json['key']}',
        versioned: json['versioned'] != false,
        fields: <DVStudioField>[
          for (final Object? field in (json['fields'] as List?) ?? const <Object?>[])
            DVStudioField.fromJson((field! as Map).cast<String, Object?>()),
        ],
      );

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

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final DVStudioReply reply = await transport(method, path, body: body);
    if (reply.status >= 200 && reply.status < 300) return reply.body;
    final Object? json = reply.body;
    final Map<Object?, Object?> error =
        json is Map ? json : const <Object?, Object?>{};
    throw DVStudioRemoteError(
      reply.status,
      '${error['error'] ?? 'http_${reply.status}'}',
      '${error['message'] ?? 'The server answered ${reply.status}.'}',
    );
  }

  Map<String, Object?> _map(Object? json) =>
      json is Map ? json.cast<String, Object?>() : const <String, Object?>{};

  List<Map<String, Object?>> _list(Object? json, String key) =>
      <Map<String, Object?>>[
        for (final Object? item in (_map(json)[key] as List?) ?? const <Object?>[])
          if (item is Map) item.cast<String, Object?>(),
      ];

  static String _segment(String value) => Uri.encodeComponent(value);

  Future<List<DVStudioModel>> models() async => <DVStudioModel>[
        for (final Map<String, Object?> model
            in _list(await _send('GET', 'api/models'), 'models'))
          DVStudioModel.fromJson(model),
      ];

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

  Future<void> savePage(DVPageDocument document) => _send(
        'PUT',
        'api/pages',
        body: <String, Object?>{'document': document.toJson()},
      );

  Future<void> deletePage(String route) =>
      _send('DELETE', 'api/pages?route=${Uri.encodeQueryComponent(route)}');

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
      _map(await _send('GET', 'graph.json'));
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
class DVStudioApp extends StatelessWidget {
  const DVStudioApp({super.key, required this.client, this.title = 'Studio'});

  final DVStudioClient client;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: DVStudioStyle.accent),
        scaffoldBackgroundColor: DVStudioStyle.canvas,
      ),
      home: Material(
        child: DVStudioScreen(
          store: DVStudioRemotePageStore(client),
          sections: dvStudioServerSections(client),
        ),
      ),
    );
  }
}

/// The sections Studio has on a server: every model's records, the build's
/// routes, functions and jobs, and who may open Studio.
List<DVStudioSection> dvStudioServerSections(DVStudioClient client) =>
    <DVStudioSection>[
      DVStudioSection(
        id: 'models',
        label: 'Models',
        icon: Icons.table_chart_outlined,
        build: (BuildContext context) => DVStudioModelsSection(client: client),
      ),
      DVStudioSection(
        id: 'routes',
        label: 'Routes',
        icon: Icons.alt_route,
        build: (BuildContext context) => _DVStudioManifestSection(
          client: client,
          kind: 'routes',
          title: 'Routes',
          columns: const <List<String>>[
            <String>['path', 'Path'],
            <String>['page', 'Page'],
            <String>['source', 'Declared in'],
          ],
        ),
      ),
      DVStudioSection(
        id: 'functions',
        label: 'Functions',
        icon: Icons.functions,
        build: (BuildContext context) => _DVStudioManifestSection(
          client: client,
          kind: 'functions',
          title: 'Backend functions',
          columns: const <List<String>>[
            <String>['name', 'Function'],
            <String>['method', 'Method'],
            <String>['path', 'Path'],
            <String>['source', 'Declared in'],
          ],
        ),
      ),
      DVStudioSection(
        id: 'jobs',
        label: 'Jobs',
        icon: Icons.work_history_outlined,
        build: (BuildContext context) => _DVStudioManifestSection(
          client: client,
          kind: 'jobs',
          title: 'Jobs',
          columns: const <List<String>>[
            <String>['name', 'Job'],
            <String>['queue', 'Queue'],
            <String>['source', 'Declared in'],
          ],
        ),
      ),
      DVStudioSection(
        id: 'queues',
        label: 'Queues',
        icon: Icons.inbox_outlined,
        build: (BuildContext context) => _DVStudioQueuesSection(client: client),
      ),
      DVStudioSection(
        id: 'cache',
        label: 'Cache',
        icon: Icons.bolt_outlined,
        build: (BuildContext context) => _DVStudioCacheSection(client: client),
      ),
      DVStudioSection(
        id: 'access',
        label: 'Access',
        icon: Icons.admin_panel_settings_outlined,
        build: (BuildContext context) => _DVStudioAccessSection(client: client),
      ),
    ];

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
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: needed, child: _table()),
          ),
        );
      },
    );
  }

  Widget _table() {
    Widget cell(String text, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: DVStudioStyle.space3, vertical: 9),
          // One line, both kinds: a heading that wraps breaks a word in two.
          child: Text(
            header ? text.toUpperCase() : text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: header
                ? const TextStyle(
                    fontSize: 11,
                    color: DVStudioStyle.muted,
                    fontWeight: FontWeight.w600,
                  )
                : const TextStyle(fontSize: 13, color: DVStudioStyle.ink),
          ),
        );
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                behavior: HitTestBehavior.opaque,
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
                        padding: const EdgeInsets.only(
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
  const DVStudioModelsSection({super.key, required this.client});

  final DVStudioClient client;

  @override
  State<DVStudioModelsSection> createState() => _DVStudioModelsSectionState();
}

class _DVStudioModelsSectionState extends State<DVStudioModelsSection> {
  List<DVStudioModel>? _models;
  DVStudioModel? _model;
  List<DVStudioRecordData>? _records;
  Object? _error;

  /// The record open in the form, or null. A record with an empty key is a
  /// new one.
  DVStudioRecordData? _editing;

  @override
  void initState() {
    super.initState();
    unawaited(_loadModels());
  }

  Future<void> _loadModels() async {
    try {
      final List<DVStudioModel> models = await widget.client.models();
      if (!mounted) return;
      setState(() => _models = models);
      if (models.isNotEmpty) await _open(models.first);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _open(DVStudioModel model) async {
    setState(() {
      _model = model;
      _records = null;
      _editing = null;
      _error = null;
    });
    try {
      final List<DVStudioRecordData> records =
          await widget.client.records(model.model);
      if (mounted && _model == model) setState(() => _records = records);
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
    if (models.isEmpty) {
      return DVStudioStyle.emptyState(
        icon: Icons.table_chart_outlined,
        title: 'No models',
        message: 'Declare a @DVModel in lib/models and rebuild, and its '
            'records are listed here.',
      );
    }
    return DVStudioStyle.panes(
      listWidth: 220,
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
              title: 'Models', subtitle: '${models.length}'),
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
              selected: model == _model,
              onTap: () => unawaited(_open(model)),
            ),
        ],
      ),
      detail: _detail(),
    );
  }

  Widget _detail() {
    final DVStudioModel? model = _model;
    if (model == null) return DVStudioStyle.placeholder('Choose a model.');
    final List<DVStudioRecordData>? records = _records;
    final DVStudioRecordData? editing = _editing;
    final List<DVStudioField> fields = model.visibleFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: model.model,
          subtitle: records == null ? null : '${records.length} records',
          actions: <Widget>[
            GestureDetector(
              key: const ValueKey<String>('dv-studio-record-new'),
              onTap: () => setState(() => _editing = const DVStudioRecordData(
                  key: '', version: 0, values: <String, Object?>{})),
              child: DVStudioStyle.control('New record',
                  enabled: true, primary: true, icon: Icons.add),
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
                            padding: const EdgeInsets.all(DVStudioStyle.space5),
                            child: _DVStudioTable(
                              headers: <String>[
                                for (final DVStudioField f in fields) f.name,
                              ],
                              rows: <List<String>>[
                                for (final DVStudioRecordData record in records)
                                  <String>[
                                    for (final DVStudioField f in fields)
                                      _cellText(
                                          f, record.values[f.name]),
                                  ],
                              ],
                              rowKeys: <Key>[
                                for (final DVStudioRecordData record in records)
                                  ValueKey<String>(
                                      'dv-studio-record-${record.key}'),
                              ],
                              selected: editing == null
                                  ? null
                                  : records.indexWhere(
                                      (DVStudioRecordData r) =>
                                          r.key == editing.key),
                              onTap: (int index) =>
                                  setState(() => _editing = records[index]),
                            ),
                          ),
              ),
              if (editing != null)
                Container(
                  width: 360,
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
                    onClose: () => setState(() => _editing = null),
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
                    },
                    onDeleted: (String key) => setState(() {
                      _records = <DVStudioRecordData>[
                        for (final DVStudioRecordData r in _records ?? const <DVStudioRecordData>[])
                          if (r.key != key) r,
                      ];
                      _editing = null;
                    }),
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
    for (final DVStudioField field in widget.model.visibleFields)
      field.name: _initial(field, widget.record.values[field.name]),
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
    for (final DVStudioField field in widget.model.visibleFields) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            padding: const EdgeInsets.all(DVStudioStyle.space4),
            children: <Widget>[
              for (final DVStudioField field in widget.model.visibleFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: DVStudioStyle.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: DVStudioStyle.overline(field.name)),
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
                            field.type,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
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
              if (widget.model.fields.any((DVStudioField f) => f.sensitive))
                DVStudioStyle.caption(
                  'Sensitive fields are not shown or written here.',
                  color: DVStudioStyle.faint,
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DVStudioStyle.space3),
                DVStudioStyle.body(_error!, color: DVStudioStyle.danger),
                if (_conflict)
                  Padding(
                    padding: const EdgeInsets.only(top: DVStudioStyle.space2),
                    child: GestureDetector(
                      onTap: widget.onReload,
                      child: DVStudioStyle.control('Reload records',
                          enabled: true, icon: Icons.refresh),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(DVStudioStyle.space3),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              if (!_isNew)
                GestureDetector(
                  key: const ValueKey<String>('dv-studio-record-delete'),
                  onTap: () => unawaited(_delete()),
                  child: DVStudioStyle.control('Delete',
                      enabled: true, icon: Icons.delete_outline),
                ),
              const Spacer(),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-record-save'),
                onTap: _saving ? null : () => unawaited(_save()),
                child: DVStudioStyle.control(
                  _saving ? 'Saving…' : (_isNew ? 'Create' : 'Save'),
                  enabled: !_saving,
                  primary: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _control(DVStudioField field) {
    final Key key = ValueKey<String>('dv-studio-field-${field.name}');
    final bool locked =
        !field.editable || (!_isNew && field.name == widget.model.key);
    if (!locked && _empty.contains(field.name)) {
      return _readOnly(key, 'empty');
    }
    if (field.baseType == 'bool' && !locked) {
      return Align(
        alignment: Alignment.centerLeft,
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
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
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
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: DVStudioStyle.canvas,
          border: Border.all(color: DVStudioStyle.line),
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
        ),
        child: DVStudioStyle.body(text, color: DVStudioStyle.muted),
      );
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border.all(color: DVStudioStyle.lineStrong),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
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
    required this.title,
    required this.columns,
  });

  final DVStudioClient client;
  final String kind;
  final String title;

  /// Each column's key in the graph and its heading.
  final List<List<String>> columns;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    padding: const EdgeInsets.all(DVStudioStyle.space5),
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
                    ),
                  ),
          ),
        ],
      );
    }, waiting: 'Loading the build manifest…');
  }
}

/// The build's queues: what waits, what died and why, and the two things an
/// operator can do about a dead letter.
class _DVStudioQueuesSection extends StatefulWidget {
  const _DVStudioQueuesSection({required this.client});

  final DVStudioClient client;

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

  Future<void> _load() async {
    try {
      final List<Map<String, Object?>> queues = await widget.client.queues();
      if (!mounted) return;
      setState(() {
        _queues = queues;
        _error = null;
        // The first queue with something dead in it is what somebody opening
        // this is most likely here for.
        _open ??= (queues.firstWhere(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
              title: 'Queues', subtitle: '${queues.length}'),
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
              onTap: () => setState(() => _open = '${queue['name']}'),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            padding: const EdgeInsets.all(DVStudioStyle.space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.error_outline,
                  size: 16, color: DVStudioStyle.danger),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              GestureDetector(
                key: ValueKey<String>('dv-studio-job-discard-$id'),
                onTap: _busy ? null : () => unawaited(_act(id, retry: false)),
                child: DVStudioStyle.control('Discard',
                    enabled: !_busy, icon: Icons.delete_outline),
              ),
              const SizedBox(width: DVStudioStyle.space2),
              GestureDetector(
                key: ValueKey<String>('dv-studio-job-retry-$id'),
                onTap: _busy ? null : () => unawaited(_act(id, retry: true)),
                child: DVStudioStyle.control('Retry',
                    enabled: !_busy, primary: true, icon: Icons.replay),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  padding: const EdgeInsets.all(DVStudioStyle.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_notice != null) ...<Widget>[
                        DVStudioStyle.body(_notice!,
                            color: DVStudioStyle.success),
                        const SizedBox(height: DVStudioStyle.space4),
                      ],
                      if (tags.isEmpty)
                        DVStudioStyle.body('Nothing on this server is cached '
                            'under a tag right now. DV.Cache.tag puts a key '
                            'under one; revalidating the tag drops them all.')
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Access',
          subtitle: 'Who may open Studio (Studio.access)',
        ),
        Expanded(
          child: _loading<List<Map<String, Object?>>>(_grants,
              (List<Map<String, Object?>> grants) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(DVStudioStyle.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      GestureDetector(
                        key: const ValueKey<String>('dv-studio-grant'),
                        onTap: _busy ? null : () => unawaited(_grant()),
                        child: DVStudioStyle.control('Grant',
                            enabled: !_busy, primary: true, icon: Icons.add),
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
                      padding: const EdgeInsets.all(DVStudioStyle.space3),
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
                          GestureDetector(
                            key: const ValueKey<String>(
                                'dv-studio-revoke-cancel'),
                            onTap: () => setState(() => _confirming = null),
                            child: DVStudioStyle.control('Keep it',
                                enabled: true),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                          GestureDetector(
                            key: const ValueKey<String>(
                                'dv-studio-revoke-confirm'),
                            onTap: _busy
                                ? null
                                : () => unawaited(_revoke(
                                    confirming.userId, confirming.tenant,
                                    confirm: true)),
                            child: DVStudioStyle.control('Revoke anyway',
                                enabled: !_busy,
                                primary: true,
                                icon: Icons.remove_circle_outline),
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

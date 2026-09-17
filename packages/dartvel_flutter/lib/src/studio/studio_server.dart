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
  });

  factory DVStudioField.fromJson(Map<String, Object?> json) => DVStudioField(
        name: '${json['name']}',
        type: '${json['type']}',
        sensitive: json['sensitive'] == true,
      );

  final String name;
  final String type;
  final bool sensitive;

  bool get nullable => type.endsWith('?');

  /// The type with no `?`.
  String get baseType => type.replaceAll('?', '').trim();

  /// Whether Studio has a control for this type. Anything else is shown and
  /// left as it is.
  bool get editable =>
      !sensitive &&
      const <String>{'String', 'int', 'double', 'num', 'bool', 'DateTime'}
          .contains(baseType);
}

/// A model, as the backend describes it.
class DVStudioModel {
  const DVStudioModel({
    required this.model,
    required this.key,
    required this.fields,
    this.versioned = true,
  });

  factory DVStudioModel.fromJson(Map<String, Object?> json) => DVStudioModel(
        model: '${json['model']}',
        key: '${json['key']}',
        versioned: json['versioned'] != false,
        fields: <DVStudioField>[
          for (final Object? field in (json['fields'] as List?) ?? const <Object?>[])
            DVStudioField.fromJson((field! as Map).cast<String, Object?>()),
        ],
      );

  final String model;
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

/// A plain table in Studio's style.
class _DVStudioTable extends StatelessWidget {
  const _DVStudioTable({
    required this.headers,
    required this.rows,
    this.rowKeys,
    this.onTap,
    this.selected,
  });

  final List<String> headers;
  final List<List<String>> rows;
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
              subtitle: '${model.visibleFields.length} fields',
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
                                      _cell(record.values[f.name]),
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
  /// switch.
  late final Map<String, Object?> _draft = <String, Object?>{
    for (final DVStudioField field in widget.model.visibleFields)
      field.name: field.baseType == 'bool'
          ? widget.record.values[field.name] == true
          : widget.record.values[field.name] == null
              ? ''
              : '${widget.record.values[field.name]}',
  };
  bool _saving = false;
  String? _error;
  bool _conflict = false;

  bool get _isNew => widget.record.key.isEmpty;

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
      } else if ('$typed' != '$before') {
        changes[field.name] = typed;
      }
    }
    return changes;
  }

  Object? _typed(DVStudioField field, Object? draft) {
    if (field.baseType == 'bool') return draft == true;
    final String text = '${draft ?? ''}'.trim();
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
                        DVStudioStyle.caption(field.type,
                            color: DVStudioStyle.faint),
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
      return Container(
        key: key,
        height: 32,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: DVStudioStyle.canvas,
          border: Border.all(color: DVStudioStyle.line),
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
        ),
        child: DVStudioStyle.body(_cell(widget.record.values[field.name]),
            color: DVStudioStyle.muted),
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

/// Who may open Studio, and how that changes.
class _DVStudioAccessSection extends StatefulWidget {
  const _DVStudioAccessSection({required this.client});

  final DVStudioClient client;

  @override
  State<_DVStudioAccessSection> createState() => _DVStudioAccessSectionState();
}

class _DVStudioAccessSectionState extends State<_DVStudioAccessSection> {
  late final Future<List<Map<String, Object?>>> _grants =
      widget.client.grants();

  @override
  Widget build(BuildContext context) {
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
                  if (grants.isEmpty)
                    DVStudioStyle.body('Nobody holds a grant. This Studio is '
                        'open because the application answers Studio.access '
                        'itself, or because this is a development build.')
                  else
                    _DVStudioTable(
                      headers: const <String>['Account', 'Tenant', 'Granted'],
                      rows: <List<String>>[
                        for (final Map<String, Object?> grant in grants)
                          <String>[
                            _cell(grant['userId']),
                            _cell(grant['tenant']),
                            _cell(grant['grantedAt']),
                          ],
                      ],
                    ),
                  const SizedBox(height: DVStudioStyle.space4),
                  DVStudioStyle.caption(
                    'Grant or revoke on the server with dartvel admin grant '
                    '<user-id> and dartvel admin revoke <user-id>, pointed at '
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
}

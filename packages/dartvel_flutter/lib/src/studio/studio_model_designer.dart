part of 'studio_server.dart';

/// The kinds of value a field designed in Studio can hold, as somebody who
/// has never written a type reads them, and the Dart type each is.
const List<(String, String)> _dvStudioFieldKinds = <(String, String)>[
  ('Text', 'String'),
  ('Whole number', 'int'),
  ('Number', 'double'),
  ('Yes or no', 'bool'),
  ('Date and time', 'DateTime'),
  ('List of text', 'List<String>'),
  ('JSON object', 'Map<String, Object?>'),
  ('Choice', _dvStudioChoice),
  ('Relation', _dvStudioRelation),
];

const String _dvStudioChoice = 'choice';
const String _dvStudioRelation = 'relation';

String _dvStudioKindLabel(String kind) => _dvStudioFieldKinds
    .firstWhere(
      ((String, String) k) => k.$2 == kind,
      orElse: () => (kind, kind),
    )
    .$1;

/// The labels an access rule reads as.
const Map<DVAccess, String> _dvStudioAccessLabels = <DVAccess, String>{
  DVAccess.anyone: 'Anyone',
  DVAccess.signedIn: 'Signed-in users',
  DVAccess.team: 'Studio team',
  DVAccess.nobody: 'Nobody',
};

/// One field as the designer holds it while it is being changed.
class _DVStudioFieldDraft {
  _DVStudioFieldDraft({
    this.name = '',
    this.kind = 'String',
    this.required = true,
    this.options = '',
    this.relation,
    this.unique = false,
    this.min = '',
    this.max = '',
    this.minLength = '',
    this.maxLength = '',
    this.pattern = '',
  });

  factory _DVStudioFieldDraft.of(DVStudioFieldSpec spec) {
    String text(Object? value) => value == null ? '' : '$value';
    final String base = spec.type.replaceAll('?', '').trim();
    return _DVStudioFieldDraft(
      name: spec.name,
      kind: spec.options != null
          ? _dvStudioChoice
          : spec.relation != null
              ? _dvStudioRelation
              : base,
      required: !spec.nullable,
      options: spec.options?.join(', ') ?? '',
      relation: spec.relation,
      unique: spec.unique,
      min: text(spec.min),
      max: text(spec.max),
      minLength: text(spec.minLength),
      maxLength: text(spec.maxLength),
      pattern: spec.pattern ?? '',
    );
  }

  /// A key the widget tree keeps the field's controls under while its name
  /// is being typed.
  final Key key = UniqueKey();

  String name;
  String kind;
  bool required;
  String options;
  String? relation;
  bool unique;
  String min;
  String max;
  String minLength;
  String maxLength;
  String pattern;

  bool get numeric => kind == 'int' || kind == 'double';
  bool get textual => kind == 'String';

  Map<String, Object?> toJson(String model) {
    num? number(String value) => num.tryParse(value.trim());
    int? whole(String value) => int.tryParse(value.trim());
    final String capital =
        name.isEmpty ? '' : '${name[0].toUpperCase()}${name.substring(1)}';
    final String base = switch (kind) {
      _dvStudioChoice => '$model$capital',
      _dvStudioRelation => 'String',
      _ => kind,
    };
    return <String, Object?>{
      'name': name.trim(),
      'type': required ? base : '$base?',
      if (kind == _dvStudioChoice)
        'options': <String>[
          for (final String option in options.split(','))
            if (option.trim().isNotEmpty) option.trim(),
        ],
      if (kind == _dvStudioRelation && relation != null) 'relation': relation,
      if (unique) 'unique': true,
      if (numeric) ...<String, Object?>{
        'min': ?number(min),
        'max': ?number(max),
      },
      if (textual) ...<String, Object?>{
        'minLength': ?whole(minLength),
        'maxLength': ?whole(maxLength),
        if (pattern.trim().isNotEmpty) 'pattern': pattern.trim(),
      },
    };
  }
}

/// One index as the designer holds it.
class _DVStudioIndexDraft {
  _DVStudioIndexDraft({this.fields = '', this.unique = false});

  final Key key = UniqueKey();
  String fields;
  bool unique;

  Map<String, Object?> toJson() => <String, Object?>{
        'fields': <String>[
          for (final String field in fields.split(','))
            if (field.trim().isNotEmpty) field.trim(),
        ],
        if (unique) 'unique': true,
      };
}

/// Designs a data model: its name, key, fields and the rules each value has
/// to meet, relations to other models, indexes, and who may use its data.
///
/// For a model written in code it shows the same, and changes nothing: that
/// model is changed in its file.
class _DVStudioModelDesigner extends StatefulWidget {
  const _DVStudioModelDesigner({
    super.key,
    required this.client,
    required this.models,
    required this.sourceWritable,
    required this.onSaved,
    required this.onClose,
    required this.onDeleted,
    this.model,
  });

  final DVStudioClient client;

  /// The model being changed, or null for a new one.
  final DVStudioModel? model;

  /// Every model, for relations.
  final List<DVStudioModel> models;
  final bool sourceWritable;
  final ValueChanged<DVStudioModel> onSaved;
  final VoidCallback onClose;
  final ValueChanged<String> onDeleted;

  @override
  State<_DVStudioModelDesigner> createState() => _DVStudioModelDesignerState();
}

class _DVStudioModelDesignerState extends State<_DVStudioModelDesigner> {
  late String _name = widget.model?.model ?? '';
  late String _key = widget.model?.key ?? 'id';
  late final List<_DVStudioFieldDraft> _fields = <_DVStudioFieldDraft>[
    if (widget.model case final DVStudioModel model)
      for (final DVStudioField field in model.fields)
        _DVStudioFieldDraft.of(field.spec)
    else ...<_DVStudioFieldDraft>[
      _DVStudioFieldDraft(name: 'id'),
      _DVStudioFieldDraft(name: 'title'),
    ],
  ];
  late final List<_DVStudioIndexDraft> _indexes = <_DVStudioIndexDraft>[
    for (final DVStudioIndexSpec index
        in widget.model?.indexes ?? const <DVStudioIndexSpec>[])
      _DVStudioIndexDraft(fields: index.fields.join(', '), unique: index.unique),
  ];
  late DVModelAccess _access = widget.model?.access ?? const DVModelAccess();
  late bool _versioned = widget.model?.versioned ?? true;
  late bool _softDelete = widget.model?.softDelete ?? false;
  bool _busy = false;
  List<String> _problems = const <String>[];
  String? _notice;

  bool get _isNew => widget.model == null;

  /// A model written in code is shown, not changed here.
  bool get _locked => widget.model != null && !widget.model!.designed;

  Map<String, Object?> _definition() => <String, Object?>{
        'key': _key,
        'fields': <Object?>[
          for (final _DVStudioFieldDraft field in _fields)
            field.toJson(_name.trim()),
        ],
        if (_indexes.isNotEmpty)
          'indexes': <Object?>[
            for (final _DVStudioIndexDraft index in _indexes) index.toJson(),
          ],
        'access': _access.toJson(),
        'versioned': _versioned,
        'softDelete': _softDelete,
      };

  Future<void> _save() async {
    final String name = _name.trim();
    if (name.isEmpty) {
      setState(() => _problems = const <String>['Name the data model.']);
      return;
    }
    setState(() {
      _busy = true;
      _problems = const <String>[];
      _notice = null;
    });
    try {
      final DVStudioModel saved =
          await widget.client.saveModel(name, _definition());
      if (!mounted) return;
      setState(() => _notice = 'Saved. ${saved.model} is ready for records.');
      widget.onSaved(saved);
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _problems = <String>[error.message]);
    } catch (error) {
      if (mounted) setState(() => _problems = <String>['$error']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final DVStudioModel? model = widget.model;
    if (model == null) return;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text('Delete ${model.model}?'),
        content: const Text(
          'Its definition goes. Its records stay in the database, and '
          'making a model with the same name again finds them.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey<String>('dv-studio-model-delete-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.client.deleteModel(model.model);
      widget.onDeleted(model.model);
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _problems = <String>[error.message]);
    }
  }

  Future<void> _writeSource() async {
    final DVStudioModel? model = widget.model;
    if (model == null) return;
    setState(() => _busy = true);
    try {
      final String file = await widget.client.writeModelSource(model.model);
      if (mounted) {
        setState(() => _notice =
            'Written to $file. The next build compiles it as ${model.model}.');
      }
    } on DVStudioRemoteError catch (error) {
      if (mounted) setState(() => _problems = <String>[error.message]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DVStudioModel? model = widget.model;
    final bool phone =
        (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < dvStudioPhoneWidth;
    return Column(
      key: const ValueKey<String>('dv-studio-model-designer'),
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: _isNew ? 'New data model' : 'Design ${model!.model}',
          subtitle: _locked ? 'Written in code' : null,
          actions: <Widget>[
            GestureDetector(
              key: const ValueKey<String>('dv-studio-model-designer-close'),
              onTap: widget.onClose,
              child: DVStudioStyle.control(
                _locked ? 'Back to records' : 'Cancel',
                enabled: true,
              ),
            ),
            if (!_locked) ...<Widget>[
              const SizedBox(width: DVStudioStyle.space2),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-model-save'),
                onTap: _busy ? null : () => unawaited(_save()),
                child: DVStudioStyle.control(
                  _busy ? 'Saving…' : 'Save model',
                  enabled: !_busy,
                  primary: true,
                  icon: Icons.check,
                ),
              ),
            ],
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: .all(phone ? DVStudioStyle.space3 : DVStudioStyle.space5),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                if (_locked)
                  _note(
                    'This data model is written in code. Change its fields '
                    'and rules in its @DVModel; Studio shows them here.',
                    DVStudioStyle.muted,
                  ),
                for (final String problem in _problems)
                  _note(problem, DVStudioStyle.danger,
                      key: const ValueKey<String>('dv-studio-model-problem')),
                if (_notice != null)
                  _note(_notice!, DVStudioStyle.success,
                      key: const ValueKey<String>('dv-studio-model-notice')),
                _section('Name and key', <Widget>[
                  _labelled(
                    'Name',
                    _isNew
                        ? DVStudioTextInput(
                            key: const ValueKey<String>(
                                'dv-studio-model-name'),
                            value: _name,
                            placeholder: 'Article',
                            onChanged: (String value) => _name = value,
                          )
                        : DVStudioStyle.body(_name),
                    hint: 'One word, capitalised: Article, BlogPost.',
                  ),
                  _labelled(
                    'Found by',
                    _locked
                        ? DVStudioStyle.body(_key)
                        : _DVStudioSelect(
                            key: const ValueKey<String>('dv-studio-model-key'),
                            value: _key,
                            options: <String>[
                              for (final _DVStudioFieldDraft f in _fields)
                                if (f.kind == 'String' && f.name.isNotEmpty)
                                  f.name,
                            ],
                            onChanged: (String value) =>
                                setState(() => _key = value),
                          ),
                    hint: 'The text field every record is found by. Left '
                        'empty on a new record, one is made up.',
                  ),
                ]),
                _section('Fields', <Widget>[
                  for (int i = 0; i < _fields.length; i++) _fieldCard(i),
                  if (!_locked)
                    Align(
                      alignment: .centerLeft,
                      child: GestureDetector(
                        key: const ValueKey<String>('dv-studio-field-add'),
                        onTap: () => setState(
                            () => _fields.add(_DVStudioFieldDraft())),
                        child: DVStudioStyle.control('Add field',
                            enabled: true, icon: Icons.add),
                      ),
                    ),
                ]),
                _section('Indexes', <Widget>[
                  DVStudioStyle.caption(
                    'Fields the database keeps in order, for fast lookups '
                    'and sorting. A unique index keeps two records from '
                    'sharing the same values.',
                  ),
                  for (int i = 0; i < _indexes.length; i++) _indexRow(i),
                  if (!_locked)
                    Align(
                      alignment: .centerLeft,
                      child: GestureDetector(
                        key: const ValueKey<String>('dv-studio-index-add'),
                        onTap: () => setState(
                            () => _indexes.add(_DVStudioIndexDraft())),
                        child: DVStudioStyle.control('Add index',
                            enabled: true, icon: Icons.add),
                      ),
                    ),
                ]),
                _section('Keeping records safe', <Widget>[
                  _toggle(
                    'dv-studio-model-versioned',
                    'Refuse an edit made to an out-of-date copy',
                    _versioned,
                    (bool value) => setState(() => _versioned = value),
                  ),
                  DVStudioStyle.caption(
                    'Two people editing one record at once: the second save '
                    'is refused rather than silently replacing the first.',
                    color: DVStudioStyle.faint,
                  ),
                  _toggle(
                    'dv-studio-model-soft-delete',
                    'Keep deleted records, so they can be restored',
                    _softDelete,
                    (bool value) => setState(() => _softDelete = value),
                  ),
                ]),
                _section('Who may use the data', <Widget>[
                  DVStudioStyle.caption(
                    'The data API at /_dartvel/data/${_name.isEmpty ? '<Model>' : _name.trim()} '
                    'asks this. Studio itself is always open to the team.',
                  ),
                  for (final (String action, String label)
                      in const <(String, String)>[
                    ('view', 'Read records'),
                    ('create', 'Create records'),
                    ('update', 'Change records'),
                    ('delete', 'Delete records'),
                  ])
                    _labelled(
                      label,
                      _locked && model?.access == null
                          ? DVStudioStyle.body('Decided by its policies')
                          : _DVStudioSelect(
                              key: ValueKey<String>(
                                  'dv-studio-model-access-$action'),
                              value: _dvStudioAccessLabels[_access.of(action)],
                              options: _dvStudioAccessLabels.values.toList(),
                              onChanged: _locked
                                  ? (_) {}
                                  : (String picked) => setState(() {
                                        final DVAccess rule = _dvStudioAccessLabels
                                            .entries
                                            .firstWhere(
                                                (MapEntry<DVAccess, String> e) =>
                                                    e.value == picked)
                                            .key;
                                        _access = DVModelAccess.fromJson(
                                            <String, Object?>{
                                          ..._access.toJson(),
                                          action: rule.name,
                                        });
                                      }),
                            ),
                    ),
                ]),
                if (!_isNew && !_locked)
                  _section('This model', <Widget>[
                    if (widget.sourceWritable)
                      Align(
                        alignment: .centerLeft,
                        child: GestureDetector(
                          key: const ValueKey<String>(
                              'dv-studio-model-write-source'),
                          onTap: _busy ? null : () => unawaited(_writeSource()),
                          child: DVStudioStyle.control(
                            'Write to lib/models',
                            enabled: !_busy,
                            icon: Icons.code,
                          ),
                        ),
                      ),
                    Align(
                      alignment: .centerLeft,
                      child: GestureDetector(
                        key: const ValueKey<String>('dv-studio-model-delete'),
                        onTap: () => unawaited(_delete()),
                        child: DVStudioStyle.control(
                          'Delete model',
                          enabled: true,
                          icon: Icons.delete_outline,
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _note(String text, Color tone, {Key? key}) => Container(
        key: key,
        margin: const .only(bottom: DVStudioStyle.space3),
        padding: const .all(DVStudioStyle.space3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              tone.withValues(alpha: 0.08), DVStudioStyle.surface),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
          borderRadius: .circular(DVStudioStyle.radius),
        ),
        child: DVStudioStyle.body(text, color: DVStudioStyle.ink),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const .only(bottom: DVStudioStyle.space5),
        child: DVStudioStyle.card(
          padding: const .all(DVStudioStyle.space4),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              DVStudioStyle.heading(title),
              const SizedBox(height: DVStudioStyle.space3),
              for (final Widget child in children) ...<Widget>[
                child,
                const SizedBox(height: DVStudioStyle.space2),
              ],
            ],
          ),
        ),
      );

  Widget _labelled(String label, Widget control, {String? hint}) => Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.overline(label),
          const SizedBox(height: 4),
          control,
          if (hint != null) ...<Widget>[
            const SizedBox(height: 4),
            DVStudioStyle.caption(hint, color: DVStudioStyle.faint),
          ],
        ],
      );

  Widget _textRule(
    String key,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) =>
      SizedBox(
        width: 150,
        child: _labelled(
          label,
          _locked
              ? DVStudioStyle.body(value.isEmpty ? '—' : value)
              : DVStudioTextInput(
                  key: ValueKey<String>(key),
                  value: value,
                  onChanged: onChanged,
                ),
        ),
      );

  Widget _toggle(String key, String label, bool value,
          ValueChanged<bool> onChanged) =>
      Row(
        mainAxisSize: .min,
        children: <Widget>[
          Switch(
            key: ValueKey<String>(key),
            value: value,
            activeThumbColor: DVStudioStyle.accent,
            onChanged: _locked ? null : onChanged,
          ),
          DVStudioStyle.body(label),
        ],
      );

  Widget _fieldCard(int i) {
    final _DVStudioFieldDraft field = _fields[i];
    final String prefix = 'dv-studio-field-design-$i';
    final List<String> targets = <String>[
      for (final DVStudioModel m in widget.models)
        if (m.module == null && m.model != _name.trim()) m.model,
    ];
    return Container(
      key: field.key,
      padding: const .all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: .circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Wrap(
            spacing: DVStudioStyle.space3,
            runSpacing: DVStudioStyle.space2,
            crossAxisAlignment: .end,
            children: <Widget>[
              SizedBox(
                width: 200,
                child: _labelled(
                  'Field',
                  _locked
                      ? DVStudioStyle.body(field.name)
                      : DVStudioTextInput(
                          key: ValueKey<String>('$prefix-name'),
                          value: field.name,
                          placeholder: 'title',
                          onChanged: (String value) =>
                              setState(() => field.name = value.trim()),
                        ),
                ),
              ),
              SizedBox(
                width: 180,
                child: _labelled(
                  'Holds',
                  _locked
                      ? DVStudioStyle.body(_dvStudioKindLabel(field.kind))
                      : _DVStudioSelect(
                          key: ValueKey<String>('$prefix-kind'),
                          value: _dvStudioKindLabel(field.kind),
                          options: <String>[
                            for (final (String label, String _)
                                in _dvStudioFieldKinds)
                              label,
                          ],
                          onChanged: (String picked) => setState(() {
                            field.kind = _dvStudioFieldKinds
                                .firstWhere(((String, String) k) =>
                                    k.$1 == picked)
                                .$2;
                          }),
                        ),
                ),
              ),
              _toggle('$prefix-required', 'Required', field.required,
                  (bool value) => setState(() => field.required = value)),
              _toggle('$prefix-unique', 'Unique', field.unique,
                  (bool value) => setState(() => field.unique = value)),
              if (!_locked && field.name != _key)
                DVStudioIconButton(
                  key: ValueKey<String>('$prefix-remove'),
                  icon: Icons.delete_outline,
                  tooltip: 'Remove field',
                  onTap: () => setState(() => _fields.removeAt(i)),
                ),
            ],
          ),
          if (field.kind == _dvStudioChoice) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space2),
            _labelled(
              'Choices',
              _locked
                  ? DVStudioStyle.body(field.options)
                  : DVStudioTextInput(
                      key: ValueKey<String>('$prefix-options'),
                      value: field.options,
                      placeholder: 'draft, published',
                      onChanged: (String value) => field.options = value,
                    ),
              hint: 'Separated by commas, each one word: draft, inReview.',
            ),
          ],
          if (field.kind == _dvStudioRelation) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space2),
            _labelled(
              'Refers to',
              _locked
                  ? DVStudioStyle.body(field.relation ?? '—')
                  : _DVStudioSelect(
                      key: ValueKey<String>('$prefix-relation'),
                      value: field.relation,
                      options: targets,
                      placeholder: targets.isEmpty
                          ? 'No other data model yet'
                          : 'Choose a data model…',
                      onChanged: (String picked) => setState(() {
                        field.relation = picked;
                        // Named the way the generator recognises a
                        // reference, so it survives being written to code.
                        final DVStudioModel? target = widget.models
                            .where((DVStudioModel m) => m.model == picked)
                            .firstOrNull;
                        final String key = target?.key ?? 'id';
                        field.name =
                            '${picked[0].toLowerCase()}${picked.substring(1)}'
                            '${key[0].toUpperCase()}${key.substring(1)}';
                      }),
                    ),
              hint: 'Holds the key of a record of that model, and is '
                  'refused when no such record exists.',
            ),
          ],
          if (field.numeric || field.textual) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space2),
            Wrap(
              spacing: DVStudioStyle.space3,
              runSpacing: DVStudioStyle.space2,
              children: <Widget>[
                if (field.numeric) ...<Widget>[
                  _textRule('$prefix-min', 'Smallest', field.min,
                      (String v) => field.min = v),
                  _textRule('$prefix-max', 'Largest', field.max,
                      (String v) => field.max = v),
                ],
                if (field.textual) ...<Widget>[
                  _textRule('$prefix-min-length', 'Shortest', field.minLength,
                      (String v) => field.minLength = v),
                  _textRule('$prefix-max-length', 'Longest', field.maxLength,
                      (String v) => field.maxLength = v),
                  SizedBox(
                    width: 240,
                    child: _labelled(
                      'Pattern',
                      _locked
                          ? DVStudioStyle.body(
                              field.pattern.isEmpty ? '—' : field.pattern)
                          : DVStudioTextInput(
                              key: ValueKey<String>('$prefix-pattern'),
                              value: field.pattern,
                              placeholder: '[a-z0-9-]+',
                              onChanged: (String v) => field.pattern = v,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _indexRow(int i) {
    final _DVStudioIndexDraft index = _indexes[i];
    return Wrap(
      key: index.key,
      spacing: DVStudioStyle.space3,
      crossAxisAlignment: .center,
      children: <Widget>[
        SizedBox(
          width: 260,
          child: _locked
              ? DVStudioStyle.body(index.fields)
              : DVStudioTextInput(
                  key: ValueKey<String>('dv-studio-index-$i-fields'),
                  value: index.fields,
                  placeholder: 'status, publishedAt',
                  onChanged: (String value) => index.fields = value,
                ),
        ),
        _toggle('dv-studio-index-$i-unique', 'Unique', index.unique,
            (bool value) => setState(() => index.unique = value)),
        if (!_locked)
          DVStudioIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove index',
            onTap: () => setState(() => _indexes.removeAt(i)),
          ),
      ],
    );
  }
}

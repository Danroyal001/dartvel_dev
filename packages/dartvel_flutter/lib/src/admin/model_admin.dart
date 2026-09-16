import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Generated CRUD admin for one model.
///
/// The model supplies the four operations — list, blank, save, delete — and
/// its own generated form; this is the screen around them. It is deliberately
/// not model-aware: every type-specific decision arrives as a callback, so
/// the generator emits one call rather than a screen per model.
///
/// Every action is asked of `DV.Auth.authorization` as `T.create`,
/// `T.update` or `T.delete` on the record it would touch. An action the
/// policy refuses is not drawn, and each is asked again at the moment it
/// writes, so a button drawn before a role was removed still writes nothing.
/// An action no policy answers is refused, as every unanswered policy is.
class DVModelAdmin<T> extends StatefulWidget {
  /// Who the policy is asked about: the application's own user, such as the
  /// generated `User` a policy written the specification's way takes.
  ///
  /// Null asks about `DV.Auth.currentUser`, which suits a policy written
  /// against `DVAuthUser` or `Object?`. A caller the policy cannot take is
  /// refused rather than cast. One given here is never exchanged for the
  /// session user when the policy cannot take it, because that would answer
  /// for somebody the application did not name.
  final Object? as;

  /// What the model is called, for the heading.
  final String title;

  /// Every stored record.
  final Future<List<T>> Function() load;

  /// Upserts a record. Returns what was stored.
  final Future<T> Function(T model) save;

  /// Removes a record.
  final Future<void> Function(T model) destroy;

  /// A new, empty record — what "New" opens.
  final T Function() blank;

  /// How a record is identified in the list.
  final String Function(T model) label;

  /// The model's generated form, wired to call [onSubmit] with the edited
  /// value.
  final Widget Function(T model, void Function(T edited) onSubmit) form;

  const DVModelAdmin({
    super.key,
    this.as,
    required this.title,
    required this.load,
    required this.save,
    required this.destroy,
    required this.blank,
    required this.label,
    required this.form,
  });

  @override
  State<DVModelAdmin<T>> createState() => _DVModelAdminState<T>();
}

class _DVModelAdminState<T> extends State<DVModelAdmin<T>> {
  List<T> _records = <T>[];
  T? _editing;
  String? _error;
  String? _notice;
  bool _loading = true;

  /// Whether the editor holds a record that is not stored yet, so saving it
  /// is a create rather than an update.
  bool _editingIsNew = false;

  /// What the policy answered for the screen as drawn. Null is not answered
  /// yet, and nothing is offered until it is.
  bool _mayCreate = false;
  bool? _maySave;
  bool? _mayDelete;

  String get _saveAction => _editingIsNew ? 'create' : 'update';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  /// Whether the policy for [action] allows it on [record], asked now.
  ///
  /// Never a cast: `canAction` refuses a caller or a resource the policy
  /// cannot take, and says why once. A policy that throws has not said yes.
  Future<bool> _may(String action, T record) async {
    final Object? caller = widget.as ?? const DVAuth().currentUser;
    try {
      return await const DVAuthAuthorization()
          .canAction(caller, '$T.$action', resource: record);
    } catch (_) {
      return false;
    }
  }

  /// Opens [record] in the editor and asks what may be done with it.
  void _open(T record, {required bool isNew}) {
    setState(() {
      _editing = record;
      _editingIsNew = isNew;
      _maySave = null;
      _mayDelete = null;
      _notice = null;
    });
    unawaited(_ask(record, isNew: isNew));
  }

  Future<void> _ask(T record, {required bool isNew}) async {
    final bool maySave = await _may(isNew ? 'create' : 'update', record);
    final bool mayDelete = await _may('delete', record);
    // Answered for a record the editor no longer holds.
    if (!mounted || !identical(_editing, record)) return;
    setState(() {
      _maySave = maySave;
      _mayDelete = mayDelete;
    });
  }

  Future<void> _reload() async {
    try {
      final records = await widget.load();
      final bool mayCreate = await _may('create', widget.blank());
      if (!mounted) return;
      setState(() {
        _records = records;
        _mayCreate = mayCreate;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // An unmigrated table is the normal state of a fresh app. Showing an
      // empty list for it would read as "you have no records".
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _save(T edited) async {
    final T? editing = _editing;
    if (editing == null) return;
    // A create is asked about what it would store. An update is asked about
    // the stored record, because ownership is judged on what exists: typing
    // somebody else's value into the form must not make a record editable.
    final String action = _saveAction;
    if (!await _may(action, _editingIsNew ? edited : editing)) {
      if (!mounted) return;
      setState(() {
        _maySave = false;
        _error = null;
        _notice = '$T.$action is not allowed.';
      });
      return;
    }
    try {
      await widget.save(edited);
      if (!mounted) return;
      _open(edited, isNew: false);
      setState(() {
        _notice = 'Saved.';
        _error = null;
      });
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _delete() async {
    final editing = _editing;
    if (editing == null) return;
    if (!await _may('delete', editing)) {
      if (!mounted) return;
      setState(() {
        _mayDelete = false;
        _error = null;
        _notice = '$T.delete is not allowed.';
      });
      return;
    }
    try {
      await widget.destroy(editing);
      if (!mounted) return;
      setState(() {
        _editing = null;
        _notice = 'Deleted.';
        _error = null;
      });
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return DVText('Loading ${widget.title}…');
    final editing = _editing;
    return DVBox.row(<Widget>[
      Expanded(flex: 2, child: _list()),
      if (editing != null)
        Expanded(flex: 5, child: _editor(editing))
      else
        Expanded(
          flex: 5,
          child: DVText('Select or create a ${widget.title} to edit.'),
        ),
    ]);
  }

  Widget _list() {
    return DVBox.scrollableList(<Widget>[
      DVText(widget.title)
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read ${widget.title}: $_error'),
      if (_notice != null) DVText(_notice!),
      for (final record in _records)
        GestureDetector(
          key: ValueKey<String>('dv-admin-record-${widget.label(record)}'),
          // Editing reads the record already listed rather than fetching it
          // again, so the form cannot disagree with the row that opened it.
          onTap: () => _open(record, isNew: false),
          child: DVText(widget.label(record)),
        ),
      if (_records.isEmpty && _error == null)
        DVText('No ${widget.title} records yet.'),
      if (_mayCreate)
        GestureDetector(
          key: const ValueKey<String>('dv-admin-new'),
          onTap: () => _open(widget.blank(), isNew: true),
          child: const DVText('New'),
        ),
    ]);
  }

  Widget _editor(T editing) {
    return DVBox.scrollableList(<Widget>[
      DVBox.wrapLine(<Widget>[
        DVText(widget.label(editing)).modifier(
            const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
        if (_mayDelete == true)
          GestureDetector(
            key: const ValueKey<String>('dv-admin-delete'),
            onTap: _delete,
            child: const DVText('Delete'),
          ),
        GestureDetector(
          key: const ValueKey<String>('dv-admin-close'),
          onTap: () => setState(() {
            _editing = null;
            _notice = null;
          }),
          child: const DVText('Close'),
        ),
      ]),
      if (_maySave == false)
        DVText('$T.$_saveAction is not allowed, so this record is read only.'),
      // Keyed by the record being edited so opening a different one rebuilds
      // the form rather than reusing the previous record's field state. A
      // record the policy will not let save is shown without Save, since a
      // DVForm with no onSubmit is a display.
      KeyedSubtree(
        key: ValueKey<String>('dv-admin-form-${widget.label(editing)}'),
        child: _maySave == true
            ? widget.form(editing, _save)
            : DVForm<T>(editing),
      ),
    ]);
  }
}

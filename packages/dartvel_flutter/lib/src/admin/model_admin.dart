import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Generated CRUD admin for one model.
///
/// The model supplies the four operations — list, blank, save, delete — and
/// its own generated form; this is the screen around them. It is deliberately
/// not model-aware: every type-specific decision arrives as a callback, so
/// the generator emits one call rather than a screen per model.
class DVModelAdmin<T> extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final records = await widget.load();
      if (!mounted) return;
      setState(() {
        _records = records;
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
    try {
      await widget.save(edited);
      if (!mounted) return;
      setState(() {
        _editing = edited;
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
    return DVBox.list(<Widget>[
      DVText(widget.title)
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read ${widget.title}: $_error'),
      if (_notice != null) DVText(_notice!),
      for (final record in _records)
        GestureDetector(
          key: ValueKey<String>('dv-admin-record-${widget.label(record)}'),
          // Editing reads the record already listed rather than fetching it
          // again, so the form cannot disagree with the row that opened it.
          onTap: () => setState(() {
            _editing = record;
            _notice = null;
          }),
          child: DVText(widget.label(record)),
        ),
      if (_records.isEmpty && _error == null)
        DVText('No ${widget.title} records yet.'),
      GestureDetector(
        key: const ValueKey<String>('dv-admin-new'),
        onTap: () => setState(() {
          _editing = widget.blank();
          _notice = null;
        }),
        child: const DVText('New'),
      ),
    ]);
  }

  Widget _editor(T editing) {
    return DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        DVText(widget.label(editing)).modifier(
            const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
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
      // Keyed by the record being edited so opening a different one rebuilds
      // the form rather than reusing the previous record's field state.
      KeyedSubtree(
        key: ValueKey<String>('dv-admin-form-${widget.label(editing)}'),
        child: widget.form(editing, _save),
      ),
    ]);
  }
}

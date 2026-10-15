part of 'studio_server.dart';

extension _StudioRecordList on _DVStudioModelsSectionState {
  Widget _recordList(DVStudioModel model, List<DVStudioRecordData> records,
      List<DVStudioField> fields) {
    final Map<String, String> params = _params ?? widget.query;
    void change(String key, String? value) {
      final next = <String, String>{...params}..remove('page');
      if (value == null || value.isEmpty) { next.remove(key); }
      else { next[key] = value; }
      _changeQuery(next);
    }
    Widget button(String key, String label, VoidCallback? run) =>
      DVStudioControl(
        key: ValueKey<String>(key),
        label: label,
        enabled: run != null,
        onTap: run,
      );
    Widget check(String key, String label, bool checked, VoidCallback run) =>
      _StudioCheckbox(
        key: ValueKey<String>(key),
        label: label,
        checked: checked,
        onChanged: run,
      );
    Widget dropdown(String key, String label, String? value,
        Map<String, String> choices, ValueChanged<String?> changed) =>
      Semantics(key: ValueKey<String>(key), label: label,
        child: DVStudioStyle.tooltip(label, DropdownButton<String>(
          hint: Text(label), value: value,
          items: <DropdownMenuItem<String>>[
            for (final entry in choices.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ], onChanged: changed,
        )),
      );
    final String? filter = params['filter'];
    final String? filterName = filter?.split(':').first ?? _filterField;
    final DVStudioField? filterField = fields.where((f) => f.name == filterName).firstOrNull;
    final String? filterValue = filter == null ? null : filter.substring(filter.indexOf(':') + 1);
    final int page = int.tryParse(params['page'] ?? '') ?? 1;
    return SingleChildScrollView(
      padding: const .all(DVStudioStyle.space5),
      child: Column(crossAxisAlignment: .stretch, children: <Widget>[
        DVStudioTextInput(
          key: const ValueKey<String>('dv-studio-records-search'),
          value: _query, placeholder: 'Search records', icon: Icons.search,
          onChanged: (String value) {
            _searchTimer?.cancel();
            _updateState(() => _query = value);
            _searchTimer = Timer(const Duration(milliseconds: 300), () => change('q', value));
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: .center, children: <Widget>[
          dropdown('dv-studio-records-filter-field', 'Filter field', filterName,
            <String, String>{for (final f in fields) f.name: _fieldLabel(f.name)},
            (String? name) {
              if (name == null) return;
              // Chosen, not applied: the value comes next.
              _updateState(() => _filterField = name);
              if (filter != null) change('filter', null);
            }),
          if (filterField != null)
            if ((filterField.options != null && filterField.options!.isNotEmpty) || filterField.baseType == 'bool')
              dropdown('dv-studio-records-filter-value', 'Filter value',
                filterValue == '' ? null : filterValue,
                <String, String>{
                  for (final option in filterField.baseType == 'bool'
                    ? <String>['true', 'false'] : (filterField.options ?? const <String>[])) option: option,
                }, (String? value) => change('filter', value == null ? null : '$filterName:$value'))
            else
              SizedBox(width: 220, child: DVStudioTextInput(
                key: const ValueKey<String>('dv-studio-records-filter-value'),
                value: filterValue ?? '', placeholder: 'Filter value',
                // Asked once typing stops, as the search is.
                onChanged: (String value) {
                  _filterTimer?.cancel();
                  _filterTimer = Timer(const Duration(milliseconds: 300),
                      () => change('filter', value.isEmpty ? null : '$filterName:$value'));
                },
              )),
          if (filter != null || _filterField != null)
            button('dv-studio-records-filter-clear', 'Clear filter', () {
              _updateState(() => _filterField = null);
              change('filter', null);
            }),
        ]),
        if (_bulkProblem case final String problem) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: DVText(problem).modifier(
                const DVModifier().fontSize(13).color(DVStudioStyle.danger)),
          ),
        ],
        if (_chosen.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          button('dv-studio-records-bulk-delete',
            'Delete ${_chosen.length} record${_chosen.length == 1 ? '' : 's'}',
            () => unawaited(_deleteChosen(model))),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 12, crossAxisAlignment: .center, children: <Widget>[
          Text(_total == 0 ? '0 records' : '${_offset + 1}–${_offset + records.length} of $_total'),
          button('dv-studio-records-previous', 'Previous page', _offset > 0
            ? () => _changeQuery(<String, String>{...params, 'page': '${page - 1}'}) : null),
          button('dv-studio-records-next', 'Next page', _offset + records.length < _total
            ? () => _changeQuery(<String, String>{...params, 'page': '${page + 1}'}) : null),
        ]),
        const SizedBox(height: 12),
        Builder(builder: (BuildContext context) {
          // The server searched, filtered and paged; this is its answer.
          final List<DVStudioRecordData> shown = records;
          return SingleChildScrollView(scrollDirection: .horizontal, child: SizedBox(
            width: math.max(550, fields.length * 160 + 64).toDouble(),
            child: Column(children: <Widget>[
              Row(children: <Widget>[
                SizedBox(width: 56, child: check('dv-studio-records-check-all', 'Choose all records on this page',
                  shown.isNotEmpty && shown.every((r) => _chosen.containsKey(r.key)), () => _updateState(() {
                    if (shown.every((r) => _chosen.containsKey(r.key))) { _chosen.clear(); }
                    else { for (final r in shown) { _chosen[r.key] = r.version; } }
                  }))),
                for (final f in fields)
                  Expanded(child: button('dv-studio-sort-${f.name}',
                    '${_fieldLabel(f.name)}${params['sort'] == f.name ? ', sorted ${params['order'] == 'desc' ? 'descending' : 'ascending'}' : ''}',
                    () {
                      final order = params['sort'] == f.name && params['order'] != 'desc' ? 'desc' : 'asc';
                      _changeQuery(<String, String>{...params, 'sort': f.name, 'order': order}..remove('page'));
                    })),
              ]),
              for (final r in shown)
                Row(
                  key: ValueKey<String>('dv-studio-record-${r.key}'),
                  children: <Widget>[
                    SizedBox(
                      width: 56,
                      child: check(
                        'dv-studio-record-check-${r.key}',
                        'Choose ${r.key}',
                        _chosen.containsKey(r.key),
                        () => _updateState(() {
                          if (_chosen.containsKey(r.key)) {
                            _chosen.remove(r.key);
                          } else {
                            _chosen[r.key] = r.version;
                          }
                        }),
                      ),
                    ),
                    for (final f in fields)
                      Expanded(
                        child: DVStudioStyle.tooltip('Open ${r.key}', InkWell(
                          onTap: () {
                            _updateState(() => _editing = r);
                            widget.onSelect?.call('${model.model}/${r.key}');
                          },
                          child: Padding(
                            padding: const .symmetric(horizontal: 8, vertical: 12),
                            child: Text(
                              _cellText(f, r.values[f.name]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )),
                      ),
                  ],
                ),
              if (shown.isEmpty) const Padding(padding: .all(16), child: Text('No matching records.')),
            ]),
          ));
        }),
      ]),
    );
  }

  Future<void> _deleteChosen(DVStudioModel model) async {
    final chosen = <String, int>{..._chosen};
    final bool? confirmed = await showDialog<bool>(context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Delete ${chosen.length} records?'),
        content: const Text('This permanently deletes the chosen records. Changed records are kept.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          DVStudioControl(key: const ValueKey<String>('dv-studio-records-bulk-delete-confirm'),
            label: 'Delete', enabled: true, onTap: () => Navigator.pop(context, true)),
        ],
      ));
    if (confirmed != true || !mounted) return;
    try {
      final result = await widget.client.deleteRecords(model.model, chosen);
      if (!mounted) return;
      final failed = result['failed'] as Map?;
      // Said on the list, which is not inside a Scaffold a SnackBar needs.
      _updateState(() => _bulkProblem = failed == null || failed.isEmpty
          ? null
          : '${failed.keys.join(', ')} could not be deleted: '
              '${failed.length == 1 ? 'it' : 'they'} changed after the list was read.');
      await _open(model);
    } on Object catch (error) {
      if (mounted) _updateState(() => _error = error);
    }
  }
}

class _StudioCheckbox extends StatefulWidget {
  const _StudioCheckbox({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final VoidCallback onChanged;

  @override
  State<_StudioCheckbox> createState() => _StudioCheckboxState();
}

class _StudioCheckboxState extends State<_StudioCheckbox> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      checked: widget.checked,
      enabled: true,
      focusable: true,
      focused: _focusNode.hasFocus,
      onTap: widget.onChanged,
      onFocus: () => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            widget.onChanged();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: .opaque,
          onTap: widget.onChanged,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Semantics(
              excludeSemantics: true,
              child: DVStudioStyle.tooltip(
                widget.label,
                Container(
                  width: 18,
                  height: 18,
                  margin: const .all(8),
                  decoration: BoxDecoration(
                    color: widget.checked ? DVStudioStyle.accent : Colors.transparent,
                    borderRadius: .circular(4),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? DVStudioStyle.accent
                          : (widget.checked ? DVStudioStyle.accent : DVStudioStyle.lineStrong),
                      width: _focusNode.hasFocus ? 2 : 1.5,
                    ),
                  ),
                  child: widget.checked
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

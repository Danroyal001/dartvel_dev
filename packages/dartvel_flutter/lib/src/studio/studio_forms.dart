/// Studio Forms & Submissions section: visual form builder, fields editor,
/// canvas form component, embed snippets, and submissions inbox.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show DVStudioForm, DVStudioFormField, DVStudioFormSubmission, dvStudioDefaultForms;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_server.dart';
import 'studio_style.dart';

enum _FormsTab { forms, submissions }

/// Studio section for designing forms and managing submissions inbox.
class DVStudioFormsSection extends StatefulWidget {
  const DVStudioFormsSection({
    super.key,
    required this.client,
    this.selectedFormId,
    this.onSelect,
  });

  final DVStudioClient client;
  final String? selectedFormId;
  final void Function(String? id)? onSelect;

  @override
  State<DVStudioFormsSection> createState() => _DVStudioFormsSectionState();
}

class _DVStudioFormsSectionState extends State<DVStudioFormsSection> {
  _FormsTab _tab = _FormsTab.forms;

  // Forms tab state
  late Future<List<DVStudioForm>> _formsFuture = _loadForms();
  List<DVStudioForm> _forms = <DVStudioForm>[];
  String? _selectedFormId;
  DVStudioForm? _workingForm;
  bool _dirty = false;
  bool _saving = false;
  String? _statusMessage;
  String? _errorMessage;

  // Submissions tab state
  late Future<({List<DVStudioFormSubmission> submissions, int total, int unread})>
      _submissionsFuture = _loadSubmissions();
  String _filterFormId = 'all';
  String _filterStatus = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedFormId = widget.selectedFormId;
  }

  @override
  void didUpdateWidget(covariant DVStudioFormsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedFormId != null &&
        widget.selectedFormId != _selectedFormId) {
      _selectedFormId = widget.selectedFormId;
      _reloadForms(_selectedFormId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<DVStudioForm>> _loadForms() async {
    try {
      final List<DVStudioForm> list = await widget.client.forms();
      _forms = list;
      if (_selectedFormId == null ||
          !list.any((DVStudioForm f) => f.id == _selectedFormId)) {
        if (list.isNotEmpty) {
          _selectedFormId = list.first.id;
          _workingForm = list.first;
        }
      } else {
        _workingForm = list.firstWhere((DVStudioForm f) => f.id == _selectedFormId);
      }
      _dirty = false;
      return list;
    } catch (_) {
      final List<DVStudioForm> defaults = dvStudioDefaultForms();
      _forms = defaults;
      if (defaults.isNotEmpty) {
        _selectedFormId = defaults.first.id;
        _workingForm = defaults.first;
      }
      return defaults;
    }
  }

  Future<({List<DVStudioFormSubmission> submissions, int total, int unread})>
      _loadSubmissions() async {
    return widget.client.submissions(
      formId: _filterFormId == 'all' ? null : _filterFormId,
      status: _filterStatus == 'all' ? null : _filterStatus,
      query: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
    );
  }

  void _reloadForms([String? selectId]) {
    setState(() {
      if (selectId != null) {
        _selectedFormId = selectId;
        widget.onSelect?.call(selectId);
      }
      _formsFuture = _loadForms();
    });
  }

  void _reloadSubmissions() {
    setState(() {
      _submissionsFuture = _loadSubmissions();
    });
  }

  void _selectForm(DVStudioForm form) {
    if (_selectedFormId == form.id && _workingForm?.id == form.id) return;
    setState(() {
      _selectedFormId = form.id;
      _workingForm = form;
      _dirty = false;
      _statusMessage = null;
      _errorMessage = null;
    });
    widget.onSelect?.call(form.id);
  }

  void _updateWorkingForm(DVStudioForm updated) {
    setState(() {
      _workingForm = updated;
      _dirty = true;
      _statusMessage = null;
      _errorMessage = null;
    });
  }

  Future<void> _saveWorkingForm() async {
    final DVStudioForm? form = _workingForm;
    if (form == null || _saving) return;
    setState(() {
      _saving = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      final DVStudioForm saved = await widget.client.saveForm(form);
      setState(() {
        _workingForm = saved;
        _dirty = false;
        _saving = false;
        _statusMessage = 'Form "${saved.name}" saved successfully.';
      });
      _reloadForms(saved.id);
    } catch (e) {
      setState(() {
        _saving = false;
        _errorMessage = 'Failed to save form: $e';
      });
    }
  }

  Future<void> _deleteCurrentForm() async {
    final DVStudioForm? form = _workingForm;
    if (form == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: DVStudioStyle.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            side: const BorderSide(color: DVStudioStyle.line),
          ),
          title: const Text(
            'Delete Form',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DVStudioStyle.ink,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${form.name}"? All associated submissions will also be deleted. This cannot be undone.',
            style: const TextStyle(fontSize: 13, color: DVStudioStyle.muted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: DVStudioStyle.muted)),
            ),
            DVStudioControl(
              label: 'Delete permanently',
              enabled: true,
              primary: true,
              icon: DVStudioIcons.delete,
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await widget.client.deleteForm(form.id);
        setState(() {
          _workingForm = null;
          _selectedFormId = null;
          _statusMessage = 'Form deleted.';
        });
        _reloadForms();
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to delete form: $e';
        });
      }
    }
  }

  Future<void> _showNewFormDialog() async {
    String name = '';
    String id = '';
    String description = '';
    String submitLabel = 'Submit';
    String successMessage = 'Thank you! Your submission has been received.';
    String targetEmail = '';
    final String targetModel = '';
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                side: const BorderSide(color: DVStudioStyle.line),
              ),
              title: const Text(
                'Create New Form',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      const Text(
                        'Design a new interactive form to capture inquiries, leads, or registrations.',
                        style: TextStyle(fontSize: 13, color: DVStudioStyle.muted),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Form Name',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        placeholder: 'e.g. Contact Form',
                        onChanged: (String v) {
                          setDialogState(() {
                            name = v;
                            if (id.isEmpty ||
                                id == _slugify(name.substring(0, name.length - 1))) {
                              id = _slugify(name);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Form ID (Key)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        placeholder: 'e.g. contact-form',
                        value: id,
                        onChanged: (String v) => id = v.trim(),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Description (Optional)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        placeholder: 'Short summary shown above fields',
                        onChanged: (String v) => description = v.trim(),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: <Widget>[
                                const Text('Submit Button Text',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: DVStudioStyle.ink)),
                                const SizedBox(height: DVStudioStyle.space1),
                                DVStudioTextInput(
                                  value: submitLabel,
                                  placeholder: 'Submit',
                                  onChanged: (String v) => submitLabel = v.trim(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: <Widget>[
                                const Text('Notification Email (Opt)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: DVStudioStyle.ink)),
                                const SizedBox(height: DVStudioStyle.space1),
                                DVStudioTextInput(
                                  placeholder: 'admin@company.com',
                                  onChanged: (String v) => targetEmail = v.trim(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Success Message',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        value: successMessage,
                        placeholder: 'Thank you! Your submission has been received.',
                        onChanged: (String v) => successMessage = v.trim(),
                      ),
                      if (dialogError != null) ...<Widget>[
                        const SizedBox(height: DVStudioStyle.space3),
                        Container(
                          padding: const .all(8),
                          decoration: BoxDecoration(
                            color: DVStudioStyle.danger.withValues(alpha: 0.1),
                            borderRadius: .circular(DVStudioStyle.radiusSmall),
                            border: Border.all(
                                color: DVStudioStyle.danger.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                                fontSize: 12, color: DVStudioStyle.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: DVStudioStyle.muted)),
                ),
                DVStudioControl(
                  label: 'Create Form',
                  enabled: true,
                  primary: true,
                  icon: DVStudioIcons.add,
                  onTap: () async {
                    if (id.trim().isEmpty && name.trim().isNotEmpty) {
                      id = _slugify(name);
                    }
                    if (name.trim().isEmpty || id.trim().isEmpty) {
                      setDialogState(() {
                        dialogError = 'Both Name and ID are required.';
                      });
                      return;
                    }
                    if (_forms.any((DVStudioForm f) => f.id == id.trim())) {
                      setDialogState(() {
                        dialogError = 'A form with ID "$id" already exists.';
                      });
                      return;
                    }

                    final DVStudioForm newForm = DVStudioForm(
                      id: id.trim(),
                      name: name.trim(),
                      description: description.isEmpty ? null : description,
                      submitLabel:
                          submitLabel.isEmpty ? 'Submit' : submitLabel,
                      successMessage: successMessage.isEmpty
                          ? 'Thank you! Your submission has been received.'
                          : successMessage,
                      targetEmail: targetEmail.isEmpty ? null : targetEmail,
                      targetModel: targetModel.isEmpty ? null : targetModel,
                      fields: const <DVStudioFormField>[
                        DVStudioFormField(
                          id: 'name',
                          label: 'Full Name',
                          type: 'text',
                          placeholder: 'Jane Doe',
                          required: true,
                        ),
                        DVStudioFormField(
                          id: 'email',
                          label: 'Email Address',
                          type: 'email',
                          placeholder: 'jane@example.com',
                          required: true,
                        ),
                        DVStudioFormField(
                          id: 'message',
                          label: 'Message',
                          type: 'textarea',
                          placeholder: 'How can we help?',
                          required: false,
                        ),
                      ],
                      updatedAt: DateTime.now().toUtc(),
                    );

                    try {
                      final DVStudioForm created =
                          await widget.client.saveForm(newForm);
                      if (context.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      _reloadForms(created.id);
                    } catch (e) {
                      setDialogState(() {
                        dialogError = 'Failed to create form: $e';
                      });
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showFieldEditorDialog({DVStudioFormField? field, int? editIndex}) async {
    final DVStudioForm? currentForm = _workingForm;
    if (currentForm == null) return;

    String fieldId = field?.id ?? '';
    String label = field?.label ?? '';
    String type = field?.type ?? 'text';
    String placeholder = field?.placeholder ?? '';
    bool required = field?.required ?? false;
    String optionsText = field?.options.join(', ') ?? '';
    String? dialogError;

    const List<String> availableTypes = <String>[
      'text',
      'email',
      'phone',
      'number',
      'textarea',
      'select',
      'checkbox',
    ];

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                side: const BorderSide(color: DVStudioStyle.line),
              ),
              title: Text(
                field == null ? 'Add Form Field' : 'Edit Field: ${field.label}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      const Text('Field Label',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        value: label,
                        placeholder: 'e.g. Phone Number',
                        onChanged: (String v) {
                          setDialogState(() {
                            label = v;
                            if (field == null &&
                                (fieldId.isEmpty ||
                                    fieldId ==
                                        _slugify(label.substring(0, label.length - 1)))) {
                              fieldId = _slugify(label);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Field ID (Key)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        value: fieldId,
                        placeholder: 'e.g. phone',
                        onChanged: (String v) => fieldId = v.trim(),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Input Type',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      Container(
                        padding: const .symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: DVStudioStyle.surface,
                          borderRadius: .circular(DVStudioStyle.radiusSmall),
                          border: Border.all(color: DVStudioStyle.line),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: type,
                            isExpanded: true,
                            dropdownColor: DVStudioStyle.surface,
                            items: availableTypes
                                .map((String t) => DropdownMenuItem<String>(
                                      value: t,
                                      child: Text(t,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: DVStudioStyle.ink)),
                                    ))
                                .toList(),
                            onChanged: (String? val) {
                              if (val != null) {
                                setDialogState(() => type = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Placeholder / Hint (Optional)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      DVStudioTextInput(
                        value: placeholder,
                        placeholder: 'e.g. +1 (555) 000-0000',
                        onChanged: (String v) => placeholder = v.trim(),
                      ),
                      if (type == 'select') ...<Widget>[
                        const SizedBox(height: DVStudioStyle.space3),
                        const Text('Dropdown Options (Comma separated)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: DVStudioStyle.ink)),
                        const SizedBox(height: DVStudioStyle.space1),
                        DVStudioTextInput(
                          value: optionsText,
                          placeholder: 'Option 1, Option 2, Option 3',
                          onChanged: (String v) => optionsText = v,
                        ),
                      ],
                      const SizedBox(height: DVStudioStyle.space3),
                      Row(
                        mainAxisAlignment: .spaceBetween,
                        children: <Widget>[
                          const Column(
                            crossAxisAlignment: .start,
                            children: <Widget>[
                              Text('Required Field',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: DVStudioStyle.ink)),
                              Text('Submitter must fill this field',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: DVStudioStyle.muted)),
                            ],
                          ),
                          Switch(
                            value: required,
                            activeThumbColor: DVStudioStyle.accent,
                            onChanged: (bool v) {
                              setDialogState(() => required = v);
                            },
                          ),
                        ],
                      ),
                      if (dialogError != null) ...<Widget>[
                        const SizedBox(height: DVStudioStyle.space3),
                        Container(
                          padding: const .all(8),
                          decoration: BoxDecoration(
                            color: DVStudioStyle.danger.withValues(alpha: 0.1),
                            borderRadius: .circular(DVStudioStyle.radiusSmall),
                            border: Border.all(
                                color: DVStudioStyle.danger.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                                fontSize: 12, color: DVStudioStyle.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: DVStudioStyle.muted)),
                ),
                DVStudioControl(
                  label: field == null ? 'Add Field' : 'Save Field',
                  enabled: true,
                  primary: true,
                  icon: field == null ? DVStudioIcons.add : Icons.check,
                  onTap: () {
                    if (fieldId.trim().isEmpty && label.trim().isNotEmpty) {
                      fieldId = _slugify(label);
                    }
                    if (label.trim().isEmpty || fieldId.trim().isEmpty) {
                      setDialogState(() {
                        dialogError = 'Field Label and ID are required.';
                      });
                      return;
                    }

                    final List<String> options = optionsText
                        .split(',')
                        .map((String s) => s.trim())
                        .where((String s) => s.isNotEmpty)
                        .toList();

                    final DVStudioFormField newField = DVStudioFormField(
                      id: fieldId.trim(),
                      label: label.trim(),
                      type: type,
                      placeholder: placeholder.isEmpty ? null : placeholder,
                      required: required,
                      options: options,
                    );

                    final List<DVStudioFormField> updatedFields =
                        List<DVStudioFormField>.from(currentForm.fields);
                    if (editIndex != null && editIndex >= 0) {
                      updatedFields[editIndex] = newField;
                    } else {
                      updatedFields.add(newField);
                    }

                    _updateWorkingForm(currentForm.copyWith(fields: updatedFields));
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeFieldAt(int index) {
    final DVStudioForm? currentForm = _workingForm;
    if (currentForm == null) return;
    final List<DVStudioFormField> updated =
        List<DVStudioFormField>.from(currentForm.fields)..removeAt(index);
    _updateWorkingForm(currentForm.copyWith(fields: updated));
  }

  void _moveField(int fromIndex, int toIndex) {
    final DVStudioForm? currentForm = _workingForm;
    if (currentForm == null) return;
    if (toIndex < 0 || toIndex >= currentForm.fields.length) return;
    final List<DVStudioFormField> updated =
        List<DVStudioFormField>.from(currentForm.fields);
    final DVStudioFormField item = updated.removeAt(fromIndex);
    updated.insert(toIndex, item);
    _updateWorkingForm(currentForm.copyWith(fields: updated));
  }

  Future<void> _exportSubmissions(String format, List<DVStudioFormSubmission> list) async {
    String content = '';
    if (format == 'csv') {
      final List<String> headers = <String>[
        'id',
        'formId',
        'status',
        'submittedAt',
        'ipAddress',
        'userAgent',
        'data'
      ];
      final StringBuffer buffer = StringBuffer();
      buffer.writeln(headers.join(','));
      for (final DVStudioFormSubmission s in list) {
        final List<String> row = <String>[
          '"${s.id}"',
          '"${s.formId}"',
          '"${s.status}"',
          '"${s.submittedAt.toIso8601String()}"',
          '"${s.ipAddress ?? ''}"',
          '"${s.userAgent ?? ''}"',
          '"${jsonEncode(s.data).replaceAll('"', '""')}"',
        ];
        buffer.writeln(row.join(','));
      }
      content = buffer.toString();
    } else {
      content = const JsonEncoder.withIndent('  ')
          .convert(<Map<String, Object?>>[for (final s in list) s.toJson()]);
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: DVStudioStyle.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            side: const BorderSide(color: DVStudioStyle.line),
          ),
          title: Text(
            'Export Submissions (${format.toUpperCase()})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DVStudioStyle.ink,
            ),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Text(
                  '${list.length} submissions formatted as ${format.toUpperCase()}:',
                  style: const TextStyle(fontSize: 13, color: DVStudioStyle.muted),
                ),
                const SizedBox(height: DVStudioStyle.space2),
                Container(
                  height: 240,
                  padding: const .all(10),
                  decoration: BoxDecoration(
                    color: DVStudioStyle.canvas,
                    borderRadius: .circular(DVStudioStyle.radiusSmall),
                    border: Border.all(color: DVStudioStyle.line),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: DVStudioStyle.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close',
                  style: TextStyle(color: DVStudioStyle.muted)),
            ),
            DVStudioControl(
              label: 'Copy to Clipboard',
              enabled: true,
              primary: true,
              icon: Icons.copy,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied ${format.toUpperCase()} to clipboard'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSubmissionDetails(DVStudioFormSubmission sub) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            final bool isUnread = sub.status == 'unread';
            return AlertDialog(
              backgroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                side: const BorderSide(color: DVStudioStyle.line),
              ),
              title: Row(
                children: <Widget>[
                  const Icon(Icons.mark_email_read_outlined,
                      size: 20, color: DVStudioStyle.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Submission ${sub.id}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      // Metadata block
                      Container(
                        padding: const .all(12),
                        decoration: BoxDecoration(
                          color: DVStudioStyle.canvas,
                          borderRadius: .circular(DVStudioStyle.radiusSmall),
                          border: Border.all(color: DVStudioStyle.line),
                        ),
                        child: Column(
                          children: <Widget>[
                            _metaRow('Form ID', sub.formId),
                            const Divider(height: 12, color: DVStudioStyle.line),
                            _metaRow('Status', sub.status.toUpperCase()),
                            const Divider(height: 12, color: DVStudioStyle.line),
                            _metaRow('Submitted', sub.submittedAt.toLocal().toString()),
                            if (sub.ipAddress != null) ...<Widget>[
                              const Divider(height: 12, color: DVStudioStyle.line),
                              _metaRow('IP Address', sub.ipAddress!),
                            ],
                            if (sub.userAgent != null) ...<Widget>[
                              const Divider(height: 12, color: DVStudioStyle.line),
                              _metaRow('User Agent', sub.userAgent!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Submitted Field Data',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space2),
                      Container(
                        padding: const .all(12),
                        decoration: BoxDecoration(
                          color: DVStudioStyle.surface,
                          borderRadius: .circular(DVStudioStyle.radiusSmall),
                          border: Border.all(color: DVStudioStyle.line),
                        ),
                        child: sub.data.isEmpty
                            ? const Text('No fields were included.',
                                style: TextStyle(
                                    fontSize: 12, color: DVStudioStyle.muted))
                            : Column(
                                crossAxisAlignment: .stretch,
                                children: sub.data.entries.map((entry) {
                                  return Padding(
                                    padding: const .symmetric(vertical: 4),
                                    child: Row(
                                      crossAxisAlignment: .start,
                                      children: <Widget>[
                                        SizedBox(
                                          width: 140,
                                          child: Text(
                                            entry.key,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: DVStudioStyle.muted,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            '${entry.value}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: DVStudioStyle.ink,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close',
                      style: TextStyle(color: DVStudioStyle.muted)),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await widget.client.deleteSubmission(sub.id);
                      if (context.mounted) Navigator.of(dialogContext).pop();
                      _reloadSubmissions();
                    } catch (_) {}
                  },
                  child: const Text('Delete',
                      style: TextStyle(color: DVStudioStyle.danger)),
                ),
                DVStudioControl(
                  label: isUnread ? 'Mark as Read' : 'Mark as Unread',
                  enabled: true,
                  primary: true,
                  icon: isUnread ? Icons.done_all : Icons.markunread,
                  onTap: () async {
                    try {
                      await widget.client.updateSubmissionStatus(
                        sub.id,
                        isUnread ? 'read' : 'unread',
                      );
                      if (context.mounted) Navigator.of(dialogContext).pop();
                      _reloadSubmissions();
                    } catch (_) {}
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      mainAxisAlignment: .spaceBetween,
      children: <Widget>[
        Text(label,
            style: const TextStyle(fontSize: 12, color: DVStudioStyle.muted)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DVStudioStyle.ink)),
      ],
    );
  }

  static String _slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DVStudioStyle.canvas,
      child: Column(
        children: <Widget>[
          // Top Navigation & Action Bar
          Container(
            height: 52,
            padding: const .symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: DVStudioStyle.surface,
              border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
            ),
            child: Row(
              children: <Widget>[
                DVStudioSegmented<_FormsTab>(
                  segments: const <DVStudioSegment<_FormsTab>>[
                    DVStudioSegment<_FormsTab>(
                      value: _FormsTab.forms,
                      label: 'Forms',
                      icon: Icons.dynamic_form_outlined,
                      tooltip: 'Form Definitions',
                    ),
                    DVStudioSegment<_FormsTab>(
                      value: _FormsTab.submissions,
                      label: 'Submissions Inbox',
                      icon: Icons.inbox_outlined,
                      tooltip: 'Visitor Responses',
                    ),
                  ],
                  value: _tab,
                  onChanged: (_FormsTab tab) {
                    setState(() {
                      _tab = tab;
                      if (tab == _FormsTab.submissions) {
                        _reloadSubmissions();
                      }
                    });
                  },
                ),
                const Spacer(),
                if (_tab == _FormsTab.forms) ...<Widget>[
                  if (_dirty) ...<Widget>[
                    TextButton(
                      onPressed: () {
                        if (_selectedFormId != null) {
                          final DVStudioForm? orig = _forms
                              .where((f) => f.id == _selectedFormId)
                              .firstOrNull;
                          if (orig != null) _selectForm(orig);
                        }
                      },
                      child: const Text('Revert',
                          style: TextStyle(color: DVStudioStyle.muted)),
                    ),
                    const SizedBox(width: 8),
                    DVStudioControl(
                      label: _saving ? 'Saving…' : 'Save Changes',
                      enabled: !_saving,
                      primary: true,
                      icon: Icons.check,
                      onTap: _saveWorkingForm,
                    ),
                    const SizedBox(width: 12),
                  ],
                  DVStudioControl(
                    label: 'New Form',
                    enabled: true,
                    icon: DVStudioIcons.add,
                    onTap: _showNewFormDialog,
                  ),
                ],
              ],
            ),
          ),
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const .symmetric(horizontal: 16, vertical: 8),
              color: DVStudioStyle.success.withValues(alpha: 0.12),
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DVStudioStyle.success,
                ),
              ),
            ),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const .symmetric(horizontal: 16, vertical: 8),
              color: DVStudioStyle.danger.withValues(alpha: 0.12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DVStudioStyle.danger,
                ),
              ),
            ),
          // Tab Content
          Expanded(
            child: _tab == _FormsTab.forms
                ? _buildFormsTab()
                : _buildSubmissionsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormsTab() {
    return FutureBuilder<List<DVStudioForm>>(
      future: _formsFuture,
      builder: (BuildContext context, AsyncSnapshot<List<DVStudioForm>> snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<DVStudioForm> forms = snapshot.data ?? _forms;
        if (forms.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.dynamic_form_outlined,
                    size: 48, color: DVStudioStyle.faint),
                const SizedBox(height: 12),
                const Text('No forms designed yet',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DVStudioStyle.ink)),
                const SizedBox(height: 6),
                const Text(
                  'Create your first form to start receiving visitor submissions.',
                  style: TextStyle(fontSize: 13, color: DVStudioStyle.muted),
                ),
                const SizedBox(height: 16),
                DVStudioControl(
                  label: 'Create Contact Form',
                  enabled: true,
                  primary: true,
                  icon: DVStudioIcons.add,
                  onTap: _showNewFormDialog,
                ),
              ],
            ),
          );
        }

        final DVStudioForm? currentForm = _workingForm;

        return Row(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            // Forms Sidebar List
            SizedBox(
              width: 280,
              child: Container(
                decoration: const BoxDecoration(
                  color: DVStudioStyle.surface,
                  border: Border(right: BorderSide(color: DVStudioStyle.line)),
                ),
                child: ListView.separated(
                  padding: const .symmetric(vertical: 8),
                  itemCount: forms.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: DVStudioStyle.line),
                  itemBuilder: (BuildContext context, int index) {
                    final DVStudioForm f = forms[index];
                    final bool isSelected = f.id == _selectedFormId;
                    return InkWell(
                      onTap: () => _selectForm(f),
                      child: Container(
                        padding: const .symmetric(horizontal: 16, vertical: 12),
                        color: isSelected
                            ? DVStudioStyle.accent.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: .start,
                                children: <Widget>[
                                  Text(
                                    f.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? DVStudioStyle.accent
                                          : DVStudioStyle.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${f.fields.length} fields · ${f.submissionsCount} submissions',
                                    style: const TextStyle(
                                        fontSize: 12, color: DVStudioStyle.muted),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.chevron_right,
                                  size: 18, color: DVStudioStyle.accent),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Form Editor & Fields Workspace
            Expanded(
              child: currentForm == null
                  ? const Center(
                      child: Text('Select a form to configure its fields.'))
                  : SingleChildScrollView(
                      padding: const .all(24),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          // Form Header
                          Row(
                            crossAxisAlignment: .center,
                            children: <Widget>[
                              Column(
                                crossAxisAlignment: .start,
                                children: <Widget>[
                                  Text(
                                    currentForm.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: DVStudioStyle.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${currentForm.id} · ${currentForm.submissionsCount} submissions received',
                                    style: const TextStyle(
                                        fontSize: 12, color: DVStudioStyle.muted),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              DVStudioControl(
                                label: 'Embed snippet',
                                enabled: true,
                                icon: Icons.code,
                                onTap: () async {
                                  final String snippet =
                                      "DVPageNode.form(formId: '${currentForm.id}')";
                                  await Clipboard.setData(ClipboardData(text: snippet));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Copied embed snippet to clipboard!'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              DVStudioControl(
                                label: 'Delete form',
                                enabled: true,
                                icon: DVStudioIcons.delete,
                                onTap: _deleteCurrentForm,
                              ),
                            ],
                          ),
                          const SizedBox(height: DVStudioStyle.space4),
                          // Form Settings Box
                          Container(
                            padding: const .all(16),
                            decoration: BoxDecoration(
                              color: DVStudioStyle.surface,
                              borderRadius:
                                  .circular(DVStudioStyle.radiusSmall),
                              border: Border.all(color: DVStudioStyle.line),
                            ),
                            child: Column(
                              crossAxisAlignment: .start,
                              children: <Widget>[
                                const Text('Form Settings',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: DVStudioStyle.ink)),
                                const SizedBox(height: DVStudioStyle.space2),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: .start,
                                        children: <Widget>[
                                          const Text('Display Name',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: DVStudioStyle.muted)),
                                          const SizedBox(height: 4),
                                          DVStudioTextInput(
                                            value: currentForm.name,
                                            onChanged: (String v) =>
                                                _updateWorkingForm(
                                                    currentForm.copyWith(
                                                        name: v.trim())),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: .start,
                                        children: <Widget>[
                                          const Text('Button Label',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: DVStudioStyle.muted)),
                                          const SizedBox(height: 4),
                                          DVStudioTextInput(
                                            value: currentForm.submitLabel,
                                            onChanged: (String v) =>
                                                _updateWorkingForm(
                                                    currentForm.copyWith(
                                                        submitLabel: v.trim())),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: .start,
                                        children: <Widget>[
                                          const Text('Email Notification',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: DVStudioStyle.muted)),
                                          const SizedBox(height: 4),
                                          DVStudioTextInput(
                                            value: currentForm.targetEmail ?? '',
                                            placeholder: 'admin@company.com',
                                            onChanged: (String v) =>
                                                _updateWorkingForm(
                                                    currentForm.copyWith(
                                                        targetEmail:
                                                            v.trim().isEmpty
                                                                ? null
                                                                : v.trim())),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text('Success Message',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: DVStudioStyle.muted)),
                                const SizedBox(height: 4),
                                DVStudioTextInput(
                                  value: currentForm.successMessage,
                                  onChanged: (String v) => _updateWorkingForm(
                                      currentForm.copyWith(
                                          successMessage: v.trim())),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: DVStudioStyle.space4),
                          // Fields Builder Header
                          Row(
                            mainAxisAlignment: .spaceBetween,
                            children: <Widget>[
                              Text(
                                'Fields (${currentForm.fields.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: DVStudioStyle.ink,
                                ),
                              ),
                              DVStudioControl(
                                label: 'Add Field',
                                enabled: true,
                                icon: DVStudioIcons.add,
                                onTap: _showFieldEditorDialog,
                              ),
                            ],
                          ),
                          const SizedBox(height: DVStudioStyle.space2),
                          // Fields List
                          Container(
                            decoration: BoxDecoration(
                              color: DVStudioStyle.surface,
                              borderRadius:
                                  .circular(DVStudioStyle.radiusSmall),
                              border: Border.all(color: DVStudioStyle.line),
                            ),
                            child: currentForm.fields.isEmpty
                                ? const Padding(
                                    padding: .all(24),
                                    child: Center(
                                      child: Text(
                                        'No fields in this form. Click "Add Field" to add one.',
                                        style: TextStyle(
                                            color: DVStudioStyle.muted),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: currentForm.fields.length,
                                    separatorBuilder: (_, __) => const Divider(
                                        height: 1, color: DVStudioStyle.line),
                                    itemBuilder: (BuildContext context, int i) {
                                      final DVStudioFormField f =
                                          currentForm.fields[i];
                                      return Padding(
                                        padding: const .symmetric(
                                            horizontal: 16, vertical: 10),
                                        child: Row(
                                          children: <Widget>[
                                            Container(
                                              padding: const .symmetric(
                                                  horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: DVStudioStyle.canvas,
                                                borderRadius: .circular(4),
                                                border: Border.all(
                                                    color: DVStudioStyle.line),
                                              ),
                                              child: Text(
                                                f.type,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: DVStudioStyle.ink,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: .start,
                                                children: <Widget>[
                                                  Row(
                                                    children: <Widget>[
                                                      Text(f.label,
                                                          style: const TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight.w500,
                                                              color: DVStudioStyle.ink)),
                                                      if (f.required) ...<Widget>[
                                                        const SizedBox(width: 6),
                                                        const Text('*',
                                                            style: TextStyle(
                                                                color:
                                                                    DVStudioStyle.danger,
                                                                fontWeight:
                                                                    FontWeight.bold)),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'ID: ${f.id}${f.placeholder != null ? ' · placeholder: "${f.placeholder}"' : ''}${f.options.isNotEmpty ? ' · options: ${f.options.join(", ")}' : ''}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: DVStudioStyle.muted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                DVStudioIconButton(
                                                  icon: Icons.arrow_upward,
                                                  tooltip: 'Move up',
                                                  onTap: i > 0
                                                      ? () => _moveField(i, i - 1)
                                                      : null,
                                                ),
                                                DVStudioIconButton(
                                                  icon: Icons.arrow_downward,
                                                  tooltip: 'Move down',
                                                  onTap: i <
                                                          currentForm.fields.length - 1
                                                      ? () => _moveField(i, i + 1)
                                                      : null,
                                                ),
                                                DVStudioIconButton(
                                                  icon: Icons.edit_outlined,
                                                  tooltip: 'Edit field',
                                                  onTap: () =>
                                                      _showFieldEditorDialog(
                                                          field: f, editIndex: i),
                                                ),
                                                DVStudioIconButton(
                                                  icon: Icons.delete_outline,
                                                  tooltip: 'Remove field',
                                                  onTap: () => _removeFieldAt(i),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: DVStudioStyle.space4),
                          // Live Form Canvas Preview
                          const Text(
                            'Live Preview',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink,
                            ),
                          ),
                          const SizedBox(height: DVStudioStyle.space2),
                          Container(
                            width: 520,
                            padding: const .all(20),
                            decoration: BoxDecoration(
                              color: DVStudioStyle.surface,
                              borderRadius:
                                  .circular(DVStudioStyle.radiusSmall),
                              border: Border.all(color: DVStudioStyle.line),
                            ),
                            child: DVStudioFormWidget(
                              formId: currentForm.id,
                              form: currentForm,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubmissionsTab() {
    return FutureBuilder<
        ({List<DVStudioFormSubmission> submissions, int total, int unread})>(
      future: _submissionsFuture,
      builder: (BuildContext context,
          AsyncSnapshot<
                  ({
                    List<DVStudioFormSubmission> submissions,
                    int total,
                    int unread
                  })>
              snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final ({
          List<DVStudioFormSubmission> submissions,
          int total,
          int unread
        }) data = snapshot.data ?? (submissions: const <DVStudioFormSubmission>[], total: 0, unread: 0);

        return Column(
          children: <Widget>[
            // Filter Bar
            Container(
              padding: const .all(12),
              decoration: const BoxDecoration(
                color: DVStudioStyle.surface,
                border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
              ),
              child: Row(
                children: <Widget>[
                  // Form Filter
                  Container(
                    padding: const .symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.canvas,
                      borderRadius: .circular(DVStudioStyle.radiusSmall),
                      border: Border.all(color: DVStudioStyle.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterFormId,
                        dropdownColor: DVStudioStyle.surface,
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(
                            value: 'all',
                            child: Text('All Forms',
                                style: TextStyle(
                                    fontSize: 13, color: DVStudioStyle.ink)),
                          ),
                          for (final DVStudioForm f in _forms)
                            DropdownMenuItem<String>(
                              value: f.id,
                              child: Text(f.name,
                                  style: const TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink)),
                            ),
                        ],
                        onChanged: (String? val) {
                          if (val != null) {
                            setState(() => _filterFormId = val);
                            _reloadSubmissions();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status Filter
                  Container(
                    padding: const .symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.canvas,
                      borderRadius: .circular(DVStudioStyle.radiusSmall),
                      border: Border.all(color: DVStudioStyle.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterStatus,
                        dropdownColor: DVStudioStyle.surface,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('All Statuses',
                                  style: TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink))),
                          DropdownMenuItem<String>(
                              value: 'unread',
                              child: Text('Unread Only',
                                  style: TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink))),
                          DropdownMenuItem<String>(
                              value: 'read',
                              child: Text('Read Only',
                                  style: TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink))),
                          DropdownMenuItem<String>(
                              value: 'archived',
                              child: Text('Archived',
                                  style: TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink))),
                        ],
                        onChanged: (String? val) {
                          if (val != null) {
                            setState(() => _filterStatus = val);
                            _reloadSubmissions();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Search Input
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13, color: DVStudioStyle.ink),
                        decoration: InputDecoration(
                          hintText: 'Search submitted data…',
                          hintStyle: const TextStyle(
                              fontSize: 13, color: DVStudioStyle.faint),
                          prefixIcon: const Icon(Icons.search,
                              size: 18, color: DVStudioStyle.muted),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                    _reloadSubmissions();
                                  },
                                )
                              : null,
                          contentPadding: const .symmetric(horizontal: 12),
                          filled: true,
                          fillColor: DVStudioStyle.canvas,
                          border: OutlineInputBorder(
                            borderRadius:
                                .circular(DVStudioStyle.radiusSmall),
                            borderSide:
                                const BorderSide(color: DVStudioStyle.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                .circular(DVStudioStyle.radiusSmall),
                            borderSide:
                                const BorderSide(color: DVStudioStyle.line),
                          ),
                        ),
                        onChanged: (String q) {
                          setState(() => _searchQuery = q);
                          _reloadSubmissions();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${data.total} total (${data.unread} unread)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DVStudioStyle.muted),
                  ),
                  const SizedBox(width: 12),
                  DVStudioControl(
                    label: 'Export CSV',
                    enabled: data.submissions.isNotEmpty,
                    icon: Icons.download,
                    onTap: () => _exportSubmissions('csv', data.submissions),
                  ),
                  const SizedBox(width: 6),
                  DVStudioControl(
                    label: 'Export JSON',
                    enabled: data.submissions.isNotEmpty,
                    icon: Icons.data_object,
                    onTap: () => _exportSubmissions('json', data.submissions),
                  ),
                ],
              ),
            ),
            // Submissions Table / List
            Expanded(
              child: data.submissions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.inbox_outlined,
                              size: 48, color: DVStudioStyle.faint),
                          const SizedBox(height: 12),
                          const Text('No submissions found',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: DVStudioStyle.ink)),
                          const SizedBox(height: 6),
                          Text(
                            _searchQuery.isNotEmpty ||
                                    _filterFormId != 'all' ||
                                    _filterStatus != 'all'
                                ? 'Try adjusting your filters or search keywords.'
                                : 'When visitors submit forms on your site, responses will appear here.',
                            style: const TextStyle(
                                fontSize: 13, color: DVStudioStyle.muted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const .all(16),
                      itemCount: data.submissions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: DVStudioStyle.space2),
                      itemBuilder: (BuildContext context, int index) {
                        final DVStudioFormSubmission s = data.submissions[index];
                        final bool isUnread = s.status == 'unread';
                        final String summary = s.data.entries
                            .take(3)
                            .map((e) => '${e.key}: ${e.value}')
                            .join(' · ');

                        return Container(
                          decoration: BoxDecoration(
                            color: DVStudioStyle.surface,
                            borderRadius:
                                .circular(DVStudioStyle.radiusSmall),
                            border: Border.all(
                              color: isUnread
                                  ? DVStudioStyle.accent.withValues(alpha: 0.4)
                                  : DVStudioStyle.line,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _showSubmissionDetails(s),
                            borderRadius:
                                .circular(DVStudioStyle.radiusSmall),
                            child: Padding(
                              padding: const .symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isUnread
                                          ? DVStudioStyle.accent
                                          : (s.status == 'archived'
                                              ? DVStudioStyle.faint
                                              : DVStudioStyle.lineStrong),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const .symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: DVStudioStyle.canvas,
                                      borderRadius: .circular(4),
                                    ),
                                    child: Text(
                                      s.formId,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: DVStudioStyle.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: <Widget>[
                                        Text(
                                          summary.isEmpty ? s.id : summary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isUnread
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: DVStudioStyle.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${s.submittedAt.toLocal()}${s.ipAddress != null ? ' · IP: ${s.ipAddress}' : ''}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: DVStudioStyle.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      DVStudioIconButton(
                                        icon: Icons.remove_red_eye_outlined,
                                        tooltip: 'View details',
                                        onTap: () => _showSubmissionDetails(s),
                                      ),
                                      DVStudioIconButton(
                                        icon: isUnread
                                            ? Icons.mark_email_read_outlined
                                            : Icons.markunread_outlined,
                                        tooltip: isUnread
                                            ? 'Mark as read'
                                            : 'Mark as unread',
                                        onTap: () async {
                                          try {
                                            await widget.client
                                                .updateSubmissionStatus(
                                              s.id,
                                              isUnread ? 'read' : 'unread',
                                            );
                                            _reloadSubmissions();
                                          } catch (_) {}
                                        },
                                      ),
                                      DVStudioIconButton(
                                        icon: Icons.delete_outline,
                                        tooltip: 'Delete submission',
                                        onTap: () async {
                                          try {
                                            await widget.client
                                                .deleteSubmission(s.id);
                                            _reloadSubmissions();
                                          } catch (_) {}
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Canvas-renderable and visitor-renderable form widget.
class DVStudioFormWidget extends StatefulWidget {
  const DVStudioFormWidget({
    super.key,
    required this.formId,
    this.form,
    this.submitLabel,
    this.successMessage,
    this.onSubmit,
  });

  final String formId;
  final DVStudioForm? form;
  final String? submitLabel;
  final String? successMessage;
  final Future<void> Function(Map<String, Object?> data)? onSubmit;

  @override
  State<DVStudioFormWidget> createState() => _DVStudioFormWidgetState();
}

class _DVStudioFormWidgetState extends State<DVStudioFormWidget> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, Object?> _values = <String, Object?>{};
  bool _submitted = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String fieldId, String? defaultValue) {
    return _controllers.putIfAbsent(
      fieldId,
      () => TextEditingController(text: defaultValue ?? ''),
    );
  }

  void _submit(DVStudioForm activeForm) async {
    setState(() {
      _errorMessage = null;
    });

    final Map<String, Object?> data = <String, Object?>{};
    for (final DVStudioFormField f in activeForm.fields) {
      if (f.type == 'checkbox') {
        data[f.id] = _values[f.id] == true;
      } else if (f.type == 'select') {
        data[f.id] = _values[f.id] ?? (f.options.isNotEmpty ? f.options.first : '');
      } else {
        final TextEditingController c =
            _controllerFor(f.id, f.defaultValue as String?);
        data[f.id] = c.text.trim();
      }

      if (f.required) {
        final Object? val = data[f.id];
        if (val == null || (val is String && val.trim().isEmpty)) {
          setState(() {
            _errorMessage = 'Please complete the "${f.label}" field.';
          });
          return;
        }
      }

      if (f.type == 'email') {
        final Object? val = data[f.id];
        if (val is String && val.isNotEmpty && (!val.contains('@') || !val.contains('.'))) {
          setState(() {
            _errorMessage = 'Please enter a valid email address for "${f.label}".';
          });
          return;
        }
      }
    }

    setState(() => _submitting = true);
    try {
      if (widget.onSubmit != null) {
        await widget.onSubmit!(data);
      }
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _errorMessage = 'Submission failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DVStudioForm activeForm = widget.form ??
        DVStudioForm(
          id: widget.formId,
          name: 'Contact Form',
          submitLabel: widget.submitLabel ?? 'Submit',
          successMessage: widget.successMessage ??
              'Thank you! Your submission has been received.',
          fields: const <DVStudioFormField>[
            DVStudioFormField(
              id: 'name',
              label: 'Full Name',
              type: 'text',
              placeholder: 'Jane Doe',
              required: true,
            ),
            DVStudioFormField(
              id: 'email',
              label: 'Email Address',
              type: 'email',
              placeholder: 'jane@example.com',
              required: true,
            ),
            DVStudioFormField(
              id: 'message',
              label: 'Message',
              type: 'textarea',
              placeholder: 'Write your message…',
              required: true,
            ),
          ],
          updatedAt: DateTime.now().toUtc(),
        );

    if (_submitted) {
      return Container(
        padding: const .all(24),
        decoration: BoxDecoration(
          color: DVStudioStyle.success.withValues(alpha: 0.08),
          borderRadius: .circular(DVStudioStyle.radiusSmall),
          border:
              Border.all(color: DVStudioStyle.success.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: .center,
          children: <Widget>[
            const Icon(Icons.check_circle_outline,
                size: 40, color: DVStudioStyle.success),
            const SizedBox(height: 12),
            Text(
              widget.successMessage ?? activeForm.successMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DVStudioStyle.success,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _submitted = false;
                  for (final TextEditingController c in _controllers.values) {
                    c.clear();
                  }
                  _values.clear();
                });
              },
              child: const Text('Submit another response'),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (activeForm.description != null) ...<Widget>[
          Text(
            activeForm.description!,
            style: const TextStyle(fontSize: 13, color: DVStudioStyle.muted),
          ),
          const SizedBox(height: DVStudioStyle.space3),
        ],
        if (_errorMessage != null) ...<Widget>[
          Container(
            padding: const .all(8),
            decoration: BoxDecoration(
              color: DVStudioStyle.danger.withValues(alpha: 0.1),
              borderRadius: .circular(DVStudioStyle.radiusSmall),
              border: Border.all(
                  color: DVStudioStyle.danger.withValues(alpha: 0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: DVStudioStyle.danger),
            ),
          ),
          const SizedBox(height: DVStudioStyle.space2),
        ],
        for (final DVStudioFormField f in activeForm.fields) ...<Widget>[
          Padding(
            padding: const .only(bottom: 12),
            child: _buildFormField(f),
          ),
        ],
        const SizedBox(height: DVStudioStyle.space2),
        SizedBox(
          height: 40,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DVStudioStyle.ink,
              foregroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: .circular(DVStudioStyle.radiusSmall),
              ),
            ),
            onPressed: _submitting ? null : () => _submit(activeForm),
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DVStudioStyle.surface,
                    ),
                  )
                : Text(
                    widget.submitLabel ?? activeForm.submitLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormField(DVStudioFormField f) {
    if (f.type == 'checkbox') {
      final bool val = _values[f.id] == true;
      return Row(
        children: <Widget>[
          Checkbox(
            value: val,
            onChanged: (bool? newVal) {
              setState(() => _values[f.id] = newVal == true);
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              f.label,
              style: const TextStyle(fontSize: 13, color: DVStudioStyle.ink),
            ),
          ),
        ],
      );
    }

    if (f.type == 'select') {
      final String val =
          (_values[f.id] as String?) ?? (f.options.isNotEmpty ? f.options.first : '');
      return Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            '${f.label}${f.required ? ' *' : ''}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DVStudioStyle.ink),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const .symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: DVStudioStyle.surface,
              borderRadius: .circular(DVStudioStyle.radiusSmall),
              border: Border.all(color: DVStudioStyle.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: val.isNotEmpty ? val : null,
                isExpanded: true,
                dropdownColor: DVStudioStyle.surface,
                items: f.options
                    .map((String opt) => DropdownMenuItem<String>(
                          value: opt,
                          child: Text(opt,
                              style: const TextStyle(
                                  fontSize: 13, color: DVStudioStyle.ink)),
                        ))
                    .toList(),
                onChanged: (String? newVal) {
                  if (newVal != null) {
                    setState(() => _values[f.id] = newVal);
                  }
                },
              ),
            ),
          ),
        ],
      );
    }

    final bool isTextarea = f.type == 'textarea';
    final TextEditingController controller =
        _controllerFor(f.id, f.defaultValue as String?);

    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          '${f.label}${f.required ? ' *' : ''}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DVStudioStyle.ink),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: isTextarea ? 3 : 1,
          keyboardType: f.type == 'email'
              ? TextInputType.emailAddress
              : (f.type == 'phone'
                  ? TextInputType.phone
                  : (f.type == 'number'
                      ? TextInputType.number
                      : TextInputType.text)),
          style: const TextStyle(fontSize: 13, color: DVStudioStyle.ink),
          decoration: InputDecoration(
            hintText: f.placeholder,
            hintStyle:
                const TextStyle(fontSize: 13, color: DVStudioStyle.faint),
            contentPadding:
                const .symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: DVStudioStyle.surface,
            border: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radiusSmall),
              borderSide: const BorderSide(color: DVStudioStyle.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radiusSmall),
              borderSide: const BorderSide(color: DVStudioStyle.line),
            ),
          ),
        ),
      ],
    );
  }
}

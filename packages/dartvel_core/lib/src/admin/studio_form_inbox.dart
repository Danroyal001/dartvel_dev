/// What a visitor's answer to a Studio form is checked against before it is
/// kept.
///
/// A form's submit endpoint is the one public write a site built in Studio
/// has, so it is where a site is filled with junk or used to store whatever a
/// client sends. An answer is kept only as the form describes it: the fields
/// it declares and nothing else, each of the type it says, a choice one of its
/// options, nothing longer than [maxValueLength]. A filled honeypot is thanked
/// and kept nowhere, so a bot learns nothing from the reply.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../database/adapter.dart';
import '../database/records.dart';
import 'studio_api.dart'
    show
        dvStudioFormsShape,
        dvStudioFormsTable,
        dvStudioSubmissionsShape,
        dvStudioSubmissionsTable;
import 'studio_forms.dart';

/// The field a person never sees and a bot fills in.
const String dvStudioFormHoneypot = '_dv_website';

/// Why an answer was not kept, with the status a reply carries.
class DVStudioFormRefusal implements Exception {
  const DVStudioFormRefusal(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// What came of an answer: its id, or none when a honeypot was filled.
typedef DVStudioFormReceipt = ({String? id, String message});

/// The forms Studio made, as visitors read and answer them.
class DVStudioFormInbox {
  DVStudioFormInbox(this.database, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DVDatabaseAdapter database;
  final DateTime Function() _clock;

  /// The longest value a field keeps.
  static const int maxValueLength = 10000;

  DVRecordAdapter get _records => DVRecordAdapter.over(database);

  /// The form [id], or null when there is none.
  Future<DVStudioForm?> form(String id) async {
    await _records.ensure(dvStudioFormsShape);
    final List<Map<String, Object?>> rows = await _records.find(
      dvStudioFormsTable,
      where: DVFilter.equals('id', id),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    final Object? fields = _decode(row['fields_json']);
    return DVStudioForm(
      id: '${row['id']}',
      name: '${row['name'] ?? row['id']}',
      description: row['description'] as String?,
      submitLabel: '${row['submit_label'] ?? 'Submit'}',
      successMessage: '${row['success_message'] ?? 'Thank you.'}',
      fields: <DVStudioFormField>[
        if (fields is List)
          for (final Object? item in fields)
            if (item is Map) DVStudioFormField.fromJson(item.cast<String, Object?>()),
      ],
      targetEmail: row['target_email'] as String?,
      targetModel: row['target_model'] as String?,
      submissionsCount: (row['submissions_count'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
    );
  }

  /// [form] as a visitor is given it: what to fill in and what is said after,
  /// never where answers go or how many came.
  static Map<String, Object?> publicJson(DVStudioForm form) => <String, Object?>{
    'id': form.id,
    'name': form.name,
    'description': ?form.description,
    'submitLabel': form.submitLabel,
    'successMessage': form.successMessage,
    'fields': <Object?>[
      for (final DVStudioFormField field in form.fields) field.toJson(),
    ],
  };

  /// Keeps [answer] to form [id] from [source], or refuses it.
  Future<DVStudioFormReceipt> submit(
    String id,
    Map<String, Object?> answer, {
    String? source,
    String? userAgent,
  }) async {
    final DVStudioForm? found = await form(id);
    if (found == null) {
      throw DVStudioFormRefusal(404, 'not_found', 'There is no form "$id".');
    }
    final Object? honeypot = answer[dvStudioFormHoneypot];
    if (honeypot is String && honeypot.trim().isNotEmpty) {
      return (id: null, message: found.successMessage);
    }

    final Map<String, Object?> kept = <String, Object?>{};
    for (final DVStudioFormField field in found.fields) {
      final Object? value = _value(field, answer[field.id]);
      if (value == null) {
        if (field.required) {
          throw DVStudioFormRefusal(
              400, 'validation_error', '${field.label} is required.');
        }
        continue;
      }
      kept[field.id] = value;
    }

    final DateTime now = _clock();
    final String submission = 'sub-${now.millisecondsSinceEpoch}-'
        '${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    await _records.ensure(dvStudioSubmissionsShape);
    await _records.insert(dvStudioSubmissionsTable, <String, Object?>{
      'id': submission,
      'form_id': found.id,
      'data_json': jsonEncode(kept),
      'status': 'unread',
      'submitted_at': now.millisecondsSinceEpoch,
      'ip_address': ?source,
      'user_agent': ?(userAgent == null
          ? null
          : userAgent.substring(0, math.min(userAgent.length, 300))),
    });
    await _records.update(
      dvStudioFormsTable,
      <String, Object?>{'submissions_count': found.submissionsCount + 1},
      where: DVFilter.equals('id', found.id),
    );
    return (id: submission, message: found.successMessage);
  }

  /// [raw] as [field] keeps it, null when it is empty, or a refusal naming
  /// the field when it is not something the field takes.
  static Object? _value(DVStudioFormField field, Object? raw) {
    Never refuse(String why) =>
        throw DVStudioFormRefusal(400, 'validation_error', '${field.label} $why.');
    if (raw == null) return null;
    switch (field.type) {
      case 'checkbox':
        if (raw is bool) return raw ? true : null;
        refuse('is a yes or a no');
      case 'number':
        final num? number = raw is num ? raw : num.tryParse('$raw'.trim());
        if (raw is String && raw.trim().isEmpty) return null;
        if (number == null || !number.isFinite) refuse('is a number');
        return number;
    }
    if (raw is! String) refuse('is text');
    final String text = raw.trim();
    if (text.isEmpty) return null;
    if (text.length > maxValueLength) {
      refuse('is longer than $maxValueLength characters');
    }
    switch (field.type) {
      case 'email':
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
          throw DVStudioFormRefusal(400, 'validation_error',
              'Invalid email address for ${field.label}.');
        }
      case 'select':
        final List<String> options = field.options;
        if (!options.contains(text)) refuse('is not one of its choices');
      case 'text' || 'phone':
        if (text.contains('\n')) refuse('is one line');
    }
    return text;
  }

  static Object? _decode(Object? json) {
    if (json is! String || json.isEmpty) return null;
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }
}

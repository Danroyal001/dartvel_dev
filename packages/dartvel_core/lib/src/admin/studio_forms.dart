library;

/// A field within a form definition.
class DVStudioFormField {
  const DVStudioFormField({
    required this.id,
    required this.label,
    this.type = 'text',
    this.placeholder,
    this.required = false,
    this.options = const <String>[],
    this.defaultValue,
  });

  /// Unique field key (e.g. `name`, `email`, `phone`, `subject`, `message`).
  final String id;

  /// Human-readable label displayed next to or above the input.
  final String label;

  /// Input type: `text`, `email`, `phone`, `number`, `textarea`, `select`, `checkbox`.
  final String type;

  /// Placeholder hint text.
  final String? placeholder;

  /// Whether filling this field is required to submit the form.
  final bool required;

  /// Selection options for dropdown or radio types.
  final List<String> options;

  /// Default initial value.
  final Object? defaultValue;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'type': type,
        if (placeholder != null) 'placeholder': placeholder,
        'required': required,
        if (options.isNotEmpty) 'options': options,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };

  factory DVStudioFormField.fromJson(Map<String, Object?> json) {
    return DVStudioFormField(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? ''}',
      type: '${json['type'] ?? 'text'}',
      placeholder: json['placeholder'] as String?,
      required: json['required'] == true,
      options: <String>[
        for (final Object? opt in (json['options'] as List?) ?? const <Object?>[])
          '$opt',
      ],
      defaultValue: json['defaultValue'],
    );
  }

  DVStudioFormField copyWith({
    String? id,
    String? label,
    String? type,
    String? placeholder,
    bool? required,
    List<String>? options,
    Object? defaultValue,
  }) {
    return DVStudioFormField(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      placeholder: placeholder ?? this.placeholder,
      required: required ?? this.required,
      options: options ?? this.options,
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }
}

/// A form definition configured in Dartvel Studio.
class DVStudioForm {
  const DVStudioForm({
    required this.id,
    required this.name,
    this.description,
    this.submitLabel = 'Submit',
    this.successMessage = 'Thank you! Your submission has been received.',
    this.fields = const <DVStudioFormField>[],
    this.targetEmail,
    this.targetModel,
    this.submissionsCount = 0,
    required this.updatedAt,
  });

  /// Unique form slug (e.g. `contact-form`, `newsletter-signup`).
  final String id;

  /// Display name of the form (e.g. `Contact Form`).
  final String name;

  /// Optional description or subtitle.
  final String? description;

  /// Label shown on the submission button.
  final String submitLabel;

  /// Success message displayed to the submitter upon valid submission.
  final String successMessage;

  /// Ordered list of form inputs.
  final List<DVStudioFormField> fields;

  /// Optional email address to notify upon receiving a submission.
  final String? targetEmail;

  /// Optional name of a `@DVModel` to insert into upon submission.
  final String? targetModel;

  /// How many submissions have been received for this form.
  final int submissionsCount;

  /// When this form definition was last updated.
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'submitLabel': submitLabel,
        'successMessage': successMessage,
        'fields': <Map<String, Object?>>[
          for (final DVStudioFormField f in fields) f.toJson(),
        ],
        if (targetEmail != null) 'targetEmail': targetEmail,
        if (targetModel != null) 'targetModel': targetModel,
        'submissionsCount': submissionsCount,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DVStudioForm.fromJson(Map<String, Object?> json) {
    return DVStudioForm(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      description: json['description'] as String?,
      submitLabel: '${json['submitLabel'] ?? 'Submit'}',
      successMessage: '${json['successMessage'] ?? 'Thank you! Your submission has been received.'}',
      fields: <DVStudioFormField>[
        for (final Object? item in (json['fields'] as List?) ?? const <Object?>[])
          if (item is Map) DVStudioFormField.fromJson(item.cast<String, Object?>()),
      ],
      targetEmail: json['targetEmail'] as String?,
      targetModel: json['targetModel'] as String?,
      submissionsCount: (json['submissionsCount'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] is String
          ? (DateTime.tryParse(json['updatedAt']! as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  DVStudioForm copyWith({
    String? id,
    String? name,
    String? description,
    String? submitLabel,
    String? successMessage,
    List<DVStudioFormField>? fields,
    String? targetEmail,
    String? targetModel,
    int? submissionsCount,
    DateTime? updatedAt,
  }) {
    return DVStudioForm(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      submitLabel: submitLabel ?? this.submitLabel,
      successMessage: successMessage ?? this.successMessage,
      fields: fields ?? this.fields,
      targetEmail: targetEmail ?? this.targetEmail,
      targetModel: targetModel ?? this.targetModel,
      submissionsCount: submissionsCount ?? this.submissionsCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// A visitor submission received through a form.
class DVStudioFormSubmission {
  const DVStudioFormSubmission({
    required this.id,
    required this.formId,
    this.data = const <String, Object?>{},
    this.status = 'unread',
    required this.submittedAt,
    this.ipAddress,
    this.userAgent,
  });

  /// Unique submission identifier (e.g. `sub-1728901234-abcd`).
  final String id;

  /// The form this submission belongs to.
  final String formId;

  /// Submitted key-value field data.
  final Map<String, Object?> data;

  /// Inbox status: `unread`, `read`, `archived`, `spam`.
  final String status;

  /// When the submission was received.
  final DateTime submittedAt;

  /// Client IP address recorded at submission time.
  final String? ipAddress;

  /// Browser User-Agent header recorded at submission time.
  final String? userAgent;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'formId': formId,
        'data': data,
        'status': status,
        'submittedAt': submittedAt.toIso8601String(),
        if (ipAddress != null) 'ipAddress': ipAddress,
        if (userAgent != null) 'userAgent': userAgent,
      };

  factory DVStudioFormSubmission.fromJson(Map<String, Object?> json) {
    return DVStudioFormSubmission(
      id: '${json['id'] ?? ''}',
      formId: '${json['formId'] ?? ''}',
      data: (json['data'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
      status: '${json['status'] ?? 'unread'}',
      submittedAt: json['submittedAt'] is String
          ? (DateTime.tryParse(json['submittedAt']! as String) ?? DateTime.now())
          : DateTime.now(),
      ipAddress: json['ipAddress'] as String?,
      userAgent: json['userAgent'] as String?,
    );
  }

  DVStudioFormSubmission copyWith({
    String? id,
    String? formId,
    Map<String, Object?>? data,
    String? status,
    DateTime? submittedAt,
    String? ipAddress,
    String? userAgent,
  }) {
    return DVStudioFormSubmission(
      id: id ?? this.id,
      formId: formId ?? this.formId,
      data: data ?? this.data,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      ipAddress: ipAddress ?? this.ipAddress,
      userAgent: userAgent ?? this.userAgent,
    );
  }
}

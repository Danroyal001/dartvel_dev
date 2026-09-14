/// Who a crash report is about, and the flags in force when it happened.
library;

import '../analytics/consent.dart';
import '../flags/flags.dart';

/// A user id for crash reports, bound to a consent category.
///
/// A report is sent without an analytics grant, because the application
/// cannot be fixed otherwise, and that is why the identity on it is bound:
/// the report leaves the device before anybody has been asked. The id is on
/// a report only while [category] is granted, read at the moment the report
/// is written, so a withdrawal takes effect on the next crash.
final class DVCrashIdentity {
  DVCrashIdentity({required this.category});

  /// The consent category the application declared its crash identity under.
  final DVConsentCategory category;

  String? _userId;
  DVConsent? _consent;

  /// The account this install is signed in as, and the consent it answers
  /// to. Null signs out.
  void identify(String? userId, {required DVConsent consent}) {
    _userId = userId;
    _consent = consent;
  }

  /// The user id a report may carry now, or null.
  ///
  /// Null without a grant, and null — never a throw — when the consent
  /// policy does not declare [category]: this is read inside a crash handler,
  /// where an exception replaces the report being written with nothing.
  String? get userId {
    final String? id = _userId;
    final DVConsent? consent = _consent;
    if (id == null || consent == null) return null;
    try {
      return consent.boundIdentity(category, userId: id);
    } on Object {
      return null;
    }
  }
}

/// Every declared flag's answer right now, for a crash report.
///
/// Through [DVFlags.peek], so taking it records no exposure — a crash does
/// not count somebody into an experiment — reports no diagnostic, and pins
/// nothing. Enum values by name, so the report is JSON. Empty rather than a
/// throw when the evaluation context cannot be read: this runs inside the
/// handler.
Map<String, Object?> dvCrashFlagsSnapshot() {
  try {
    final DVFlagContext context = DVFlags.context();
    return <String, Object?>{
      for (final DVFeatureFlag<Object?> flag in DVFlags.declared)
        flag.key: switch (DVFlags.peek<Object?>(flag, context: context).value) {
          final Enum value => value.name,
          final Object? value => value,
        },
    };
  } on Object {
    return const <String, Object?>{};
  }
}

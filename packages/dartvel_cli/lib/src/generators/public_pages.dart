/// Which data models get a generated public page, keyed by what, and which
/// of their fields a page may never show.
///
/// Every model has a page per record unless it says `generatePublicPages:
/// false`. The model generator, the static-path manifest and the router each
/// need the same answer, and three copies of it are three chances to
/// generate a route for a model whose class has no page to serve.
library;

import 'annotation_args.dart';

/// One field of a model, as the generators read it.
typedef DVPublicPagesField = ({String type, String name});

/// A model's generated public pages, decided from its declaration.
class DVPublicPages {
  const DVPublicPages._({
    required this.className,
    required this.generates,
    required this.explicit,
    required this.protectedFields,
    required this.personal,
    this.keyField,
    this.publishedField,
    this.skipped,
  });

  final String className;

  /// Whether the model gets a page per record.
  final bool generates;

  /// Whether the model wrote `generatePublicPages: true` rather than taking
  /// the default. A page that was asked for and cannot be made stops the
  /// build; a default that cannot be made is skipped with [skipped].
  final bool explicit;

  /// The field the route carries and `find` looks a record up by, when the
  /// model gets a page.
  final String? keyField;

  /// The bool field whose false keeps a record's page unwritten and
  /// unserved: `published`, else `isPublished`. Null when the model has
  /// neither, and every record is published.
  final String? publishedField;

  /// Why a model that did not opt out gets no page, for the build log. Null
  /// when it gets one, or said `generatePublicPages: false`.
  final String? skipped;

  /// Fields a page never shows except to a viewer the model's
  /// `viewSensitive` policy admits, and never puts in page data, static
  /// output or the sitemap: its `@DVModel.sensitiveField()`s and the field
  /// naming its privacy subject. Every field, for a [personal] model.
  final Set<String> protectedFields;

  /// Whether a row is its own privacy subject (`subject: DVSubject.self`),
  /// so every field of it is the person's.
  final bool personal;

  /// The route the page is served at: the model's name, plural and
  /// kebab-case, then the key. Never written out in an annotation.
  String? get route => keyField == null
      ? null
      : '/${dvPluralRouteSegment(className)}/:$keyField';

  /// Decides for the model [className] (without its leading underscore),
  /// declared with [modelArgs] and [fields], of which [sensitive] are
  /// `@DVModel.sensitiveField()`s.
  ///
  /// [takenRoutes] are the routes the application's own pages serve. A
  /// default page whose route one of them already has yields to it, because
  /// the page somebody wrote is the one they meant.
  ///
  /// Throws [StateError] where `generatePublicPages: true` asked for a page
  /// that cannot be made, or the value is not a literal the generator can
  /// read.
  static DVPublicPages of({
    required String className,
    required String modelArgs,
    required List<DVPublicPagesField> fields,
    Set<String> sensitive = const <String>{},
    Set<String> takenRoutes = const <String>{},
  }) {
    final Map<String, String> named = <String, String>{
      for (final String part in dvSplitArgs(modelArgs))
        if (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)').firstMatch(part)
            case final RegExpMatch m)
          m.group(1)!: part.substring(m.end).trim(),
    };

    final String? declared = named['generatePublicPages'];
    if (declared != null && declared != 'true' && declared != 'false') {
      throw StateError(
        'Dartvel: _$className: generatePublicPages: $declared is not true or '
        'false. Write the literal, which the generator reads.',
      );
    }
    final bool explicit = declared == 'true';

    final String? subject = named['subject']
        ?.replaceFirst(RegExp(r'^const\s+'), '')
        .trim();
    final bool personal = subject == 'DVSubject.self';
    final String? subjectField = subject == null
        ? null
        : (RegExp(r'^#([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(subject) ??
                  RegExp(
                    r'''^DVSubject\.(?:field|through)\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]''',
                  ).firstMatch(subject))
              ?.group(1);
    final Set<String> protectedFields = <String>{
      ...sensitive,
      if (subjectField != null) subjectField,
      if (personal) ...fields.map((DVPublicPagesField f) => f.name),
    };

    final String? keyField = dvModelKeyField(fields);
    final String? publishedField = _publishedField(fields);

    DVPublicPages none({String? skipped}) => DVPublicPages._(
      className: className,
      generates: false,
      explicit: explicit,
      protectedFields: protectedFields,
      personal: personal,
      publishedField: publishedField,
      skipped: skipped,
    );

    if (declared == 'false') return none();
    // A resolver names the paths for a page the application writes, so the
    // model has no generated page of its own unless it also asks for one.
    if (!explicit && named.containsKey('publicPathsResolver')) return none();

    if (!explicit) {
      final String optIn =
          'Add generatePublicPages: true to give it one, or '
          'generatePublicPages: false to say so and silence this.';
      if (named['tenantScoped'] == 'true') {
        return none(
          skipped:
              '$className has no public pages: its rows belong to a '
              'tenant, and a public page is rendered with no request to take '
              'a tenant from. Say generatePublicPages: false to silence this.',
        );
      }
      final String? account = _accountWord(className);
      if (account != null) {
        return none(
          skipped:
              '$className has no public pages: $account, and records '
              'like these are not published by default. $optIn',
        );
      }
      if (personal) {
        return none(
          skipped:
              '$className has no public pages: each row is its own '
              'privacy subject (subject: DVSubject.self), a person, and a '
              'person\'s record is not published by default. $optIn',
        );
      }
    }

    if (keyField == null) {
      if (explicit) {
        throw StateError(
          '@DVModel(generatePublicPages: true) on _$className requires a '
          'String slug, id, or other String field so Dartvel can generate a '
          'parameterized public page route.',
        );
      }
      return none(
        skipped:
            '$className has no public pages: it has no String field for '
            'a page\'s route to carry. Add a String slug or id to give it '
            'one, or say generatePublicPages: false to silence this.',
      );
    }

    if (!personal && protectedFields.contains(keyField)) {
      final String why = sensitive.contains(keyField)
          ? '$keyField is a sensitive field'
          : '$keyField names the privacy subject';
      if (explicit) {
        throw StateError(
          '@DVModel(generatePublicPages: true) on _$className would key its '
          'pages by $keyField, and $why. A key is in every URL, the sitemap '
          'and the static build. Give the model a String slug or id.',
        );
      }
      return none(
        skipped:
            '$className has no public pages: its key, $why, and a key '
            'is in every URL. Add a String slug or id to give it pages, or '
            'say generatePublicPages: false to silence this.',
      );
    }

    if (!explicit) {
      // A record about a person (an order, a booking, a message) is theirs.
      // Hiding the field that names them still publishes the rest of it, so
      // such a model is public only when each record says so: an article
      // has an author and a published flag, an order has neither.
      if (subjectField != null && publishedField == null) {
        return none(
          skipped:
              '$className has no public pages: each record is about a '
              'person (subject: $subject) and has no published or '
              'isPublished flag to say which records they meant to publish. '
              'Add generatePublicPages: true to give it one, or '
              'generatePublicPages: false to say so and silence this.',
        );
      }
    }

    final String route = '/${dvPluralRouteSegment(className)}/:$keyField';
    if (!explicit) {
      final String shape = dvRouteShape(route);
      for (final String taken in takenRoutes) {
        if (dvRouteShape(taken) != shape) continue;
        return none(
          skipped:
              '$className has no generated pages: $route is served by '
              'the application\'s own page at $taken. Say '
              'generatePublicPages: false to silence this.',
        );
      }
    }

    return DVPublicPages._(
      className: className,
      generates: true,
      explicit: explicit,
      protectedFields: protectedFields,
      personal: personal,
      keyField: keyField,
      publishedField: publishedField,
    );
  }

  /// What [className] stands for when it is an account, a credential or the
  /// framework's own record, else null.
  ///
  /// Read from the name because that is all a declaration says about what a
  /// model is for, and the cost of the two mistakes differs: a model wrongly
  /// matched loses a default page and says so in the build log; one wrongly
  /// missed publishes a table of sessions.
  static String? _accountWord(String className) {
    final List<String> words = RegExp(
      r'[A-Z]+(?=[A-Z][a-z0-9])|[A-Z]?[a-z0-9]+|[A-Z]+',
    ).allMatches(className).map((Match m) => m.group(0)!).toList();
    if (words.isEmpty) return null;
    if (words.first == 'DV' && words.length > 1) {
      return 'the DV prefix is the framework\'s own';
    }
    if (words.length == 1 &&
        const <String>{
          'User',
          'Users',
          'Account',
          'Accounts',
          'Audit',
          'Audits',
          'Role',
          'Roles',
          'Permission',
          'Permissions',
        }.contains(words.single)) {
      return 'it is an account or its access';
    }
    const Set<String> credentialWords = <String>{
      'Session',
      'Sessions',
      'Token',
      'Tokens',
      'Credential',
      'Credentials',
      'Password',
      'Passwords',
      'Passkey',
      'Passkeys',
      'Secret',
      'Secrets',
      'Otp',
      'OTP',
      'Totp',
      'TOTP',
    };
    if (words.any(credentialWords.contains)) {
      return 'it is a session or a credential';
    }
    final String tail = words.length < 2
        ? ''
        : '${words[words.length - 2]}${words.last}';
    if (const <String>{
      'ApiKey',
      'APIKey',
      'TimeCode',
      'RecoveryCode',
    }.contains(tail)) {
      return 'it is a session or a credential';
    }
    if (words.length >= 2 &&
        words[words.length - 2] == 'Audit' &&
        const <String>{
          'Log',
          'Logs',
          'Entry',
          'Entries',
          'Event',
          'Events',
          'Trail',
          'Record',
          'Records',
        }.contains(words.last)) {
      return 'it is an audit record';
    }
    return null;
  }

  static String? _publishedField(List<DVPublicPagesField> fields) {
    final Set<String> bools = <String>{
      for (final DVPublicPagesField f in fields)
        if (f.type == 'bool') f.name,
    };
    if (bools.contains('published')) return 'published';
    if (bools.contains('isPublished')) return 'isPublished';
    return null;
  }
}

/// The field a model's generated `find` looks a record up by, and its page
/// route carries: `slug`, else `id`, else the first `String` field. Null for
/// a model with no `String` field.
String? dvModelKeyField(Iterable<DVPublicPagesField> fields) {
  final List<String> strings = <String>[
    for (final DVPublicPagesField f in fields)
      if (f.type == 'String') f.name,
  ];
  if (strings.contains('slug')) return 'slug';
  if (strings.contains('id')) return 'id';
  return strings.isEmpty ? null : strings.first;
}

/// [path] with every parameter's name dropped, so `/articles/:id` and
/// `/articles/:slug` compare as the one route they are.
String dvRouteShape(String path) => path
    .split('/')
    .map((String segment) => segment.startsWith(':') ? ':' : segment)
    .join('/');

/// A model's name as the first segment of its route: `BlogPost` is
/// `blog-posts`, `Category` is `categories`.
String dvPluralRouteSegment(String className) {
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < className.length; index += 1) {
    final String char = className[index];
    final String lower = char.toLowerCase();
    if (index > 0 && char != lower) buffer.write('-');
    buffer.write(lower);
  }
  final String singular = buffer.toString();
  if (singular.endsWith('s')) return singular;
  if (singular.endsWith('y')) {
    return '${singular.substring(0, singular.length - 1)}ies';
  }
  return '${singular}s';
}

/// The fields of [source] declared `@DVModel.sensitiveField(...)`, or with
/// the deprecated `@DVSensitiveModelField(...)`, however many other
/// annotations stand between it and the declaration.
Set<String> dvSensitiveFieldNames(String source) => <String>{
  for (final RegExpMatch m in RegExp(
    r'@(?:DVModel\.sensitiveField|DVSensitiveModelField)\s*\([^)]*\)\s*'
    r'(?:@[A-Za-z0-9_.]+\s*\([^)]*\)\s*)*'
    r'final\s+.+?\s+([A-Za-z0-9_]+)\s*;',
    dotAll: true,
  ).allMatches(source))
    m.group(1)!,
};

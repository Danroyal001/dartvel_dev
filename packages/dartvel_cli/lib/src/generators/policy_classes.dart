/// Reads `@DVPolicy(ModelType)` classes and turns them into registrations.
///
/// The annotation was in the specification and in the annotations library and
/// nowhere else: `@DVPolicy` appeared in exactly one file in the repository,
/// the one declaring it. So a developer could write a PostPolicy, watch it
/// compile, and have every question about a post answered by default-deny,
/// because nothing had ever registered a check. It fails closed, which is the
/// right direction to fail, and it still means the authorization model the
/// application wrote down is not the one it runs.
library;

import 'annotation_args.dart';

/// The actions the runtime answers questions in.
///
/// A method not on this list is left alone. Registering one under its own
/// name would put a key in the registry nothing will ever ask for, and would
/// hide a typo: a method called `updaet` would be registered rather than
/// reported.
const List<String> dvPolicyActions = <String>[
  'viewAny',
  'view',
  'create',
  'update',
  'delete',
  'restore',
  'forceDelete',
  'export',
  'impersonate',
];

/// One conventional method on a policy class.
class DVPolicyMethod {
  const DVPolicyMethod({required this.action});

  final String action;
}

/// One `@DVPolicy(Resource) class Name { ... }`.
class DVPolicyClass {
  const DVPolicyClass({
    required this.className,
    required this.resource,
    required this.methods,
  });

  final String className;
  final String resource;
  final List<DVPolicyMethod> methods;
}

/// Every policy class [source] declares.
///
/// [relativePath] is only used in refusals, and every refusal names it: a
/// generated file cannot be edited, so the message has to point at the file
/// that can.
List<DVPolicyClass> dvPolicyClassesIn(String source, String relativePath) {
  final List<DVPolicyClass> classes = <DVPolicyClass>[];
  // `class` immediately after the annotation, rather than the annotation on
  // its own: `@DVPolicy(` inside a string literal is a real thing in this
  // repository's own site prose, and requiring the declaration after it is
  // what keeps a sentence from being parsed as a policy.
  final RegExp declaration = RegExp(
    r'@DVPolicy\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*'
    r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{',
  );
  for (final RegExpMatch match in declaration.allMatches(source)) {
    final String resource = match.group(1)!;
    final String className = match.group(2)!;
    final String body = _bodyFrom(source, match.end - 1);

    _refuseConstructorArguments(
      body: body,
      className: className,
      relativePath: relativePath,
    );

    final List<DVPolicyMethod> methods = <DVPolicyMethod>[];
    for (final RegExpMatch method in _methods.allMatches(body)) {
      final String action = method.group(2)!;
      if (!dvPolicyActions.contains(action)) continue;
      final List<String> parameters = dvSplitArgs(method.group(3)!)
          .where((String parameter) => parameter.trim().isNotEmpty)
          .toList();
      if (parameters.length != 2) {
        throw StateError(
          'The $action policy on $className in $relativePath takes '
          '${parameters.length} parameter(s). A policy method takes the user '
          'and the resource, because can(user, action, resource) always has '
          'a resource and the registry is keyed by its type -- a check '
          'without one could never be reached by the question it answers.',
        );
      }
      // `Order?` is the same resource as `Order`. A route has no order to
      // hand the policy, so a method that answers for one takes it nullable,
      // and the registry keys both under Order.
      final String taken = _typeOf(parameters[1]).replaceFirst(RegExp(r'\?$'), '');
      if (taken != resource) {
        throw StateError(
          'The $action policy on $className in $relativePath is annotated '
          '@DVPolicy($resource) and takes a $taken. The registration is '
          'typed by the method, so this would register $action for $taken -- '
          '$resource would keep failing closed while $taken is opened by a '
          'policy nobody wrote for it.',
        );
      }
      methods.add(DVPolicyMethod(action: action));
    }
    classes.add(DVPolicyClass(
      className: className,
      resource: resource,
      methods: methods,
    ));
  }
  return classes;
}

/// The body of a class whose opening brace is at [open], without it.
String _bodyFrom(String source, int open) {
  int depth = 0;
  for (int i = open; i < source.length; i++) {
    final String character = source[i];
    if (character == '{') depth++;
    if (character == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  return source.substring(open + 1);
}

/// A method declaration: a return type, a name, parameters, and a body or an
/// arrow. The tail is what keeps a call inside another method's body from
/// being read as a declaration of its own.
final RegExp _methods = RegExp(
  r'([A-Za-z_][A-Za-z0-9_<>?, ]*?)\s+'
  r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*'
  r'(?:async\s*)?(?:=>|\{)',
);

/// The type a parameter declares.
String _typeOf(String parameter) {
  final String cleaned = parameter
      .trim()
      .replaceFirst(RegExp(r'^(?:required\s+|final\s+|covariant\s+)+'), '');
  final int space = cleaned.lastIndexOf(RegExp(r'\s'));
  if (space < 0) return cleaned;
  return cleaned.substring(0, space).trim();
}

/// Refuses a policy class the generated file cannot construct.
///
/// The generated file builds one. A required argument would make it fail to
/// compile, in a file nobody wrote and nobody can fix; saying so here names
/// the file that has to change instead.
void _refuseConstructorArguments({
  required String body,
  required String className,
  required String relativePath,
}) {
  final RegExpMatch? constructor = RegExp(
    '(?:const\\s+)?$className\\s*\\(([^)]*)\\)\\s*(?:;|:|\\{)',
  ).firstMatch(body);
  if (constructor == null) return;
  final String parameters = constructor.group(1)!.trim();
  if (parameters.isEmpty) return;
  if (parameters.startsWith('{') || parameters.startsWith('[')) return;
  throw StateError(
    '$className in $relativePath cannot be built without arguments, and the '
    'generated policy registrations construct one. Give it a no-argument '
    'constructor, or make its arguments optional.',
  );
}

/// One constructor parameter of the class a policy takes.
class DVResourceParameter {
  const DVResourceParameter({
    required this.name,
    required this.type,
    required this.named,
  });

  /// The field it initialises, which is also the record value it reads.
  final String name;

  /// The field's declared type, `?` included.
  final String type;

  final bool named;
}

/// How the generated backend can build a policy's resource class from a
/// record's values: its constructor, when every parameter initialises a
/// field of the same name.
class DVResourceShape {
  const DVResourceShape(this.parameters);

  final List<DVResourceParameter> parameters;
}

/// The shape of `class [className]` declared in [source], or null when it is
/// not declared there or its constructor does anything but initialise
/// fields.
///
/// The replay route is handed a record's values and a policy written against
/// the application's own class for the model. Building that class by the
/// constructor the application wrote -- `this.id`, `this.ownerId` -- is the
/// one thing the generator can do without inventing an argument; a
/// constructor that computes something is the application's code, and is
/// left alone, so the policy is asked with the values and refuses.
DVResourceShape? dvResourceShapeIn(String source, String className) {
  final RegExpMatch? declaration = RegExp(
    r'class\s+' + RegExp.escape(className) + r'\b[^{;]*\{',
  ).firstMatch(source);
  if (declaration == null) return null;
  final String body = _bodyFrom(source, declaration.end - 1);

  final Map<String, String> fields = <String, String>{
    for (final RegExpMatch field in RegExp(
      r'final\s+([A-Za-z_][A-Za-z0-9_<>?, ]*?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*;',
    ).allMatches(body))
      field.group(2)!: field.group(1)!.trim(),
  };

  final RegExpMatch? constructor = RegExp(
    r'(?:const\s+)?' + RegExp.escape(className) + r'\s*\(',
  ).firstMatch(body);
  if (constructor == null) return null;
  int depth = 0;
  int close = -1;
  for (int i = constructor.end - 1; i < body.length; i++) {
    if (body[i] == '(') depth++;
    if (body[i] == ')') {
      depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
  }
  if (close < 0) return null;
  // An initializer list or a body computes something from the arguments.
  if (!body.substring(close + 1).trimLeft().startsWith(';')) return null;

  final String parameters = body.substring(constructor.end, close);
  final int brace = parameters.indexOf(RegExp(r'[{\[]'));
  final String positional =
      brace < 0 ? parameters : parameters.substring(0, brace);
  final String rest = brace < 0
      ? ''
      : parameters.substring(brace + 1).replaceFirst(RegExp(r'[}\]]\s*$'), '');
  final bool named = brace >= 0 && parameters[brace] == '{';

  final List<DVResourceParameter> shape = <DVResourceParameter>[];
  for (final (String part, bool isNamed) in <(String, bool)>[
    for (final String part in dvSplitArgs(positional)) (part, false),
    for (final String part in dvSplitArgs(rest)) (part, named),
  ]) {
    final RegExpMatch? initialising = RegExp(
      r'^(?:required\s+)?this\.([A-Za-z_][A-Za-z0-9_]*)\s*(?:=.*)?$',
      dotAll: true,
    ).firstMatch(part.trim());
    if (initialising == null) return null;
    final String name = initialising.group(1)!;
    final String? type = fields[name];
    if (type == null) return null;
    shape.add(DVResourceParameter(name: name, type: type, named: isNamed));
  }
  return DVResourceShape(shape);
}

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
      final String taken = _typeOf(parameters[1]);
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

/// Visual backend workflows: a serializable step tree that can be executed
/// directly or exported as an ordinary `@DVBackendFunction`.
///
/// The same bargain the page builder makes. A workflow is data, so saving it
/// publishes; and it exports to real Dart, so a project can take the builder
/// out of the loop whenever it wants.
library dartvel_core.studio.workflow;

import 'dart:async';
import 'dart:convert';

import '../database/adapter.dart';

/// Thrown when a workflow cannot run: an unknown action, a missing variable,
/// a malformed step.
///
/// Deliberately loud. A workflow that silently yields null on a typo is worse
/// than one that stops and says which step failed.
class DVWorkflowException implements Exception {
  final String message;

  /// The step that failed, when the failure belongs to one.
  final String? stepId;

  const DVWorkflowException(this.message, {this.stepId});

  @override
  String toString() => 'DVWorkflowException'
      '${stepId == null ? '' : ' (step $stepId)'}: $message';
}

/// A value a step consumes: either a literal or a reference to a variable.
///
/// `{'\$var': 'user'}` reads the variable `user`; anything else is the literal
/// itself. Keeping references explicit means a literal string that happens to
/// look like a name is never mistaken for one.
class DVWorkflowValue {
  final Object? literal;
  final String? variable;

  const DVWorkflowValue.literal(this.literal) : variable = null;
  const DVWorkflowValue.reference(String this.variable) : literal = null;

  static DVWorkflowValue fromJson(Object? json) {
    if (json is Map && json.length == 1 && json[r'$var'] is String) {
      return DVWorkflowValue.reference(json[r'$var'] as String);
    }
    return DVWorkflowValue.literal(json);
  }

  Object? toJson() =>
      variable == null ? literal : <String, Object?>{r'$var': variable};

  /// Resolves against [variables], failing loudly on an unknown name.
  Object? resolve(Map<String, Object?> variables, {String? stepId}) {
    final name = variable;
    if (name == null) return literal;
    if (!variables.containsKey(name)) {
      throw DVWorkflowException(
        'Unknown variable "$name". Declared variables: '
        '${variables.keys.join(', ')}',
        stepId: stepId,
      );
    }
    return variables[name];
  }

  /// The Dart expression for this value, for code export.
  String toDartSource() {
    if (variable != null) return variable!;
    final value = literal;
    if (value is String) {
      return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
    }
    return '$value';
  }
}

/// One step in a workflow.
class DVWorkflowStep {
  final String id;

  /// `call`, `set`, `condition`, or `return`.
  final String type;

  /// For `call`: the registered action name. For `set`: the variable name.
  final String? name;

  /// Arguments for `call`, or the single `value` for `set`/`return`.
  final Map<String, DVWorkflowValue> arguments;

  /// For `call`: the variable the result is stored in, when it is kept.
  final String? assignTo;

  /// For `condition`: the branches, keyed `then` and `else`.
  final Map<String, List<DVWorkflowStep>> branches;

  DVWorkflowStep({
    String? id,
    required this.type,
    this.name,
    Map<String, DVWorkflowValue>? arguments,
    this.assignTo,
    Map<String, List<DVWorkflowStep>>? branches,
  })  : id = id ?? _newId(),
        arguments = arguments ?? <String, DVWorkflowValue>{},
        branches = branches ?? <String, List<DVWorkflowStep>>{};

  static int _counter = 0;

  static String _newId() =>
      's${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  /// Calls a registered action, optionally keeping its result.
  factory DVWorkflowStep.call(
    String action, {
    Map<String, DVWorkflowValue> arguments = const <String, DVWorkflowValue>{},
    String? assignTo,
  }) =>
      DVWorkflowStep(
        type: 'call',
        name: action,
        arguments: arguments,
        assignTo: assignTo,
      );

  /// Assigns a value to a variable.
  factory DVWorkflowStep.set(String variable, DVWorkflowValue value) =>
      DVWorkflowStep(
        type: 'set',
        name: variable,
        arguments: <String, DVWorkflowValue>{'value': value},
      );

  /// Branches on the truthiness of `condition`.
  factory DVWorkflowStep.condition(
    DVWorkflowValue condition, {
    List<DVWorkflowStep> then = const <DVWorkflowStep>[],
    List<DVWorkflowStep> otherwise = const <DVWorkflowStep>[],
  }) =>
      DVWorkflowStep(
        type: 'condition',
        arguments: <String, DVWorkflowValue>{'condition': condition},
        branches: <String, List<DVWorkflowStep>>{
          'then': then,
          'else': otherwise,
        },
      );

  /// Ends the workflow with a value.
  factory DVWorkflowStep.returns(DVWorkflowValue value) => DVWorkflowStep(
        type: 'return',
        arguments: <String, DVWorkflowValue>{'value': value},
      );

  factory DVWorkflowStep.fromJson(Map<String, Object?> json) => DVWorkflowStep(
        id: json['id'] as String?,
        type: json['type']! as String,
        name: json['name'] as String?,
        assignTo: json['assignTo'] as String?,
        arguments: <String, DVWorkflowValue>{
          for (final entry
              in ((json['arguments'] as Map?) ?? const <Object?, Object?>{})
                  .entries)
            '${entry.key}': DVWorkflowValue.fromJson(entry.value),
        },
        branches: <String, List<DVWorkflowStep>>{
          for (final entry
              in ((json['branches'] as Map?) ?? const <Object?, Object?>{})
                  .entries)
            '${entry.key}': <DVWorkflowStep>[
              for (final step in entry.value! as List)
                DVWorkflowStep.fromJson((step! as Map).cast<String, Object?>()),
            ],
        },
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        if (name != null) 'name': name,
        if (assignTo != null) 'assignTo': assignTo,
        if (arguments.isNotEmpty)
          'arguments': <String, Object?>{
            for (final entry in arguments.entries)
              entry.key: entry.value.toJson(),
          },
        if (branches.isNotEmpty)
          'branches': <String, Object?>{
            for (final entry in branches.entries)
              entry.key: <Object?>[
                for (final step in entry.value) step.toJson(),
              ],
          },
      };
}

/// A builder-editable backend function.
class DVWorkflowDocument {
  /// The generated function's name, and the key it is stored under.
  final String name;

  /// Input parameter names. They arrive as variables when the workflow runs.
  final List<String> parameters;

  final List<DVWorkflowStep> steps;

  DVWorkflowDocument({
    required this.name,
    List<String>? parameters,
    List<DVWorkflowStep>? steps,
  })  : parameters = parameters ?? <String>[],
        steps = steps ?? <DVWorkflowStep>[];

  factory DVWorkflowDocument.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw ArgumentError.value(
        json,
        'json',
        'A workflow needs a non-empty "name": it is both the generated '
            'function name and the key it is stored under.',
      );
    }
    return DVWorkflowDocument(
      name: name,
      parameters: <String>[
        for (final p in (json['parameters'] as List?) ?? const <Object?>[])
          p! as String,
      ],
      steps: <DVWorkflowStep>[
        for (final step in (json['steps'] as List?) ?? const <Object?>[])
          DVWorkflowStep.fromJson((step! as Map).cast<String, Object?>()),
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'parameters': parameters,
        'steps': <Object?>[for (final step in steps) step.toJson()],
      };

  /// Full code export: the workflow as an ordinary private
  /// `@DVBackendFunction`, the same shape a hand-written one has.
  ///
  /// Actions become calls to functions of the same name, so an exported
  /// workflow depends on the same code the runner called — not on any part
  /// of the builder.
  String toDartSource() {
    final buffer = StringBuffer()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln()
      ..writeln('// Exported from Dartvel Studio. Ordinary backend function:')
      ..writeln('// edit freely, the builder is no longer involved.')
      ..writeln('@DVBackendFunction()')
      ..writeln("@pragma('vm:entry-point')")
      // The generator requires a private backend function to be
      // expression-bodied until body lowering exists, so the steps live in a
      // public helper — the same shape the spec documents for pages that need
      // a larger body.
      ..writeln(
        'Future<Object?> _$name('
        '${parameters.map((String p) => 'Object? $p').join(', ')}'
        ') => ${name}Body(${parameters.join(', ')});',
      )
      ..writeln()
      ..writeln(
        'Future<Object?> ${name}Body('
        '${parameters.map((String p) => 'Object? $p').join(', ')}'
        ') async {',
      );
    for (final step in steps) {
      _writeStep(buffer, step, 1);
    }
    // The trailing return is only emitted when the body can actually fall
    // through; after an unconditional return it would be dead code the
    // analyzer rejects.
    if (steps.isEmpty || steps.last.type != 'return') {
      buffer.writeln('  return null;');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  void _writeStep(StringBuffer buffer, DVWorkflowStep step, int depth) {
    final pad = '  ' * depth;
    switch (step.type) {
      case 'set':
        buffer.writeln(
          '${pad}final ${step.name} = '
          '${step.arguments['value']!.toDartSource()};',
        );
      case 'call':
        final args = step.arguments.entries
            .map((MapEntry<String, DVWorkflowValue> e) =>
                '${e.key}: ${e.value.toDartSource()}')
            .join(', ');
        final call = 'await ${step.name}($args)';
        buffer.writeln(
          step.assignTo == null
              ? '$pad$call;'
              : '${pad}final ${step.assignTo} = $call;',
        );
      case 'condition':
        buffer.writeln(
          '${pad}if (${step.arguments['condition']!.toDartSource()} == true) {',
        );
        for (final child in step.branches['then'] ?? const <DVWorkflowStep>[]) {
          _writeStep(buffer, child, depth + 1);
        }
        final otherwise = step.branches['else'] ?? const <DVWorkflowStep>[];
        if (otherwise.isEmpty) {
          buffer.writeln('$pad}');
        } else {
          buffer.writeln('$pad} else {');
          for (final child in otherwise) {
            _writeStep(buffer, child, depth + 1);
          }
          buffer.writeln('$pad}');
        }
      case 'return':
        buffer.writeln(
          '${pad}return ${step.arguments['value']!.toDartSource()};',
        );
      default:
        throw DVWorkflowException(
          'Cannot export a step of unknown type "${step.type}".',
          stepId: step.id,
        );
    }
  }
}

/// The registry of actions a workflow may call, and the runner that executes
/// one.
class DVWorkflows {
  DVWorkflows._();

  static final Map<String, Future<Object?> Function(Map<String, Object?>)>
      _actions = {};

  /// Registers an action a workflow step can call by name.
  ///
  /// Generated backend functions register themselves here, so a workflow can
  /// call the same code an application does.
  static void registerAction(
    String name,
    Future<Object?> Function(Map<String, Object?> arguments) handler,
  ) {
    _actions[name] = handler;
  }

  /// The action names currently callable.
  static Set<String> get actions => _actions.keys.toSet();

  static void reset() => _actions.clear();

  /// Runs [document] with [input] bound to its parameters.
  ///
  /// Returns whatever a `return` step produced, or null when none ran.
  static Future<Object?> run(
    DVWorkflowDocument document, {
    Map<String, Object?> input = const <String, Object?>{},
  }) async {
    final missing = document.parameters
        .where((String p) => !input.containsKey(p))
        .toList();
    if (missing.isNotEmpty) {
      throw DVWorkflowException(
        'Missing input for ${missing.join(', ')}. '
        'Workflow "${document.name}" declares '
        '${document.parameters.join(', ')}.',
      );
    }

    final variables = <String, Object?>{
      for (final parameter in document.parameters)
        parameter: input[parameter],
    };
    final result = await _runSteps(document.steps, variables);
    return result.returned ? result.value : null;
  }

  static Future<({bool returned, Object? value})> _runSteps(
    List<DVWorkflowStep> steps,
    Map<String, Object?> variables,
  ) async {
    for (final step in steps) {
      switch (step.type) {
        case 'set':
          final value = step.arguments['value'];
          if (value == null || step.name == null) {
            throw DVWorkflowException(
              'A set step needs a variable name and a value.',
              stepId: step.id,
            );
          }
          variables[step.name!] = value.resolve(variables, stepId: step.id);
        case 'call':
          final handler = _actions[step.name];
          if (handler == null) {
            throw DVWorkflowException(
              'No action named "${step.name}". Registered: '
              '${_actions.keys.join(', ')}',
              stepId: step.id,
            );
          }
          final arguments = <String, Object?>{
            for (final entry in step.arguments.entries)
              entry.key: entry.value.resolve(variables, stepId: step.id),
          };
          final value = await handler(arguments);
          if (step.assignTo != null) variables[step.assignTo!] = value;
        case 'condition':
          final condition = step.arguments['condition'];
          if (condition == null) {
            throw DVWorkflowException(
              'A condition step needs a condition.',
              stepId: step.id,
            );
          }
          final branch =
              condition.resolve(variables, stepId: step.id) == true
                  ? 'then'
                  : 'else';
          final result = await _runSteps(
            step.branches[branch] ?? const <DVWorkflowStep>[],
            variables,
          );
          // A return inside a branch ends the whole workflow, not just the
          // branch.
          if (result.returned) return result;
        case 'return':
          final value = step.arguments['value'];
          if (value == null) {
            throw DVWorkflowException(
              'A return step needs a value.',
              stepId: step.id,
            );
          }
          return (
            returned: true,
            value: value.resolve(variables, stepId: step.id),
          );
        default:
          throw DVWorkflowException(
            'Unknown step type "${step.type}".',
            stepId: step.id,
          );
      }
    }
    return (returned: false, value: null);
  }
}

/// Stores workflow documents, the way `DVPageStore` stores pages: saving
/// publishes, because a workflow is data.
class DVWorkflowStore {
  static const String table = 'dartvel_workflows';

  const DVWorkflowStore();

  static final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// Workflow names whose document changed.
  static Stream<String> get changes => _changes.stream;

  Future<void> _initialize() async {
    await const DVDatabase().execute(
      'CREATE TABLE IF NOT EXISTS $table (name TEXT, document TEXT)',
    );
  }

  Future<void> save(DVWorkflowDocument document) async {
    await _initialize();
    const database = DVDatabase();
    await database.execute(
      'DELETE FROM $table WHERE name = ?',
      <Object?>[document.name],
    );
    await database.execute(
      'INSERT INTO $table (name, document) VALUES (?, ?)',
      <Object?>[document.name, jsonEncode(document.toJson())],
    );
    _changes.add(document.name);
  }

  Future<DVWorkflowDocument?> load(String name) async {
    await _initialize();
    final rows = await const DVDatabase().query(
      'SELECT document FROM $table WHERE name = ?',
      <Object?>[name],
    );
    if (rows.isEmpty) return null;
    return DVWorkflowDocument.fromJson(
      (jsonDecode(rows.first['document']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<List<String>> names() async {
    await _initialize();
    final rows = await const DVDatabase().query('SELECT name FROM $table');
    return <String>[for (final row in rows) row['name']! as String]..sort();
  }

  Future<void> delete(String name) async {
    await _initialize();
    await const DVDatabase().execute(
      'DELETE FROM $table WHERE name = ?',
      <Object?>[name],
    );
    _changes.add(name);
  }
}

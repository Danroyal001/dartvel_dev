/// What a windowed client may be served: the classification of every change
/// between its contract and the current one, the plan for each version in the
/// window, and the adapters that serve a degraded response.
library dartvel_core.protocol.compatibility;

import '../diagnostics/diagnostics.dart';
import '../observability/logging.dart';
import 'contract.dart';

/// The outcome of a handshake, and of every call a client makes.
enum DVProtocolResult {
  /// The client speaks the current contract.
  compatible,

  /// The client is inside the window. Its responses are adapted, and only in
  /// ways that stay true in its own vocabulary.
  degraded,

  /// The client is outside the window, or inside it with a change no adapter
  /// may make on its behalf.
  upgradeRequired,
}

enum DVProtocolChangeKind {
  modelAdded,
  modelRemoved,
  syncChanged,
  fieldAdded,
  fieldRemoved,
  fieldRenamed,
  fieldTypeChanged,
  enumAdded,
  enumRemoved,
  enumMemberAdded,
  enumMemberRemoved,
  functionAdded,
  functionRemoved,
  parameterAdded,
  parameterRemoved,
  parameterRenamed,
  parameterTypeChanged,
  returnTypeChanged,
}

/// Whether an adapter may make a change on an old client's behalf.
enum DVProtocolChangeSafety {
  /// It only hides what the old client never knew: a field its shape does not
  /// contain, an argument it does not send that has a default, a member mapped
  /// to a declared fallback it knows, or something it never calls.
  hidden,

  /// It would change the meaning of something the old client understands.
  /// Served only through a declared adapter (`DV-PROTO-004` without one).
  lossy,

  /// An enum member the old client cannot be handed and no fallback it knows.
  /// Not a guess: the client is told to upgrade (`DV-PROTO-006`).
  upgradeRequired,
}

/// One difference between an old contract and the current one.
class DVProtocolChange {
  const DVProtocolChange(this.kind, this.subject, this.safety, this.detail);

  final DVProtocolChangeKind kind;

  /// What changed, in the form a [DVProtocolAdapter] names it: `User` for a
  /// model, `User.email` for a field, `Role.guest` for an enum member,
  /// `createUser` for a function, `createUser.role` for a parameter and
  /// `createUser.returns` for a return type.
  final String subject;
  final DVProtocolChangeSafety safety;
  final String detail;

  @override
  String toString() => '$subject: $detail (${safety.name})';
}

/// Compares two contracts.
abstract final class DVProtocolDiff {
  /// Every change from [old] to [current], each classified by what an adapter
  /// may do about it without an explicit opt-in.
  static List<DVProtocolChange> between(
    DVProtocolContract old,
    DVProtocolContract current,
  ) {
    final List<DVProtocolChange> changes = <DVProtocolChange>[];

    for (final DVProtocolModel model in current.models) {
      final DVProtocolModel? before = old.model(model.name);
      if (before == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.modelAdded,
            model.name,
            DVProtocolChangeSafety.hidden,
            'model added',
          ),
        );
        continue;
      }
      if (before.synced != model.synced) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.syncChanged,
            model.name,
            // An old client subscribed to a stream that no longer comes is
            // told nothing; one that never subscribed loses nothing.
            before.synced
                ? DVProtocolChangeSafety.lossy
                : DVProtocolChangeSafety.hidden,
            before.synced ? 'model stopped syncing' : 'model started syncing',
          ),
        );
      }
      _members(
        changes,
        owner: model.name,
        before: before.fields,
        after: model.fields,
        parameters: false,
      );
    }
    for (final DVProtocolModel before in old.models) {
      if (current.model(before.name) == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.modelRemoved,
            before.name,
            DVProtocolChangeSafety.lossy,
            'model removed',
          ),
        );
      }
    }

    for (final DVProtocolEnum enumeration in current.enums) {
      final DVProtocolEnum? before = old.enumNamed(enumeration.name);
      if (before == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.enumAdded,
            enumeration.name,
            DVProtocolChangeSafety.hidden,
            'enum added',
          ),
        );
        continue;
      }
      final String? fallback = enumeration.fallback;
      final bool fallbackKnown =
          fallback != null &&
          enumeration.members.contains(fallback) &&
          before.members.contains(fallback);
      for (final String member in enumeration.members) {
        if (before.members.contains(member)) continue;
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.enumMemberAdded,
            '${enumeration.name}.$member',
            fallbackKnown
                ? DVProtocolChangeSafety.hidden
                : DVProtocolChangeSafety.upgradeRequired,
            fallbackKnown
                ? 'member added; served to old clients as $fallback'
                : fallback == null
                ? 'member added and ${enumeration.name} declares no fallback'
                : 'member added and the fallback $fallback is not a member '
                      'old clients know',
          ),
        );
      }
      for (final String member in before.members) {
        if (enumeration.members.contains(member)) continue;
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.enumMemberRemoved,
            '${enumeration.name}.$member',
            DVProtocolChangeSafety.lossy,
            'member removed; old clients still send and expect it',
          ),
        );
      }
    }
    for (final DVProtocolEnum before in old.enums) {
      if (current.enumNamed(before.name) == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.enumRemoved,
            before.name,
            DVProtocolChangeSafety.lossy,
            'enum removed',
          ),
        );
      }
    }

    for (final DVProtocolFunction function in current.functions) {
      final DVProtocolFunction? before = old.function(function.name);
      if (before == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.functionAdded,
            function.name,
            DVProtocolChangeSafety.hidden,
            'function added',
          ),
        );
        continue;
      }
      _members(
        changes,
        owner: function.name,
        before: before.parameters,
        after: function.parameters,
        parameters: true,
      );
      if (before.returns != function.returns) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.returnTypeChanged,
            '${function.name}.returns',
            DVProtocolChangeSafety.lossy,
            'return type changed from ${before.returns} to ${function.returns}',
          ),
        );
      }
    }
    for (final DVProtocolFunction before in old.functions) {
      if (current.function(before.name) == null) {
        changes.add(
          DVProtocolChange(
            DVProtocolChangeKind.functionRemoved,
            before.name,
            DVProtocolChangeSafety.lossy,
            'function removed',
          ),
        );
      }
    }
    return changes;
  }

  static void _members(
    List<DVProtocolChange> changes, {
    required String owner,
    required List<DVProtocolField> before,
    required List<DVProtocolField> after,
    required bool parameters,
  }) {
    DVProtocolField? find(List<DVProtocolField> in_, String name) {
      for (final DVProtocolField f in in_) {
        if (f.name == name) return f;
      }
      return null;
    }

    final String noun = parameters ? 'argument' : 'field';
    final Set<String> accounted = <String>{};
    for (final DVProtocolField field in after) {
      final String subject = '$owner.${field.name}';
      final DVProtocolField? same = find(before, field.name);
      if (same != null) {
        accounted.add(same.name);
        if (same.type != field.type) {
          changes.add(
            DVProtocolChange(
              parameters
                  ? DVProtocolChangeKind.parameterTypeChanged
                  : DVProtocolChangeKind.fieldTypeChanged,
              subject,
              // Either direction changes what an old client reads or sends: a
              // wider type hands it values it cannot decode, a narrower one
              // refuses values it still sends.
              DVProtocolChangeSafety.lossy,
              '$noun type changed from ${same.type} to ${field.type}',
            ),
          );
        }
        continue;
      }
      final String? from = field.renamedFrom;
      final DVProtocolField? renamed = from == null ? null : find(before, from);
      if (renamed != null && find(after, from!) == null) {
        accounted.add(from);
        final bool sameType = renamed.type == field.type;
        changes.add(
          DVProtocolChange(
            parameters
                ? DVProtocolChangeKind.parameterRenamed
                : DVProtocolChangeKind.fieldRenamed,
            subject,
            sameType
                ? DVProtocolChangeSafety.hidden
                : DVProtocolChangeSafety.lossy,
            sameType
                ? '$noun renamed from $from'
                : '$noun renamed from $from and its type changed from '
                      '${renamed.type} to ${field.type}',
          ),
        );
        continue;
      }
      final bool optional = field.nullable || field.hasDefault;
      changes.add(
        DVProtocolChange(
          parameters
              ? DVProtocolChangeKind.parameterAdded
              : DVProtocolChangeKind.fieldAdded,
          subject,
          optional
              ? DVProtocolChangeSafety.hidden
              : DVProtocolChangeSafety.lossy,
          optional
              ? '$noun added'
              : 'required $noun added with no default; old clients do not send '
                    'it',
        ),
      );
    }
    for (final DVProtocolField field in before) {
      if (accounted.contains(field.name)) continue;
      changes.add(
        DVProtocolChange(
          parameters
              ? DVProtocolChangeKind.parameterRemoved
              : DVProtocolChangeKind.fieldRemoved,
          '$owner.${field.name}',
          DVProtocolChangeSafety.lossy,
          '$noun removed; old clients still read or send it',
        ),
      );
    }
  }
}

/// A declared, reviewed adaptation for a lossy change.
///
/// [from] is the old protocol version it serves and [subject] the change it
/// covers, named as [DVProtocolChange.subject] names it. An adapter for one
/// version does not cover another: the same subject can mean a different
/// change against a different old contract.
class DVProtocolAdapter {
  const DVProtocolAdapter({
    required this.from,
    required this.subject,
    this.response,
    this.request,
  });

  final int from;
  final String subject;

  /// Converts a current value into what the old client reads.
  final Object? Function(Object? value)? response;

  /// Converts what the old client sent into a current value.
  final Object? Function(Object? value)? request;
}

/// A finding from building a plan: `DV-PROTO-004` or `DV-PROTO-006`.
class DVProtocolProblem {
  const DVProtocolProblem(this.code, this.protocol, this.message);

  final String code;

  /// The old protocol version the problem is about.
  final int protocol;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// What one served protocol version gets.
class DVProtocolVersionPlan {
  const DVProtocolVersionPlan({
    required this.protocol,
    required this.result,
    required this.changes,
  });

  final int protocol;
  final DVProtocolResult result;
  final List<DVProtocolChange> changes;
}

/// The plan for every version in the window, built eagerly from the lockfile.
///
/// Built for every served version up front rather than per observed client:
/// an adaptation derived in response to a request from a stale client runs
/// along a path no test ever ran. The set is bounded by the window, and every
/// lossy change without a declared adapter is a finding here, before anything
/// is served.
class DVProtocolPlan {
  DVProtocolPlan._({
    required this.current,
    required this.versions,
    required this.errors,
    required this.warnings,
    required Map<int, DVProtocolAdapterSet> adapters,
  }) : _adapters = adapters;

  factory DVProtocolPlan.build({
    required DVProtocolLock lock,
    DVProtocolWindow window = const DVProtocolWindow(),
    required DateTime now,
    List<DVProtocolAdapter> adapters = const <DVProtocolAdapter>[],
    void Function(String code, String message)? onDiagnostic,
  }) {
    final DVProtocolRelease? latest = lock.current;
    if (latest == null) {
      throw StateError('no protocol version is recorded in the lockfile');
    }
    final void Function(String, String) diagnose =
        onDiagnostic ?? dvLogProtocolDiagnostic;
    final Map<int, DVProtocolVersionPlan> versions =
        <int, DVProtocolVersionPlan>{};
    final Map<int, DVProtocolAdapterSet> sets = <int, DVProtocolAdapterSet>{};
    final List<DVProtocolProblem> errors = <DVProtocolProblem>[];
    final List<DVProtocolProblem> warnings = <DVProtocolProblem>[];
    final Set<String> warned = <String>{};

    final List<int> served = window.served(lock, now: now).toList()..sort();
    for (final int protocol in served) {
      final DVProtocolContract old = lock.release(protocol)!.contract;
      final List<DVProtocolChange> changes = DVProtocolDiff.between(
        old,
        latest.contract,
      );
      final List<DVProtocolAdapter> declared = <DVProtocolAdapter>[
        for (final DVProtocolAdapter a in adapters)
          if (a.from == protocol) a,
      ];
      final Set<String> covered = <String>{
        for (final DVProtocolAdapter a in declared) a.subject,
      };
      DVProtocolResult result = changes.isEmpty
          ? DVProtocolResult.compatible
          : DVProtocolResult.degraded;
      for (final DVProtocolChange change in changes) {
        if (change.safety == DVProtocolChangeSafety.hidden ||
            covered.contains(change.subject)) {
          continue;
        }
        result = DVProtocolResult.upgradeRequired;
        if (change.safety == DVProtocolChangeSafety.lossy) {
          errors.add(
            DVProtocolProblem(
              'DV-PROTO-004',
              protocol,
              'protocol $protocol is in the window and ${change.subject} needs '
                  'a lossy adaptation with no declared adapter: ${change.detail}',
            ),
          );
        } else if (warned.add(change.subject)) {
          warnings.add(
            DVProtocolProblem(
              'DV-PROTO-006',
              protocol,
              '${change.subject}: ${change.detail}; clients on protocol '
                  '$protocol and older are narrowed out of the window',
            ),
          );
        }
      }
      versions[protocol] = DVProtocolVersionPlan(
        protocol: protocol,
        result: result,
        changes: changes,
      );
      if (result == DVProtocolResult.degraded) {
        sets[protocol] = DVProtocolAdapterSet._(
          protocol: protocol,
          old: old,
          current: latest.contract,
          adapters: declared,
          diagnose: diagnose,
        );
      }
    }
    return DVProtocolPlan._(
      current: latest.protocol,
      versions: versions,
      errors: errors,
      warnings: warnings,
      adapters: sets,
    );
  }

  /// The backend's protocol version.
  final int current;

  /// Every served version, keyed by protocol.
  final Map<int, DVProtocolVersionPlan> versions;

  /// `DV-PROTO-004` findings. A build with any fails.
  final List<DVProtocolProblem> errors;

  /// `DV-PROTO-006` findings.
  final List<DVProtocolProblem> warnings;

  final Map<int, DVProtocolAdapterSet> _adapters;

  /// What a client on [client] gets, or null when it is ahead of this backend
  /// -- a state the backend cannot adapt to, because the shape it would need
  /// to produce is one it has never seen.
  DVProtocolResult? resultFor(int client) {
    if (client > current) return null;
    return versions[client]?.result ?? DVProtocolResult.upgradeRequired;
  }

  /// The adapters for a degraded client, or null when it needs none (it is
  /// current) or is served nothing (it must upgrade).
  DVProtocolAdapterSet? adapterFor(int client) => _adapters[client];
}

/// Serves one degraded protocol version.
class DVProtocolAdapterSet {
  DVProtocolAdapterSet._({
    required this.protocol,
    required DVProtocolContract old,
    required DVProtocolContract current,
    required List<DVProtocolAdapter> adapters,
    required void Function(String code, String message) diagnose,
  }) : _old = old,
       _current = current,
       _declared = <String, DVProtocolAdapter>{
         for (final DVProtocolAdapter a in adapters) a.subject: a,
       },
       _diagnose = diagnose;

  /// The old protocol version this set serves.
  final int protocol;
  final DVProtocolContract _old;
  final DVProtocolContract _current;
  final Map<String, DVProtocolAdapter> _declared;
  final void Function(String code, String message) _diagnose;

  /// A current record of [model], in the old client's vocabulary.
  Object? model(String model, Object? value) {
    _report(model);
    return _modelToOld(model, value);
  }

  /// A backend function's current result, in the old client's vocabulary.
  Object? result(String function, Object? value) {
    final DVProtocolFunction? declared = _current.function(function);
    if (declared == null) return value;
    _report(function);
    final Object? Function(Object?)? adapt =
        _declared['$function.returns']?.response;
    return adapt != null ? adapt(value) : _toOld(declared.returns, value);
  }

  /// The arguments an old client sent, as the current function reads them.
  ///
  /// An argument the old client does not send is left absent, so the
  /// function's own default supplies it -- the server-side default, not one
  /// restated here.
  Map<String, Object?> arguments(String function, Map<String, Object?> args) {
    final DVProtocolFunction? current = _current.function(function);
    final DVProtocolFunction? old = _old.function(function);
    if (current == null || old == null) return Map<String, Object?>.of(args);
    final Map<String, String> renamed = <String, String>{
      for (final DVProtocolField p in current.parameters)
        if (p.renamedFrom != null &&
            old.parameter(p.renamedFrom!) != null &&
            current.parameter(p.renamedFrom!) == null)
          p.renamedFrom!: p.name,
    };
    Map<String, Object?> out = <String, Object?>{};
    args.forEach((String key, Object? value) {
      final String target = renamed[key] ?? key;
      final DVProtocolField? parameter = current.parameter(target);
      final Object? Function(Object?)? adapt =
          _declared['$function.$target']?.request;
      out[target] = adapt != null
          ? adapt(value)
          : parameter == null
          ? value
          : _toCurrent(parameter.type, value);
    });
    final Object? Function(Object?)? whole = _declared[function]?.request;
    if (whole != null) {
      out = (whole(out)! as Map<Object?, Object?>).cast<String, Object?>();
    }
    return out;
  }

  void _report(String subject) {
    _diagnose(
      'DV-PROTO-003',
      'response degraded for a windowed client: $subject served to protocol '
          '$protocol',
    );
  }

  Object? _toOld(String type, Object? value) {
    if (value == null) return null;
    final String t = type.endsWith('?')
        ? type.substring(0, type.length - 1)
        : type;
    final String? listOf = _inner(t, 'List');
    if (listOf != null && value is List) {
      return <Object?>[for (final Object? item in value) _toOld(listOf, item)];
    }
    final String? mapOf = _mapValue(t);
    if (mapOf != null && value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': _toOld(mapOf, e.value),
      };
    }
    final DVProtocolEnum? enumeration = _current.enumNamed(t);
    if (enumeration != null && value is String) {
      final DVProtocolEnum? before = _old.enumNamed(t);
      if (before == null || before.members.contains(value)) return value;
      final Object? Function(Object?)? adapt = _declared['$t.$value']?.response;
      if (adapt != null) return adapt(value);
      final String? fallback = enumeration.fallback;
      if (fallback != null && before.members.contains(fallback)) {
        return fallback;
      }
      // The plan refuses to degrade a version with this change, so reaching
      // here means an adapter set was used for a version it was not built
      // for. Never guess a member.
      throw StateError('$t.$value has no fallback protocol $protocol knows');
    }
    if (_current.model(t) != null) return _modelToOld(t, value);
    return value;
  }

  Object? _modelToOld(String name, Object? value) {
    if (value is! Map) return value;
    final DVProtocolModel? model = _current.model(name);
    final DVProtocolModel? before = _old.model(name);
    if (model == null || before == null) return value;
    final Object? Function(Object?)? whole = _declared[name]?.response;
    if (whole != null) return whole(value);
    final Map<String, Object?> out = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final String key = '${entry.key}';
      final DVProtocolField? field = model.field(key);
      if (field == null) {
        // Not part of the contract, so no rule of the contract's applies.
        out[key] = entry.value;
        continue;
      }
      final String? oldName = before.field(key) != null
          ? key
          : (field.renamedFrom != null &&
                before.field(field.renamedFrom!) != null)
          ? field.renamedFrom
          : null;
      // A field the old shape does not contain: omitted.
      if (oldName == null) continue;
      final Object? Function(Object?)? adapt =
          _declared['$name.$key']?.response;
      out[oldName] = adapt != null
          ? adapt(entry.value)
          : _toOld(field.type, entry.value);
    }
    return out;
  }

  Object? _toCurrent(String type, Object? value) {
    if (value == null) return null;
    final String t = type.endsWith('?')
        ? type.substring(0, type.length - 1)
        : type;
    final String? listOf = _inner(t, 'List');
    if (listOf != null && value is List) {
      return <Object?>[
        for (final Object? item in value) _toCurrent(listOf, item),
      ];
    }
    final String? mapOf = _mapValue(t);
    if (mapOf != null && value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': _toCurrent(mapOf, e.value),
      };
    }
    final DVProtocolModel? model = _current.model(t);
    final DVProtocolModel? before = _old.model(t);
    if (model == null || before == null || value is! Map) return value;
    final Object? Function(Object?)? whole = _declared[t]?.request;
    if (whole != null) return whole(value);
    final Map<String, String> renamed = <String, String>{
      for (final DVProtocolField f in model.fields)
        if (f.renamedFrom != null &&
            before.field(f.renamedFrom!) != null &&
            model.field(f.renamedFrom!) == null)
          f.renamedFrom!: f.name,
    };
    final Map<String, Object?> out = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final String key = renamed['${entry.key}'] ?? '${entry.key}';
      final DVProtocolField? field = model.field(key);
      final Object? Function(Object?)? adapt = _declared['$t.$key']?.request;
      out[key] = adapt != null
          ? adapt(entry.value)
          : field == null
          ? entry.value
          : _toCurrent(field.type, entry.value);
    }
    return out;
  }

  static String? _inner(String type, String generic) {
    final String open = '$generic<';
    if (!type.startsWith(open) || !type.endsWith('>')) return null;
    return type.substring(open.length, type.length - 1).trim();
  }

  static String? _mapValue(String type) {
    final String? inner = _inner(type, 'Map');
    if (inner == null) return null;
    final int comma = inner.indexOf(',');
    return comma == -1 ? null : inner.substring(comma + 1).trim();
  }
}

final DVLogger _protocolLogger = DVLogger();

/// The default diagnostic sink: the log, at the level the registry assigns.
void dvLogProtocolDiagnostic(String code, String message) {
  final String level = DVDiagnostics.find(code)?.level ?? 'warning';
  _protocolLogger.log(
    '$code: $message',
    level: switch (level) {
      'debug' => DVLogLevel.debug,
      'info' => DVLogLevel.info,
      'error' => DVLogLevel.error,
      _ => DVLogLevel.warn,
    },
  );
}

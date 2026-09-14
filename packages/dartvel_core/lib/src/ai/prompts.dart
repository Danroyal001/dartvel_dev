/// Prompts as versioned assets: typed on both sides, fingerprinted, locked
/// against edits that do not move the version, and overridable from a store
/// the way page documents are.
///
/// The repository is the source of truth. The store is how a wording fix gets
/// out without a release, and every stored version is checked against what
/// the repository has recorded, because a version only the store holds is
/// one the next export-less deploy loses.
library dartvel_core.ai.prompts;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../observability/observability.dart';
import 'ai.dart';

/// A declaration the AI operations layer refuses, carrying its diagnostic
/// code (`DV-AIOPS-005`, `DV-AIOPS-006`).
class DVAIOpsError implements Exception {
  const DVAIOpsError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Marks a prompt: `@DVPrompt(id: 'ticket.summary', version: 4)`.
class DVPrompt {
  const DVPrompt({required this.id, required this.version});

  final String id;
  final int version;
}

/// A prompt as it is written in source.
class DVPromptTemplate {
  const DVPromptTemplate({
    required this.system,
    this.input = const <String, Type>{},
    this.output,
    this.schema = const <String, DVJsonValue>{},
  });

  final String system;

  /// The inputs the call site passes, by name and type.
  final Map<String, Type> input;

  /// The type the output is read into. Recorded by name in the fingerprint.
  final Type? output;

  /// The JSON Schema a structured answer is requested with. Empty means the
  /// prompt is answered as plain text.
  final DVJsonObject schema;
}

/// Where a resolved prompt came from.
enum DVPromptSource { compiled, stored }

/// One version of one prompt, in a form that can be stored, locked and
/// compared.
///
/// Types become their names here, because a store holds text; that is also
/// why a stored version cannot change the shape a call site was compiled
/// against.
class DVPromptVersion {
  DVPromptVersion({
    required this.id,
    required this.version,
    required this.system,
    Map<String, String> input = const <String, String>{},
    this.output,
    DVJsonObject schema = const <String, DVJsonValue>{},
  })  : input = Map<String, String>.unmodifiable(input),
        schema = Map<String, DVJsonValue>.unmodifiable(schema) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'a prompt needs an id');
    }
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'versions start at 1');
    }
  }

  factory DVPromptVersion.compiled(DVPrompt prompt, DVPromptTemplate template) =>
      DVPromptVersion(
        id: prompt.id,
        version: prompt.version,
        system: template.system,
        input: <String, String>{
          for (final MapEntry<String, Type> entry in template.input.entries)
            entry.key: '${entry.value}',
        },
        output: template.output == null ? null : '${template.output}',
        schema: template.schema,
      );

  final String id;
  final int version;
  final String system;
  final Map<String, String> input;
  final String? output;
  final DVJsonObject schema;

  /// A digest of what the call site depends on: input names and types, the
  /// output type and the schema. Declaration order does not move it.
  String get shape => dvCanonicalDigest(<String, Object?>{
        'input': input,
        'output': output,
        'schema': DVJsonCodec.toJsonObject(schema),
      });

  /// A digest of everything a model sees from this version: the wording and
  /// the shape. Two versions with one fingerprint are the same prompt.
  String get fingerprint => dvCanonicalDigest(<String, Object?>{
        'system': system,
        'shape': shape,
      });

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'version': version,
        'system': system,
        'input': input,
        if (output != null) 'output': output,
        'schema': DVJsonCodec.toJsonObject(schema),
      };

  factory DVPromptVersion.fromJson(Map<String, Object?> json) =>
      DVPromptVersion(
        id: json['id']! as String,
        version: json['version']! as int,
        system: json['system']! as String,
        input: <String, String>{
          for (final MapEntry<String, Object?> entry
              in ((json['input'] as Map<String, Object?>?) ??
                      const <String, Object?>{})
                  .entries)
            entry.key: entry.value! as String,
        },
        output: json['output'] as String?,
        schema: DVJsonCodec.fromJsonObject(
            (json['schema'] as Map<String, Object?>?) ??
                const <String, Object?>{}),
      );

  @override
  String toString() => 'DVPromptVersion($id@$version)';
}

/// A SHA-256 over [value] encoded with every map's keys sorted, so the digest
/// depends on content and never on insertion order.
String dvCanonicalDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(dvCanonicalJson(value)))).toString();

/// [value] with every map's keys sorted, recursively.
Object? dvCanonicalJson(Object? value) {
  if (value is Map) {
    final List<String> keys = <String>[
      for (final Object? key in value.keys) '$key',
    ]..sort();
    return <String, Object?>{
      for (final String key in keys) key: dvCanonicalJson(value[key]),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final Object? item in value) dvCanonicalJson(item)];
  }
  return value;
}

/// One version as the lockfile records it.
class DVPromptLockEntry {
  const DVPromptLockEntry({required this.version, required this.fingerprint});

  final int version;
  final String fingerprint;
}

/// What checking prompts against the lockfile, or the store against the
/// repository, found.
class DVPromptLockProblem {
  const DVPromptLockProblem({
    required this.code,
    required this.promptId,
    required this.version,
    required this.message,
  });

  /// `DV-AIOPS-006` from the lockfile, `DV-AIOPS-001` from a store audit.
  final String code;
  final String promptId;
  final int version;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// The committed prompt lockfile, `dartvel.prompts.lock`: every version each
/// prompt has had, and the fingerprint it had.
///
/// It is what makes "edited without incrementing the version" checkable. The
/// source only holds the current version; without a record of what version 4
/// said, version 4 with new wording is indistinguishable from version 4.
class DVPromptLock {
  const DVPromptLock(this.prompts);

  const DVPromptLock.empty() : prompts = const <String, List<DVPromptLockEntry>>{};

  /// Where the lockfile lives, next to `pubspec.yaml`.
  static const String fileName = 'dartvel.prompts.lock';

  /// The on-disk format. A lockfile in another format is refused, not guessed.
  static const int format = 1;

  /// By prompt id, oldest version first.
  final Map<String, List<DVPromptLockEntry>> prompts;

  DVPromptLockEntry? entry(String id, int version) {
    for (final DVPromptLockEntry e
        in prompts[id] ?? const <DVPromptLockEntry>[]) {
      if (e.version == version) return e;
    }
    return null;
  }

  /// Whether [version] is recorded with exactly its fingerprint.
  bool contains(DVPromptVersion version) =>
      entry(version.id, version.version)?.fingerprint == version.fingerprint;

  /// Compares the compiled prompts with what is recorded.
  ///
  /// A recorded version whose fingerprint moved is `DV-AIOPS-006`, and so is
  /// a version below the newest recorded one: an evaluation scored the newest,
  /// and a build carrying an older number cannot be told apart from it in the
  /// outputs it records. A prompt or version not recorded yet is not a
  /// problem; [record] adds it.
  List<DVPromptLockProblem> check(Iterable<DVPromptVersion> compiled) {
    final List<DVPromptLockProblem> problems = <DVPromptLockProblem>[];
    for (final DVPromptVersion v in compiled) {
      final List<DVPromptLockEntry> history =
          prompts[v.id] ?? const <DVPromptLockEntry>[];
      if (history.isEmpty) continue;
      final DVPromptLockEntry? recorded = entry(v.id, v.version);
      final int newest = history.last.version;
      if (recorded != null && recorded.fingerprint != v.fingerprint) {
        problems.add(DVPromptLockProblem(
          code: 'DV-AIOPS-006',
          promptId: v.id,
          version: v.version,
          message: 'prompt "${v.id}" changed without incrementing its version: '
              'version ${v.version} is recorded as ${recorded.fingerprint} and '
              'the build has ${v.fingerprint}. Increment the version to '
              '${newest + 1}.',
        ));
      } else if (v.version < newest) {
        problems.add(DVPromptLockProblem(
          code: 'DV-AIOPS-006',
          promptId: v.id,
          version: v.version,
          message: 'prompt "${v.id}" is at version ${v.version} and version '
              '$newest is recorded. A version that goes backwards cannot be '
              'told apart from the one an evaluation scored; ship the old '
              'wording as version ${newest + 1}.',
        ));
      }
    }
    return problems;
  }

  /// Records every compiled version not yet recorded, refusing when [check]
  /// finds a problem.
  DVPromptLock record(Iterable<DVPromptVersion> compiled) {
    final List<DVPromptVersion> versions = compiled.toList();
    final List<DVPromptLockProblem> problems = check(versions);
    if (problems.isNotEmpty) {
      throw DVAIOpsError(
        problems.first.code,
        problems.map((DVPromptLockProblem p) => p.message).join('\n'),
      );
    }
    final Map<String, List<DVPromptLockEntry>> next =
        <String, List<DVPromptLockEntry>>{
      for (final MapEntry<String, List<DVPromptLockEntry>> e in prompts.entries)
        e.key: List<DVPromptLockEntry>.of(e.value),
    };
    for (final DVPromptVersion v in versions) {
      final List<DVPromptLockEntry> history =
          next.putIfAbsent(v.id, () => <DVPromptLockEntry>[]);
      if (history.any((DVPromptLockEntry e) => e.version == v.version)) {
        continue;
      }
      history
        ..add(DVPromptLockEntry(version: v.version, fingerprint: v.fingerprint))
        ..sort((DVPromptLockEntry a, DVPromptLockEntry b) =>
            a.version.compareTo(b.version));
    }
    return DVPromptLock(next);
  }

  String encode() {
    final List<String> ids = prompts.keys.toList()..sort();
    return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'format': format,
          'prompts': <String, Object?>{
            for (final String id in ids)
              id: <Object?>[
                for (final DVPromptLockEntry e in prompts[id]!)
                  <String, Object?>{
                    'version': e.version,
                    'fingerprint': e.fingerprint,
                  },
              ],
          },
        })}\n';
  }

  /// Reads a lockfile, refusing one whose versions do not ascend: that file
  /// was edited by hand, and a check against it would pass edits it should
  /// refuse.
  static DVPromptLock decode(String source) {
    final Object? root = jsonDecode(source);
    if (root is! Map<String, Object?>) {
      throw const FormatException('prompt lockfile is not a JSON object');
    }
    if (root['format'] != format) {
      throw FormatException(
          'prompt lockfile format ${root['format']} is not $format');
    }
    final Object? all = root['prompts'];
    if (all is! Map<String, Object?>) {
      throw const FormatException('prompt lockfile has no prompts object');
    }
    final Map<String, List<DVPromptLockEntry>> prompts =
        <String, List<DVPromptLockEntry>>{};
    for (final MapEntry<String, Object?> e in all.entries) {
      final Object? list = e.value;
      if (list is! List<Object?>) {
        throw FormatException('prompt "${e.key}" is not a list of versions');
      }
      final List<DVPromptLockEntry> history = <DVPromptLockEntry>[];
      for (final Object? item in list) {
        if (item is! Map<String, Object?> ||
            item['version'] is! int ||
            item['fingerprint'] is! String) {
          throw FormatException(
              'prompt "${e.key}" has an entry without version and fingerprint');
        }
        final int version = item['version']! as int;
        if (history.isNotEmpty && version <= history.last.version) {
          throw FormatException('prompt "${e.key}" version $version follows '
              '${history.last.version}; versions ascend');
        }
        history.add(DVPromptLockEntry(
            version: version, fingerprint: item['fingerprint']! as String));
      }
      prompts[e.key] = history;
    }
    return DVPromptLock(prompts);
  }
}

/// Where stored prompt versions live.
///
/// Each prompt has the versions stored for it and a stack of activations:
/// the top answers, and popping it is a rollback to exactly what answered
/// before.
abstract class DVPromptStore {
  Future<Set<String>> ids();

  /// Every version stored for [id].
  Future<List<DVPromptVersion>> versions(String id);

  /// The version answering for [id], or null when the compiled one does.
  Future<DVPromptVersion?> active(String id);

  /// Stores [version] and makes it the one answering.
  Future<void> put(DVPromptVersion version);

  /// Makes whatever answered before the current activation answer again.
  /// Returns false when nothing is active.
  Future<bool> pop(String id);

  /// Removes a stored version and every activation of it.
  Future<void> delete(String id, int version);
}

class DVMemoryPromptStore implements DVPromptStore {
  final Map<String, Map<int, DVPromptVersion>> _versions =
      <String, Map<int, DVPromptVersion>>{};
  final Map<String, List<int>> _activations = <String, List<int>>{};

  @override
  Future<Set<String>> ids() async => _versions.keys.toSet();

  @override
  Future<List<DVPromptVersion>> versions(String id) async =>
      List<DVPromptVersion>.unmodifiable(
          (_versions[id] ?? const <int, DVPromptVersion>{}).values);

  @override
  Future<DVPromptVersion?> active(String id) async {
    final List<int>? stack = _activations[id];
    if (stack == null || stack.isEmpty) return null;
    return _versions[id]![stack.last];
  }

  @override
  Future<void> put(DVPromptVersion version) async {
    (_versions[version.id] ??= <int, DVPromptVersion>{})[version.version] =
        version;
    (_activations[version.id] ??= <int>[]).add(version.version);
  }

  @override
  Future<bool> pop(String id) async {
    final List<int>? stack = _activations[id];
    if (stack == null || stack.isEmpty) return false;
    stack.removeLast();
    return true;
  }

  @override
  Future<void> delete(String id, int version) async {
    _versions[id]?.remove(version);
    _activations[id]?.removeWhere((int v) => v == version);
    if (_versions[id]?.isEmpty ?? false) _versions.remove(id);
  }
}

/// A prompt as it will be sent, and where it came from.
class DVResolvedPrompt {
  const DVResolvedPrompt(this.version, this.source);

  final DVPromptVersion version;
  final DVPromptSource source;
}

/// The compiled prompts, the store that overrides them, and the lockfile that
/// says what the repository has recorded.
class DVPrompts {
  DVPrompts({DVPromptStore? store, this.lock, DVLogger? logger})
      : store = store ?? DVMemoryPromptStore(),
        _logger = logger;

  final DVPromptStore store;
  final DVPromptLock? lock;
  final DVLogger? _logger;

  DVLogger get _log => _logger ?? DVObservability.logger;

  final Map<String, DVPromptVersion> _compiled = <String, DVPromptVersion>{};
  final Map<String, DVPromptTemplate> _templates = <String, DVPromptTemplate>{};
  final Set<String> _reported = <String>{};

  /// Registers a compiled prompt. Normally called by generated code.
  void register(DVPrompt prompt, DVPromptTemplate template) {
    final DVPromptVersion version = DVPromptVersion.compiled(prompt, template);
    final DVPromptVersion? existing = _compiled[prompt.id];
    if (existing != null) {
      if (existing.version == version.version &&
          existing.fingerprint == version.fingerprint) {
        return;
      }
      throw ArgumentError.value(prompt.id, 'prompt',
          'is already registered as ${existing.version}; one id is one prompt');
    }
    _compiled[prompt.id] = version;
    _templates[prompt.id] = template;
  }

  DVPromptVersion? compiled(String id) => _compiled[id];

  DVPromptTemplate? template(String id) => _templates[id];

  Iterable<DVPromptVersion> get compiledVersions => _compiled.values;

  /// The version that answers for [id]: the active stored one, or else the
  /// compiled one.
  Future<DVResolvedPrompt> resolve(String id) async {
    final DVPromptVersion compiled = _compiled[id] ??
        (throw ArgumentError.value(id, 'id', 'no prompt is registered'));
    final DVPromptVersion? stored = await store.active(id);
    if (stored == null) return DVResolvedPrompt(compiled, DVPromptSource.compiled);
    if (!_hasCounterpart(stored) &&
        _reported.add('${stored.id}@${stored.version}#${stored.fingerprint}')) {
      _log.log(
        'DV-AIOPS-001: stored prompt "${stored.id}" version ${stored.version} '
        'has no counterpart in the repository; the next deploy reverts it. '
        'Export it back to source.',
        level: DVLogLevel.warn,
        code: 'DV-AIOPS-001',
        context: <String, Object?>{
          'prompt': stored.id,
          'version': stored.version,
          'fingerprint': stored.fingerprint,
        },
      );
    }
    return DVResolvedPrompt(stored, DVPromptSource.stored);
  }

  bool _hasCounterpart(DVPromptVersion v) {
    final DVPromptVersion? compiled = _compiled[v.id];
    if (compiled != null &&
        compiled.version == v.version &&
        compiled.fingerprint == v.fingerprint) {
      return true;
    }
    return lock?.contains(v) ?? false;
  }

  /// Stores [version] and makes it answer.
  ///
  /// A stored version carries wording, not shape: the call site was compiled
  /// against the inputs and output it has. And a number already used, by
  /// the compiled prompt, the lockfile or the store, cannot carry other text.
  Future<void> ship(DVPromptVersion version) async {
    final DVPromptVersion? compiled = _compiled[version.id];
    if (compiled == null) {
      throw ArgumentError.value(version.id, 'version',
          'no compiled prompt has this id, so no call site can use it');
    }
    if (version.shape != compiled.shape) {
      throw ArgumentError.value(
          version,
          'version',
          'changes the inputs, output or schema the call site was compiled '
              'against; a stored version changes wording only');
    }
    String? usedBy;
    if (compiled.version == version.version &&
        compiled.fingerprint != version.fingerprint) {
      usedBy = 'the compiled prompt';
    }
    final DVPromptLockEntry? locked = lock?.entry(version.id, version.version);
    if (locked != null && locked.fingerprint != version.fingerprint) {
      usedBy ??= 'the lockfile';
    }
    for (final DVPromptVersion existing in await store.versions(version.id)) {
      if (existing.version == version.version &&
          existing.fingerprint != version.fingerprint) {
        usedBy ??= 'an earlier stored version';
      }
    }
    if (usedBy != null) {
      throw DVAIOpsError(
        'DV-AIOPS-006',
        'prompt "${version.id}" version ${version.version} is already '
            '$usedBy with other text; a changed prompt takes a new version',
      );
    }
    await store.put(version);
  }

  /// Removes a stored version. When it was answering, what answered before
  /// it answers again, down to the compiled prompt.
  Future<void> unship(String id, int version) => store.delete(id, version);

  /// Ships the version that answered before the current one: that version,
  /// with its own number and fingerprint, rather than a new version that
  /// reverses the change.
  Future<DVResolvedPrompt> rollback(String id) async {
    if (!await store.pop(id)) {
      throw StateError('prompt "$id" has no stored version answering; the '
          'compiled version is already the one in use');
    }
    return resolve(id);
  }

  /// Every stored version with no counterpart in the repository
  /// (`DV-AIOPS-001`): not compiled, and not in the lockfile with its
  /// fingerprint.
  Future<List<DVPromptLockProblem>> audit() async {
    final List<DVPromptLockProblem> problems = <DVPromptLockProblem>[];
    final List<String> ids = (await store.ids()).toList()..sort();
    for (final String id in ids) {
      for (final DVPromptVersion v in await store.versions(id)) {
        if (_hasCounterpart(v)) continue;
        problems.add(DVPromptLockProblem(
          code: 'DV-AIOPS-001',
          promptId: id,
          version: v.version,
          message: 'stored prompt "$id" version ${v.version} has no '
              'counterpart in the repository; the next deploy reverts it',
        ));
      }
    }
    return problems;
  }
}

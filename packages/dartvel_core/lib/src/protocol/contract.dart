/// The contract a client and a backend must agree on, its protocol version,
/// the committed lockfile that records the history of both, and the window of
/// versions a backend still serves.
library dartvel_core.protocol.contract;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A model field or a function parameter.
///
/// [type] is the Dart type as written, nullability included: `String?` and
/// `String` are different contracts, because an old client that reads a
/// non-null field breaks the first time it is handed a null.
class DVProtocolField {
  const DVProtocolField(
    this.name,
    this.type, {
    this.hasDefault = false,
    this.renamedFrom,
  });

  final String name;
  final String type;

  /// Whether the declaration supplies a default, so a caller that does not
  /// send it still produces a value.
  final bool hasDefault;

  /// The name this field had before a rename. A rename without it reads as a
  /// removal and an addition, which is a lossy change; with it, an adapter
  /// can serve the old name.
  final String? renamedFrom;

  bool get nullable => type.endsWith('?');

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    if (hasDefault) 'hasDefault': true,
    if (renamedFrom != null) 'renamedFrom': renamedFrom,
  };

  static DVProtocolField fromJson(Map<String, Object?> json) => DVProtocolField(
    _string(json, 'name'),
    _string(json, 'type'),
    hasDefault: json['hasDefault'] == true,
    renamedFrom: json['renamedFrom'] as String?,
  );
}

/// A model: the fields a client reads and writes, and whether it syncs.
///
/// [synced] is part of the contract because the sync schema is: a model that
/// stops syncing leaves an old client subscribed to a stream that never comes.
class DVProtocolModel {
  const DVProtocolModel(this.name, this.fields, {this.synced = false});

  final String name;
  final List<DVProtocolField> fields;
  final bool synced;

  DVProtocolField? field(String name) {
    for (final DVProtocolField f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'fields': _sortedByName(
      fields,
      (DVProtocolField f) => f.name,
    ).map((DVProtocolField f) => f.toJson()).toList(),
    if (synced) 'synced': true,
  };

  static DVProtocolModel fromJson(Map<String, Object?> json) => DVProtocolModel(
    _string(json, 'name'),
    _objects(json, 'fields').map(DVProtocolField.fromJson).toList(),
    synced: json['synced'] == true,
  );
}

/// An enum that crosses the wire, serialized by member name.
///
/// [fallback] is the member an old client is handed for a member it has never
/// heard of. Without one, a new member is not something an adapter may guess
/// at: the old client is told to upgrade.
class DVProtocolEnum {
  const DVProtocolEnum(this.name, this.members, {this.fallback});

  final String name;
  final List<String> members;
  final String? fallback;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    // Sorted: members travel by name, so declaration order is not part of
    // the contract and reordering them must not burn a protocol version.
    'members': <String>[...members]..sort(),
    if (fallback != null) 'fallback': fallback,
  };

  static DVProtocolEnum fromJson(Map<String, Object?> json) => DVProtocolEnum(
    _string(json, 'name'),
    _strings(json, 'members'),
    fallback: json['fallback'] as String?,
  );
}

/// A backend function's signature as a client calls it.
///
/// An injected `DVContext` first parameter is not listed: the client never
/// supplies it, so it is not something the two sides agree on.
class DVProtocolFunction {
  const DVProtocolFunction(
    this.name, {
    this.parameters = const <DVProtocolField>[],
    required this.returns,
  });

  final String name;
  final List<DVProtocolField> parameters;
  final String returns;

  DVProtocolField? parameter(String name) {
    for (final DVProtocolField p in parameters) {
      if (p.name == name) return p;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'parameters': _sortedByName(
      parameters,
      (DVProtocolField f) => f.name,
    ).map((DVProtocolField f) => f.toJson()).toList(),
    'returns': returns,
  };

  static DVProtocolFunction fromJson(Map<String, Object?> json) =>
      DVProtocolFunction(
        _string(json, 'name'),
        parameters: _objects(
          json,
          'parameters',
        ).map(DVProtocolField.fromJson).toList(),
        returns: _string(json, 'returns'),
      );
}

/// Everything a client and a backend must agree on: model fields and their
/// types, backend function signatures, and the sync schema.
class DVProtocolContract {
  const DVProtocolContract({
    this.models = const <DVProtocolModel>[],
    this.enums = const <DVProtocolEnum>[],
    this.functions = const <DVProtocolFunction>[],
  });

  final List<DVProtocolModel> models;
  final List<DVProtocolEnum> enums;
  final List<DVProtocolFunction> functions;

  DVProtocolModel? model(String name) {
    for (final DVProtocolModel m in models) {
      if (m.name == name) return m;
    }
    return null;
  }

  DVProtocolEnum? enumNamed(String name) {
    for (final DVProtocolEnum e in enums) {
      if (e.name == name) return e;
    }
    return null;
  }

  DVProtocolFunction? function(String name) {
    for (final DVProtocolFunction f in functions) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// The canonical form: every list sorted by name, so the same contract
  /// written in a different order is the same JSON and the same [shape].
  Map<String, Object?> toJson() => <String, Object?>{
    'models': _sortedByName(
      models,
      (DVProtocolModel m) => m.name,
    ).map((DVProtocolModel m) => m.toJson()).toList(),
    'enums': _sortedByName(
      enums,
      (DVProtocolEnum e) => e.name,
    ).map((DVProtocolEnum e) => e.toJson()).toList(),
    'functions': _sortedByName(
      functions,
      (DVProtocolFunction f) => f.name,
    ).map((DVProtocolFunction f) => f.toJson()).toList(),
  };

  static DVProtocolContract fromJson(Map<String, Object?> json) =>
      DVProtocolContract(
        models: _objects(json, 'models').map(DVProtocolModel.fromJson).toList(),
        enums: _objects(json, 'enums').map(DVProtocolEnum.fromJson).toList(),
        functions: _objects(
          json,
          'functions',
        ).map(DVProtocolFunction.fromJson).toList(),
      );

  /// The digest of the contract the protocol integer stands for: the first
  /// eight hex digits of SHA-256 over [toJson].
  String get shape => sha256
      .convert(utf8.encode(jsonEncode(toJson())))
      .toString()
      .substring(0, 8);
}

/// One protocol version as the lockfile records it.
///
/// The contract travels with the number so a later build can derive the
/// adaptations for every version still in the window from what that version
/// actually was, rather than from a reconstruction of it.
class DVProtocolRelease {
  const DVProtocolRelease({
    required this.protocol,
    required this.shape,
    required this.released,
    required this.contract,
  });

  final int protocol;
  final String shape;

  /// The day this version became current, in UTC.
  final DateTime released;
  final DVProtocolContract contract;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol,
    'shape': shape,
    'released': _day(released),
    'contract': contract.toJson(),
  };
}

/// What comparing the build's contract with the lockfile found.
class DVProtocolLockCheck {
  const DVProtocolLockCheck({
    required this.ok,
    this.code,
    this.message,
    this.unlocked = false,
  });

  final bool ok;

  /// `DV-PROTO-001` when the shape moved without the integer.
  final String? code;
  final String? message;

  /// The project has no protocol recorded yet. Not a pass: a build that has
  /// never recorded its contract has nothing to compare the next one with.
  final bool unlocked;
}

/// The committed protocol lockfile, oldest version first.
class DVProtocolLock {
  const DVProtocolLock(this.releases);

  /// Where the lockfile lives, next to `pubspec.yaml`.
  static const String fileName = 'dartvel.protocol.lock';

  /// The on-disk format. A lockfile in another format is refused, not guessed.
  static const int format = 1;

  final List<DVProtocolRelease> releases;

  DVProtocolRelease? get current => releases.isEmpty ? null : releases.last;

  DVProtocolRelease? release(int protocol) {
    for (final DVProtocolRelease r in releases) {
      if (r.protocol == protocol) return r;
    }
    return null;
  }

  /// Compares [contract] with the current version.
  ///
  /// Any difference from the current shape is a change, including a return
  /// to an older one: the clients in the field are reading the current shape,
  /// and they are the ones a revert breaks.
  DVProtocolLockCheck check(DVProtocolContract contract) {
    final DVProtocolRelease? latest = current;
    if (latest == null) {
      return const DVProtocolLockCheck(
        ok: false,
        unlocked: true,
        message:
            'no protocol is recorded; bump the protocol to record '
            'version 1',
      );
    }
    final String shape = contract.shape;
    if (shape == latest.shape) return const DVProtocolLockCheck(ok: true);
    return DVProtocolLockCheck(
      ok: false,
      code: 'DV-PROTO-001',
      message:
          'contract shape changed without incrementing the protocol '
          'version: protocol ${latest.protocol} is ${latest.shape}, the build '
          'is $shape. Bump the protocol to record version '
          '${latest.protocol + 1}.',
    );
  }

  /// Records [contract] as the next protocol version, current from [at].
  ///
  /// Refuses a contract whose shape is already current: a version that changes
  /// nothing still occupies a slot in every backend's window.
  DVProtocolLock bump(DVProtocolContract contract, {required DateTime at}) {
    final String shape = contract.shape;
    final DVProtocolRelease? latest = current;
    if (latest != null && latest.shape == shape) {
      throw StateError(
        'protocol ${latest.protocol} already has shape $shape; nothing to bump',
      );
    }
    return DVProtocolLock(<DVProtocolRelease>[
      ...releases,
      DVProtocolRelease(
        protocol: (latest?.protocol ?? 0) + 1,
        shape: shape,
        released: DateTime.utc(at.year, at.month, at.day),
        contract: contract,
      ),
    ]);
  }

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'format': format, 'releases': releases.map((DVProtocolRelease r) => r.toJson()).toList()})}\n';

  /// Reads a lockfile, refusing one that contradicts itself: a recorded shape
  /// that is not its contract's digest, or versions that do not ascend by one.
  /// Either means the file was edited by hand, and a window built on it would
  /// serve a contract nobody shipped.
  static DVProtocolLock decode(String source) {
    final Object? root = jsonDecode(source);
    if (root is! Map<String, Object?>) {
      throw const FormatException('protocol lockfile is not a JSON object');
    }
    if (root['format'] != format) {
      throw FormatException(
        'protocol lockfile format ${root['format']} is not $format',
      );
    }
    final List<DVProtocolRelease> releases = <DVProtocolRelease>[];
    for (final Map<String, Object?> entry in _objects(root, 'releases')) {
      final int protocol = entry['protocol'] is int
          ? entry['protocol']! as int
          : throw const FormatException('protocol must be an integer');
      final int expected = releases.isEmpty ? 1 : releases.last.protocol + 1;
      if (protocol != expected) {
        throw FormatException(
          'protocol $protocol follows ${expected - 1}; versions ascend by one',
        );
      }
      final DVProtocolContract contract = DVProtocolContract.fromJson(
        (entry['contract'] as Map<Object?, Object?>?)
                ?.cast<String, Object?>() ??
            (throw FormatException('protocol $protocol has no contract')),
      );
      final String shape = _string(entry, 'shape');
      if (shape != contract.shape) {
        throw FormatException(
          'protocol $protocol records shape $shape but its contract is '
          '${contract.shape}',
        );
      }
      releases.add(
        DVProtocolRelease(
          protocol: protocol,
          shape: shape,
          released: _parseDay(_string(entry, 'released')),
          contract: contract,
        ),
      );
    }
    return DVProtocolLock(releases);
  }
}

/// How far back a backend serves: [versions] previous protocol versions or
/// [minimumAge], whichever reaches further.
class DVProtocolWindow {
  const DVProtocolWindow({
    this.versions = 3,
    this.minimumAge = const Duration(days: 90),
    this.strandThreshold = 0.005,
  });

  /// Previous versions served in addition to the current one.
  final int versions;

  /// A version superseded less than this long ago is served regardless of
  /// [versions].
  final Duration minimumAge;

  /// The share of sessions, over the last seven days, a version outside a
  /// candidate's window may carry before the deploy gate refuses it.
  final double strandThreshold;

  /// Reads `dartvel.protocol` from `pubspec.yaml`. Absent means the defaults;
  /// a value that cannot be read is refused rather than defaulted, because a
  /// typo that silently became the default would be a window nobody chose.
  factory DVProtocolWindow.fromConfig(Map<Object?, Object?>? config) {
    if (config == null) return const DVProtocolWindow();
    final Object? window = config['window'];
    if (window != null && (window is! int || window < 0)) {
      throw FormatException(
        'dartvel.protocol.window must be a non-negative integer, got $window',
      );
    }
    final Object? age = config['minimumAge'];
    final Object? threshold = config['strandThreshold'];
    return DVProtocolWindow(
      versions: window as int? ?? 3,
      minimumAge: age == null ? const Duration(days: 90) : _parseAge('$age'),
      strandThreshold: threshold == null ? 0.005 : _parseThreshold(threshold),
    );
  }

  /// The protocol versions in [lock] this window serves at [now].
  ///
  /// A version's age is measured from when it stopped being current -- the day
  /// its successor was released -- because that is the age of the newest
  /// install still carrying it.
  Set<int> served(DVProtocolLock lock, {required DateTime now}) {
    final DVProtocolRelease? latest = lock.current;
    if (latest == null) return <int>{};
    final DateTime cutoff = now.toUtc().subtract(minimumAge);
    final Set<int> served = <int>{};
    for (int i = 0; i < lock.releases.length; i += 1) {
      final DVProtocolRelease release = lock.releases[i];
      final bool byCount = release.protocol >= latest.protocol - versions;
      final bool byAge =
          i == lock.releases.length - 1 ||
          !lock.releases[i + 1].released.isBefore(cutoff);
      if (byCount || byAge) served.add(release.protocol);
    }
    return served;
  }

  static Duration _parseAge(String value) {
    final Match? match = RegExp(r'^\s*(\d+)\s*([hdw])\s*$').firstMatch(value);
    if (match == null) {
      throw FormatException(
        'dartvel.protocol.minimumAge must be a number of hours, days or weeks '
        '(e.g. 90d), got "$value"',
      );
    }
    final int n = int.parse(match.group(1)!);
    return switch (match.group(2)) {
      'h' => Duration(hours: n),
      'w' => Duration(days: 7 * n),
      _ => Duration(days: n),
    };
  }

  static double _parseThreshold(Object value) {
    double? fraction;
    if (value is num) {
      fraction = value.toDouble();
    } else {
      final Match? match = RegExp(
        r'^\s*(\d+(?:\.\d+)?)\s*%\s*$',
      ).firstMatch('$value');
      if (match != null) fraction = double.parse(match.group(1)!) / 100;
    }
    if (fraction == null || fraction < 0 || fraction > 1) {
      throw FormatException(
        'dartvel.protocol.strandThreshold must be a percentage (e.g. 0.5%) or '
        'a fraction between 0 and 1, got $value',
      );
    }
    return fraction;
  }
}

List<T> _sortedByName<T>(List<T> items, String Function(T) name) =>
    <T>[...items]..sort((T a, T b) => name(a).compareTo(name(b)));

String _string(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is String) return value;
  throw FormatException('"$key" must be a string, got $value');
}

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) return <Map<String, Object?>>[];
  if (value is! List) throw FormatException('"$key" must be a list');
  return <Map<String, Object?>>[
    for (final Object? item in value)
      if (item is Map)
        item.cast<String, Object?>()
      else
        throw FormatException('"$key" must hold objects, got $item'),
  ];
}

List<String> _strings(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) return <String>[];
  if (value is! List) throw FormatException('"$key" must be a list');
  return <String>[
    for (final Object? item in value)
      if (item is String)
        item
      else
        throw FormatException('"$key" must hold strings, got $item'),
  ];
}

String _day(DateTime at) {
  final DateTime utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}';
}

DateTime _parseDay(String value) {
  final Match? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('released must be YYYY-MM-DD, got "$value"');
  }
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

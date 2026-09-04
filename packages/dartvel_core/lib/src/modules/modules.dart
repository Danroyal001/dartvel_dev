import '../lifecycle/lifecycle.dart';

/// A mounted Dartvel module.
///
/// A module is a full Dartvel application boundary configured under
/// `dartvel.module` / `dartvel.modules` in `pubspec.yaml`. The parent
/// application reaches it through the generated `DV.Modules.<id>` accessor.
///
/// Module code must not hard-code its mount point: [mountPath] is assigned by
/// the parent at registration, so the same module can be mounted anywhere.
class DVModule {
  DVModule({
    required this.id,
    required String mountPath,
    Map<String, Object?> config = const <String, Object?>{},
    Map<String, String> assets = const <String, String>{},
  })  : _mountPath = mountPath,
        config = Map.unmodifiable(config),
        assets = Map.unmodifiable(assets);

  /// The module identifier, matching the generated `DV.Modules.<id>`.
  final String id;

  String _mountPath;

  /// Where the parent mounted this module, e.g. `/store`.
  String get mountPath => _mountPath;

  /// Configuration the parent passed at mount time.
  final Map<String, Object?> config;

  /// Where this module's backend functions answer, when they are not the
  /// parent's.
  ///
  /// A split-backend or federated module runs its functions as its own
  /// service, and the module's generated client asks here before falling
  /// back to the application's own base. Null when the parent serves them,
  /// which is what lets the caller tell the two cases apart -- answering
  /// with the parent's address would make them identical to anything reading
  /// this, and a module calling the wrong service does not crash, it gets a
  /// 404 from an application that was built and deployed and looks right.
  String? get apiBase {
    final Object? declared = config['backend'];
    if (declared == null) return null;
    final String value = '$declared'.trim();
    return value.isEmpty ? null : value;
  }

  /// The globals this module shares with whatever mounted it.
  ///
  /// `dartvel.module.globals.export` in the module's own pubspec. Empty is
  /// the default and means nothing is shared: the specification isolates
  /// module globals and asks for sharing to be written down, because a
  /// parent reaching into a module's state turns anything the module keeps
  /// into somebody's dependency without its author knowing.
  List<String> get exportedGlobals => _globalNames('export');

  /// The application globals this module may read.
  ///
  /// `dartvel.modules.<id>.globals.inherit` in the parent's pubspec: the
  /// parent decides what it hands down, and the module reads it without
  /// naming the parent, so the same module standing alone reads its own.
  List<String> get inheritedGlobals => _globalNames('inherit');

  List<String> _globalNames(String key) {
    final Object? globals = config['globals'];
    if (globals is! Map) return const <String>[];
    final Object? names = globals[key];
    if (names is! List) return const <String>[];
    return <String>[
      for (final Object? name in names)
        if ('$name'.trim().isNotEmpty) '$name'.trim(),
    ];
  }

  /// The module's own asset paths, each mapped to the path that finds it
  /// once the module is mounted.
  ///
  /// Flutter serves another package's asset under `packages/<name>/`, so a
  /// module standing alone and the same module mounted ask for the same
  /// file by different names. Module code asks by its own name and gets
  /// the right one, which is what keeps the mount point out of the code.
  final Map<String, String> assets;

  /// Where [path] is served from now: the mounted path when this module was
  /// mounted, and [path] itself when it is running on its own.
  String asset(String path) => assets[path] ?? path;

  final _lifecycle = DVMutableLifecycleSignal<DVModuleLifecycle>(
    DVModuleLifecycle.discovered,
  );

  /// `DV.Modules.<id>.lifecycle` — observed, never assigned by app code.
  DVLifecycleSignal<DVModuleLifecycle> get lifecycle => _lifecycle;

  /// Resolves a path within this module against its mount point, so module
  /// code can build URLs without knowing where it was mounted.
  String resolve(String path) {
    final base = _mountPath.endsWith('/')
        ? _mountPath.substring(0, _mountPath.length - 1)
        : _mountPath;
    final suffix = path.startsWith('/') ? path : '/$path';
    return '$base$suffix';
  }

  /// Framework-only: advances this module's lifecycle state.
  void setLifecycle(DVModuleLifecycle state) => _lifecycle.set(state);

  /// Framework-only: re-mounts the module at a different path.
  void setMountPath(String path) => _mountPath = path;
}

/// Thrown when a module is requested that was never registered.
class DVUnknownModuleException implements Exception {
  DVUnknownModuleException(this.id, this.known);

  final String id;
  final List<String> known;

  @override
  String toString() {
    final available = known.isEmpty ? '(none registered)' : known.join(', ');
    return 'DVUnknownModuleException: no module "$id". Registered: $available. '
        'Modules are declared under dartvel.modules in pubspec.yaml and '
        'reached through the generated DV.Modules.<id> accessor.';
  }
}

/// The registry behind `DV.Modules`.
///
/// The generator emits typed `DV.Modules.<id>` accessors on top of this; the
/// registry itself stays string-keyed so the runtime does not need to know the
/// set of modules ahead of time.
class DVModuleRegistry {
  DVModuleRegistry();

  final _modules = <String, DVModule>{};

  /// Ids of every registered module, in registration order.
  List<String> get ids => List.unmodifiable(_modules.keys);

  /// Every registered module, in registration order.
  List<DVModule> get all => List.unmodifiable(_modules.values);

  /// Whether [id] is registered.
  bool has(String id) => _modules.containsKey(id);

  /// The module registered as [id].
  ///
  /// Throws [DVUnknownModuleException] rather than returning null, because a
  /// missing module is a configuration error the developer needs to see.
  DVModule call(String id) => get(id);

  /// The module registered as [id]. See [call].
  DVModule get(String id) {
    final module = _modules[id];
    if (module == null) {
      throw DVUnknownModuleException(id, ids);
    }
    return module;
  }

  /// The module registered as [id], or null when absent.
  DVModule? maybeGet(String id) => _modules[id];

  /// Framework-only: registers a module discovered from `pubspec.yaml`.
  ///
  /// Re-registering an id replaces the entry, so hot restart does not
  /// accumulate stale modules.
  DVModule register({
    required String id,
    required String mountPath,
    Map<String, Object?> config = const <String, Object?>{},
    Map<String, String> assets = const <String, String>{},
  }) {
    final module = DVModule(id: id, mountPath: mountPath, config: config, assets: assets);
    _modules[id] = module;
    return module;
  }

  /// Test-only: empties the registry.
  void resetForTesting() => _modules.clear();
}

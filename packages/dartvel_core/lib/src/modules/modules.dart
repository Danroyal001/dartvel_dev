import '../database/adapter.dart';
import '../lifecycle/lifecycle.dart';


/// Where a module's data lives, as the parent declared it.
///
/// `dartvel.modules.<id>.data` in the parent's pubspec. The mode has been
/// read, carried into the generated registry and checked against the
/// deployment for a while; these are what it does once the application is
/// running.
enum DVModuleDataMode {
  /// The parent's database, the parent's tables. The default.
  shared,

  /// The parent's database, the module's own tables within it.
  schemaIsolated,

  /// A database of the module's own, configured by whoever mounts it.
  databaseIsolated,

  /// Somewhere else entirely: the module's own deployment owns the data and
  /// answers for it. There is no local table to read.
  remote,
}


/// How a module's own look combines with the application's.
///
/// `dartvel.modules.<id>.theme` in the parent's pubspec. The parent's theme
/// is its MaterialApp's, which is application code; the module's is whatever
/// the module declares. The mode is therefore a rule for combining two
/// things rather than a switch on one.
enum DVModuleThemeMode {
  /// The application's theme. The module contributes nothing. The default.
  inherit,

  /// The application's theme with the module's own decisions applied over
  /// it: what the module did not say, the application still says.
  extend,

  /// The module's theme, in place of the application's.
  override,

  /// The module's theme, and no path back to the application's -- not even
  /// through the values the module left at their defaults.
  isolated,
}

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



  /// How this module's look combines with the application's.
  ///
  /// Defaults to [DVModuleThemeMode.inherit]. An unrecognised value is
  /// refused rather than falling back, for the same reason [dataMode] refuses
  /// one: a typo in a pubspec should not quietly become a decision.
  DVModuleThemeMode get themeMode {
    final Object? declared = config['theme'];
    if (declared == null) return DVModuleThemeMode.inherit;
    return switch ('$declared'.trim()) {
      '' || 'inherit' => DVModuleThemeMode.inherit,
      'extend' => DVModuleThemeMode.extend,
      'override' => DVModuleThemeMode.override,
      'isolated' => DVModuleThemeMode.isolated,
      final String other => throw StateError(
          'Module "$id" declares theme mode "$other", which is not one of '
          'inherit, extend, override or isolated.',
        ),
    };
  }

  /// Where this module's data lives, as the parent declared it.
  ///
  /// Defaults to [DVModuleDataMode.shared], which is the specification's
  /// default. An unrecognised value is refused rather than falling back:
  /// falling back would put a module's tables in the parent's database
  /// because somebody mistyped a word in a pubspec, and nothing would say so.
  DVModuleDataMode get dataMode {
    final Object? declared = config['data'];
    if (declared == null) return DVModuleDataMode.shared;
    return switch ('$declared'.trim()) {
      '' || 'shared' => DVModuleDataMode.shared,
      'schema-isolated' => DVModuleDataMode.schemaIsolated,
      'database-isolated' => DVModuleDataMode.databaseIsolated,
      'remote' => DVModuleDataMode.remote,
      final String other => throw StateError(
          'Module "$id" declares data mode "$other", which is not one of '
          'shared, schema-isolated, database-isolated or remote. A mode '
          'nobody recognises is not treated as shared: that would put this '
          "module's tables in the application's database because of a typo.",
        ),
    };
  }

  /// The table a model of this module's actually reads and writes.
  ///
  /// Shared modules use the name the model declared, because that is what
  /// the parent's migration created. A schema-isolated module's tables carry
  /// its id, so a module with an Order model mounted into an application
  /// that also has orders reads its own rows rather than somebody else's --
  /// which is what it did before, silently, because both queried `orders`.
  ///
  /// A prefix rather than a real database schema: SQLite is the zero-config
  /// local default and has no schemas, so a schema would mean two naming
  /// rules that have to agree, and the day they disagree is the day the
  /// migration writes one table and the query reads another.
  String table(String name) {
    switch (dataMode) {
      case DVModuleDataMode.shared:
      case DVModuleDataMode.databaseIsolated:
        // Nothing to disambiguate from in either case: the parent's
        // migration made this table, or the module has the database to
        // itself. Prefixing an isolated database would also make the same
        // module read different tables standing alone and mounted.
        return name;
      case DVModuleDataMode.schemaIsolated:
        if (!_identifier.hasMatch(id)) {
          throw ArgumentError.value(
            id,
            'id',
            'A schema-isolated module\'s id becomes part of a table name, so '
                'it has to be a plain SQL identifier. Rename the module, or '
                'give it data mode database-isolated.',
          );
        }
        return '${id}_$name';
      case DVModuleDataMode.remote:
        throw StateError(
          'Module "$id" is mounted with data mode remote, so "$name" is not '
          'a table in this application. Its own deployment owns that data; '
          "ask it through the module's API rather than the database.",
        );
    }
  }

  DVDatabaseAdapter? _database;

  /// Framework-and-host: the database this module reads, for a module that
  /// was mounted with a database of its own.
  ///
  /// Whoever mounts a database-isolated module has to say where its data
  /// lives; nothing else can know.
  void useDatabase(DVDatabaseAdapter adapter) => _database = adapter;

  /// The database this module's models read and write.
  ///
  /// Shared and schema-isolated modules share the application's connection
  /// and differ only in table names. A database-isolated one uses the
  /// adapter it was given, and never quietly falls back to the
  /// application's: a module writing into the parent's database while its
  /// declaration says it does not is a data leak that reads as working.
  DVDatabaseAdapter get database {
    switch (dataMode) {
      case DVModuleDataMode.shared:
      case DVModuleDataMode.schemaIsolated:
        return const DVDatabase().adapter;
      case DVModuleDataMode.databaseIsolated:
        final DVDatabaseAdapter? own = _database;
        if (own == null) {
          throw StateError(
            'Module "$id" is mounted with data mode database-isolated and no '
            'database was configured for it. Call '
            'DV.Modules.$id.useDatabase(...) with the adapter its data lives '
            "in. It does not fall back to the application's: a module "
            'writing into a database its declaration says it does not use is '
            'a leak that looks like it is working.',
          );
        }
        return own;
      case DVModuleDataMode.remote:
        throw StateError(
          'Module "$id" is mounted with data mode remote, so it has no local '
          "database. Its own deployment owns its data; call the module's API.",
        );
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

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

/// The process-wide module registry.
///
/// `DV.Modules` is this object rather than one of its own: a second registry
/// would be a second answer to "what was this module mounted as", and the
/// two would agree until the day they did not.
final DVModuleRegistry dvModuleRegistry = DVModuleRegistry();

/// How a module's generated models reach their data.
///
/// A module's models are generated from the module's own project, standing
/// alone, so the mount-time answer cannot be written into them: the same
/// module is mounted into different applications with different modes. They
/// ask here instead, by their own module id, which the module's own pubspec
/// declares.
///
/// A module nobody mounted is its own application: plain table names in the
/// configured database, which is what makes `dart test` inside a module
/// work without a parent.
class DVModuleData {
  const DVModuleData(this.moduleId);

  /// The module's own id, from `dartvel.module.id` in its pubspec.
  final String moduleId;

  DVModule? get _mounted => dvModuleRegistry.maybeGet(moduleId);

  /// The table [name] resolves to, given how this module was mounted.
  String table(String name) => _mounted?.table(name) ?? name;

  /// The database this module's models read and write.
  DVDatabaseAdapter get database =>
      _mounted?.database ?? const DVDatabase().adapter;
}

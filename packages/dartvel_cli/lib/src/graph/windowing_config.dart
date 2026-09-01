/// The windowing configuration, as `dartvel inspect windows` reports it.
///
/// Windowing is configured almost entirely by defaults: an application that
/// writes nothing under `dartvel.windowing` still gets single-instance on
/// desktop, `lastWindow` exit, restore on launch and a persisted workspace.
/// So "what windowing policy is in effect here" cannot be answered by reading
/// pubspec.yaml -- most of the answer is not in it, and the part that is looks
/// exactly like the part that is not.
///
/// Hence [sources]: every value says whether it was written or assumed.
library dartvel.graph.windowing_config;

/// One project's windowing policy.
class DVWindowingConfig {
  const DVWindowingConfig({
    required this.enabled,
    required this.singleInstance,
    required this.exit,
    required this.restoreOnLaunch,
    required this.workspacePersist,
    required this.workspaceTearOut,
    required this.sources,
    required this.problems,
  });

  final bool enabled;
  final bool singleInstance;

  /// `lastWindow` | `mainWindow` | `explicit`.
  final String exit;

  final bool restoreOnLaunch;
  final bool workspacePersist;

  /// `auto` | `disabled`.
  final String workspaceTearOut;

  /// Where each value came from: `pubspec.yaml` or `default`.
  final Map<String, String> sources;

  /// Configuration that was written but cannot be honoured.
  ///
  /// Reported rather than passed through. An unknown exit policy would reach
  /// the runtime as a string nothing matches, and the window would simply
  /// never close the way the developer asked -- with no error anywhere.
  final List<String> problems;

  static const Set<String> _exitPolicies = <String>{
    'lastWindow',
    'mainWindow',
    'explicit',
  };
  static const Set<String> _tearOutModes = <String>{'auto', 'disabled'};

  /// Reads the `dartvel:` section of a pubspec.
  ///
  /// Never throws: a malformed pubspec should make `inspect` say so, not
  /// crash.
  static DVWindowingConfig parse(Object? dartvelSection) {
    final Map<String, String> sources = <String, String>{};
    final List<String> problems = <String>[];

    final Object? section =
        dartvelSection is Map ? dartvelSection['windowing'] : null;
    if (section != null && section is! Map) {
      problems.add(
          'dartvel.windowing must be a map, but is a ${section.runtimeType}.');
    }
    final Map<Object?, Object?> windowing =
        section is Map ? section : const <Object?, Object?>{};
    final Object? workspaceRaw = windowing['workspace'];
    if (workspaceRaw != null && workspaceRaw is! Map) {
      problems.add('dartvel.windowing.workspace must be a map, but is a '
          '${workspaceRaw.runtimeType}.');
    }
    final Map<Object?, Object?> workspace =
        workspaceRaw is Map ? workspaceRaw : const <Object?, Object?>{};

    bool readBool(Map<Object?, Object?> from, String key, String name,
        {required bool fallback}) {
      final Object? value = from[key];
      if (value == null) {
        sources[name] = 'default';
        return fallback;
      }
      if (value is! bool) {
        // Not coerced: `singleInstance: "false"` is a quoting mistake, and
        // reading it as truthy does the opposite of what was written.
        problems.add('dartvel.windowing.$name must be true or false, but is '
            '"$value".');
        sources[name] = 'default';
        return fallback;
      }
      sources[name] = 'pubspec.yaml';
      return value;
    }

    String readEnum(Map<Object?, Object?> from, String key, String name,
        Set<String> allowed, String fallback) {
      final Object? value = from[key];
      if (value == null) {
        sources[name] = 'default';
        return fallback;
      }
      if (value is! String || !allowed.contains(value)) {
        problems.add('dartvel.windowing.$name is "$value", which is not one of '
            '${allowed.join(', ')}.');
        sources[name] = 'default';
        return fallback;
      }
      sources[name] = 'pubspec.yaml';
      return value;
    }

    return DVWindowingConfig(
      enabled: readBool(windowing, 'enabled', 'enabled', fallback: true),
      singleInstance: readBool(windowing, 'singleInstance', 'singleInstance',
          fallback: true),
      exit: readEnum(windowing, 'exit', 'exit', _exitPolicies, 'lastWindow'),
      restoreOnLaunch: readBool(windowing, 'restoreOnLaunch', 'restoreOnLaunch',
          fallback: true),
      workspacePersist: readBool(workspace, 'persist', 'workspace.persist',
          fallback: true),
      workspaceTearOut: readEnum(
          workspace, 'tearOut', 'workspace.tearOut', _tearOutModes, 'auto'),
      sources: sources,
      problems: problems,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'singleInstance': singleInstance,
        'exit': exit,
        'restoreOnLaunch': restoreOnLaunch,
        'workspace': <String, Object?>{
          'persist': workspacePersist,
          'tearOut': workspaceTearOut,
        },
        'sources': sources,
        'problems': problems,
      };
}

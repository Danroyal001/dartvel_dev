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
    required this.displayNames,
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

  /// Per device profile, the names it gives displays against their positions.
  ///
  /// `displays: { Customer: { index: 1 } }` in a profile, which is where the
  /// specification puts them: a profile author knows a machine's screen layout
  /// before it boots, and `DVDisplayHint.byName('Customer')` is how a kiosk
  /// addresses one.
  final Map<String, Map<String, int>> displayNames;

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
      displayNames: _displayNames(dartvelSection, problems),
      sources: sources,
      problems: problems,
    );
  }

  /// Reads `dartvel.deviceProfiles.<id>.displays`.
  static Map<String, Map<String, int>> _displayNames(
    Object? dartvelSection,
    List<String> problems,
  ) {
    final Object? profiles =
        dartvelSection is Map ? dartvelSection['deviceProfiles'] : null;
    if (profiles == null) return const <String, Map<String, int>>{};
    if (profiles is! Map) {
      problems.add('dartvel.deviceProfiles must be a map, but is a '
          '${profiles.runtimeType}.');
      return const <String, Map<String, int>>{};
    }

    final Map<String, Map<String, int>> byProfile = <String, Map<String, int>>{};
    profiles.forEach((Object? id, Object? body) {
      final Object? displays = body is Map ? body['displays'] : null;
      if (displays == null) return;
      if (displays is! Map) {
        problems.add('dartvel.deviceProfiles.$id.displays must be a map, but '
            'is a ${displays.runtimeType}.');
        return;
      }

      final Map<String, int> names = <String, int>{};
      final Map<int, String> takenBy = <int, String>{};
      displays.forEach((Object? name, Object? entry) {
        final Object? index = entry is Map ? entry['index'] : null;
        if (index is! int) {
          // Never defaulted to zero: index 0 is the operator's own screen on
          // most machines, which is the one wrong answer that looks plausible.
          problems.add('dartvel.deviceProfiles.$id.displays.$name needs an '
              'integer index, e.g. { index: 1 }.');
          return;
        }
        if (index < 0) {
          problems.add('dartvel.deviceProfiles.$id.displays.$name has index '
              '$index, which is not a display position.');
          return;
        }
        final String? already = takenBy[index];
        if (already != null) {
          // Both are legal alone and the runtime has to pick one, so the
          // choice belongs in the profile rather than in iteration order.
          problems.add('dartvel.deviceProfiles.$id.displays gives index '
              '$index two names, "$already" and "$name".');
          return;
        }
        takenBy[index] = '$name';
        names['$name'] = index;
      });

      if (names.isNotEmpty) byProfile['$id'] = names;
    });
    return byProfile;
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
        'displayNames': displayNames,
        'sources': sources,
        'problems': problems,
      };
}

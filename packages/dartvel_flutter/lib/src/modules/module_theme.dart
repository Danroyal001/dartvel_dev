/// A module's theme, and how the parent's mode combines it with its own.
///
/// The mode lives in core, because it is read from a pubspec and carried into
/// the registry there. The combining lives here, because a ThemeData is
/// Flutter's and core does not import it.
///
/// A module declares its theme the way it declares its database: by calling
/// a method on its own registration. Nothing else can supply it -- the
/// parent's theme is the parent's, and a module's is written in the module.
library dartvel_flutter.modules.theme;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/material.dart';

/// Themes declared by modules, by module id.
///
/// Beside the registry rather than in it: DVModule is core's and a ThemeData
/// is not something core can hold.
final Map<String, ThemeData> _declared = <String, ThemeData>{};

/// A module's own look, and how it is read back.
extension DVModuleTheming on DVModule {
  /// Declares this module's theme.
  ///
  /// Called by the module's own code. What the parent does with it is the
  /// parent's `theme:` declaration, which the module never sees -- so the
  /// same module keeps its own look where it is asked to and takes the
  /// application's where it is not.
  void useTheme(ThemeData theme) => _declared[id] = theme;

  /// The theme this module declared, or null when it declared none.
  ThemeData? get declaredTheme => _declared[id];
}

/// Test-only: forgets every declared module theme.
@visibleForTesting
void dvResetModuleThemes() => _declared.clear();

/// Wraps [child] in whatever theme the module mounted as [moduleId] should
/// render in.
///
/// Applied by the generated router around a module's own pages. A module
/// nobody registered, or one that declared no theme of its own, renders in
/// the application's: a parent can ask for `override` and mount a module that
/// has nothing to override with, and dropping to Flutter's bare defaults
/// there would look like the application had broken.
Widget dvModuleTheme(BuildContext context, String moduleId, Widget child) {
  final DVModule? module = dvModuleRegistry.maybeGet(moduleId);
  if (module == null) return child;

  final DVModuleThemeMode mode = module.themeMode;
  if (mode == DVModuleThemeMode.inherit) return child;

  final ThemeData? own = module.declaredTheme;
  if (own == null) return child;

  final ThemeData parent = Theme.of(context);
  final ThemeData resolved = switch (mode) {
    // override and isolated coincide here, and it is worth being plain about
    // that rather than writing two branches that do the same thing. Theme
    // replaces what descendants see, so neither leaves a path back to the
    // parent's values -- not even through the fields the module left at
    // their defaults. Where the specification distinguishes them is what a
    // module may *reach for*, and a theme is not reached for: it is found by
    // looking up, and this stops the lookup either way.
    DVModuleThemeMode.override || DVModuleThemeMode.isolated => own,
    // What the module said, over what the application said. A ThemeData
    // carries a value for every field whether or not its author set one, so
    // "what the module did not say" is read from the fields that still hold
    // the framework's default.
    DVModuleThemeMode.extend => _extend(parent, own),
    DVModuleThemeMode.inherit => parent,
  };
  return Theme(data: resolved, child: child);
}

/// [own] applied over [parent], keeping the parent's value wherever the
/// module left the framework's default in place.
///
/// The comparison is against a bare ThemeData built the same way, because a
/// ThemeData has a value for every field whichever ones its author actually
/// wrote. Without that, "extend" and "override" would be the same thing under
/// two names.
ThemeData _extend(ThemeData parent, ThemeData own) {
  final ThemeData bare = ThemeData(brightness: own.brightness);
  return parent.copyWith(
    colorScheme: own.colorScheme == bare.colorScheme ? null : own.colorScheme,
    textTheme: own.textTheme == bare.textTheme ? null : own.textTheme,
    visualDensity:
        own.visualDensity == bare.visualDensity ? null : own.visualDensity,
    scaffoldBackgroundColor: own.scaffoldBackgroundColor ==
            bare.scaffoldBackgroundColor
        ? null
        : own.scaffoldBackgroundColor,
    appBarTheme: own.appBarTheme == bare.appBarTheme ? null : own.appBarTheme,
    cardTheme: own.cardTheme == bare.cardTheme ? null : own.cardTheme,
    iconTheme: own.iconTheme == bare.iconTheme ? null : own.iconTheme,
  );
}

/// A module's chrome, and how the parent's mode combines it with the page's.
///
/// The mode lives in core, because it is read from a pubspec and carried into
/// the registry there. The composing lives here, because chrome is widgets.
///
/// A module declares its chrome the way it declares its theme and its
/// database: by calling a method on its own registration. What the parent
/// does with it is the parent's `shell:` declaration, which the module never
/// sees, so the same module keeps its own chrome where it is asked to and
/// takes the application's where it is not.
library dartvel_flutter.modules.shell;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

/// Builds a module's chrome around [child].
typedef DVModuleShellBuilder = Widget Function(
    BuildContext context, Widget child);

final Map<String, DVModuleShellBuilder> _declared =
    <String, DVModuleShellBuilder>{};

/// A module's own chrome, and how it is read back.
extension DVModuleShelling on DVModule {
  /// Declares the chrome this module's pages sit in.
  void useShell(DVModuleShellBuilder builder) => _declared[id] = builder;

  /// The chrome this module declared, or null when it declared none.
  DVModuleShellBuilder? get declaredShell => _declared[id];
}

/// Test-only: forgets every declared module shell.
@visibleForTesting
void dvResetModuleShells() => _declared.clear();

/// Whether the page inside this subtree should draw its own scaffold.
///
/// An InheritedWidget rather than a constructor argument, because the page
/// widget between the router and DVPageShell is generated from the module's
/// own project and knows nothing about being mounted. The mount point is the
/// parent's decision, and so is this.
class DVPageChrome extends InheritedWidget {
  const DVPageChrome({
    super.key,
    required this.draw,
    required super.child,
  });

  /// False where the module's mode replaced the page's chrome or removed it.
  final bool draw;

  /// Whether a page under [context] should draw its own scaffold. True when
  /// nothing said otherwise, which is every page outside a module.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DVPageChrome>()?.draw ?? true;

  @override
  bool updateShouldNotify(DVPageChrome oldWidget) => draw != oldWidget.draw;
}

/// Wraps [child] in whatever chrome the module mounted as [moduleId] should
/// render in.
///
/// Applied by the generated router around a module's own pages, and nowhere
/// else: putting a module's chrome around the application's own pages would
/// be the mode applying to the wrong half of the application.
Widget dvModuleShell(BuildContext context, String moduleId, Widget child) {
  final DVModule? module = dvModuleRegistry.maybeGet(moduleId);
  if (module == null) return child;

  final DVModuleShellMode mode = module.shellMode;
  if (mode == DVModuleShellMode.inherit) return child;

  final DVModuleShellBuilder? own = module.declaredShell;

  // Unlike a theme, an absent shell is a decision the parent can make on its
  // own: "this module has no chrome" needs nothing from the module, so
  // override and none both take effect whether or not one was declared.
  final bool drawPageChrome = mode == DVModuleShellMode.extend;
  final Widget page = DVPageChrome(draw: drawPageChrome, child: child);

  // none means none, the module's own included. A module that declares
  // chrome and is mounted into a kiosk screen has to lose it, or the parent
  // asked for a bare panel and got a titled one.
  if (mode == DVModuleShellMode.none || own == null) return page;
  return Builder(builder: (BuildContext inner) => own(inner, page));
}

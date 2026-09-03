/// Stand-in for builds without `dart:ffi` — the web.
library dartvel_flutter.platform.windows.unsupported;

import 'windows_capabilities.dart';

/// The Windows bindings, unavailable here.
class DVWindowsBindings {
  const DVWindowsBindings._();

  static bool get isRegistered => false;

  /// What Win32 covers, which is a fact about the platform rather than about
  /// where this code is running — so the list can be asserted anywhere.
  static const Set<String> implemented = dvWindowsImplementedBindings;

  static bool register() => false;

  static void unregister() {}
}

/// The Windows kiosk enforcement, unavailable here.
class DVWindowsKiosk {
  const DVWindowsKiosk._();

  static String? lastConfineError;
  static bool confined = false;
  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};
  static List<String> get held => const <String>[];
  static Future<void> release() async {}
}

/// The Windows global shortcuts, unavailable here.
class DVWindowsShortcuts {
  const DVWindowsShortcuts._();

  static const Set<String> implemented = <String>{'shortcuts.register', 'shortcuts.unregister'};
  static int? get debugPumpThread => null;
  static int? debugNumericId(String id) => null;
  static Future<void> unregister() async {}
}

/// The Windows application menu, unavailable here.
class DVWindowsMenus {
  const DVWindowsMenus._();

  static const Set<String> implemented = <String>{'menus.setApplicationMenu'};
  static int? get debugWindow => null;
  static List<String> menuTitles(int hWnd) => const <String>[];
  static void unregister() {}
}

/// The Windows tray icon, unavailable here.
class DVWindowsTray {
  const DVWindowsTray._();

  static const Set<String> implemented = <String>{'tray.show', 'tray.hide'};
  static String? lastError;
  static bool get shown => false;
  static int? debugCommandFor(String id) => null;
  static void unregister() {}
}

/// Printing, unavailable here.
class DVWindowsPrinting {
  const DVWindowsPrinting._();

  static const Set<String> implemented = <String>{'printing.toFile'};
}

/// What a Windows dialog showed, unavailable here.
class DVWindowsDialogSeen {
  const DVWindowsDialogSeen({this.title, this.filterLabels = const <String>[], this.currentFolder, this.currentName, this.messageText});
  final String? title;
  final List<String> filterLabels;
  final String? currentFolder;
  final String? currentName;
  final String? messageText;
}

/// A Windows dialog, unavailable here.
class DVWindowsDialog {
  const DVWindowsDialog._();
  DVWindowsDialogSeen inspect() => const DVWindowsDialogSeen();
  void selectPath(String path) {}
  void accept() {}
  void cancel() {}
}

typedef DVWindowsDialogAutomation = void Function(DVWindowsDialog dialog);

/// The Windows dialogs, unavailable here.
class DVWindowsDialogs {
  const DVWindowsDialogs._();

  static const Set<String> implemented = <String>{'dialogs.openFile', 'dialogs.saveFile', 'dialogs.chooseDirectory', 'dialogs.message', 'media.pick'};
  static String? lastError;
  static Duration automationTimeout = const Duration(seconds: 8);
  static void automate(DVWindowsDialogAutomation? automation) {}
  static void unregister() {}
}

/// The names the Windows bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies drift, and a drifted capability list is invisible:
/// the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.windows.capabilities;

/// What Win32 is bound for, and nothing more.
///
/// Notifications are absent deliberately. A modern Windows toast needs an
/// AppUserModelID registered against a real Start Menu shortcut, and the
/// legacy `Shell_NotifyIcon` balloon is deprecated and silently ignored under
/// Focus Assist. Registering either would produce a binding that reports
/// success and shows nothing, which is worse than the "not registered" error.
const Set<String> dvWindowsImplementedBindings = <String>{
  // user32 clipboard, with the global-memory dance it requires.
  'clipboard.copy',
  'clipboard.paste',

  // GetSystemMetrics.
  'screen.geometry',

  // SetWindowText and ShowWindow against the process's own top-level window.
  'window.setTitle',
  'window.maximize',
  'window.minimize',
  'window.restore',

  // SetWindowPos, moving nothing and reordering nothing.
  'window.setSize',
};

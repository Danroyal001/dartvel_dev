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

  // RegisterHotKey for the escape combos, ClipCursor for the pointer, the
  // window style for fullscreen. Notifications are never claimed held: Focus
  // Assist has no public API.
  'kiosk.enforce',
  'kiosk.release',

  // RegisterHotKey on a pump thread of its own, which is where Win32
  // delivers WM_HOTKEY; a refusal carries the Win32 error.
  'shortcuts.register',
  'shortcuts.unregister',

  // The shared device runtime -- manifest, health, watchdog, provisioning,
  // diagnostics -- reading through this platform's probes.
  'device.capabilityManifest',
  'device.health',
  'device.watchdog.arm',
  'device.watchdog.heartbeat',
  'device.fleet.provision',
  'device.diagnostics.collect',

  // A Win32 menu bar on the process's window, the window subclassed so
  // WM_COMMAND is dispatched by the item's id.
  'menus.setApplicationMenu',

  // Shell_NotifyIcon on the process's window: the icon, its tooltip, a
  // popup menu on click, the item chosen dispatched by id. Refused where the
  // session has no notification area.
  'tray.show',
  'tray.hide',

  // GDI: pictures onto pages, to a PDF through Microsoft Print to PDF with
  // the output named so no dialog asks, or to the default printer.
  'printing.toFile',
  'printing.print',

  // What a desktop grants without asking, and the deep link the app was
  // launched with: the same answers as Linux, being facts about a desktop
  // process rather than about the desktop.
  'permissions.isGranted',
  'permissions.request',
  'deepLinks.initial',

  // The common dialogs with a hook, the folder browser with its callback,
  // the message box under a CBT hook: each answerable from its own loop.
  'dialogs.openFile',
  'dialogs.saveFile',
  'dialogs.chooseDirectory',
  'dialogs.message',
  'media.pick',

  // An OLE drop target on the process's window: CF_HDROP for the files a
  // file manager drags, CF_UNICODETEXT for a browser's text.
  'dragDrop.accept',
  'dragDrop.stop',
};

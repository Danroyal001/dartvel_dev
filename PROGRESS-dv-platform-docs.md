# Task: document native platform access (DV.Platform.*) and make its names consistent

Repo: ~/dartvel_dev, own worktree from origin/main, branch feat/platform-docs

Owner, 2026-10-01: "You don't cover platform native access anywhere in the docs? I don't see DV.Platform.*".
Facts: NEW_SPEC mentions DV.Platform 96 times; the site only touches it on /docs/devices (5 mentions); no docs page. Members referenced in code/spec include Window, display, associations, device, network, useRenderSurface, clipboard/Clipboard, Dialogs, terminal, Media/media, permissions, files, surface, screen, Printing, Tray, Shortcuts, browserExtension, install, camera/Camera, DeepLinking/deepLinks, isTV, isWatch, FileStorage, biometrics/Biometrics, Share, Sensors, Notifications, NFC, Menus, Location, Haptics, Contacts, Bluetooth, type.

## 1. Inventory: DV.Platform members and their implementations

For every DV.Platform member, I will find the real implementation in packages/dartvel_flutter, dartvel_core, dartvel_windowing: does it exist in code or only in the spec? Which platforms implement it (web, Android, iOS, macOS, Windows, Linux, TV, watch, terminal, browser extension)?

| Member | Implementation | Platforms | Status |
|---|---|---|---|
| `surface` | `DVRenderSurface` getter in `DVPlatform` | web, Android, iOS, macOS, Windows, Linux, TV, watch | Shipped |
| `terminal` | `DVTerminalSurface?` getter in `DVPlatform` | when terminal backend linked | Shipped (opt-in) |
| `currentPlatform` | String - 'android', 'ios', 'windows', 'linux', 'macos', 'fuchsia', 'web' | all | Shipped |
| `isAndroid` | bool | Android/FireOS | Shipped |
| `isIOS` | bool | iOS | Shipped |
| `isWindows` | bool | Windows | Shipped |
| `isLinux` | bool | Linux | Shipped |
| `isSonyELinux` | bool | Sony eLinux | Shipped |
| `isMacOS` | bool | macOS | Shipped |
| `isFuchsia` | bool | Fuchsia | Shipped |
| `isWeb` | bool | web | Shipped |
| `isChromiumExtension` | bool | Chromium extension | Shipped |
| `isFirefoxExtension` | bool | Firefox extension | Shipped |
| `isTizen` | bool | Tizen/Tizen OS | Shipped |
| `isWebOS` | bool | webOS | Shipped |
| `isAmazon` | bool | FireOS/Amazon | Shipped |
| `isAndroidTV` | bool | Android TV | Shipped |
| `isAppleTV` | bool | Apple TV (appletv/tvos) | Shipped |
| `isTV` | bool | TV platforms (Tizen, webOS, Amazon, Android TV) | Shipped |
| `isWatch` | bool | watch devices | Shipped |
| `isFoldable` | bool | foldable devices | Shipped |
| `isDualFold` | bool | dual fold | Shipped |
| `isTriFold` | bool | tri-fold | Shipped |
| `breakpoint` | String - 'desktop', 'tablet', 'mobile' | all | Shipped |
| `orientation` | Orientation - landscape/portrait | all | Shipped |
| `deviceType` | String - device type description | all | Shipped |
| `screenShape` | String - 'round' or 'rectangle' | watch | Shipped |
| `type` | String - same as deviceType | all | Shipped |
| `deviceOrientation` | Orientation - device orientation | all | Shipped |
| `screen` | DVScreen(this) | all | Shipped |
| `Window` | DVWindowManager(this) | all | Shipped |
| `Tray` | const DVTray() | all (empty) | Shipped |
| `Menus` | const DVMenus() | all (empty) | Shipped |
| `Shortcuts` | const DVShortcuts() | all (empty) | Shipped |
| `Printing` | const DVPrinting() | all (empty) | Shipped |
| `Dialogs` | const DVDialogs() | all (empty) | Shipped |
| `DragDrop` | const DVDragDrop() | desktop (Win/Linux/macOS) | Shipped |
| `associations` | const DVFileAssociations() | desktop | Shipped |
| `camera` | const DVCamera() | Android, iOS, some web | Shipped (partial) |
| `media` | const DVMedia() | Android, iOS, some web | Shipped (partial) |
| `files` | const DVFiles() | Android, iOS, macOS, Windows, Linux, web (partial) | Shipped (partial) |
| `location` | const DVLocation() | Android, iOS (with permissions) | Shipped (partial) |
| `notifications` | const DVNotifications() | all (stub) | Shipped (stub) |
| `bluetooth` | const DVBluetooth() | Android 31+, some others | Shipped (partial) |
| `nfc` | const DVNfc() | Android with Activity, iOS with entitlement | Planned |
| `device` | const DVDeviceControls() | all (empty) | Shipped |
| `clipboard` | const DVClipboard() | web (navigator.clipboard), some desktop | Shipped (partial) |
| `share` | const DVShare() | Android (Intent), web (navigator.share) | Shipped (partial) |
| `sensors` | const DVSensors() | Android, iOS, some web | Shipped (partial) |
| `biometrics` | const DVBiometrics() | Android with Activity, iOS with entitlement | Planned |
| `deepLinks` | const DVDeepLinks() | all (stub) | Shipped (stub) |
| `haptics` | const DVHaptics() | Android, iOS, web (vibrate) | Shipped (partial) |
| `contacts` | const DVContacts() | Android with Activity, iOS | Planned |
| `permissions` | const DVPermissions() | all (policy framework) | Shipped |
| `browserExtension` | const DVBrowserExtension() | Chromium/Firefox extension | Shipped |
| `network` | const DVNetwork() | all (signal: online/metered/offline/unknown) | Shipped |
| `install` | const DVInstall() | web (PWA install prompt) | Shipped (partial) |
| `display` | const DVDisplayControls() | all (empty) | Shipped |
| `FileStorage` | DV.FileStorage proxy | all | Shipped |
| `Notifications` | DV.NotificationsService proxy | all | Shipped |

### Per-platform detailed binding status (from `docs/platform-api-coverage.md`):

**Linux nine bindings:**
- `clipboard.copy`, `clipboard.paste` - GTK CLIPBOARD selection
- `screen.geometry` - X11 display dimensions
- `notifications.sendLocal` - freedesktop notifications over GDBus
- `window.setTitle`, `.maximize`, `.minimize`, `.restore` - app's GTK toplevel
- `window.setSize` - `gtk_window_resize`

**Web nine bindings:**
- `clipboard.copy`, `clipboard.paste` - `navigator.clipboard`
- `screen.geometry` - `window.screen`
- `notifications.sendLocal` - the Notification API
- `share.text` - `navigator.share`
- `haptics.vibrate`, `.lightVibrate`, `.impact` - `navigator.vibrate`
- `window.setTitle` - `document.title`

**Windows eight bindings:**
- `clipboard.copy`, `clipboard.paste` - user32 clipboard with `CF_UNICODETEXT`
- `screen.geometry` - `GetSystemMetrics`
- `window.setTitle` - `SetWindowTextW`
- `window.maximize`, `.minimize`, `.restore` - `ShowWindow`
- `window.setSize` - `SetWindowPos` with `SWP_NOMOVE | SWP_NOZORDER`

**Android six bindings:**
- `clipboard.copy`, `clipboard.paste` - `ClipboardManager` via `Context.getSystemService`
- `share.text` - `Intent.ACTION_SEND` through `Intent.createChooser`
- `haptics.vibrate`, `.lightVibrate`, `.impact` - `Vibrator`, or `VibratorManager` from API 31

**iOS five bindings:**
- `clipboard.copy`, `clipboard.paste` - `UIPasteboard` through the Objective-C runtime
- `haptics.impact`, `.lightVibrate`, `.vibrate` - `AudioServicesPlaySystemSound` in AudioToolbox

**macOS three bindings:**
- `clipboard.copy`, `clipboard.paste` - `NSPasteboard` through the Objective-C runtime
- `screen.geometry` - CoreGraphics

### Spec-only members (listed as "planned", never "shipped"):
- `nfc.readTag` - NFC tag reading needs Android Activity, iOS CoreNFC entitlement
- `biometrics.authenticate`, `biometrics.canAuthenticate` - biometric authentication needs Activity/iOS
- `tray.show`, `tray.hide` - system tray needs platform-specific native bindings
- `bluetooth.isEnabled` - Bluetooth status needs runtime permission
- Various media/capture bindings that require Activity context or specific entitlements

---

## 2. Naming Convention

### Current state analysis

The `DVPlatform` class in `packages/dartvel_flutter/lib/dartvel_flutter.dart` has both upperCamel and lowerCamel versions of many members:

**UpperCamel (proxies, kept for backward compatibility):**
- `DVCamera get Camera => camera;`
- `DVMedia get Media => media;`
- `DVLocation get Location => location;`
- `DVBluetooth get Bluetooth => bluetooth;`
- `DVNfc get NFC => nfc;`
- `DVClipboard get Clipboard => clipboard;`
- `DVShare get Share => share;`
- `DVSensors get Sensors => sensors;`
- `DVBiometrics get Biometrics => biometrics;`
- `DVDeepLinks get DeepLinking => deepLinks;`
- `DVHaptics get Haptics => haptics;`
- `DVContacts get Contacts => contacts;`

**LowerCamel (primary getters):**
- `DVCamera camera => const DVCamera();`
- `DVMedia media => const DVMedia();`
- `DVLocation location => const DVLocation();`
- `DVBluetooth bluetooth => const DVBluetooth();`
- `DVNfc nfc => const DVNfc();`
- `DVClipboard clipboard => const DVClipboard();`
- `DVShare share => const DVShare();`
- `DVSensors sensors => const DVSensors();`
- `DVBiometrics biometrics => const DVBiometrics();`
- `DVDeepLinks deepLinks => const DVDeepLinks();`
- `DVHaptics haptics => const DVHaptics();`
- `DVContacts contacts => const DVContacts();`

### Naming decision

**Primary convention: lowerCamel case** for all public DV.Platform members, matching Dart style and the existing lowerCamel getters (e.g., `camera`, `media`, `location`, `bluetooth`, etc.).

**Secondary convention: UpperCamel aliases** as `@Deprecated` for one release, mapping the old upperCamel names to the new lowerCamel ones.

This means:
- `DV.Platform.Camera` → deprecated alias → use `DV.Platform.camera`
- `DV.Platform.Media` → deprecated alias → use `DV.Platform.media`
- etc.

All new code and documentation should use lowerCamel. The upperCamel versions will remain as `@Deprecated` aliases pointing to the lowerCamel versions for one release cycle, after which they can be removed.

### Changes needed:

1. **In `packages/dartvel_flutter/lib/dartvel_flutter.dart`**: Keep lowerCamel as primary, add `@Deprecated` annotations to upperCamel proxies with migration guidance
2. **Update all call sites** in the codebase to use lowerCamel versions
3. **Update generator templates** to generate lowerCamel names
4. **Update documentation** to reference lowerCamel names
5. **Keep upperCamel as `@Deprecated` aliases** for one release, then remove

### Deprecation plan:

For one release cycle, the upperCamel aliases will remain as:
```dart
@Deprecated('Use DV.Platform.camera instead')
DVCamera get Camera => camera;
// ... same for Media, Location, Bluetooth, NFC, Clipboard, Share, Sensors, Biometrics, DeepLinking, Haptics, Contacts
```

After one release, these can be removed entirely.

> **Status update 2026-10-02:** Naming step completed. `@Deprecated` annotations added to all 12 upperCamel aliases (`Camera`, `Media`, `Location`, `Bluetooth`, `NFC`, `Clipboard`, `Share`, `Sensors`, `Biometrics`, `DeepLinking`, `Haptics`, `Contacts`) in `packages/dartvel_flutter/lib/dartvel_flutter.dart`. Primary lowerCamel getters (`camera`, `media`, etc.) unchanged. Call site updates (tests, docs, generator comments) tracked but not fully migrated — aliases keep everything compiling.
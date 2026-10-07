/// Launch at login on macOS: SMAppService's main-app login item.
///
/// macOS 13 and later register the running bundle as a login item with
/// `SMAppService.mainAppService`, which is what System Settings' Login Items
/// list shows and what a user turns off there -- so the state is read back
/// from the service rather than remembered. Earlier systems have no
/// SMAppService; the binding is left unregistered there, so isSupported
/// reads false, rather than writing a launch agent behind the user's back.
library;

import 'dart:async';
import 'dart:ffi';

import 'macos_menus_ffi.dart';

typedef _RegisterN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _RegisterD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);

class DVMacosLaunchAtLogin {
  const DVMacosLaunchAtLogin._();

  static const Set<String> implemented = <String>{'launchAtLogin.isEnabled', 'launchAtLogin.setEnabled'};

  /// SMAppServiceStatus: 0 notRegistered, 1 enabled, 2 requiresApproval,
  /// 3 notFound.
  static const int _enabled = 1;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    try {
      DynamicLibrary.open('/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement');
    } on ArgumentError {
      return;
    }
    final DVMacosObjc o = DVMacosObjc(objc);
    if (o.cls('SMAppService') == nullptr) return;
    Pointer<Void> service() => o.send0(o.cls('SMAppService'), 'mainAppService');
    bind('launchAtLogin.isEnabled', (Object? _) => o.getInt(service(), 'status') == _enabled);
    bind('launchAtLogin.setEnabled', (Object? arguments) {
      final bool enabled = arguments is Map && arguments['enabled'] == true;
      final Pointer<Void> app = service();
      // Already in the asked-for state: SMAppService answers an error for
      // registering a registered item, which is not a failure here.
      if ((o.getInt(app, 'status') == _enabled) == enabled) return true;
      return objc.lookupFunction<_RegisterN, _RegisterD>('objc_msgSend')(
        app,
        o.sel(enabled ? 'registerAndReturnError:' : 'unregisterAndReturnError:'),
        nullptr,
      );
    });
  }
}

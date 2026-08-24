/// Browser platform bindings, behind a conditional import so a native build
/// never sees `dart:js_interop`.
library dartvel_flutter.platform.web;

export 'web_bindings_unsupported.dart'
    if (dart.library.js_interop) 'web_bindings_js.dart';

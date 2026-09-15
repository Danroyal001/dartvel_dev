import 'dart:io';

import 'package:dartvel_core/dartvel.dart';

import '../platform/device_runtime.dart';
import '../platform/webcrypto_key_store_io.dart';
import 'session_client.dart';

/// A sealed session token in a file.
///
/// The path is resolved on each use rather than at construction, because the
/// generated runtime builds the store before the platform bindings have named
/// the directory an Android application may write.
class DVFileSessionTokenSink implements DVSessionTokenSink {
  DVFileSessionTokenSink(String path) : _path = (() => path);

  DVFileSessionTokenSink.resolving(String Function() path) : _path = path;

  final String Function() _path;

  @override
  Future<String?> read() async {
    final File file = File(_path());
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String? value) async {
    final File file = File(_path());
    if (value == null) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    // Written beside it and renamed over it, so a crash mid-write leaves the
    // previous token or the new one and never half of either.
    final File partial = File('${file.path}.partial');
    await partial.writeAsString(value, flush: true);
    await partial.rename(file.path);
  }
}

/// The session token store a generated runtime uses for [app]: sealed under
/// the application key `dartvel key` manages, in a file in the device's state
/// directory, else under the user's home.
DVSessionTokenStore? dvSessionTokenStoreFor(String app) =>
    DVSealedSessionTokenStore(
      sink: DVFileSessionTokenSink.resolving(() {
        final String? state = DVDeviceRuntime.stateDirectory;
        return state != null
            ? '$state/sessions/$app.token'
            : '${dvHostHome() ?? Directory.systemTemp.path}/.dartvel/sessions/$app.token';
      }),
      keys: () => dvAppKeyStoreFor(app),
    );

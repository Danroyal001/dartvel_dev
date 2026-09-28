import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'dart:io' show exit;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:dartvel_core/dartvel.dart' show DVCredentialedOrigins, DVCrashConfig, DVDevServerHost, dvDevBackendUrl, DVCrashSink, DVCrashStore, DVModuleRpc, DVStartupProfile, dvLiveWindowsPathFor, dvLocalAnalyticsDatabase;
import 'package:dartvel_core/framework.dart' show DVOfflineReplay, DVOfflineSync, dvLocalOfflineDatabase, dvOfflineSendOverHttp;
import 'package:dartvel_flutter/dartvel_flutter.dart' show DV, DVAuth, DVNetworkStatus, DVSessionAuthProvider, DVSessionClient, dvSessionDeviceLabel, dvSessionTokenStoreFor, DVAppLifecycle, DVCrashInstallation, DVDeviceRuntime, DVPageStore, dvStartAppLifecycleBridge, DVWindowSharedStore, dvAppKeyStoreFor, DVLinuxBindings, DVWindowsBindings, DVMacosBindings, DVIosBindings, DVAndroidBindings, DVWebBindings, DVShorebirdUpdates, DVAppLaunch, DVHomeWidgets, DVNativeBridge, DVRouteTarget, DVWindowOptions, DVRenderSurface;
import 'dartvel_config.g.dart' as cfg;
import 'home_widgets.g.dart' show dartvelHomeWidgets;
import 'flags.g.dart' show registerDartvelFlags;
import 'http.g.dart' show configureDartvelHttp;
import 'analytics.g.dart' show configureDartvelAnalytics;
import 'client_jobs.g.dart' show registerDartvelClientJobs;
import 'models.g.dart' show registerDartvelModels;
import 'modules.g.dart' show registerDartvelModules;
import 'client_schedules.g.dart' show dartvelStartClientSchedules;
import 'policies.g.dart' show dartvelRegisterPolicies;
import 'functions.g.dart' show DartvelClient, dvModuleRpcSend;

/// Wires the generated runtime into the short `DV.baseUrl` / `DV.api(...)` API.
/// Called automatically during app/router initialization.
///
/// This runs while the router is being built, which is **before `runApp`**.
/// Nothing added here may assume a Flutter binding exists: reading
/// `WidgetsBinding.instance` throws at this point, the application never
/// reaches its first frame, and no package test catches it because a widget
/// test always has a binding already. What it looks like instead is the site
/// build reporting "Captured 0 of 4 routes" and blaming resource pressure.
/// Call `WidgetsFlutterBinding.ensureInitialized()` and use what it returns.
void configureDartvelRuntime({List<String> arguments = const <String>[]}) {
  // The application lifecycle, which had a setter called from nowhere but
  // its own test: an application observing DV.lifecycle.app saw
  // uninitialized for the life of the process. An enum that reports one
  // value forever is a field, not a signal.
  DV.lifecycle.setApp(DVAppLifecycle.booting);
  // And every state after this one, from the platform. booting and ready
  // were the only two anything ever set, so an application observing the
  // signal to save a draft when it goes into the background never saw
  // backgrounded and one refreshing on the way back never saw the return --
  // an enum whose other states existed and were produced by nothing.
  dvStartAppLifecycleBridge();
  DV.registerRuntime(
    baseUrl: () => DartvelRuntime.baseUrl,
    apiBasePath: () => DartvelRuntime.apiBasePath,
    api: DartvelRuntime.api,
  );
  // A dispatched job is useless without its codec and handler, so they are
  // registered as part of configuring the runtime rather than left to the
  // application to remember.
  // Startup, phase by phase: what a device fleet is asked to answer for.
  DVStartupProfile.current.mark('configure');
  // Every codec and handler, the ones only a Flutter process can run too.
  registerDartvelClientJobs();
  // The flags this build declares, so a synced rule set naming one it does
  // not know is reported rather than silently ignored.
  registerDartvelFlags();
  registerDartvelModels();
  // The modules this application mounts, so DV.Modules.<id> is the module
  // the build mounted rather than an unknown id.
  registerDartvelModules();
  // The hosts dartvel.http declares, before anything can call out: a
  // project that declared its gateway in pubspec.yaml otherwise met
  // DV-HTTP-001 on its first DV.Http request.
  configureDartvelHttp();
  // A module call carried to the backend goes the way every other call does.
  DVModuleRpc.transport = dvModuleRpcSend;
  // What this application's @DVHomeWidget declarations are. The list was
  // generated, exported from the barrel and read by nothing -- so
  // DVHomeWidgets.publish took any string at all, and a misspelled id wrote
  // under a key no widget asks for and left the home screen showing its
  // placeholder, with true coming back to the caller.
  DVHomeWidgets.declare(dartvelHomeWidgets);
  DVStartupProfile.current.mark('generated');
  // The platform's native bindings -- clipboard, window, notifications and
  // the rest. Registered here rather than left to the application, because a
  // separate call the application had to remember is exactly how every real
  // app on Linux was throwing "binding not registered" from
  // DV.Platform.Clipboard.copy().
  registerPlatformBindings();
  DVStartupProfile.current.mark('bindings');
  // Crash reporting, after the bindings: on Android the directory the records
  // are kept in is the files directory they found. Before this nothing
  // installed the crash runtime, so a real application recorded no crash.
  installDartvelCrashReporting();
  // DV.Auth signs in through this application's own backend unless the
  // application configures another provider. A native session token is
  // sealed under the application key `dartvel key` manages before it is
  // written, and handed to every generated call; in a browser the server's
  // HttpOnly cookie is the session and no token is kept. After the bindings,
  // because on Android the token file goes in the directory they find. A
  // stored session is checked with the server at launch; the keyring is asked
  // nothing unless one is stored.
  //
  // In a browser the cookie goes to the page's own origin unless a fetch asks
  // for credentials, so a web build served from another origin than its API
  // was signed out on every call. The backend's origin is named, exactly, and
  // nothing else is: the server's half is dartvel.server.cors with
  // allowCredentials and the web build's origins listed.
  if (kIsWeb) {
    final String? credentials = DVCredentialedOrigins.allowBackend(DartvelRuntime.baseUrl);
    if (credentials != null) debugPrint('[dartvel] $credentials');
  }
  final DVSessionClient dartvelSessions = DVSessionClient(
    api: DartvelRuntime.api,
    onToken: (String? token) => DartvelClient.setAuthToken(token ?? ''),
    tokens: kIsWeb ? null : dvSessionTokenStoreFor('dartvel_dev'),
    // The platform and the kind of client, so the sessions page tells
    // devices apart -- never a host name or anything else that names the
    // machine or the person.
    device: dvSessionDeviceLabel(),
  );
  DVSessionClient.install(dartvelSessions);
  DVAuth.installDefaultProvider(DVSessionAuthProvider(dartvelSessions));
  // Offline data models: every write is queued on this device, and this is
  // what sends the queue -- now, for whatever the last session left, and
  // again whenever DV.Platform.network says the server can be reached. It
  // posts as the signed-in person, with the headers every generated call
  // carries. The store is the platform's: a SQLite file on a device,
  // IndexedDB in a browser. Opened only when an offline model is used.
  DVOfflineSync.install(
    database: () => dvLocalOfflineDatabase('dartvel_dev', androidStateDirectory: DVDeviceRuntime.stateDirectory),
    send: dvOfflineSendOverHttp(
      endpoint: () => DartvelRuntime.api(DVOfflineReplay.path),
      headers: () => DartvelClient.defaultHeaders,
    ),
    reachability: DV.Platform.network.changes.map((DVNetworkStatus status) => status != DVNetworkStatus.offline),
    canReachTheServer: () => DV.Platform.network.canReachTheServer,
  );
  // A generated call refused for a missing second factor presents the
  // challenge over the current screen and is sent again once it is presented.
  DVAuth.installStepUp();
  if (!kIsWeb) {
    unawaited(dartvelSessions.restore().then<void>((_) {}, onError: (Object _) {}));
  }
  // DV.Analytics from dartvel.analytics, over this device's own database:
  // consent belongs to the install. After the bindings, because the database
  // is opened as the runtime starts and on Android the directory it goes in
  // is the files directory they find; and after the flags, so the exposure
  // sink it connects is for flags the runtime knows. Nothing in a project
  // that declares no analytics.
  configureDartvelAnalytics(database: () => dvLocalAnalyticsDatabase('dartvel_dev', androidStateDirectory: DVDeviceRuntime.stateDirectory));
  // The arguments this process was started with -- a file association, a
  // dartvel:// link, a second launch -- and the launches that come after it.
  startDartvelLaunch(arguments);
  // World anchor tokens in the shared window store are encrypted under the
  // application key, and refused when there is none. The store has no
  // application id to name a key store by; this is the name `dartvel key`
  // manages. Set before any store below is made, and read only when a token
  // is first written, so no keyring is asked anything at startup.
  DVWindowSharedStore.defaultAppKeys = () => dvAppKeyStoreFor('dartvel_dev');

  // Every @DVClientCron schedule, registered and ticking. The entries were
  // generated and nothing started them, so a schedule declared on a page
  // never ran once. Starts no timer when the application declares none.
  dartvelStartClientSchedules();

  // Every @DVPolicy class, registered before a page can ask whether to draw
  // an action: a client that registered nothing would hide every one of
  // them. The generated server registers the ones it can load -- every class
  // whose file does not reach Flutter -- before its first route exists.
  dartvelRegisterPolicies();

  // Reads stored Studio documents into memory so an override resolves during
  // navigation instead of flashing the compiled page first.
  unawaited(DVPageStore.prime());

  // The last phase is the one that matters to whoever is waiting: the frame
  // they can see. Measured after the frame rather than before it, because a
  // router that is built is not a screen that is up.
  //
  // The binding is ensured rather than assumed. This runs from the router's
  // constructor, before runApp, so on a real launch there is no binding yet
  // and `WidgetsBinding.instance` throws on a null check -- which took the
  // application down at startup rather than reporting a bad measurement. It
  // is idempotent and returns whatever binding is already installed, so a
  // test binding stays the one in use.
  WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
    DVStartupProfile.current.mark('first frame');
    // Ready here rather than at the end of configuration: a router that is
    // built is not a screen somebody can see, which is the same reason the
    // startup profile measures the frame instead of the constructor.
    DV.lifecycle.setApp(DVAppLifecycle.ready);
  });
}

/// Installs DV.Crashes for this application: FlutterError.onError,
/// PlatformDispatcher.onError and the isolate's (or the window's) error
/// listeners, each chained to whatever handler was already there, and the
/// reports the previous run left sent now.
///
/// Returns null under `flutter test`, where the test framework owns those
/// hooks, unless [evenUnderTest]. [store] and [sink] replace the defaults.
DVCrashInstallation? installDartvelCrashReporting({DVCrashStore? store, DVCrashSink? sink, bool evenUnderTest = false}) =>
    DV.Crashes.installApplication(
      appId: 'dartvel_dev',
      release: '0.9.0',
      // dartvel.crashes, as the build checked it.
      config: DVCrashConfig.parse(<String, Object?>{
        'sink': 'none',
        'nonFatalSampleRate': 1.0,
        'breadcrumbs': 64,
        'fullReportsPerRelease': 5,
        'ingest': <String, Object?>{
          'perInstallPerHour': 30,
          'perSourcePerHour': 300,
          'maxBytes': 262144,
        },
      }),
      // The backend a Dartvel sink sends to: the one this runtime calls.
      api: DartvelRuntime.api,
      store: store,
      sink: sink,
      evenUnderTest: evenUnderTest,
    );

/// The rendering backends this build links. GUI only: there is no decision
/// to make at launch, and no terminal code to make it with.
const Set<DVRenderSurface> dartvelLinkedSurfaces = <DVRenderSurface>{DVRenderSurface.gui};

/// Nothing to negotiate in a GUI-only build. Awaited by main so that a
/// build with the terminal linked can put a decision here.
Future<void> negotiateDartvelLaunch(List<String> arguments) async {}


/// Takes the single-instance lock and opens what this launch asked for, or
/// hands it to the process that has the lock and ends this one. Desktop
/// only: elsewhere a launch has no arguments and no second process.
void startDartvelLaunch(List<String> arguments) {
  if (kIsWeb) return;
  final bool desktop = switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
    _ => false,
  };
  if (!desktop) {
    // Android and iOS carry the link on the launch rather than on argv: the
    // Activity's intent on one, the two AppDelegate overrides dartvel build
    // writes on the other. Both ends of that were built and nothing joined
    // them up, because this function starts on desktop and returned here --
    // so a home widget's tap opened the application at its own starting
    // route. It comes up, at the wrong place, which is what makes it a bug
    // nobody reports.
    //
    // After the first frame, because DV.Navigation throws without a router
    // and this runs from the router's constructor, before runApp. invoke
    // rather than require, because a platform with no binding for the name
    // must still start.
    WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
      unawaited(DVAppLaunch.openLaunchLink(
        link: () => DVNativeBridge.invoke<String>('deepLinks.initial'),
        open: (String route) async =>
            DV.Navigation.navigate(DVRouteTarget(route)),
      ));
    });
    return;
  }
  unawaited(DVAppLaunch.start(
    appId: 'dartvel_dev',
    arguments: arguments,
    open: (String route) async {
      await DV.Platform.Window.open(DVRouteTarget(route), options: DVWindowOptions.external);
    },
  ).then((result) {
    // A second launch has done its job once its arguments are handed over;
    // staying open would be a second window of the same application.
    if (!result.isPrimary) exit(0);
    // The one that stays publishes what it has open beside its lock, for
    // `dartvel inspect windows` to read while it runs.
    DV.Platform.Window.publishLiveWindows(dvLiveWindowsPathFor('dartvel_dev'), app: 'dartvel_dev');
  }));
}

/// Loads the running platform's native libraries and wires its bindings.
///
/// One switch over the platform, not four ifs that could each be true on a
/// mis-detected host. A platform whose libraries are missing -- a headless
/// container without X11 -- is reported and carried on from, because an app
/// that cannot copy to the clipboard is still an app.
void registerPlatformBindings() {
  // The browser's bindings: clipboard, sharing, permissions and the rest, over
  // dart:js_interop. This was a bare return, so in every web application
  // DV.Platform.clipboard threw "not registered" and a Copy button copied
  // nothing. The native classes below are not reached: dart:ffi is not there.
  if (kIsWeb) {
    DVWebBindings.register();
    return;
  }
  // DV.Updates on a build made with Shorebird's engine, whose updater is
  // already in the process; on any other build this registers nothing.
  DVShorebirdUpdates.register();
  final bool registered = switch (defaultTargetPlatform) {
    TargetPlatform.linux => DVLinuxBindings.register(),
    TargetPlatform.windows => DVWindowsBindings.register(),
    TargetPlatform.macOS => DVMacosBindings.register(),
    TargetPlatform.iOS => DVIosBindings.register(),
    // Android was missing, and the default below reported success for it: so
    // every Android binding -- clipboard, haptics, sharing, and now the
    // kiosk -- was dead in every real application while the capability list
    // claimed them.
    TargetPlatform.android => DVAndroidBindings.register(),
    _ => true,
  };
  if (!registered) {
    final String? why = defaultTargetPlatform == TargetPlatform.android
        ? DVAndroidBindings.lastFailure
        : null;
    debugPrint('[dartvel] native bindings for $defaultTargetPlatform did not '
        'load; platform APIs will report themselves unbound.'
        '${why == null ? '' : ' $why'}');
  }
}

class DartvelRuntime {
  static const String _override = String.fromEnvironment('DARTVEL_BACKEND_URL', defaultValue: '');
  static bool _emulatorNoteShown = false;

  static String _adjustDevHost(String url) {
    // A phone that opened the preview from `dartvel dev` on the LAN has no
    // backend on its own localhost; the machine that served the page does.
    if (kIsWeb) return kReleaseMode ? url : dvDevBackendUrl(url, page: Uri.base);
    try {
      final u = Uri.parse(url);
      final host = (u.host).toLowerCase();
      final isLocal = host == 'localhost' || host == '127.0.0.1';
      // A development build paired with `dartvel dev` reaches
      // the backend on the machine running it, not on the phone.
      final paired = DVDevServerHost.current;
      if (!kReleaseMode && isLocal && paired != null) {
        return u.replace(host: paired).toString();
      }
      final onAndroid = defaultTargetPlatform == TargetPlatform.android;
      if (onAndroid && isLocal) {
        final updated = u.replace(host: '10.0.2.2').toString();
        if (!_emulatorNoteShown) {
          _emulatorNoteShown = true;
          debugPrint('''
=== DARTVEL DEV ===
Detected Android emulator. Using 10.0.2.2 for backend.
Base: $url -> $updated
===================
''');
        }
        return updated;
      }
    } catch (_) {}
    return url;
  }

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    // A web-server build is served by the binary that answers its API, on
    // the same origin. dartvel.prodBackendHost names another deployment's
    // backend, and posting there from the binary's own pages reached a host
    // that may not exist.
    if (kIsWeb && kReleaseMode && const bool.fromEnvironment('DARTVEL_WEB_SERVER')) {
      return Uri.base.origin;
    }
    final url = kReleaseMode ? cfg.dvProdBackendHost : cfg.dvDevBackendHost;
    return _adjustDevHost(url);
  }

  static String get apiBasePath => cfg.dvApiBasePath;

  static Uri api(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final api  = apiBasePath.startsWith('/') ? apiBasePath : '/$apiBasePath';
    final sub  = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$api$sub');
  }

  /// [path] from the backend's root, outside the API base path: where a
  /// backend function declaring `rawPath` is served.
  static Uri raw(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final sub  = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$sub');
  }
}

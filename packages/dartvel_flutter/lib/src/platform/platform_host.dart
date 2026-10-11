/// The extension point for runtimes a page can be hosted in.
///
/// A host is an environment that embeds the application and brings its own
/// chrome and services: a messenger's mini-app container, a browser
/// extension, a kiosk shell. Dartvel knows nothing about any particular one.
/// A package registers a [DVPlatformHost] once at startup and the framework
/// consults the hosts that report themselves active:
///
/// * [DVPlatformHost.frame] wraps every page (theme, insets, ready signals);
/// * [DVPlatformHost.attachRouter] / [DVPlatformHost.detachRouter] let the
///   host drive its own back control from the router;
/// * [DVPlatformHost.signInCredential] answers `DV.Auth.signInWithProvider`
///   for the provider names the host lists in [DVPlatformHost.signInProviders];
/// * [DVPlatformHost.fileStorage] replaces the default `DV.FileStorage`
///   adapter where the host is the only storage the page can reach;
/// * [DVPlatformHost.flags] feed `DV.Platform.isChromiumExtension` and
///   `isFirefoxExtension`.
///
/// Nothing is registered by default: an ordinary application has no hosts and
/// every method here is inert.
library;

import 'package:dartvel_core/dartvel.dart' show DVFileStorageAdapter;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A credential a host hands the session client in place of a typed password.
class const DVHostCredential({
  required final String identifier,
  required final String secret,
});

/// One hosting environment. Subclass it and override what the host provides.
abstract class DVPlatformHost {
  DVPlatformHost();

  /// Flag [DVPlatformHost.flags] carries inside a Chromium browser extension.
  static const String chromiumExtensionFlag = 'chromium-extension';

  /// Flag [DVPlatformHost.flags] carries inside a Firefox browser extension.
  static const String firefoxExtensionFlag = 'firefox-extension';

  /// A stable name; registering a second host with the same id replaces the
  /// first.
  String get id;

  /// Whether the application is running inside this host right now.
  bool get isActive;

  /// Named facts about the host while it is active.
  Set<String> get flags => const <String>{};

  /// The page, wrapped in whatever the host needs around every page.
  Widget frame(BuildContext context, Widget page) => page;

  /// The router that drives navigation, handed over when it is attached.
  void attachRouter(GoRouter router) {}

  /// The attached router is gone.
  void detachRouter() {}

  /// The provider names [signInCredential] answers for.
  Set<String> get signInProviders => const <String>{};

  /// The credential for signing in with [provider], or null when the host has
  /// none. Throws [StateError] when it should have one and cannot.
  DVHostCredential? signInCredential(String provider) => null;

  /// Storage that replaces the application default while the host is active,
  /// or null.
  DVFileStorageAdapter? get fileStorage => null;
}

/// The registered hosts. Reached through `DV.Platform.registerHost`.
abstract final class DVPlatformHosts {
  static final List<DVPlatformHost> _hosts = <DVPlatformHost>[];

  /// Every registered host, in registration order.
  static List<DVPlatformHost> get all => List<DVPlatformHost>.unmodifiable(_hosts);

  /// The registered hosts that are active now.
  static List<DVPlatformHost> get active => List<DVPlatformHost>.unmodifiable(
        <DVPlatformHost>[
          for (final DVPlatformHost host in _hosts)
            if (host.isActive) host,
        ],
      );

  static void register(DVPlatformHost host) {
    final int existing = _hosts.indexWhere((DVPlatformHost other) => other.id == host.id);
    if (existing >= 0) {
      _hosts[existing] = host;
    } else {
      _hosts.add(host);
    }
  }

  static void unregister(String id) => _hosts.removeWhere((DVPlatformHost host) => host.id == id);

  static DVPlatformHost? byId(String id) {
    for (final DVPlatformHost host in _hosts) {
      if (host.id == id) return host;
    }
    return null;
  }

  /// Whether any active host carries [flag].
  static bool hasFlag(String flag) => active.any((DVPlatformHost host) => host.flags.contains(flag));

  /// The first active host's storage, or null.
  static DVFileStorageAdapter? get fileStorage {
    for (final DVPlatformHost host in active) {
      final DVFileStorageAdapter? storage = host.fileStorage;
      if (storage != null) return storage;
    }
    return null;
  }

  static DVHostCredential? signInCredential(String provider) {
    for (final DVPlatformHost host in active) {
      if (host.signInProviders.contains(provider)) return host.signInCredential(provider);
    }
    return null;
  }

  /// Tells every active host about [router].
  static void attachRouter(GoRouter router) {
    for (final DVPlatformHost host in active) {
      host.attachRouter(router);
    }
  }

  static void detachRouter() {
    for (final DVPlatformHost host in active) {
      host.detachRouter();
    }
  }

  /// Forgets every host. For tests.
  static void reset() => _hosts.clear();
}

/// Wraps a page in every active host's frame. The framework puts this around
/// each page; with no active host it is the page.
class const DVHostFrame({super.key, required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget framed = child;
    for (final DVPlatformHost host in DVPlatformHosts.active.reversed) {
      framed = host.frame(context, framed);
    }
    return framed;
  }
}

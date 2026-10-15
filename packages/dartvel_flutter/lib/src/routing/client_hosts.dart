/// `dartvel.hosts` on the client: which part of the route tree the host the
/// page was loaded from shows, and where a route lives when it is another
/// host's.
///
/// The generated router installs the table with [dvUseHosts] before it is
/// built. Without that call every function here returns what it was given,
/// and [DVRouter] keeps go_router's own parser: an application without hosts
/// routes exactly as it did.
library dartvel_flutter.routing.client_hosts;

import 'package:dartvel_core/dartvel.dart' show DVHostMatch, DVHosts;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

DVHosts _hosts = DVHosts.none;
DVHostMatch? _current;

/// Installs [hosts] for this page. [host] is the host it was loaded from:
/// `Uri.base.host` on the web; off the web an application is not served
/// from a host, and the primary host's view -- the whole route tree, no
/// mount -- is the one it routes by. An unknown host is the primary, as it
/// is on the server.
void dvUseHosts(DVHosts hosts, {String? host}) {
  _hosts = hosts;
  _current = hosts.isEmpty
      ? null
      : hosts.matchOrPrimary(host ?? (kIsWeb ? Uri.base.host : null));
}

/// Back to no hosts, for tests.
@visibleForTesting
void dvResetHosts() {
  _hosts = DVHosts.none;
  _current = null;
}

/// The installed hosts, empty when none are.
DVHosts get dvInstalledHosts => _hosts;

/// The host this page was loaded from, or null without hosts.
DVHostMatch? get dvCurrentHost => _current;

/// The mount of the current host when it has one other than `/`: the case
/// in which a location needs mapping at all.
String? get _mount {
  final DVHostMatch? current = _current;
  if (current == null) return null;
  final String mount = current.mount;
  return mount == '/' ? null : mount;
}

/// Whether a router on this page has to map locations.
bool get dvHostsMapLocations => _mount != null;

/// Splits [location] into its path and the `?query#fragment` after it.
(String, String) _split(String location) {
  final int at = location.indexOf(RegExp('[?#]'));
  return at < 0
      ? (location, '')
      : (location.substring(0, at), location.substring(at));
}

bool _under(String path, String mount) =>
    path == mount || path.startsWith('$mount/');

/// A location the platform reported -- the address bar on first load, a
/// reload, a typed address -- as the route it means.
///
/// On a mounted host a location not under the mount is mapped to mount +
/// location, so `foo.apps.example.com/` is the `/apps/foo` page. One already
/// under the mount is an in-app navigation and is left alone. Unchanged on
/// the primary host and without hosts.
String dvLocationFromPlatform(String location) {
  final String? mount = _mount;
  if (mount == null) return location;
  final (String path, String rest) = _split(location);
  if (_under(path, mount)) return location;
  return '${_current!.internalPath(path)}$rest';
}

/// The address the browser shows for an internal [location]: under the
/// mount, the path without it. Unchanged otherwise.
String dvLocationToPlatform(String location) {
  final String? mount = _mount;
  if (mount == null) return location;
  final (String path, String rest) = _split(location);
  if (!_under(path, mount)) return location;
  return '${_current!.hostPath(path)}$rest';
}

/// Where a link to the internal [location] points: a path on this origin,
/// the mount stripped, when this host owns the route; an absolute URL on the
/// host that does otherwise. [location] itself without hosts.
String dvPublicLocation(String location) {
  final DVHostMatch? current = _current;
  if (current == null) return location;
  final (String path, String rest) = _split(location);
  final DVHostMatch owner = _hosts.owner(path);
  if (owner.origin == current.origin) {
    return '${current.hostPath(path) ?? path}$rest';
  }
  final int hash = rest.indexOf('#');
  final String query = hash < 0 ? rest : rest.substring(0, hash);
  final String fragment = hash < 0 ? '' : rest.substring(hash);
  final String url = _hosts.publicUrl(
    path,
    query: query.isEmpty ? null : query.substring(1),
  );
  return '$url$fragment';
}

/// Whether [location] is an absolute URL: a link [dvPublicLocation] sent to
/// another host, which is navigated to rather than routed.
bool dvIsOtherOrigin(String location) =>
    Uri.tryParse(location)?.hasScheme ?? false;

/// The canonical URL of the page at [hostPath] on this host, as the server
/// writes it: the public URL of the route the path means. Null without
/// hosts, when the page's own canonical (or none) is what the head says.
String? dvHostCanonicalUrl(String hostPath) {
  if (_current == null) return null;
  final (String path, _) = _split(dvLocationFromPlatform(hostPath));
  return _hosts.publicUrl(path);
}

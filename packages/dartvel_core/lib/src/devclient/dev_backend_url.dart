/// The backend a development build calls, seen from the device it runs on.
library;

/// [configured] with a loopback host replaced by the host [page] was served
/// from.
///
/// `dartvel dev` configures the backend as `localhost`, which is right on the
/// machine running it and wrong everywhere else: a phone that opened the
/// preview at `http://10.0.0.7:8080` has no backend on its own localhost, so
/// every call failed while the page itself loaded. The page's own host is the
/// machine that served it, which is the machine running the backend.
///
/// Only for a loopback backend and a page served over http(s) from somewhere
/// else. A deployed backend is never rewritten.
String dvDevBackendUrl(String configured, {required Uri page}) {
  final Uri? backend = Uri.tryParse(configured);
  if (backend == null || !_isLoopback(backend.host)) return configured;
  if (page.scheme != 'http' && page.scheme != 'https') return configured;
  if (page.host.isEmpty || _isLoopback(page.host)) return configured;
  return backend.replace(host: page.host).toString();
}

bool _isLoopback(String host) {
  final String h = host.toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
}

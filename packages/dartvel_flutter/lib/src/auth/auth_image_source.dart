/// Where an auth page image comes from.
class const DVAuthImageSource({
  required final bool network,
  required final String location,
});

/// An image named by `dartvel.pwa.icon` or `dartvel.auth.heroImage`. A file in
/// the project's web/ folder is not in the asset bundle: on the web the site
/// serves it from its root, so it is fetched relative to the page's base.
/// Everything else is an asset.
DVAuthImageSource dvAuthImageSource(String path, {required bool web}) =>
    web && path.startsWith('web/')
        ? DVAuthImageSource(network: true, location: path.substring(4))
        : DVAuthImageSource(network: false, location: path);

/// The offline banner every page carries.
///
/// `DV.Platform.network` reported the connection and nothing showed it, so a
/// reader on a train saw a page that looked live. The banner is the rendering
/// of that signal, in the page shell, so no page has to remember it -- and it
/// is not exported, so no page can be told to.
library dartvel_flutter.state.offline_banner;

import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DV, DVFrameworkStrings;
import 'package:flutter/material.dart';

import '../platform/network.dart';

/// Shown only while the network reports [DVNetworkStatus.offline].
///
/// Not for [DVNetworkStatus.unknown], which is every target with no binding:
/// a banner there would sit on every page of every app for ever. Nor for
/// [DVNetworkStatus.metered], which is a connection.
class DVOfflineBanner extends StatelessWidget {
  const DVOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (const DVNetwork().watch(context) != .offline) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final String text = DV.I18n.t(DVFrameworkStrings.offline);
    return Semantics(
      // Announced when it appears: a sighted reader sees the banner arrive,
      // and a screen reader user would otherwise never learn of it.
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.inverseSurface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const .symmetric(horizontal: 16, vertical: 10),
            child: Text(
              text,
              textAlign: .center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

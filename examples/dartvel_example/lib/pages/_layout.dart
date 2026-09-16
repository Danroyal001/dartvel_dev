import 'package:flutter/material.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

import '../theme/palette.dart';

/// Around every page: the palette's ink as the default text colour.
///
/// On Apple platforms a page's shell is Cupertino, whose text style does not
/// follow the Material theme into dark mode; setting it here is what keeps a
/// DVText with no colour of its own readable in both.
class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DefaultTextStyle.merge(
      style: TextStyle(color: p.ink),
      child: child,
    );
  }
}

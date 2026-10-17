import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'auth_image_source.dart';

/// Which prebuilt account page a frame is drawn for.
enum DVAuthScreen { signIn, signUp, secondFactor, account }

/// Draws a whole account screen around the framework's [form]: the app's own
/// layout, art and copy, with the sign-in logic left to the framework.
typedef DVAuthFrameBuilder = Widget Function(
    BuildContext context, DVAuthScreen screen, Widget form);

/// Identity for prebuilt auth pages. Generated from dartvel.pwa and dartvel.auth.
///
/// [frameBuilder] replaces the default two-panel frame entirely, so an app's
/// sign-in looks like that app rather than like every other Dartvel app.
/// [signInTitle] and [signUpTitle] name the pages in the app's own words.
class const DVAuthAppearance({
  final String name = 'Welcome',
  final String tagline = 'A place for what matters to you.',
  final String? icon,
  final String? heroImage,
  final Color? brandPanelColor,
  final WidgetBuilder? brandPanelBuilder,
  final DVAuthFrameBuilder? frameBuilder,
  final String? signInTitle,
  final String? signUpTitle,
}) {
  /// The heading an account page shows.
  String titleFor(DVAuthScreen screen) => switch (screen) {
        DVAuthScreen.signIn => signInTitle ?? 'Sign in to your account',
        DVAuthScreen.signUp => signUpTitle ?? 'Create an account',
        DVAuthScreen.secondFactor => 'Verify your identity',
        DVAuthScreen.account => name,
      };
}

/// Shared, theme-derived layout for sign-in, sign-up and account pages.
class const DVAuthFrame({
  super.key,
  required final DVAuthAppearance appearance,
  required final List<Widget> children,
  final DVAuthScreen screen = DVAuthScreen.account,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final DVAuthFrameBuilder? custom = appearance.frameBuilder;
    if (custom != null) {
      return custom(
        context,
        screen,
        Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      );
    }
    return _defaultFrame(context);
  }

  Widget _defaultFrame(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      final wide = box.maxWidth >= 720;
      final panelColor =
          appearance.brandPanelColor ?? theme.colorScheme.primaryContainer;
      final panelTextColor = appearance.brandPanelColor == null
          ? theme.colorScheme.onPrimaryContainer
          : ThemeData.estimateBrightnessForColor(panelColor) == Brightness.dark
          ? Colors.white
          : Colors.black;
      final padding = box.maxWidth <= 320 ? 12.0 : 32.0;
      final content = Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          if (!wide) ...[
            // A phone gets the brand too, not a bare form under a small name.
            Row(
              children: [
                if (appearance.icon case final icon?) ...[
                  _authImage(icon, width: 40, height: 40),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(appearance.name, style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 6),
            Text(appearance.tagline, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
          ],
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 20),
          ],
        ],
      );
      final form = Padding(
        padding: .all(padding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: content,
          ),
        ),
      );
      // A panel the application drew owns its whole box: wrapping it in the default one drew a box
      // inside a box, in two colours.
      final Widget? custom = appearance.brandPanelBuilder?.call(context);
      final panel = custom != null
          ? KeyedSubtree(
              key: const ValueKey('dv-auth-brand-panel'),
              child: custom,
            )
          : Container(
              key: const ValueKey('dv-auth-brand-panel'),
              padding: const .all(48),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: const .all(.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: .start,
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  if (appearance.icon case final icon?) ...[
                    _authImage(icon, width: 64, height: 64),
                    const SizedBox(height: 32),
                  ],
                  Text(
                    appearance.name,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: panelTextColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appearance.tagline,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: panelTextColor,
                    ),
                  ),
                  if (appearance.heroImage case final image?) ...[
                    const SizedBox(height: 32),
                    _authImage(image, fit: .cover),
                  ],
                ],
              ),
            );
      return Material(
        // The page the app's other screens sit on, not the card colour.
        color: theme.scaffoldBackgroundColor,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: wide
                    ? Padding(
                        padding: const .all(32),
                        child: Row(
                          crossAxisAlignment: .center,
                          children: [
                            Expanded(child: panel),
                            Expanded(child: form),
                          ],
                        ),
                      )
                    : form,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// An auth page image from the asset bundle, or from the site for a file in
/// the project's web/ folder; a missing one leaves no gap.
Widget _authImage(String path, {double? width, double? height, BoxFit? fit}) {
  final DVAuthImageSource source = dvAuthImageSource(path, web: kIsWeb);
  Widget missing(BuildContext context, Object error, StackTrace? stack) =>
      const SizedBox.shrink();
  return source.network
      ? Image.network(source.location,
          width: width, height: height, fit: fit, errorBuilder: missing)
      : Image.asset(source.location,
          width: width, height: height, fit: fit, errorBuilder: missing);
}

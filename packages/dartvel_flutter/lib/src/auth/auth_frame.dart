import 'package:flutter/material.dart';

/// Identity for prebuilt auth pages. Generated from dartvel.pwa and dartvel.auth.
class const DVAuthAppearance({
  final String name = 'Welcome',
  final String tagline = 'A place for what matters to you.',
  final String? icon,
  final String? heroImage,
  final Color? brandPanelColor,
  final WidgetBuilder? brandPanelBuilder,
});

/// Shared, theme-derived layout for sign-in, sign-up and account pages.
class const DVAuthFrame({
  super.key,
  required final DVAuthAppearance appearance,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      final wide = box.maxWidth >= 720;
      final panelColor = appearance.brandPanelColor ?? theme.colorScheme.primaryContainer;
      final panelTextColor = appearance.brandPanelColor == null
          ? theme.colorScheme.onPrimaryContainer
          : ThemeData.estimateBrightnessForColor(panelColor) == Brightness.dark
              ? Colors.white : Colors.black;
      final padding = box.maxWidth <= 320 ? 12.0 : 32.0;
      final content = Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          if (!wide) ...[
            Text(appearance.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
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
      final panel = Container(
        key: const ValueKey('dv-auth-brand-panel'),
        padding: const .all(48),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: const .all(.circular(24)),
        ),
        child:
            appearance.brandPanelBuilder?.call(context) ??
            Column(
              crossAxisAlignment: .start,
              mainAxisAlignment: .center,
              mainAxisSize: .min,
              children: [
                if (appearance.icon case final icon?) ...[
                  Image.asset(
                    icon,
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
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
                  Image.asset(
                    image,
                    fit: .cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
      );
      return Material(
        color: theme.colorScheme.surface,
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

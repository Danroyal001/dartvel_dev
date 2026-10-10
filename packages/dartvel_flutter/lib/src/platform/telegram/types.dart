import 'dart:async';

import 'package:flutter/material.dart';

/// Internal delivery contract; absent APIs fail explicitly.
abstract interface class DVTelegramBridge {
  Object? read(String name);
  Future<Object?> call(
    String name,
    List<Object?> arguments, {
    bool callback = false,
    bool errorFirst = false,
  });
  Stream<void> event(String name);
}

class const DVTelegramUser({
  required final int id,
  required final String firstName,
  final String? lastName,
  final String? username,
  final String? languageCode,
  final String? photoUrl,
  final bool isPremium = false,
});

class const DVTelegramTheme({
  required final bool dark,
  required final Map<String, String> params,
});
class const DVTelegramViewport({
  required final double height,
  required final double stableHeight,
  required final bool expanded,
  required final EdgeInsets safeArea,
  required final EdgeInsets contentSafeArea,
});

/// A platform signal, with the same watch(context) convention as network.
class DVTelegramSignal<T> {
  DVTelegramSignal(this._read, this.changes);
  final T Function() _read;
  final Stream<T> changes;
  final Expando<StreamSubscription<T>> _watchers = Expando();
  T get value => _read();
  T read() => _read();
  T watch(BuildContext context) {
    final element = context as Element;
    if (_watchers[element] == null) {
      late final StreamSubscription<T> sub;
      sub = changes.listen((_) {
        if (element.mounted) {
          element.markNeedsBuild();
        } else {
          _watchers[element] = null;
          unawaited(sub.cancel());
        }
      });
      _watchers[element] = sub;
    }
    return value;
  }
}

Color? _color(String? value) =>
    value != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
    ? Color(0xff000000 | int.parse(value.substring(1), radix: 16))
    : null;

/// Preserve the application's typography and geometry; map Telegram roles.
ThemeData dvTelegramTheme(ThemeData base, DVTelegramTheme telegram) {
  final p = telegram.params;
  final scheme = base.colorScheme.copyWith(
    brightness: telegram.dark ? .dark : .light,
    primary: _color(p['button_color']),
    onPrimary: _color(p['button_text_color']),
    surface: _color(p['bg_color']),
    onSurface: _color(p['text_color']),
    surfaceContainer: _color(p['secondary_bg_color']),
    surfaceContainerLow: _color(p['section_bg_color']),
    onSurfaceVariant: _color(p['hint_color'] ?? p['subtitle_text_color']),
    secondary: _color(p['accent_text_color'] ?? p['link_color']),
    error: _color(p['destructive_text_color']),
  );
  final text = _color(p['text_color']);
  return base.copyWith(
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: _color(p['bg_color']),
    textTheme: text == null
        ? base.textTheme
        : base.textTheme.apply(bodyColor: text, displayColor: text),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: _color(p['header_bg_color']),
    ),
  );
}

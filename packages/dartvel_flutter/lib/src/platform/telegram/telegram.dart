import 'dart:async';

import 'package:flutter/material.dart';

import 'source_stub.dart'
    if (dart.library.js_interop) 'source_web.dart'
    as source;
import 'types.dart';

export 'types.dart'
    show
        DVTelegramUser,
        DVTelegramTheme,
        DVTelegramViewport,
        DVTelegramSignal,
        dvTelegramTheme;

DVTelegram? _instance;
DVTelegram? dvTelegramHere() {
  final bridge = source.dvTelegramBridge();
  if (bridge == null) return null;
  return _instance ??= DVTelegram._(bridge);
}

/// Telegram's host controls. User and initData are untrusted until the server
/// validates initData; never authorize a purchase or access from these fields.
class DVTelegram {
  DVTelegram._(this._bridge) {
    theme = DVTelegramSignal(
      _theme,
      _bridge.event('themeChanged').map((_) => _theme()),
    );
    viewport = DVTelegramSignal(
      _viewport,
      _bridge.event('viewportChanged').map((_) => _viewport()),
    );
  }
  final DVTelegramBridge _bridge;
  late final DVTelegramSignal<DVTelegramTheme> theme;
  late final DVTelegramSignal<DVTelegramViewport> viewport;
  String get initData => _bridge.read('initData') as String? ?? '';
  String get version => _bridge.read('version') as String? ?? '';
  String get platform => _bridge.read('platform') as String? ?? '';
  DVTelegramUser? get user {
    final data = _bridge.read('initDataUnsafe');
    final user = data is Map ? data['user'] : null;
    if (user is! Map || user['id'] is! num || user['first_name'] is! String) {
      return null;
    }
    return DVTelegramUser(
      id: (user['id'] as num).toInt(),
      firstName: user['first_name'] as String,
      lastName: user['last_name'] as String?,
      username: user['username'] as String?,
      languageCode: user['language_code'] as String?,
      photoUrl: user['photo_url'] as String?,
      isPremium: user['is_premium'] == true,
    );
  }

  DVTelegramTheme _theme() {
    final raw = _bridge.read('themeParams');
    return DVTelegramTheme(
      dark: _bridge.read('colorScheme') == 'dark',
      params: Map.unmodifiable({
        if (raw is Map)
          for (final entry in raw.entries)
            if (entry.value is String) '${entry.key}': entry.value as String,
      }),
    );
  }

  EdgeInsets _insets(String field) {
    final raw = _bridge.read(field);
    double n(String name) => raw is Map && raw[name] is num
        ? (raw[name] as num).toDouble().clamp(0, double.infinity)
        : 0;
    return .fromLTRB(n('left'), n('top'), n('right'), n('bottom'));
  }

  DVTelegramViewport _viewport() => DVTelegramViewport(
    height: (_bridge.read('viewportHeight') as num?)?.toDouble() ?? 0,
    stableHeight:
        (_bridge.read('viewportStableHeight') as num?)?.toDouble() ?? 0,
    expanded: _bridge.read('isExpanded') == true,
    safeArea: _insets('safeAreaInset'),
    contentSafeArea: _insets('contentSafeAreaInset'),
  );

  late final mainButton = DVTelegramButton._(
    _bridge,
    'MainButton',
    'mainButtonClicked',
  );
  late final secondaryButton = DVTelegramButton._(
    _bridge,
    'SecondaryButton',
    'secondaryButtonClicked',
  );
  late final backButton = DVTelegramButton._(
    _bridge,
    'BackButton',
    'backButtonClicked',
  );
  late final settingsButton = DVTelegramButton._(
    _bridge,
    'SettingsButton',
    'settingsButtonClicked',
  );
  late final haptics = DVTelegramHaptics._(_bridge);
  late final cloudStorage = DVTelegramStorage._(
    _bridge,
    'CloudStorage',
    device: false,
  );
  late final deviceStorage = DVTelegramStorage._(
    _bridge,
    'DeviceStorage',
    device: true,
  );
  late final secureStorage = DVTelegramStorage._(
    _bridge,
    'SecureStorage',
    device: true,
  );
  Future<void> ready() async {
    await _bridge.call('ready', []);
  }

  Future<void> expand() async {
    await _bridge.call('expand', []);
  }

  Future<void> close() async {
    await _bridge.call('close', []);
  }

  Future<void> openLink(Uri url, {bool tryInstantView = false}) async {
    if (!const ['https', 'http'].contains(url.scheme)) {
      throw ArgumentError.value(url, 'url');
    }
    await _bridge.call('openLink', [
      url.toString(),
      {'try_instant_view': tryInstantView},
    ]);
  }

  Future<void> openTelegramLink(Uri url) async {
    if (url.scheme != 'https' || url.host != 't.me') {
      throw ArgumentError.value(url, 'url');
    }
    await _bridge.call('openTelegramLink', [url.toString()]);
  }

  Future<bool> shareMessage(String id) async =>
      await _bridge.call('shareMessage', [id], callback: true) == true;
  Future<void> shareToStory(
    Uri media, {
    String? text,
    Uri? link,
    String? linkName,
  }) async {
    await _bridge.call('shareToStory', [
      media.toString(),
      {
        'text': ?text,
        if (link != null)
          'widget_link': {'url': link.toString(), 'name': ?linkName},
      },
    ]);
  }

  Future<bool> requestContact() async =>
      await _bridge.call('requestContact', [], callback: true) == true;
  Future<bool> requestWriteAccess() async =>
      await _bridge.call('requestWriteAccess', [], callback: true) == true;
  Stream<String> get qrTexts => _bridge
      .event('qrTextReceived')
      .map((_) => _bridge.read('_qrText') as String? ?? '');
  Future<void> scanQr({String? text}) async {
    await _bridge.call('showScanQrPopup', [
      {'text': ?text},
    ]);
  }

  Future<void> closeQrScanner() async {
    await _bridge.call('closeScanQrPopup', []);
  }

  Future<String> openInvoice(Uri url) async =>
      '${await _bridge.call('openInvoice', [url.toString()], callback: true)}';
  Future<void> requestFullscreen() async {
    await _bridge.call('requestFullscreen', []);
  }

  Future<void> exitFullscreen() async {
    await _bridge.call('exitFullscreen', []);
  }

  Future<void> lockOrientation() async {
    await _bridge.call('lockOrientation', []);
  }

  Future<void> unlockOrientation() async {
    await _bridge.call('unlockOrientation', []);
  }

  Future<void> addToHomeScreen() async {
    await _bridge.call('addToHomeScreen', []);
  }

  Future<String> checkHomeScreenStatus() async =>
      '${await _bridge.call('checkHomeScreenStatus', [], callback: true)}';
}

class DVTelegramButton {
  DVTelegramButton._(this._bridge, this._name, String event)
    : clicks = _bridge.event(event);
  final DVTelegramBridge _bridge;
  final String _name;
  final Stream<void> clicks;
  Future<void> show() async {
    await _bridge.call('$_name.show', []);
  }

  Future<void> hide() async {
    await _bridge.call('$_name.hide', []);
  }

  Future<void> set({
    String? text,
    String? color,
    String? textColor,
    bool? active,
    bool? visible,
    String? position,
  }) async {
    await _bridge.call('$_name.setParams', [
      {
        'text': ?text,
        'color': ?color,
        'text_color': ?textColor,
        'is_active': ?active,
        'is_visible': ?visible,
        'position': ?position,
      },
    ]);
  }

  Future<void> showProgress({bool leaveActive = false}) async {
    await _bridge.call('$_name.showProgress', [leaveActive]);
  }

  Future<void> hideProgress() async {
    await _bridge.call('$_name.hideProgress', []);
  }
}

enum DVTelegramImpact { light, medium, heavy, rigid, soft }

enum DVTelegramFeedback { error, success, warning }

class DVTelegramHaptics {
  DVTelegramHaptics._(this._bridge);
  final DVTelegramBridge _bridge;
  Future<void> impact(DVTelegramImpact style) async {
    await _bridge.call('HapticFeedback.impactOccurred', [style.name]);
  }

  Future<void> notification(DVTelegramFeedback type) async {
    await _bridge.call('HapticFeedback.notificationOccurred', [type.name]);
  }

  Future<void> selectionChanged() async {
    await _bridge.call('HapticFeedback.selectionChanged', []);
  }
}

class DVTelegramStorage {
  DVTelegramStorage._(this._bridge, this._name, {required this.device});
  final DVTelegramBridge _bridge;
  final String _name;
  final bool device;
  Future<String?> get(String key) async => await _bridge.call(
    '$_name.getItem',
    [key],
    callback: true,
    errorFirst: true,
  ) as String?;
  Future<void> set(String key, String value) async {
    await _bridge.call(
      '$_name.setItem',
      [key, value],
      callback: true,
      errorFirst: true,
    );
  }

  Future<void> delete(String key) async {
    await _bridge.call(
      '$_name.removeItem',
      [key],
      callback: true,
      errorFirst: true,
    );
  }

  Future<void> clear() async {
    if (!device) {
      final keys = await _bridge.call(
        '$_name.getKeys',
        [],
        callback: true,
        errorFirst: true,
      );
      if (keys is! List)
        throw StateError('Telegram returned invalid storage keys');
      if (keys.isEmpty) return;
      await _bridge.call(
        '$_name.removeItems',
        [keys],
        callback: true,
        errorFirst: true,
      );
      return;
    }
    await _bridge.call('$_name.clear', [], callback: true, errorFirst: true);
  }
}

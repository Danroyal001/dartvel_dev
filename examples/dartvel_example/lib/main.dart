import 'dart:async';

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'shop/account.dart';
import 'shop/appearance.dart';
import 'shop/cart.dart';
import 'shop/catalog.dart';
import 'shop/saved.dart';
import 'theme/palette.dart';

void main() {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // Use path-based URLs on web (no hash)
  usePathUrlStrategy();
  runApp(createDartvelExampleApp());
}

void configureDartvelExample() {
  final DVLocalAuthProvider auth = DVLocalAuthProvider();
  DV.Auth.configure(auth);
  DV.AI.configure(const LocalDVAIAdapter());
  // The device's own store. The generated server keeps the same models in
  // SQLite; this one lives in memory, so the demo starts fresh every launch
  // and runs anywhere Flutter does.
  DV.Database.configure(MemoryDVDatabaseAdapter());
  resetShopStore();
  DV.Notifications.register(DVMemoryNotificationProvider());
  DV.Notifications.mail.useProvider(DVMemoryMailProvider());
  Analytics.register(LocalAnalyticsProvider());

  // The globals every screen reads.
  DV.global<Cart>(const Cart());
  DV.global<SavedCoffees>(const SavedCoffees(<String>{'yirgacheffe'}));
  DV.global<Account>(const Account());
  DV.global<Appearance>(Appearance(DV.Theme.mode));

  unawaited(openShopStore());
  unawaited(registerDemoAccount(auth));
}

Widget createDartvelExampleApp() {
  configureDartvelExample();
  final GoRouter router = createDartvelRouter();
  return ProviderScope(
    child: Builder(
      builder: (BuildContext context) => MaterialApp.router(
        title: 'Oakline Coffee',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: shopTheme(Palette.light),
        darkTheme: shopTheme(Palette.dark),
        themeMode: context.global<Appearance>().mode,
      ),
    ),
  );
}

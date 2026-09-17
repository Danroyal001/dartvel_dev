import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start a11y-semantics
Widget checkoutButton(VoidCallback onCheckout) => DVText('Pay now').modifier(
      DVModifier()
          .paddingSymmetric(horizontal: 20, vertical: 14)
          .minimumTapTarget()
          .semanticButton()
          .semanticLabel('Pay for the items in your cart')
          .onTap(onCheckout),
    );
// docs:end

// docs:start a11y-switch-control
// Space steps focus through the page and Enter activates, while switch
// control is on. autoScan steps on a timer for a single-switch user.
Widget drivableBySwitches(Widget page) => DVSwitchControl(
      autoScan: const Duration(seconds: 2),
      child: page,
    );

// A TV remote's D-pad and select key move focus and activate.
Widget drivableByRemote(Widget page) => DVHardwareKeys(child: page);

void turnSwitchControlOn() => DV.Accessibility.switchControl.enabled = true;
// docs:end

bool checks() {
  // docs:start a11y-checks
  final DVAccessibilityReport report = DV.Accessibility.report(<DVAccessibilityCheck>[
    DV.Accessibility.contrast(
      foreground: const Color(0xFF6B7280),
      background: const Color(0xFFFFFFFF),
    ),
    DV.Accessibility.tapTarget(size: const Size(40, 40)),
  ]);
  for (final DVAccessibilityCheck failure in report.failures) {
    DV.log(failure.message); // Tap target 40.0x40.0 is smaller than 48.0x48.0.
  }
  // docs:end
  return report.passed;
}

// docs:start i18n-keys
class AppText {
  static const DVTranslationKey cartTitle = DVTranslationKey('cart.title');
  static const DVTranslationKey cartItems = DVTranslationKey('cart.items');
}

void loadTranslations() {
  DV.I18n.loadAll(const <DVTranslationCatalog>[
    DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{AppText.cartTitle: 'Your cart'},
      plurals: <DVTranslationKey, DVPluralForms>{
        AppText.cartItems: DVPluralForms(one: '{count} item', other: '{count} items'),
      },
    ),
    DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{AppText.cartTitle: 'Votre panier'},
      plurals: <DVTranslationKey, DVPluralForms>{
        AppText.cartItems: DVPluralForms(one: '{count} article', other: '{count} articles'),
      },
    ),
  ]);
}
// docs:end

void useTranslations() {
  // docs:start i18n-use
  DV.I18n.useLocale(LocaleTag.frFR);
  final String title = DV.I18n.t(AppText.cartTitle); // Votre panier
  final String count = DV.I18n.plural(AppText.cartItems, 3); // 3 articles
  // docs:end
  DV.log('$title $count');
}

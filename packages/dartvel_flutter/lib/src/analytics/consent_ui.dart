/// The consent banner and the consent settings screen, built from the
/// categories `dartvel.analytics.consent` declares.
///
/// Both exist to ask, and the thing each must never do is answer on the
/// person's behalf: closing the banner is not a choice, leaving the screen is
/// not a save, a choice the database refused is not shown as made, and a
/// tracking category is not granted on iOS without the system's prompt.
library dartvel_flutter.analytics.consent_ui;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVBox, DVModifier, DVText;
import 'app_tracking_transparency.dart';

/// Records [answers] as a choice made through [prompt], and returns whether
/// everything that was answered was written.
///
/// Where [DVAppTrackingTransparency.applies], a tracking category the person
/// said yes to is granted only if the system prompt allows it, and recorded
/// as answered through that prompt; if the prompt could not be shown nothing
/// is recorded for it and it stays at its default. A tracking category the
/// person said no to is recorded as no without asking the system anything.
Future<bool> dvRecordConsentChoice(
  DVConsent consent,
  Map<DVConsentCategory, bool> answers, {
  required DVConsentPrompt prompt,
}) async {
  final bool throughSystem = DVAppTrackingTransparency.applies();
  final Map<DVConsentCategory, bool> direct = <DVConsentCategory, bool>{};
  final Set<DVConsentCategory> trackingWanted = <DVConsentCategory>{};
  for (final MapEntry<DVConsentCategory, bool> answer in answers.entries) {
    final DVConsentDeclaration? declared =
        consent.policy.declaration(answer.key);
    if (declared == null || declared.required) continue;
    if (declared.tracking && throughSystem && answer.value) {
      trackingWanted.add(answer.key);
    } else {
      direct[answer.key] = answer.value;
    }
  }

  bool saved = true;
  if (direct.isNotEmpty) {
    saved = await consent.record(direct,
        asked: direct.keys.toSet(), prompt: prompt);
    // A grant that was not written is not consent, and asking the system
    // for tracking on top of a choice that did not save would record half
    // of it.
    if (!saved) return false;
  }
  if (trackingWanted.isEmpty) return saved;

  final DVTrackingAuthorization status =
      await DVAppTrackingTransparency.request();
  final bool? allowed = switch (status) {
    DVTrackingAuthorization.authorized => true,
    DVTrackingAuthorization.denied || DVTrackingAuthorization.restricted =>
      false,
    DVTrackingAuthorization.notDetermined ||
    DVTrackingAuthorization.unavailable =>
      null,
  };
  if (allowed == null) return saved;
  return consent.record(
    <DVConsentCategory, bool>{
      for (final DVConsentCategory c in trackingWanted) c: allowed,
    },
    asked: trackingWanted,
    prompt: DVConsentPrompt.appTrackingTransparency,
  );
}

DVAnalyticsRuntime? _configured(DVAnalyticsRuntime? given) =>
    given ?? (DVAnalyticsRuntime.isConfigured ? DVAnalyticsRuntime.current : null);

Widget _action(String key, String label, VoidCallback? onPressed) =>
    KeyedSubtree(
      key: ValueKey<String>(key),
      child: DVText(label).modifier(
        const DVModifier()
            .padding(10)
            .rounded(8)
            .backgroundColor(
                onPressed == null ? const Color(0xFF9CA3AF) : const Color(0xFF111827))
            .color(Colors.white)
            .onPressed(onPressed ?? () {}),
      ),
    );

String _label(String name) => name.isEmpty
    ? name
    : name[0].toUpperCase() +
        name
            .substring(1)
            .replaceAllMapped(RegExp('[A-Z]'), (Match m) => ' ${m[0]!.toLowerCase()}');

/// Asks for consent over [child] until somebody answers under the current
/// policy version.
///
/// Shown only once the stored consent has been read, so it never offers a
/// choice over one already made; and again whenever the policy version
/// changes, because an answer to last version is not consent to this one.
/// "Accept all" and "Reject all" record an answer for every category it
/// asks about; "Choose" opens [DVConsentSettingsPage]; "Not now" closes it
/// for the rest of the session and records nothing. In an application with
/// no analytics configured it is [child] alone.
class DVConsentBanner extends StatefulWidget {
  const DVConsentBanner({super.key, required this.child, this.analytics});

  final Widget child;

  /// The runtime to ask for; the configured `DV.Analytics` when null.
  final DVAnalyticsRuntime? analytics;

  static Expando<bool> _closed = Expando<bool>('dv-consent-banner-closed');

  /// Closes the banner for the rest of the session for [analytics]: an
  /// answer was saved somewhere else, such as the settings screen.
  static void markAnswered(DVAnalyticsRuntime analytics) =>
      _closed[analytics] = true;

  /// Forgets which banners were closed, for tests.
  @visibleForTesting
  static void resetForTest() => _closed = Expando<bool>('dv-consent-banner-closed');

  @override
  State<DVConsentBanner> createState() => _DVConsentBannerState();
}

class _DVConsentBannerState extends State<DVConsentBanner> {
  bool _saving = false;
  bool _notSaved = false;

  DVAnalyticsRuntime? get _runtime => _configured(widget.analytics);

  @override
  void initState() {
    super.initState();
    _runtime?.whenReady(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _answer(DVAnalyticsRuntime runtime, DVConsent consent,
      {required bool grant}) async {
    setState(() => _saving = true);
    final bool saved = await dvRecordConsentChoice(
      consent,
      <DVConsentCategory, bool>{
        for (final DVConsentDeclaration d in consent.policy.askable)
          d.category: grant,
      },
      prompt: DVConsentPrompt.banner,
    );
    if (saved) DVConsentBanner.markAnswered(runtime);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notSaved = !saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DVAnalyticsRuntime? runtime = _runtime;
    if (runtime == null) return widget.child;
    final DVConsent? consent = runtime.loadedConsent;
    final bool show = consent != null &&
        consent.needsPrompt &&
        consent.policy.askable.isNotEmpty &&
        DVConsentBanner._closed[runtime] != true;
    // Sized to the space the page is given, so the banner sits at the bottom
    // of it. Sized to the page's own content instead, a short page made a
    // short stack and the banner was drawn -- and clipped -- at its bottom
    // edge: present in the tree, invisible, and impossible to answer. Loose
    // where the space is unbounded, as inside a scroll view, which cannot be
    // filled.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Stack(
        fit: constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? StackFit.expand
            : StackFit.loose,
        children: <Widget>[
          widget.child,
          if (show)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: KeyedSubtree(
                key: const ValueKey<String>('dv-consent-banner'),
                child: _banner(context, runtime, consent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _banner(
      BuildContext context, DVAnalyticsRuntime runtime, DVConsent consent) {
    final List<String> asked = <String>[
      for (final DVConsentDeclaration d in consent.policy.askable)
        _label(d.category.name),
    ];
    return Material(
      elevation: 6,
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DVBox.list(<Widget>[
            const DVText('Your privacy choices'),
            DVText('This application would like your permission for: '
                '${asked.join(', ')}. Nothing is collected for these until '
                'you choose.'),
            if (_notSaved)
              const KeyedSubtree(
                key: ValueKey<String>('dv-consent-not-saved'),
                child: DVText('Your choice could not be saved, so nothing '
                    'was turned on. Please try again.'),
              ),
            DVBox.wrapLine(
              <Widget>[
                _action('dv-consent-accept-all', 'Accept all',
                    _saving ? null : () => unawaited(_answer(runtime, consent, grant: true))),
                _action('dv-consent-reject-all', 'Reject all',
                    _saving ? null : () => unawaited(_answer(runtime, consent, grant: false))),
                _action('dv-consent-choose', 'Choose', () {
                  unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (BuildContext _) => Scaffold(
                      appBar: AppBar(title: const Text('Privacy choices')),
                      body: DVConsentSettingsPage(analytics: runtime),
                    ),
                  )).then((_) {
                    if (mounted) setState(() {});
                  }));
                }),
                _action('dv-consent-dismiss', 'Not now', () {
                  // Closed, not answered: nothing is recorded and every
                  // category stays at its declared default.
                  DVConsentBanner._closed[runtime] = true;
                  setState(() {});
                }),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Every declared category with a switch, and a save.
///
/// Each switch starts where the category stands. Nothing is recorded until
/// "Save", and leaving without it records nothing; a required category is
/// shown on and cannot be switched off.
class DVConsentSettingsPage extends StatefulWidget {
  const DVConsentSettingsPage({super.key, this.analytics});

  /// The runtime to record for; the configured `DV.Analytics` when null.
  final DVAnalyticsRuntime? analytics;

  @override
  State<DVConsentSettingsPage> createState() => _DVConsentSettingsPageState();
}

class _DVConsentSettingsPageState extends State<DVConsentSettingsPage> {
  Map<String, bool>? _choices;
  bool _saving = false;
  bool _notSaved = false;
  bool _saved = false;

  DVAnalyticsRuntime? get _runtime => _configured(widget.analytics);

  @override
  void initState() {
    super.initState();
    _runtime?.whenReady(() {
      if (!mounted) return;
      final DVConsent consent = _runtime!.loadedConsent!;
      setState(() {
        _choices = <String, bool>{
          for (final DVConsentDeclaration d in consent.policy.askable)
            d.category.name: consent.isGranted(d.category),
        };
      });
    });
  }

  Future<void> _save(DVAnalyticsRuntime runtime, DVConsent consent) async {
    final Map<String, bool> choices = _choices!;
    setState(() {
      _saving = true;
      _saved = false;
    });
    final bool saved = await dvRecordConsentChoice(
      consent,
      <DVConsentCategory, bool>{
        for (final MapEntry<String, bool> c in choices.entries)
          DVConsentCategory(c.key): c.value,
      },
      prompt: DVConsentPrompt.settingsScreen,
    );
    if (saved) DVConsentBanner.markAnswered(runtime);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved;
      _notSaved = !saved;
      // What was actually recorded, which on iOS may be less than what was
      // switched on.
      _choices = <String, bool>{
        for (final String name in choices.keys)
          name: consent.isGranted(DVConsentCategory(name)),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final DVAnalyticsRuntime? runtime = _runtime;
    if (runtime == null) {
      return const Center(
        child: DVText('This application does not collect analytics, so there '
            'is nothing to choose.'),
      );
    }
    final DVConsent? consent = runtime.loadedConsent;
    final Map<String, bool>? choices = _choices;
    if (consent == null || choices == null) {
      return const Center(child: DVText('Loading your privacy choices…'));
    }
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          DVBox.list(<Widget>[
            const DVText('Choose what this application may collect. Nothing '
                'changes until you save.'),
            for (final DVConsentDeclaration d in consent.policy.categories)
              DVBox.row(<Widget>[
                Switch(
                  key: ValueKey<String>('dv-consent-toggle-${d.category.name}'),
                  value: d.required ? true : choices[d.category.name]!,
                  onChanged: d.required || _saving
                      ? null
                      : (bool value) => setState(() {
                            choices[d.category.name] = value;
                            _saved = false;
                          }),
                ),
                DVText(d.required
                    ? '${_label(d.category.name)} (always on)'
                    : _label(d.category.name)),
              ]),
            if (_notSaved)
              const KeyedSubtree(
                key: ValueKey<String>('dv-consent-not-saved'),
                child: DVText('Your choices could not be saved, so nothing '
                    'new was turned on. Please try again.'),
              ),
            if (_saved)
              const KeyedSubtree(
                key: ValueKey<String>('dv-consent-saved'),
                child: DVText('Saved.'),
              ),
            _action('dv-consent-save', 'Save',
                _saving ? null : () => unawaited(_save(runtime, consent))),
          ]),
        ],
      ),
    );
  }
}

/// `DV.Analytics.ConsentBanner(child: ...)` and
/// `DV.Analytics.ConsentSettingsPage()`, the way `DV.Auth` provides its
/// sign-in pages.
extension DVAnalyticsConsentPages on DVAnalyticsRuntime {
  /// A [DVConsentBanner] over [child] for this runtime.
  Widget ConsentBanner({required Widget child}) =>
      DVConsentBanner(analytics: this, child: child);

  /// A [DVConsentSettingsPage] for this runtime.
  Widget ConsentSettingsPage() => DVConsentSettingsPage(analytics: this);
}

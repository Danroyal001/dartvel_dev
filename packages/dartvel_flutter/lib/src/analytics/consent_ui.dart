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
import 'package:material_ui/material_ui.dart';

import '../../dartvel_flutter.dart'
    show DVBox, DVModifier, DVNavLink, DVRouteTarget, DVText;
import 'app_tracking_transparency.dart';
import '../seo/capture_hold.dart';

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

/// A banner or settings action. Every one is drawn the same, in the app
/// theme's primary colours: rejecting has to be as easy to see and reach as
/// accepting, which a grey "Reject" beside a bold "Accept" is not. The words
/// are the control's name -- its tooltip and its screen-reader label.
Widget _action(BuildContext context, String key, String label,
    VoidCallback? onPressed) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  // The label centred in whatever width the button is given (a share of a
  // row, or the full width when stacked).
  DVModifier modifier = const DVModifier();
  modifier = modifier.align(Alignment.center);
  return KeyedSubtree(
    key: ValueKey<String>(key),
    child: DVText(label).modifier(
      modifier
          .paddingSymmetric(horizontal: 12, vertical: 8)
          .minimumTapTarget(width: 44, height: 44)
          .rounded(8)
          .backgroundColor(onPressed == null
              ? scheme.onSurface.withValues(alpha: 0.12)
              : scheme.primary)
          .color(onPressed == null
              ? scheme.onSurface.withValues(alpha: 0.38)
              : scheme.onPrimary)
          .fontWeight(.w600)
          .tooltip(label)
          .onPressed(onPressed ?? () {}),
    ),
  );
}

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

  /// Held while the stored answer is unread: until then the page has no
  /// banner and looks finished, and a prerender that read it then wrote the
  /// page without one.
  DVCaptureHold? _hold;

  @override
  void initState() {
    super.initState();
    final DVAnalyticsRuntime? runtime = _runtime;
    if (runtime == null) return;
    if (runtime.loadedConsent == null) _hold = DVCaptureHold.begin();
    runtime.whenReady(() {
      if (!mounted) return;
      setState(() {});
      // Let go once the frame with the banner (or without it) is drawn.
      WidgetsBinding.instance.addPostFrameCallback((_) => _letGo());
    });
    // A pipeline that cannot start never calls whenReady; the page is then
    // as finished as it will get.
    runtime.ready.then<void>((_) {}, onError: (Object _) => _letGo());
  }

  void _letGo() {
    _hold?.release();
    _hold = null;
  }

  @override
  void dispose() {
    _letGo();
    super.dispose();
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
    final DVConsentBannerText text = consent.policy.banner;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> asked = <String>[
      for (final DVConsentDeclaration d in consent.policy.askable)
        _label(d.category.name),
    ];
    final String body = text.body ??
        'This application would like your permission for: '
            '${asked.join(', ')}. Nothing is collected for these until you '
            'choose.';
    final String? privacy = text.privacyUrl;
    final Widget? link = privacy == null
        ? null
        : privacy.startsWith('/')
            ? DVNavLink(
                // The application's own page, given as data in pubspec.yaml.
                to: DVRouteTarget(privacy),
                padding: .zero,
                child: _linkText(text.privacyLabel, scheme),
              )
            : DVNavLink.external(
                privacy,
                padding: .zero,
                child: _linkText(text.privacyLabel, scheme),
              );
    // A compact sheet at the bottom of the page, as wide as a phone and no
    // wider: on a desktop a full-width bar is a long line nobody reads, and
    // on a phone the page's own call to action stays above it.
    return SafeArea(
      top: false,
      child: DVBox(
        DVBox(
          DVBox.list(
            <Widget>[
              DVBox.row(
                <Widget>[
                  DVText(text.title).modifier(const DVModifier()
                      .fontWeight(.w700)
                      .fontSize(15)
                      .color(scheme.onSurface)
                      .heading(2)),
                  KeyedSubtree(
                    key: const ValueKey<String>('dv-consent-dismiss'),
                    child: DVBox(
                      Icon(Icons.close, size: 20, color: scheme.onSurface),
                      const DVModifier()
                          .tooltip('Close')
                          .minimumTapTarget(width: 44, height: 44)
                          .onPressed(() {
                        // Closed, not answered: nothing is recorded and every
                        // category stays at its declared default.
                        DVConsentBanner._closed[runtime] = true;
                        setState(() {});
                      }),
                    ),
                  ),
                ],
                align: .spaceBetween,
                crossAlign: .center,
              ),
              DVText(body).modifier(const DVModifier()
                  .fontSize(13)
                  .lineHeight(1.4)
                  .color(scheme.onSurfaceVariant)),
              ?link,
              if (_notSaved)
                KeyedSubtree(
                  key: const ValueKey<String>('dv-consent-not-saved'),
                  child: const DVText('Your choice could not be saved, so nothing '
                          'was turned on. Please try again.')
                      .modifier(const DVModifier().color(scheme.error)),
                ),
              // One row of equal shares; stacked, each the full width, where
              // three would not fit side by side (owner, 19 Nov 2026: three
              // natural widths and a gap on the right looked broken).
              LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
                final bool row = box.maxWidth >= 300;
                final List<Widget> actions = <Widget>[
                  _action(
                      context,
                      'dv-consent-accept-all',
                      text.acceptLabel,
                      _saving
                          ? null
                          : () =>
                              unawaited(_answer(runtime, consent, grant: true))),
                  _action(
                      context,
                      'dv-consent-reject-all',
                      text.rejectLabel,
                      _saving
                          ? null
                          : () => unawaited(
                              _answer(runtime, consent, grant: false))),
                  _action(context, 'dv-consent-choose', text.settingsLabel, () {
                    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (BuildContext _) => Scaffold(
                        appBar: AppBar(title: DVText(text.title)),
                        body: DVConsentSettingsPage(analytics: runtime),
                      ),
                    )).then((_) {
                      if (mounted) setState(() {});
                    }));
                  }),
                ];
                if (!row) return DVBox.list(actions, spacing: 8);
                // Equal shares: a plain Row, since DVBox.row with spacing
                // lays out as an OverflowBar, which cannot share its width.
                return Row(spacing: 8, children: <Widget>[for (final Widget action in actions) Expanded(child: action)]);
              }),
            ],
            spacing: 8,
          ),
          const DVModifier()
              .paddingSymmetric(horizontal: 16, vertical: 12)
              .maxWidth(560),
        ),
        const DVModifier()
            .backgroundColor(scheme.surface)
            .radius(const BorderRadius.vertical(top: Radius.circular(16)))
            .border(Border(top: BorderSide(color: scheme.outlineVariant)))
            .shadow(<BoxShadow>[
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, -2),
              ),
            ])
            .align(Alignment.topCenter),
      ),
    );
  }

  static Widget _linkText(String label, ColorScheme scheme) =>
      DVText(label).modifier(const DVModifier()
          .fontSize(14)
          .color(scheme.primary)
          .decoration(TextDecoration.underline));
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
      type: .transparency,
      child: ListView(
        padding: const .all(16),
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
            _action(context, 'dv-consent-save', 'Save',
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

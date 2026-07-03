library dartvel_flutter;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';

// conditional SEO impl (web does real work; others no-op)
import 'src/seo_platform_stub.dart'
    if (dart.library.html) 'src/seo_platform_web.dart' as seo_platform;

// ==========================================
// UI & Styling Primitives (NEW_SPEC.md)
// ==========================================

class DVStyleModifier {
  final Style style;
  const DVStyleModifier([this.style = const Style.empty()]);

  DVStyleModifier padding(double value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.padding(value))]));

  DVStyleModifier margin(double value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.margin(value))]));

  DVStyleModifier rounded(double value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.borderRadius(value))]));

  DVStyleModifier color(Color value) =>
      DVStyleModifier(Style.concat([style, Style(TextSpec.style(TextStyle(color: value)))]));

  DVStyleModifier backgroundColor(Color value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.color(value))]));

  DVStyleModifier width(double value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.width(value))]));

  DVStyleModifier height(double value) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.height(value))]));

  DVStyleModifier shadow(List<BoxShadow> shadows) =>
      DVStyleModifier(Style.concat([style, Style(BoxSpec.shadows(shadows))]));

  DVStyleModifier card() => DVStyleModifier(Style.concat([
        style,
        const Style(
          BoxSpec.color(Colors.white),
          BoxSpec.padding(16),
          BoxSpec.borderRadius(8),
        )
      ]));
}

class DVBox extends StatelessWidget {
  final Widget? child;
  final DVStyleModifier? modifier;

  const DVBox({
    super.key,
    this.child,
    this.modifier,
  });

  DVBox styleModifier(DVStyleModifier mod) => DVBox(
        modifier: mod,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = modifier?.style ?? const Style.empty();
    return Box(
      style: effectiveStyle,
      child: child,
    );
  }
}

class DVText extends StatelessWidget {
  final String text;
  final DVStyleModifier? modifier;

  const DVText(
    this.text, {
    super.key,
    this.modifier,
  });

  DVText styleModifier(DVStyleModifier mod) => DVText(
        text,
        modifier: mod,
      );

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = modifier?.style ?? const Style.empty();
    return StyledText(
      text,
      style: effectiveStyle,
    );
  }
}

// ==========================================
// Riverpod-powered Signals & State
// ==========================================

final _signalProviders = Expando<List<StateProvider<Object?>>>();
final _signalListeners = Expando<Map<StateProvider<Object?>, ProviderSubscription<Object?>>>();

class DVSignal<T> {
  final ProviderContainer container;
  final StateProvider<T> provider;
  final Element element;

  DVSignal(this.container, this.provider, this.element);

  T read() => container.read(provider);

  T get value {
    final listeners = _signalListeners[element] ??= {};
    if (!listeners.containsKey(provider)) {
      final sub = container.listen<T>(provider, (prev, next) {
        if (element.mounted) {
          element.markNeedsBuild();
        }
      });
      listeners[provider] = sub;
    }
    return container.read(provider);
  }

  set value(T newValue) {
    container.read(provider.notifier).state = newValue;
  }

  void update(T Function(T) cb) {
    container.read(provider.notifier).update(cb);
  }
}

extension DVSignalContextX on BuildContext {
  DVSignal<T> signal<T>(T initialValue) {
    final element = this as Element;
    final container = ProviderScope.containerOf(this);

    var list = _signalProviders[element];
    if (list == null) {
      list = [];
      _signalProviders[element] = list;
    }

    // Attempt to locate an existing provider of matching type
    StateProvider<T>? matchedProvider;
    for (final p in list) {
      if (p is StateProvider<T>) {
        matchedProvider = p;
        break;
      }
    }

    if (matchedProvider == null) {
      matchedProvider = StateProvider<T>((ref) => initialValue);
      list.add(matchedProvider);
    }

    return DVSignal<T>(container, matchedProvider, element);
  }

  T global<T>() => DV.global<T>();
}

extension DVModelSignalX on Object {
  DVSignal<T> signal<T>(BuildContext context) {
    return context.signal<T>(this as T);
  }
}

DVSignal<T> signal<T>(BuildContext context, T value) => context.signal<T>(value);

// ==========================================
// Model Forms
// ==========================================

class DVForm<T> extends StatefulWidget {
  final T? initialValue;
  final Widget Function(BuildContext, T)? builder;

  const DVForm({
    super.key,
    this.initialValue,
    this.builder,
  });

  const DVForm.builder({
    super.key,
    required Widget Function(BuildContext, T) builder,
    this.initialValue,
  }) : builder = builder;

  @override
  State<DVForm<T>> createState() => _DVFormState<T>();
}

class _DVFormState<T> extends State<DVForm<T>> {
  late T formValue;

  @override
  void initState() {
    super.initState();
    formValue = widget.initialValue ?? _instantiateDefault();
  }

  T _instantiateDefault() {
    try {
      return (T as dynamic).call();
    } catch (_) {
      return null as T;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.builder != null) {
      return widget.builder!(context, formValue);
    }
    return Form(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            decoration: const InputDecoration(labelText: 'Form Input'),
            onChanged: (val) {
              // Stub update
            },
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Platform, Auth, Theme, Tenants & SEO
// ==========================================

class DVCamera {
  const DVCamera();
  Future<List<int>> takePhoto() async => [];
}

class DVLocation {
  const DVLocation();
  Future<Map<String, double>> getCoordinates() async => {'lat': 0.0, 'lng': 0.0};
}

class DVNotifications {
  const DVNotifications();
  Future<void> sendLocalNotification(String title, String body) async {}
}

class DVPlatform {
  const DVPlatform();

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get isWeb => kIsWeb;

  DVCamera get camera => const DVCamera();
  DVLocation get location => const DVLocation();
  DVNotifications get notifications => const DVNotifications();
}

class DVAuth {
  const DVAuth();
  Object? get currentUser => null;
  Future<void> signIn() async {}
  Future<void> signOut() async {}
  Future<void> signUp() async {}
}

class DVTheme {
  const DVTheme();
  ThemeMode get mode => ThemeMode.system;
  void setMode(ThemeMode mode) {}
}

class DV {
  static final _globals = <Type, Object>{};

  static T global<T>([T? instance]) {
    if (instance != null) {
      _globals[T] = instance as Object;
      return instance;
    }
    final inst = _globals[T];
    if (inst == null) {
      throw StateError('Global instance of type $T not registered');
    }
    return inst as T;
  }

  static DVPlatform get Platform => const DVPlatform();
  static DVAuth get Auth => const DVAuth();
  static DVTheme get Theme => const DVTheme();
  static String get currentTenant => 'default';
}

// ==========================================
// Existing Routing & Page Transitions
// ==========================================

class DartvelRouteState extends InheritedWidget {
  final Map<String, String> params;
  final Map<String, String> query;

  const DartvelRouteState({
    super.key,
    required this.params,
    required this.query,
    required super.child,
  });

  static DartvelRouteState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DartvelRouteState>()!;

  @override
  bool updateShouldNotify(DartvelRouteState old) =>
      params != old.params || query != old.query;
}

extension DartvelRouteX on BuildContext {
  Map<String, String> get dvParams => DartvelRouteState.of(this).params;
  Map<String, String> get dvQuery => DartvelRouteState.of(this).query;
}

class SeoProps {
  final String? title;
  final String? description;
  final String? canonicalUrl;
  final String? imageUrl;
  final String? siteName;
  final String? twitterHandle;
  final Map<String, String> extraMeta;

  const SeoProps({
    this.title,
    this.description,
    this.canonicalUrl,
    this.imageUrl,
    this.siteName,
    this.twitterHandle,
    this.extraMeta = const {},
  });

  SeoProps merge(SeoProps other) => SeoProps(
        title: other.title ?? title,
        description: other.description ?? description,
        canonicalUrl: other.canonicalUrl ?? canonicalUrl,
        imageUrl: other.imageUrl ?? imageUrl,
        siteName: other.siteName ?? siteName,
        twitterHandle: other.twitterHandle ?? twitterHandle,
        extraMeta: {...extraMeta, ...other.extraMeta},
      );

  static const empty = SeoProps();
}

enum DvTransition { none, fade, slideLeft, slideUp, scale, sharedAxis }

class PageTransitionSpec {
  final DvTransition type;
  final Duration duration;
  final Curve curve;

  const PageTransitionSpec({
    this.type = DvTransition.fade,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeInOut,
  });

  static const none = PageTransitionSpec(
      type: DvTransition.none, duration: Duration.zero, curve: Curves.linear);
}

abstract class DartvelPage extends StatelessWidget {
  const DartvelPage({super.key});

  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      SeoProps.empty;

  PageTransitionSpec get transition => const PageTransitionSpec();

  Future<Object?> loadData(
          Map<String, String> params, Map<String, String> query) async =>
      null;

  Future<List<Map<String, String>>> get staticPaths async => [];
}

abstract class DartvelLayout extends StatelessWidget {
  final Widget child;
  const DartvelLayout({super.key, required this.child});
}

class DvDataScope extends InheritedWidget {
  final Object? data;
  const DvDataScope({super.key, required this.data, required super.child});

  static DvDataScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DvDataScope>()!;

  @override
  bool updateShouldNotify(DvDataScope oldWidget) => data != oldWidget.data;
}

class DvDataLoader extends StatelessWidget {
  final Future<Object?> Function() load;
  final Widget child;
  final Widget? loading;
  final Widget? error;

  const DvDataLoader(
      {super.key,
      required this.load,
      required this.child,
      this.loading,
      this.error});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Object?>(
      future: load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loading ?? const DvDefaultLoading();
        }
        if (snapshot.hasError) {
          return error ?? const DvDefaultError();
        }
        return DvDataScope(data: snapshot.data, child: child);
      },
    );
  }
}

class DartvelSeo extends StatelessWidget {
  final SeoProps props;
  final SeoProps defaults;
  final Widget child;

  const DartvelSeo({
    super.key,
    required this.props,
    required this.defaults,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final merged = defaults.merge(props);
      seo_platform.applySeo(merged);
    }
    return child;
  }
}

CustomTransitionPage<T> dvTransitionPage<T>({
  LocalKey? key,
  required Widget child,
  required PageTransitionSpec spec,
}) {
  if (spec.type == DvTransition.none) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionsBuilder: (c, a, sA, ch) => ch,
      transitionDuration: spec.duration,
      reverseTransitionDuration: spec.duration,
    );
  }

  Widget builder(
      BuildContext c, Animation<double> a, Animation<double> sA, Widget ch) {
    final curved = CurvedAnimation(parent: a, curve: spec.curve);
    switch (spec.type) {
      case DvTransition.fade:
        return FadeTransition(opacity: curved, child: ch);
      case DvTransition.slideLeft:
        return SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
                  .animate(curved),
          child: ch,
        );
      case DvTransition.slideUp:
        return SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                  .animate(curved),
          child: ch,
        );
      case DvTransition.scale:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: ch,
        );
      case DvTransition.sharedAxis:
        final fade = FadeTransition(opacity: curved, child: ch);
        return SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(curved),
          child: fade,
        );
      case DvTransition.none:
        return ch;
    }
  }

  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionsBuilder: builder,
    transitionDuration: spec.duration,
    reverseTransitionDuration: spec.duration,
  );
}

class DvDefaultLoading extends StatelessWidget {
  const DvDefaultLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class DvDefaultError extends StatelessWidget {
  final String? message;
  const DvDefaultError({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final text = message ?? 'Something went wrong';
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class DvI18nScope extends InheritedWidget {
  final String localeTag;

  const DvI18nScope({
    super.key,
    required this.localeTag,
    required super.child,
  });

  Locale get locale {
    final parts = localeTag.replaceAll('_', '-').split('-');
    if (parts.isEmpty || parts[0].isEmpty) return const Locale('en');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }

  static DvI18nScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DvI18nScope>()!;

  @override
  bool updateShouldNotify(DvI18nScope oldWidget) =>
      localeTag != oldWidget.localeTag;
}

class DvI18n {
  static String normalize(String? raw, List<String> allowed, String fallback) {
    final tag = (raw ?? '').trim();
    if (tag.isEmpty) return fallback;
    for (final a in allowed) {
      if (a.toLowerCase() == tag.toLowerCase()) return a;
    }
    return allowed.isEmpty ? (tag.isNotEmpty ? tag : fallback) : fallback;
  }

  static Locale parseLocale(String tag) {
    final parts = tag.replaceAll('_', '-').split('-');
    if (parts.isEmpty || parts[0].isEmpty) return const Locale('en');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }

  static void updateLang(BuildContext context, String param, String newLang) {
    final router = GoRouter.of(context);
    final state = GoRouterState.of(context);
    final uri = state.uri;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp[param] = newLang;
    final newUri = uri.replace(queryParameters: qp);
    router.go(newUri.toString());
  }
}

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

class DVModifier {
  final Style style;
  final VoidCallback? onTapCallback;
  final DecorationImage? bgImage;

  const DVModifier({
    this.style = const Style.empty(),
    this.onTapCallback,
    this.bgImage,
  });

  const DVModifier.fromStyle([this.style = const Style.empty()])
      : onTapCallback = null,
        bgImage = null;

  DVModifier _copyWith({Style? style, VoidCallback? onTapCallback, DecorationImage? bgImage}) {
    return DVModifier(
      style: style ?? this.style,
      onTapCallback: onTapCallback ?? this.onTapCallback,
      bgImage: bgImage ?? this.bgImage,
    );
  }

  DVModifier padding(double value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.padding(value))]));

  DVModifier margin(double value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.margin(value))]));

  DVModifier rounded(double value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.borderRadius(value))]));

  DVModifier color(Color value) =>
      _copyWith(style: Style.concat([style, Style(TextSpec.style(TextStyle(color: value)))]));

  DVModifier backgroundColor(Color value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.color(value))]));

  DVModifier width(double value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.width(value))]));

  DVModifier height(double value) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.height(value))]));

  DVModifier shadow(List<BoxShadow> shadows) =>
      _copyWith(style: Style.concat([style, Style(BoxSpec.shadows(shadows))]));

  DVModifier card() => _copyWith(style: Style.concat([
        style,
        const Style(
          BoxSpec.color(Colors.white),
          BoxSpec.padding(16),
          BoxSpec.borderRadius(8),
        )
      ]));

  DVModifier onTap(VoidCallback callback) => _copyWith(onTapCallback: callback);
  DVModifier onPressed(VoidCallback callback) => _copyWith(onTapCallback: callback);

  DVModifier backgroundImage(DecorationImage image) => _copyWith(bgImage: image);
}

typedef DVStyleModifier = DVModifier;

class DVBox extends StatelessWidget {
  final Widget? child;
  final DVModifier? modifier;

  const DVBox([this.child, this.modifier]);

  DVBox modifier(DVModifier mod) => DVBox(child, mod);
  DVBox styleModifier(DVModifier mod) => DVBox(child, mod);

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = modifier?.style ?? const Style.empty();
    Widget result = Box(
      style: effectiveStyle,
      child: child,
    );

    if (modifier?.bgImage != null) {
      result = Container(
        decoration: BoxDecoration(
          image: modifier!.bgImage,
        ),
        child: result,
      );
    }

    if (modifier?.onTapCallback != null) {
      result = GestureDetector(
        onTap: modifier!.onTapCallback,
        child: result,
      );
    }

    return result;
  }
}

class DVText extends StatelessWidget {
  final String text;
  final DVModifier? modifier;

  const DVText(this.text, [this.modifier]);

  DVText modifier(DVModifier mod) => DVText(text, mod);
  DVText styleModifier(DVModifier mod) => DVText(text, mod);

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = modifier?.style ?? const Style.empty();
    Widget result = StyledText(
      text,
      style: effectiveStyle,
    );

    if (modifier?.onTapCallback != null) {
      result = GestureDetector(
        onTap: modifier!.onTapCallback,
        child: result,
      );
    }

    return result;
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

  T global<T>() {
    final provider = _globalProviders.putIfAbsent(
      T,
      () => StateProvider<Object?>((ref) => DV.global<T>()),
    ) as StateProvider<T>;

    final container = ProviderScope.containerOf(this);
    DV.container = container;
    final element = this as Element;
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
}

final _globalProviders = <Type, StateProvider<Object?>>{};

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

  const DVForm([this.initialValue]) : builder = null;

  const DVForm.builder({
    super.key,
    required Widget Function(BuildContext, T) this.builder,
    this.initialValue,
  });

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
    
    // Automatic Form Generation from Model JSON Map
    final fields = <Widget>[];
    if (formValue != null) {
      try {
        final jsonMap = (formValue as dynamic).toJson() as Map<String, dynamic>;
        jsonMap.forEach((key, value) {
          fields.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextFormField(
                initialValue: value?.toString() ?? '',
                decoration: InputDecoration(
                  labelText: key.toUpperCase(),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (val) {
                  // Best-effort update or stub
                },
              ),
            ),
          );
        });
      } catch (_) {
        fields.add(const Text('No form controls generated. Model must support toJson().'));
      }
    } else {
      fields.add(Text('Empty form for type $T'));
    }

    return Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: fields,
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

class DVBluetooth {
  const DVBluetooth();
  Future<bool> isEnabled() async => false;
  Stream<List<String>> scanDevices() => const Stream.empty();
}

class DVNfc {
  const DVNfc();
  Future<bool> isAvailable() async => false;
  Future<String> readTag() async => '';
}

class DVClipboard {
  const DVClipboard();
  Future<void> copy(String text) async {}
  Future<String?> paste() async => null;
}

class DVShare {
  const DVShare();
  Future<void> shareText(String text) async {}
}

class DVSensors {
  const DVSensors();
  Stream<Map<String, double>> get accelerometer => const Stream.empty();
  Stream<Map<String, double>> get gyroscope => const Stream.empty();
}

class DVBiometrics {
  const DVBiometrics();
  Future<bool> canAuthenticate() async => false;
  Future<bool> authenticate() async => false;
}

class DVDeepLinks {
  const DVDeepLinks();
  Future<String?> getInitialLink() async => null;
  Stream<String> getLinkStream() => const Stream.empty();
}

class DVHaptics {
  const DVHaptics();
  Future<void> vibrate() async {}
  Future<void> lightVibrate() async {}
}

class DVContacts {
  const DVContacts();
  Future<List<Map<String, String>>> getContacts() async => [];
}

class DVPlatform {
  const DVPlatform();

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool get isFuchsia => !kIsWeb && defaultTargetPlatform == TargetPlatform.fuchsia;
  bool get isWeb => kIsWeb;
  
  bool get isTizen => false;
  bool get isWebOS => false;
  bool get isAmazon => false;
  bool get isTV => false;
  bool get isWatch => false;
  bool get isFoldable => false;

  double get screenWidth => 375.0;
  double get screenHeight => 812.0;
  Map<String, double> get safeAreas => {'top': 44.0, 'bottom': 34.0, 'left': 0.0, 'right': 0.0};
  String get breakpoint => 'mobile';
  Orientation get orientation => Orientation.portrait;
  String get deviceType => 'phone';
  String get screenShape => 'rectangle';

  DVCamera get camera => const DVCamera();
  DVLocation get location => const DVLocation();
  DVNotifications get notifications => const DVNotifications();
  DVBluetooth get bluetooth => const DVBluetooth();
  DVNfc get nfc => const DVNfc();
  DVClipboard get clipboard => const DVClipboard();
  DVShare get share => const DVShare();
  DVSensors get sensors => const DVSensors();
  DVBiometrics get biometrics => const DVBiometrics();
  DVDeepLinks get deepLinks => const DVDeepLinks();
  DVHaptics get haptics => const DVHaptics();
  DVContacts get contacts => const DVContacts();
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

class DVAI {
  const DVAI();
  Future<String> chat(String prompt, {String provider = 'gemini'}) async => 'AI Response';
  Future<List<double>> embed(String text) async => [];
  Future<Map<String, dynamic>> structuredOutput(String prompt, Map<String, dynamic> schema) async => {};
}

class DVDatabase {
  const DVDatabase();
  Future<List<Map<String, dynamic>>> query(String sql, [List<Object?>? params]) async => [];
  Future<int> execute(String sql, [List<Object?>? params]) async => 0;
}

class DVCache {
  const DVCache();
  Future<T?> get<T>(String key) async => null;
  Future<void> set(String key, Object? value, [Duration? ttl]) async {}
  Future<void> delete(String key) async {}
}

class DVStorage {
  const DVStorage();
  Future<void> upload(String key, List<int> bytes) async {}
  Future<List<int>> download(String key) async => [];
  Future<void> delete(String key) async {}
}

class DVRealtime {
  const DVRealtime();
  Future<void> syncModel(Object model) async {}
  Future<void> presence(String channel) async {}
  Future<void> subscribe(String channel, Function(dynamic) onEvent) async {}
}

class DV {
  static final _globals = <Type, Object>{};
  static ProviderContainer? container;

  static T global<T>([T? instance]) {
    if (instance != null) {
      _globals[T] = instance as Object;
      final provider = _globalProviders[T];
      if (provider != null && container != null) {
        container!.read(provider.notifier).state = instance;
      } else if (provider == null) {
        _globalProviders[T] = StateProvider<Object?>((ref) => instance);
      }
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
  static DVAI get AI => const DVAI();
  static DVDatabase get DB => const DVDatabase();
  static DVCache get Cache => const DVCache();
  static DVStorage get Storage => const DVStorage();
  static DVRealtime get Realtime => const DVRealtime();
  static String get currentTenant => 'default';
}

// ==========================================
// Existing Routing & Page Transitions
// ==========================================

class DVRouteTarget {
  final String path;
  const DVRouteTarget(this.path);
}

extension DartvelNavigationX on BuildContext {
  void navigateToPage(DVRouteTarget target) {
    go(target.path);
  }
}

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

/// A Dartvel page widget represented as a class.
abstract class DVClassWidget extends DartvelPage {
  /// Default constructor.
  const DVClassWidget({super.key});
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

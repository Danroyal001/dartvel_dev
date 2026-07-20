library dartvel_flutter;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// conditional SEO implementation
import 'src/browser_extension_platform_memory.dart'
    if (dart.library.html) 'src/browser_extension_platform_web.dart'
    as browser_extension_platform;
import 'src/seo_platform_memory.dart'
    if (dart.library.html) 'src/seo_platform_web.dart' as seo_platform;

export 'package:dartvel_core/dartvel.dart'
    show
        Analytics,
        AnalyticsEvent,
        AnalyticsProvider,
        DVAIAgentRequest,
        DVAIAgentResult,
        DVAITranscript,
        DVAIToolEntry,
        DVAIToolHandler,
        DVAIToolRegistry,
        BillingPlan,
        DVCronEntry,
        DVCronTarget,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVFormControls,
        DVFormControlsFactory,
        DVAuthAuthorization,
        DVJob,
        DVExportResult,
        DVExportOptions,
        DVMiddleware,
        DVMiddlewareKey,
        DVMiddlewares,
        DVPolicy,
        DVPolicies,
        DVPolicyAction,
        DVUseMiddleware,
        DVCacheTags,
        DVEmptySearchProvider,
        DVImportResult,
        DVImportChunk,
        DVImportRowError,
        DVJsonBool,
        DVJsonList,
        DVJsonMap,
        DVJsonNull,
        DVJsonNumber,
        DVJsonObject,
        DVJsonString,
        DVJsonValue,
        DVInMemoryQueueAdapter,
        DVJobEnvelope,
        DVJobHandler,
        DVJobState,
        DVMailAddress,
        DVMailMessage,
        DVMailPriority,
        DVMailProvider,
        DVNotificationMail,
        DVMemoryMailProvider,
        DVMemoryNotificationProvider,
        DVNotificationChannel,
        DVNotificationMessage,
        DVNotificationProvider,
        DVNotificationProviderKind,
        DVNotificationsService,
        DVPolicyCheck,
        DVQueueAdapter,
        DVQueues,
        DVReportResult,
        DVScheduledReport,
        DVSearchProvider,
        DVSearchResultPage,
        DVSentNotification,
        DVShell,
        DVShellCommand,
        DVShellResult,
        DVShellResultFuture,
        DVTestHarness,
        DVLocalBillingProvider,
        Entitlement,
        LocalAnalyticsProvider,
        formControlsFactories,
        registerFormControlsFactory;
export 'package:go_router/go_router.dart';

// ==========================================
// UI & Styling Primitives (NEW_SPEC.md)
// ==========================================

class DVModifier {
  final EdgeInsetsGeometry? paddingValue;
  final EdgeInsetsGeometry? marginValue;
  final BorderRadiusGeometry? borderRadius;
  final Color? textColor;
  final double? fontSizeValue;
  final FontWeight? fontWeightValue;
  final double? letterSpacingValue;
  final Color? boxColor;
  final double? widthValue;
  final double? heightValue;
  final AlignmentGeometry? alignmentValue;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTapCallback;
  final DecorationImage? bgImage;
  final String? semanticLabelValue;
  final String? semanticHintValue;
  final bool? semanticButtonValue;
  final Size? minimumTapTargetValue;

  const DVModifier({
    this.paddingValue,
    this.marginValue,
    this.borderRadius,
    this.textColor,
    this.fontSizeValue,
    this.fontWeightValue,
    this.letterSpacingValue,
    this.boxColor,
    this.widthValue,
    this.heightValue,
    this.alignmentValue,
    this.shadows,
    this.onTapCallback,
    this.bgImage,
    this.semanticLabelValue,
    this.semanticHintValue,
    this.semanticButtonValue,
    this.minimumTapTargetValue,
  });

  const DVModifier.fromStyle()
      : paddingValue = null,
        marginValue = null,
        borderRadius = null,
        textColor = null,
        fontSizeValue = null,
        fontWeightValue = null,
        letterSpacingValue = null,
        boxColor = null,
        widthValue = null,
        heightValue = null,
        alignmentValue = null,
        shadows = null,
        onTapCallback = null,
        bgImage = null,
        semanticLabelValue = null,
        semanticHintValue = null,
        semanticButtonValue = null,
        minimumTapTargetValue = null;

  DVModifier _copyWith({
    EdgeInsetsGeometry? paddingValue,
    EdgeInsetsGeometry? marginValue,
    BorderRadiusGeometry? borderRadius,
    Color? textColor,
    double? fontSizeValue,
    FontWeight? fontWeightValue,
    double? letterSpacingValue,
    Color? boxColor,
    double? widthValue,
    double? heightValue,
    AlignmentGeometry? alignmentValue,
    List<BoxShadow>? shadows,
    VoidCallback? onTapCallback,
    DecorationImage? bgImage,
    String? semanticLabelValue,
    String? semanticHintValue,
    bool? semanticButtonValue,
    Size? minimumTapTargetValue,
  }) {
    return DVModifier(
      paddingValue: paddingValue ?? this.paddingValue,
      marginValue: marginValue ?? this.marginValue,
      borderRadius: borderRadius ?? this.borderRadius,
      textColor: textColor ?? this.textColor,
      fontSizeValue: fontSizeValue ?? this.fontSizeValue,
      fontWeightValue: fontWeightValue ?? this.fontWeightValue,
      letterSpacingValue: letterSpacingValue ?? this.letterSpacingValue,
      boxColor: boxColor ?? this.boxColor,
      widthValue: widthValue ?? this.widthValue,
      heightValue: heightValue ?? this.heightValue,
      alignmentValue: alignmentValue ?? this.alignmentValue,
      shadows: shadows ?? this.shadows,
      onTapCallback: onTapCallback ?? this.onTapCallback,
      bgImage: bgImage ?? this.bgImage,
      semanticLabelValue: semanticLabelValue ?? this.semanticLabelValue,
      semanticHintValue: semanticHintValue ?? this.semanticHintValue,
      semanticButtonValue: semanticButtonValue ?? this.semanticButtonValue,
      minimumTapTargetValue:
          minimumTapTargetValue ?? this.minimumTapTargetValue,
    );
  }

  DVModifier padding(double value) =>
      _copyWith(paddingValue: EdgeInsets.all(value));

  DVModifier margin(double value) =>
      _copyWith(marginValue: EdgeInsets.all(value));

  DVModifier rounded(double value) =>
      _copyWith(borderRadius: BorderRadius.circular(value));

  DVModifier color(Color value) => _copyWith(textColor: value);

  DVModifier fontSize(double value) => _copyWith(fontSizeValue: value);

  DVModifier fontWeight(FontWeight value) => _copyWith(fontWeightValue: value);

  DVModifier letterSpacing(double value) =>
      _copyWith(letterSpacingValue: value);

  DVModifier backgroundColor(Color value) => _copyWith(boxColor: value);

  DVModifier width(double value) => _copyWith(widthValue: value);

  DVModifier height(double value) => _copyWith(heightValue: value);

  DVModifier align(AlignmentGeometry value) => _copyWith(alignmentValue: value);

  DVModifier shadow(List<BoxShadow> shadows) => _copyWith(shadows: shadows);

  DVModifier card() => _copyWith(
        boxColor: boxColor ?? Colors.white,
        paddingValue: paddingValue ?? const EdgeInsets.all(16),
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      );

  DVModifier onTap(VoidCallback callback) => _copyWith(onTapCallback: callback);
  DVModifier onPressed(VoidCallback callback) =>
      _copyWith(onTapCallback: callback);

  DVModifier backgroundImage(DecorationImage image) =>
      _copyWith(bgImage: image);

  DVModifier semanticLabel(String value) =>
      _copyWith(semanticLabelValue: value);

  DVModifier semanticHint(String value) => _copyWith(semanticHintValue: value);

  DVModifier semanticButton([bool value = true]) =>
      _copyWith(semanticButtonValue: value);

  DVModifier minimumTapTarget({
    double width = 48,
    double height = 48,
  }) =>
      _copyWith(minimumTapTargetValue: Size(width, height));
}

typedef DVStyleModifier = DVModifier;

enum _DVBoxLayout {
  vertical,
  row,
  grid,
  wrap,
  stack,
  horizontalScrollable,
  masonry,
}

typedef DVWidgetBuilder<T> = Widget Function(T item);

class DVBox<T> extends StatelessWidget {
  final Widget? _child;
  final List<Widget>? _children;
  final DVModifier? _modifier;
  final _DVBoxLayout _layout;
  final int _columns;
  final double _spacing;
  final bool _scrollable;
  final List<T>? _items;
  final Widget Function(BuildContext, T)? _itemBuilder;

  const DVBox([Widget? child, DVModifier? modifier])
      : _child = child,
        _children = null,
        _modifier = modifier,
        _layout = _DVBoxLayout.vertical,
        _columns = 1,
        _spacing = 8,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.list(List<Widget> children, {DVModifier? modifier})
      : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.vertical,
        _columns = 1,
        _spacing = 8,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.row(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.row,
        _columns = 1,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.wrapLine(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.wrap,
        _columns = 1,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.wrap(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.wrap,
        _columns = 1,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.stack(List<Widget> children, {DVModifier? modifier})
      : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.stack,
        _columns = 1,
        _spacing = 8,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.grid(
    List<Widget> children, {
    DVModifier? modifier,
    int columns = 2,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.grid,
        _columns = columns,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.horizontalScrollable(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.horizontalScrollable,
        _columns = 1,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.masonry(
    List<Widget> children, {
    DVModifier? modifier,
    int columns = 2,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.masonry,
        _columns = columns,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox._({
    Widget? child,
    List<Widget>? children,
    DVModifier? modifier,
    _DVBoxLayout layout = _DVBoxLayout.vertical,
    int columns = 1,
    double spacing = 8,
    bool scrollable = false,
    List<T>? items,
    Widget Function(BuildContext, T)? itemBuilder,
  })  : _child = child,
        _children = children,
        _modifier = modifier,
        _layout = layout,
        _columns = columns,
        _spacing = spacing,
        _scrollable = scrollable,
        _items = items,
        _itemBuilder = itemBuilder;

  static DVBox<T> builder<T>(
    Iterable<T> items,
    DVWidgetBuilder<T> builder, [
    DVModifier? modifier,
  ]) {
    return DVBox<T>._(
      modifier: modifier,
      items: List<T>.from(items),
      itemBuilder: (context, item) => builder(item),
    );
  }

  DVBox<T> modifier(DVModifier mod) => _copyWith(modifier: mod);
  DVBox<T> styleModifier(DVModifier mod) => modifier(mod);

  DVBox<T> row({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.row, spacing: spacing);

  DVBox<T> grid({int columns = 2, double spacing = 8}) => _copyWith(
        layout: _DVBoxLayout.grid,
        columns: columns,
        spacing: spacing,
      );

  DVBox<T> wrapLine({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.wrap, spacing: spacing);

  DVBox<T> wrap({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.wrap, spacing: spacing);

  DVBox<T> stack() => _copyWith(layout: _DVBoxLayout.stack);

  DVBox<T> horizontalScrollable({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.horizontalScrollable, spacing: spacing);

  DVBox<T> masonry({int columns = 2, double spacing = 8}) => _copyWith(
        layout: _DVBoxLayout.masonry,
        columns: columns,
        spacing: spacing,
      );

  DVBox<T> scrollable() => _copyWith(scrollable: true);

  DVBox<T> _copyWith({
    DVModifier? modifier,
    _DVBoxLayout? layout,
    int? columns,
    double? spacing,
    bool? scrollable,
  }) {
    return DVBox<T>._(
      child: _child,
      children: _children,
      modifier: modifier ?? _modifier,
      layout: layout ?? _layout,
      columns: columns ?? _columns,
      spacing: spacing ?? _spacing,
      scrollable: scrollable ?? _scrollable,
      items: _items,
      itemBuilder: _itemBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    Widget result = Container(
      width: _modifier?.widthValue,
      height: _modifier?.heightValue,
      alignment: _modifier?.alignmentValue,
      margin: _modifier?.marginValue,
      padding: _modifier?.paddingValue,
      decoration: BoxDecoration(
        color: _modifier?.boxColor,
        borderRadius: _modifier?.borderRadius,
        boxShadow: _modifier?.shadows,
        image: _modifier?.bgImage,
      ),
      child: content,
    );

    if (_modifier?.onTapCallback != null) {
      result = GestureDetector(
        onTap: _modifier!.onTapCallback,
        child: result,
      );
    }

    final minimumTapTarget = _modifier?.minimumTapTargetValue;
    if (minimumTapTarget != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumTapTarget.width,
          minHeight: minimumTapTarget.height,
        ),
        child: result,
      );
    }

    if (_modifier?.semanticLabelValue != null ||
        _modifier?.semanticHintValue != null ||
        _modifier?.semanticButtonValue != null) {
      result = Semantics(
        label: _modifier?.semanticLabelValue,
        hint: _modifier?.semanticHintValue,
        button: _modifier?.semanticButtonValue,
        excludeSemantics: _modifier?.semanticLabelValue != null,
        child: result,
      );
    }

    return result;
  }

  Widget? _buildContent(BuildContext context) {
    final builder = _itemBuilder;
    final items = _items;
    if (builder != null && items != null) {
      return _buildDynamicCollection(context, items, builder);
    }

    final child = _child;
    if (child != null) return _maybeScrollable(child);
    final children = _children;
    if (children != null) return _buildStaticCollection(children);
    return null;
  }

  Widget _buildStaticCollection(List<Widget> children) {
    final spaced = _spaced(children);
    final Widget result;
    switch (_layout) {
      case _DVBoxLayout.vertical:
        result = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: spaced,
        );
        break;
      case _DVBoxLayout.row:
        result = Row(
          mainAxisSize: MainAxisSize.min,
          children: spaced,
        );
        break;
      case _DVBoxLayout.grid:
        result = GridView.count(
          crossAxisCount: _safeColumns,
          mainAxisSpacing: _spacing,
          crossAxisSpacing: _spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
        break;
      case _DVBoxLayout.wrap:
        result =
            Wrap(spacing: _spacing, runSpacing: _spacing, children: children);
        break;
      case _DVBoxLayout.stack:
        result = Stack(children: children);
        break;
      case _DVBoxLayout.horizontalScrollable:
        result = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: spaced),
        );
        break;
      case _DVBoxLayout.masonry:
        result = _buildMasonry(children);
        break;
    }
    return _maybeScrollable(result);
  }

  Widget _buildDynamicCollection(
    BuildContext context,
    List<T> items,
    Widget Function(BuildContext, T) builder,
  ) {
    switch (_layout) {
      case _DVBoxLayout.grid:
        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: !_scrollable,
          physics: _scrollable ? null : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _safeColumns,
            mainAxisSpacing: _spacing,
            crossAxisSpacing: _spacing,
          ),
          itemBuilder: (context, index) => builder(context, items[index]),
        );
      case _DVBoxLayout.horizontalScrollable:
        return SizedBox(
          height: _modifier?.heightValue ?? 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) => builder(context, items[index]),
            separatorBuilder: (_, __) => SizedBox(width: _spacing),
          ),
        );
      case _DVBoxLayout.wrap:
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [for (final item in items) builder(context, item)],
        );
      case _DVBoxLayout.stack:
        return Stack(
          children: [for (final item in items) builder(context, item)],
        );
      case _DVBoxLayout.row:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: _spaced([for (final item in items) builder(context, item)]),
        );
      case _DVBoxLayout.masonry:
        return _buildMasonry(
            [for (final item in items) builder(context, item)]);
      case _DVBoxLayout.vertical:
        return ListView.separated(
          itemCount: items.length,
          shrinkWrap: !_scrollable,
          physics: _scrollable ? null : const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) => builder(context, items[index]),
          separatorBuilder: (_, __) => SizedBox(height: _spacing),
        );
    }
  }

  Widget _buildMasonry(List<Widget> children) {
    final columns = List.generate(_safeColumns, (_) => <Widget>[]);
    for (int i = 0; i < children.length; i++) {
      columns[i % _safeColumns].add(children[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < columns.length; i++)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _spaced(columns[i]),
            ),
          ),
      ],
    );
  }

  Widget _maybeScrollable(Widget child) {
    if (!_scrollable || _layout == _DVBoxLayout.horizontalScrollable) {
      return child;
    }
    return SingleChildScrollView(child: child);
  }

  List<Widget> _spaced(List<Widget> children) {
    if (children.length < 2 || _spacing <= 0) return children;
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i != children.length - 1) {
        result.add(_layout == _DVBoxLayout.row ||
                _layout == _DVBoxLayout.horizontalScrollable
            ? SizedBox(width: _spacing)
            : SizedBox(height: _spacing));
      }
    }
    return result;
  }

  int get _safeColumns => _columns < 1 ? 1 : _columns;
}

class DVText extends StatelessWidget {
  final String text;
  final DVModifier? _modifier;

  const DVText(this.text, [DVModifier? modifier]) : _modifier = modifier;

  DVText modifier(DVModifier mod) => DVText(text, mod);
  DVText styleModifier(DVModifier mod) => DVText(text, mod);

  @override
  Widget build(BuildContext context) {
    Widget result = Text(
      text,
      style: TextStyle(
        color: _modifier?.textColor,
        fontSize: _modifier?.fontSizeValue,
        fontWeight: _modifier?.fontWeightValue,
        letterSpacing: _modifier?.letterSpacingValue,
      ),
    );

    if (_modifier?.onTapCallback != null) {
      result = GestureDetector(
        onTap: _modifier!.onTapCallback,
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
final _signalListeners =
    Expando<Map<StateProvider<Object?>, ProviderSubscription<Object?>>>();

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

DVSignal<T> signal<T>(BuildContext context, T value) =>
    context.signal<T>(value);

// ==========================================
// Model Forms
// ==========================================

class DVForm<T> extends StatefulWidget {
  final T? initialValue;
  final Widget Function(DVFormControls)? builder;

  const DVForm([this.initialValue]) : builder = null;

  const DVForm.builder(Widget Function(DVFormControls) this.builder,
      [this.initialValue, Key? key])
      : super(key: key);

  @override
  State<DVForm<T>> createState() => _DVFormState<T>();
}

extension DVFormAliasX on Object {
  Widget Form() => DVForm<Object>(this);
}

class _DVFormState<T> extends State<DVForm<T>> {
  late T formValue;
  late T _initialValue;

  @override
  void initState() {
    super.initState();
    formValue = widget.initialValue ?? _instantiateDefault();
    _initialValue = formValue;
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
    final factory = formControlsFactories[T];
    final formControls = factory != null
        ? factory(
            formValue,
            onSubmit: _submit,
            onReset: _reset,
          )
        : DVFormControls(
            formValue,
            onSubmit: _submit,
            onReset: _reset,
          );

    if (widget.builder != null) {
      return widget.builder!(formControls);
    }

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
                  // Generated form controls update concrete generated models.
                },
              ),
            ),
          );
        });
      } catch (_) {
        fields.add(const DVText(
            'No form controls generated. Model must support toJson().'));
      }
    } else {
      fields.add(DVText('Empty form for type $T'));
    }

    return Form(
      child: DVBox.list(fields),
    );
  }

  void _submit() {
    setState(() {
      _initialValue = formValue;
    });
  }

  void _reset() {
    setState(() {
      formValue = _initialValue;
    });
  }
}

// ==========================================
// Platform, Auth, Theme, Tenants & SEO
// ==========================================

class DVNativeBridge {
  static final Map<String, FutureOr<Object?> Function(Object?)> _handlers = {};

  static Future<T?> invoke<T>(String method, [Object? arguments]) async {
    final handler = _handlers[method];
    if (handler == null) return null;
    final value = await handler(arguments);
    return value is T ? value : null;
  }

  static Future<T> require<T>(String method, [Object? arguments]) async {
    final handler = _handlers[method];
    if (handler == null) {
      throw StateError(
        'Native binding "$method" is not registered. Generate and register an FFI/ffigen or JNI/jnigen binding before calling this API.',
      );
    }
    final value = await handler(arguments);
    if (value is! T) {
      throw StateError(
        'Native binding "$method" returned ${value.runtimeType}, expected $T.',
      );
    }
    return value;
  }

  static void register(
    String method,
    FutureOr<Object?> Function(Object?) handler,
  ) {
    _handlers[method] = handler;
  }

  static void unregister(String method) {
    _handlers.remove(method);
  }
}

class DVCamera {
  const DVCamera();

  Future<List<int>> takePhoto() async {
    final bytes =
        await DVNativeBridge.require<List<dynamic>>('camera.takePhoto');
    return bytes.cast<int>();
  }
}

class DVMedia {
  const DVMedia();

  Future<List<Map<String, Object?>>> pick({
    String type = 'image',
    bool multiple = false,
  }) async {
    final items = await DVNativeBridge.invoke<List<dynamic>>(
      'media.pick',
      {'type': type, 'multiple': multiple},
    );
    if (items == null) {
      throw StateError(
        'Native binding "media.pick" is not registered. Generate and register an FFI/ffigen or JNI/jnigen binding before calling this API.',
      );
    }
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }
}

class DVFiles {
  const DVFiles();
  static final Map<String, List<int>> _memory = {};

  Future<void> writeBytes(String path, List<int> bytes) async {
    final handled = await DVNativeBridge.invoke<bool>(
      'files.writeBytes',
      {'path': path, 'bytes': bytes},
    );
    if (handled != true) _memory[path] = List<int>.from(bytes);
  }

  Future<List<int>> readBytes(String path) async {
    final bytes = await DVNativeBridge.invoke<List<dynamic>>(
      'files.readBytes',
      {'path': path},
    );
    if (bytes != null) return bytes.cast<int>();
    return List<int>.from(_memory[path] ?? const <int>[]);
  }

  Future<void> delete(String path) async {
    final handled = await DVNativeBridge.invoke<bool>(
      'files.delete',
      {'path': path},
    );
    if (handled != true) _memory.remove(path);
  }
}

class DVLocation {
  const DVLocation();

  Future<Map<String, double>> getCoordinates() async {
    final result =
        await DVNativeBridge.require<Map<dynamic, dynamic>>('location.current');
    return {
      'latitude': (result['latitude'] as num?)?.toDouble() ?? 0,
      'longitude': (result['longitude'] as num?)?.toDouble() ?? 0,
    };
  }
}

class DVNotifications {
  const DVNotifications();
  static final List<Map<String, String>> _sent = [];

  Future<void> sendLocalNotification(String title, String body) async {
    final handled = await DVNativeBridge.require<bool>(
      'notifications.sendLocal',
      {'title': title, 'body': body},
    );
    if (!handled) {
      throw StateError('Native notification binding rejected the request.');
    }
    _sent.add({'title': title, 'body': body});
  }

  List<Map<String, String>> get sentNotifications => List.unmodifiable(_sent);
}

enum DVUpdateChannel {
  production,
  beta,
  staging,
  development,
}

class DVUpdateInfo {
  final bool available;
  final String? version;
  final String? patchId;
  final bool required;
  final Map<String, String> metadata;

  const DVUpdateInfo({
    required this.available,
    this.version,
    this.patchId,
    this.required = false,
    this.metadata = const <String, String>{},
  });

  factory DVUpdateInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawMetadata = map['metadata'];
    return DVUpdateInfo(
      available: map['available'] == true,
      version: map['version']?.toString(),
      patchId: map['patchId']?.toString(),
      required: map['required'] == true,
      metadata: rawMetadata is Map
          ? rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }
}

class DVUpdates {
  const DVUpdates();

  Future<DVUpdateInfo> check({
    DVUpdateChannel channel = DVUpdateChannel.production,
  }) async {
    final result = await DVNativeBridge.require<Map<dynamic, dynamic>>(
      'updates.check',
      {'channel': channel.name},
    );
    return DVUpdateInfo.fromMap(result);
  }

  Future<void> apply({
    DVUpdateChannel channel = DVUpdateChannel.production,
  }) async {
    final handled = await DVNativeBridge.require<bool>(
      'updates.apply',
      {'channel': channel.name},
    );
    if (!handled) {
      throw StateError('Native update binding rejected the update request.');
    }
  }

  Future<void> rollback({
    DVUpdateChannel channel = DVUpdateChannel.production,
  }) async {
    final handled = await DVNativeBridge.require<bool>(
      'updates.rollback',
      {'channel': channel.name},
    );
    if (!handled) {
      throw StateError('Native update binding rejected the rollback request.');
    }
  }
}

class DVBluetooth {
  const DVBluetooth();
  Future<bool> isEnabled() async =>
      DVNativeBridge.require<bool>('bluetooth.isEnabled');

  Stream<List<String>> scanDevices() async* {
    final devices =
        await DVNativeBridge.require<List<dynamic>>('bluetooth.scanDevices');
    yield devices.cast<String>();
  }
}

class DVNfc {
  const DVNfc();
  Future<bool> isAvailable() async =>
      DVNativeBridge.require<bool>('nfc.isAvailable');
  Future<String> readTag() async =>
      DVNativeBridge.require<String>('nfc.readTag');
}

class DVHardwareCapability {
  final String id;
  final String label;
  final bool available;
  final Map<String, String> metadata;

  const DVHardwareCapability({
    required this.id,
    required this.label,
    required this.available,
    this.metadata = const <String, String>{},
  });

  factory DVHardwareCapability.fromMap(Map<dynamic, dynamic> map) {
    final rawMetadata = map['metadata'];
    return DVHardwareCapability(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      available: map['available'] == true,
      metadata: rawMetadata is Map
          ? rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  Map<String, Object> toMap() => <String, Object>{
        'id': id,
        'label': label,
        'available': available,
        'metadata': metadata,
      };
}

class DVHardwareCapabilityManifest {
  final String deviceId;
  final List<DVHardwareCapability> capabilities;

  const DVHardwareCapabilityManifest({
    required this.deviceId,
    required this.capabilities,
  });

  factory DVHardwareCapabilityManifest.fromMap(Map<dynamic, dynamic> map) {
    final rawCapabilities = map['capabilities'];
    return DVHardwareCapabilityManifest(
      deviceId: map['deviceId']?.toString() ?? '',
      capabilities: rawCapabilities is List
          ? rawCapabilities
              .whereType<Map<dynamic, dynamic>>()
              .map(DVHardwareCapability.fromMap)
              .toList(growable: false)
          : const <DVHardwareCapability>[],
    );
  }
}

class DVDeviceHealth {
  final bool healthy;
  final DateTime checkedAt;
  final Map<String, String> diagnostics;

  const DVDeviceHealth({
    required this.healthy,
    required this.checkedAt,
    this.diagnostics = const <String, String>{},
  });

  factory DVDeviceHealth.fromMap(Map<dynamic, dynamic> map) {
    final rawDiagnostics = map['diagnostics'];
    return DVDeviceHealth(
      healthy: map['healthy'] == true,
      checkedAt: DateTime.tryParse(map['checkedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      diagnostics: rawDiagnostics is Map
          ? rawDiagnostics.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }
}

class DVFleetProvisioningRequest {
  final String deviceId;
  final String fleetId;
  final Map<String, String> labels;

  const DVFleetProvisioningRequest({
    required this.deviceId,
    required this.fleetId,
    this.labels = const <String, String>{},
  });

  Map<String, Object> toMap() => <String, Object>{
        'deviceId': deviceId,
        'fleetId': fleetId,
        'labels': labels,
      };
}

class DVDeviceProvisioningResult {
  final String deviceId;
  final String fleetId;
  final bool provisioned;

  const DVDeviceProvisioningResult({
    required this.deviceId,
    required this.fleetId,
    required this.provisioned,
  });

  factory DVDeviceProvisioningResult.fromMap(Map<dynamic, dynamic> map) {
    return DVDeviceProvisioningResult(
      deviceId: map['deviceId']?.toString() ?? '',
      fleetId: map['fleetId']?.toString() ?? '',
      provisioned: map['provisioned'] == true,
    );
  }
}

class DVDeviceDiagnosticsBundle {
  final String deviceId;
  final Map<String, String> logs;
  final Map<String, String> metrics;

  const DVDeviceDiagnosticsBundle({
    required this.deviceId,
    this.logs = const <String, String>{},
    this.metrics = const <String, String>{},
  });

  factory DVDeviceDiagnosticsBundle.fromMap(Map<dynamic, dynamic> map) {
    Map<String, String> stringMap(Object? value) {
      if (value is! Map) return const <String, String>{};
      return value.map((key, item) => MapEntry('$key', '$item'));
    }

    return DVDeviceDiagnosticsBundle(
      deviceId: map['deviceId']?.toString() ?? '',
      logs: stringMap(map['logs']),
      metrics: stringMap(map['metrics']),
    );
  }
}

class DVDeviceControls {
  const DVDeviceControls();

  Future<DVHardwareCapabilityManifest> capabilityManifest() async {
    final result = await DVNativeBridge.require<Map<dynamic, dynamic>>(
      'device.capabilityManifest',
    );
    return DVHardwareCapabilityManifest.fromMap(result);
  }

  Future<DVDeviceHealth> health() async {
    final result =
        await DVNativeBridge.require<Map<dynamic, dynamic>>('device.health');
    return DVDeviceHealth.fromMap(result);
  }

  Future<void> armWatchdog({
    required Duration timeout,
    String reason = 'runtime',
  }) async {
    final handled = await DVNativeBridge.require<bool>(
      'device.watchdog.arm',
      <String, Object>{
        'timeoutMs': timeout.inMilliseconds,
        'reason': reason,
      },
    );
    if (!handled) throw StateError('Native watchdog binding rejected arm.');
  }

  Future<void> heartbeat() async {
    final handled = await DVNativeBridge.require<bool>(
      'device.watchdog.heartbeat',
    );
    if (!handled) {
      throw StateError('Native watchdog binding rejected heartbeat.');
    }
  }

  Future<DVDeviceProvisioningResult> provision(
    DVFleetProvisioningRequest request,
  ) async {
    final result = await DVNativeBridge.require<Map<dynamic, dynamic>>(
      'device.fleet.provision',
      request.toMap(),
    );
    return DVDeviceProvisioningResult.fromMap(result);
  }

  Future<DVDeviceDiagnosticsBundle> collectDiagnostics() async {
    final result = await DVNativeBridge.require<Map<dynamic, dynamic>>(
      'device.diagnostics.collect',
    );
    return DVDeviceDiagnosticsBundle.fromMap(result);
  }
}

class DVClipboard {
  const DVClipboard();
  static String? _text;

  Future<void> copy(String text) async {
    final handled =
        await DVNativeBridge.invoke<bool>('clipboard.copy', {'text': text});
    if (handled != true) _text = text;
  }

  Future<String?> paste() async =>
      await DVNativeBridge.invoke<String>('clipboard.paste') ?? _text;
}

class DVShare {
  const DVShare();
  static String? _lastSharedText;

  Future<void> shareText(String text) async {
    final handled =
        await DVNativeBridge.require<bool>('share.text', {'text': text});
    if (!handled) {
      throw StateError('Native share binding rejected the request.');
    }
    _lastSharedText = text;
  }

  String? get lastSharedText => _lastSharedText;
}

class DVSensors {
  const DVSensors();
  Stream<Map<String, double>> get accelerometer async* {
    final value = await DVNativeBridge.require<Map<dynamic, dynamic>>(
        'sensors.accelerometer');
    yield _sensorMap(value);
  }

  Stream<Map<String, double>> get gyroscope async* {
    final value = await DVNativeBridge.require<Map<dynamic, dynamic>>(
        'sensors.gyroscope');
    yield _sensorMap(value);
  }

  Map<String, double> _sensorMap(Map<dynamic, dynamic>? value) => {
        'x': (value?['x'] as num?)?.toDouble() ?? 0,
        'y': (value?['y'] as num?)?.toDouble() ?? 0,
        'z': (value?['z'] as num?)?.toDouble() ?? 0,
      };
}

class DVBiometrics {
  const DVBiometrics();
  Future<bool> canAuthenticate() async =>
      DVNativeBridge.require<bool>('biometrics.canAuthenticate');
  Future<bool> authenticate() async =>
      DVNativeBridge.require<bool>('biometrics.authenticate');
}

class DVDeepLinks {
  const DVDeepLinks();
  static final StreamController<String> _links =
      StreamController<String>.broadcast();

  Future<String?> getInitialLink() =>
      DVNativeBridge.require<String?>('deepLinks.initial');
  Stream<String> getLinkStream() => _links.stream;
  void dispatch(String link) => _links.add(link);
}

class DVHaptics {
  const DVHaptics();
  Future<void> vibrate() async {
    await DVNativeBridge.require<bool>('haptics.vibrate');
  }

  Future<void> lightVibrate() async {
    await DVNativeBridge.require<bool>('haptics.lightVibrate');
  }

  Future<void> impact() async {
    await DVNativeBridge.require<bool>('haptics.impact');
  }
}

class DVContacts {
  const DVContacts();
  Future<List<Map<String, String>>> getContacts() async {
    final contacts =
        await DVNativeBridge.require<List<dynamic>>('contacts.getContacts');
    return contacts
        .whereType<Map<dynamic, dynamic>>()
        .map((contact) => contact.map(
              (key, value) => MapEntry('$key', '$value'),
            ))
        .toList();
  }
}

class DVPermissions {
  const DVPermissions();
  static final Map<String, bool> _grants = {};

  Future<bool> request(String permission) async {
    final result = await DVNativeBridge.invoke<bool>(
      'permissions.request',
      {'permission': permission},
    );
    if (result == null) {
      throw StateError(
        'Native binding "permissions.request" is not registered. Generate and register an FFI/ffigen or JNI/jnigen binding before calling this API.',
      );
    }
    _grants[permission] = result;
    return result;
  }

  Future<bool> isGranted(String permission) async {
    final result = await DVNativeBridge.invoke<bool>(
      'permissions.isGranted',
      {'permission': permission},
    );
    if (result != null) return result;
    final cached = _grants[permission];
    if (cached != null) return cached;
    throw StateError(
      'Native binding "permissions.isGranted" is not registered. Generate and register an FFI/ffigen or JNI/jnigen binding before calling this API.',
    );
  }
}

class DVScreen {
  final DVPlatform _platform;
  const DVScreen(this._platform);

  Size get size => Size(_platform.screenWidth, _platform.screenHeight);
  Map<String, double> get safeAreaBounds => _platform.safeAreas;
  String get breakPoints => _platform.breakpoint;
  String get shape => _platform.screenShape;
}

class DVWindow {
  final DVPlatform _platform;
  const DVWindow(this._platform);

  Rect get bounds =>
      Offset.zero & Size(_platform.screenWidth, _platform.screenHeight);

  Future<void> setTitle(String title) async {
    await DVNativeBridge.require<bool>('window.setTitle', {'title': title});
  }

  Future<void> maximize() async {
    await DVNativeBridge.require<bool>('window.maximize');
  }

  Future<void> minimize() async {
    await DVNativeBridge.require<bool>('window.minimize');
  }

  Future<void> restore() async {
    await DVNativeBridge.require<bool>('window.restore');
  }

  Future<void> persistState(String key) async {
    await DVNativeBridge.require<bool>('window.persistState', {'key': key});
  }

  Future<void> restoreState(String key) async {
    await DVNativeBridge.require<bool>('window.restoreState', {'key': key});
  }
}

class DVTrayMenuItem {
  final String id;
  final String label;
  final bool enabled;

  const DVTrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = true,
  });

  Map<String, Object> toMap() => <String, Object>{
        'id': id,
        'label': label,
        'enabled': enabled,
      };
}

class DVTray {
  const DVTray();

  Future<void> show({
    required String icon,
    String? tooltip,
    List<DVTrayMenuItem> menu = const <DVTrayMenuItem>[],
  }) async {
    final handled = await DVNativeBridge.require<bool>('tray.show', {
      'icon': icon,
      if (tooltip != null) 'tooltip': tooltip,
      'menu': menu.map((item) => item.toMap()).toList(growable: false),
    });
    if (!handled) throw StateError('Native tray binding rejected show.');
  }

  Future<void> hide() async {
    final handled = await DVNativeBridge.require<bool>('tray.hide');
    if (!handled) throw StateError('Native tray binding rejected hide.');
  }
}

class DVMenuItem {
  final String id;
  final String label;
  final String? shortcut;
  final List<DVMenuItem> children;
  final bool enabled;

  const DVMenuItem({
    required this.id,
    required this.label,
    this.shortcut,
    this.children = const <DVMenuItem>[],
    this.enabled = true,
  });

  Map<String, Object> toMap() => <String, Object>{
        'id': id,
        'label': label,
        if (shortcut != null) 'shortcut': shortcut!,
        'enabled': enabled,
        'children':
            children.map((item) => item.toMap()).toList(growable: false),
      };
}

class DVApplicationMenu {
  final List<DVMenuItem> items;

  const DVApplicationMenu(this.items);

  Map<String, Object> toMap() => <String, Object>{
        'items': items.map((item) => item.toMap()).toList(growable: false),
      };
}

class DVMenus {
  const DVMenus();

  Future<void> setApplicationMenu(DVApplicationMenu menu) async {
    final handled = await DVNativeBridge.require<bool>(
      'menus.setApplicationMenu',
      menu.toMap(),
    );
    if (!handled) {
      throw StateError('Native menus binding rejected setApplicationMenu.');
    }
  }
}

class DVGlobalShortcut {
  final String id;
  final String accelerator;

  const DVGlobalShortcut({
    required this.id,
    required this.accelerator,
  });

  Map<String, Object> toMap() => <String, Object>{
        'id': id,
        'accelerator': accelerator,
      };
}

class DVShortcuts {
  const DVShortcuts();

  Future<void> register(DVGlobalShortcut shortcut) async {
    final handled = await DVNativeBridge.require<bool>(
      'shortcuts.register',
      shortcut.toMap(),
    );
    if (!handled) {
      throw StateError('Native shortcuts binding rejected register.');
    }
  }

  Future<void> unregister(String id) async {
    final handled = await DVNativeBridge.require<bool>(
      'shortcuts.unregister',
      {'id': id},
    );
    if (!handled) {
      throw StateError('Native shortcuts binding rejected unregister.');
    }
  }
}

class DVFullscreenOptions {
  final bool hideSystemUi;
  final bool lockOrientation;

  const DVFullscreenOptions({
    this.hideSystemUi = true,
    this.lockOrientation = false,
  });

  Map<String, Object> toMap() => <String, Object>{
        'hideSystemUi': hideSystemUi,
        'lockOrientation': lockOrientation,
      };
}

class DVKioskOptions {
  final bool fullscreen;
  final bool disableBackGesture;
  final bool keepScreenAwake;
  final List<String> allowedExitKeys;

  const DVKioskOptions({
    this.fullscreen = true,
    this.disableBackGesture = true,
    this.keepScreenAwake = true,
    this.allowedExitKeys = const <String>[],
  });

  Map<String, Object> toMap() => <String, Object>{
        'fullscreen': fullscreen,
        'disableBackGesture': disableBackGesture,
        'keepScreenAwake': keepScreenAwake,
        'allowedExitKeys': allowedExitKeys,
      };
}

class DVDisplayState {
  final bool isFullscreen;
  final bool isKiosk;

  const DVDisplayState({
    required this.isFullscreen,
    required this.isKiosk,
  });
}

class DVDisplayControls {
  const DVDisplayControls();

  static bool _isFullscreen = false;
  static bool _isKiosk = false;

  bool get isFullscreen => _isFullscreen;
  bool get isKiosk => _isKiosk;
  DVDisplayState get currentState => DVDisplayState(
        isFullscreen: _isFullscreen,
        isKiosk: _isKiosk,
      );

  Future<void> enterFullscreen([
    DVFullscreenOptions options = const DVFullscreenOptions(),
  ]) async {
    await _requireDisplayBinding('display.enterFullscreen', options.toMap());
    _isFullscreen = true;
  }

  Future<void> exitFullscreen() async {
    await _requireDisplayBinding('display.exitFullscreen');
    _isFullscreen = false;
  }

  Future<void> enableKiosk([
    DVKioskOptions options = const DVKioskOptions(),
  ]) async {
    await _requireDisplayBinding('display.enableKiosk', options.toMap());
    _isKiosk = true;
    if (options.fullscreen) _isFullscreen = true;
  }

  Future<void> disableKiosk() async {
    await _requireDisplayBinding('display.disableKiosk');
    _isKiosk = false;
  }

  Future<void> _requireDisplayBinding(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    final handled = await DVNativeBridge.require<bool>(method, arguments);
    if (!handled) {
      throw StateError(
          'Native display binding "$method" rejected the request.');
    }
  }
}

class DVBrowserExtension {
  const DVBrowserExtension();

  bool get isAvailable => isChromium || isFirefox;
  bool get isChromium => browser_extension_platform.isChromiumExtension();
  bool get isFirefox => browser_extension_platform.isFirefoxExtension();

  Map<String, Object?> getManifest() {
    return browser_extension_platform.getManifest();
  }

  Future<Object?> sendMessage(Object? message) {
    return browser_extension_platform.sendMessage(message);
  }

  Future<void> tabsCreate(String url, {bool active = true}) {
    return browser_extension_platform.tabsCreate(url, active: active);
  }
}

class DVPlatform {
  const DVPlatform();

  static const String _platformOverride =
      String.fromEnvironment('DARTVEL_PLATFORM');
  static const String _deviceTypeOverride =
      String.fromEnvironment('DARTVEL_DEVICE_TYPE');

  String get currentPlatform {
    if (_platformOverride.isNotEmpty) return _platformOverride.toLowerCase();
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  bool get isAndroid =>
      currentPlatform == 'android' || currentPlatform == 'fireos';
  bool get isIOS => currentPlatform == 'ios';
  bool get isWindows => currentPlatform == 'windows';
  bool get isLinux => currentPlatform == 'linux';
  bool get isMacOS => currentPlatform == 'macos';
  bool get isFuchsia => currentPlatform == 'fuchsia';
  bool get isWeb => currentPlatform == 'web';
  bool get isChromiumExtension =>
      browser_extension_platform.isChromiumExtension();
  bool get isFirefoxExtension =>
      browser_extension_platform.isFirefoxExtension();

  bool get isTizen =>
      currentPlatform == 'tizen' || currentPlatform == 'tizenos';
  bool get isWebOS => currentPlatform == 'webos';
  bool get isAmazon =>
      currentPlatform == 'fireos' || currentPlatform == 'amazon';
  bool get isTV =>
      _deviceTypeOverride == 'tv' ||
      isTizen ||
      isWebOS ||
      isAmazon ||
      currentPlatform == 'androidtv' ||
      currentPlatform == 'appletv';
  bool get isWatch =>
      _deviceTypeOverride == 'watch' || currentPlatform.contains('watch');
  bool get isFoldable => _deviceTypeOverride == 'foldable';

  ui.FlutterView? get _view {
    final views = ui.PlatformDispatcher.instance.views;
    return views.isEmpty ? null : views.first;
  }

  double get screenWidth {
    final view = _view;
    if (view == null) return 0;
    return view.physicalSize.width / view.devicePixelRatio;
  }

  double get screenHeight {
    final view = _view;
    if (view == null) return 0;
    return view.physicalSize.height / view.devicePixelRatio;
  }

  Map<String, double> get safeAreas {
    final view = _view;
    if (view == null) {
      return {'top': 0, 'bottom': 0, 'left': 0, 'right': 0};
    }
    final ratio = view.devicePixelRatio;
    return {
      'top': view.padding.top / ratio,
      'bottom': view.padding.bottom / ratio,
      'left': view.padding.left / ratio,
      'right': view.padding.right / ratio,
    };
  }

  String get breakpoint {
    final width = screenWidth;
    if (width >= 1200) return 'desktop';
    if (width >= 840) return 'tablet';
    return 'mobile';
  }

  Orientation get orientation => screenWidth >= screenHeight
      ? Orientation.landscape
      : Orientation.portrait;

  String get deviceType {
    if (_deviceTypeOverride.isNotEmpty) return _deviceTypeOverride;
    if (isTV) return 'tv';
    if (isWatch) return 'watch';
    if (isFoldable) return 'foldable';
    if (isWeb) return 'web';
    if (breakpoint == 'desktop') return 'desktop';
    if (breakpoint == 'tablet') return 'tablet';
    return 'phone';
  }

  String get screenShape => isWatch ? 'round' : 'rectangle';
  String get type => deviceType;
  Orientation get deviceOrientation => orientation;
  DVScreen get screen => DVScreen(this);
  DVWindow get Window => DVWindow(this);
  DVTray get Tray => const DVTray();
  DVMenus get Menus => const DVMenus();
  DVShortcuts get Shortcuts => const DVShortcuts();

  DVCamera get camera => const DVCamera();
  DVMedia get media => const DVMedia();
  DVFiles get files => const DVFiles();
  DVLocation get location => const DVLocation();
  DVNotifications get notifications => const DVNotifications();
  DVBluetooth get bluetooth => const DVBluetooth();
  DVNfc get nfc => const DVNfc();
  DVDeviceControls get device => const DVDeviceControls();
  DVClipboard get clipboard => const DVClipboard();
  DVShare get share => const DVShare();
  DVSensors get sensors => const DVSensors();
  DVBiometrics get biometrics => const DVBiometrics();
  DVDeepLinks get deepLinks => const DVDeepLinks();
  DVHaptics get haptics => const DVHaptics();
  DVContacts get contacts => const DVContacts();
  DVPermissions get permissions => const DVPermissions();
  DVBrowserExtension get browserExtension => const DVBrowserExtension();
  DVDisplayControls get display => const DVDisplayControls();
}

class DVAuth {
  const DVAuth();
  static DVAuthUser? _currentUser;

  Object? get currentUser => _currentUser;
  DVAuthAuthorization get authorization => const DVAuthAuthorization();

  void registerPolicy<TUser, TResource>(
    String action,
    DVPolicyCheck<TUser, TResource> check,
  ) {
    authorization.register<TUser, TResource>(action, check);
  }

  Future<bool> can<TUser, TResource>(
    TUser user,
    String action,
    TResource resource,
  ) {
    return authorization.can<TUser, TResource>(user, action, resource);
  }

  Future<void> authorize<TUser, TResource>(
    TUser user,
    String action,
    TResource resource,
  ) {
    return authorization.authorize<TUser, TResource>(user, action, resource);
  }

  Future<void> signIn() async {
    _currentUser = DVAuthUser(
      id: _newId('anon'),
      provider: 'anonymous',
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Email and password are required.');
    }
    _currentUser = DVAuthUser(
      id: _newId('email'),
      email: email.trim(),
      provider: 'email',
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithProvider(String provider) async {
    if (provider.trim().isEmpty) {
      throw ArgumentError('Provider is required.');
    }
    _currentUser = DVAuthUser(
      id: _newId(provider),
      provider: provider.trim(),
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithRawOAuth(Map<String, Object?> oauth) async {
    _currentUser = DVAuthUser(
      id: (oauth['id'] ?? oauth['sub'] ?? _newId('oauth')).toString(),
      email: oauth['email']?.toString(),
      provider: oauth['provider']?.toString() ?? 'oauth',
      metadata: Map<String, Object?>.from(oauth),
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithPasskey() async {
    _currentUser = DVAuthUser(
      id: _newId('passkey'),
      provider: 'passkey',
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithBiometrics() async {
    final authenticated = await DV.Platform.biometrics.authenticate();
    if (!authenticated) {
      throw StateError('Biometric authentication was not completed.');
    }
    _currentUser = DVAuthUser(
      id: _newId('biometric'),
      provider: 'biometric',
      createdAt: DateTime.now(),
    );
  }

  Future<void> signInWithFingerprint() => signInWithBiometrics();

  Future<void> signInWithFaceRecognition() => signInWithBiometrics();

  Future<void> signInWithWeb3() async {
    _currentUser = DVAuthUser(
      id: _newId('web3'),
      provider: 'web3',
      createdAt: DateTime.now(),
    );
  }

  Future<void> signOut() async {
    _currentUser = null;
  }

  Future<void> signUp({
    String? email,
    String? password,
    Map<String, Object?> metadata = const {},
  }) async {
    if ((email == null || email.trim().isEmpty) && metadata.isEmpty) {
      throw ArgumentError('Email or metadata is required to create a user.');
    }
    _currentUser = DVAuthUser(
      id: _newId('user'),
      email: email?.trim(),
      provider: email == null ? 'custom' : 'email',
      metadata: metadata,
      createdAt: DateTime.now(),
    );
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';

  Widget SignInWithEmailAndPasswordPage() => _EmailPasswordAuthPage(auth: this);
  Widget SignInWithProviderPage() =>
      _ProviderAuthPage(auth: this, provider: 'provider');
  Widget SignInWithRawOAuthPage() =>
      _ProviderAuthPage(auth: this, provider: 'oauth');
  Widget SignInWithPasskeyPage() =>
      _ProviderAuthPage(auth: this, provider: 'passkey');
  Widget SignInWithWeb3Page() =>
      _ProviderAuthPage(auth: this, provider: 'web3');
}

class DVAuthUser {
  final String id;
  final String? email;
  final String provider;
  final Map<String, Object?> metadata;
  final DateTime createdAt;

  const DVAuthUser({
    required this.id,
    this.email,
    required this.provider,
    this.metadata = const {},
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'provider': provider,
        'metadata': metadata,
        'createdAt': createdAt.toIso8601String(),
      };
}

extension DVFlutterTestHarness on DVTestHarness {
  DVAuthUser fakeAuthUser({
    String id = 'test-user',
    String? email = 'test@example.com',
    String provider = 'fake',
    Map<String, Object?> metadata = const <String, Object?>{},
    DateTime? createdAt,
  }) {
    return DVAuthUser(
      id: id,
      email: email,
      provider: provider,
      metadata: metadata,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<T> asUser<T>(
    DVAuthUser user,
    FutureOr<T> Function() callback,
  ) async {
    final previous = DVAuth._currentUser;
    DVAuth._currentUser = user;
    try {
      return await Future<T>.sync(callback);
    } finally {
      DVAuth._currentUser = previous;
    }
  }

  void resetAuth() {
    DVAuth._currentUser = null;
  }

  Map<String, List<int>> fakeStorage() {
    DVStorage._memory.clear();
    return DVStorage._memory;
  }

  MemoryDVDatabaseAdapter fakeDatabase() {
    final adapter = MemoryDVDatabaseAdapter();
    DVDatabase.configure(adapter);
    return adapter;
  }

  LocalDVAIAdapter fakeAI() {
    const adapter = LocalDVAIAdapter();
    DVAI.configure(adapter);
    const DVAIToolRegistry().clear();
    return adapter;
  }

  void fakeNativeBinding(
    String method,
    FutureOr<Object?> Function(Object?) handler,
  ) {
    DVNativeBridge.register(method, handler);
  }

  void resetNativeBindings() {
    DVNativeBridge._handlers.clear();
  }

  void resetStorage() {
    DVStorage._memory.clear();
  }

  void refreshDatabase() {
    fakeDatabase();
  }

  void resetAI() {
    DVAI.configure(const LocalDVAIAdapter());
    const DVAIToolRegistry().clear();
  }
}

class _EmailPasswordAuthPage extends StatefulWidget {
  final DVAuth auth;
  const _EmailPasswordAuthPage({required this.auth});

  @override
  State<_EmailPasswordAuthPage> createState() => _EmailPasswordAuthPageState();
}

class _EmailPasswordAuthPageState extends State<_EmailPasswordAuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            type: MaterialType.transparency,
            child: DVBox.list([
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const DVText('Sign in').modifier(
                const DVModifier()
                    .padding(12)
                    .rounded(8)
                    .backgroundColor(const Color(0xFF111827))
                    .color(Colors.white)
                    .onPressed(() {
                  unawaited(
                    widget.auth.signInWithEmailAndPassword(
                      email: _email.text,
                      password: _password.text,
                    ),
                  );
                }),
              ),
            ]),
          ),
        ),
      );
}

class _ProviderAuthPage extends StatelessWidget {
  final DVAuth auth;
  final String provider;

  const _ProviderAuthPage({required this.auth, required this.provider});

  @override
  Widget build(BuildContext context) => Center(
        child: DVText('Continue with $provider').modifier(
          const DVModifier()
              .padding(12)
              .rounded(8)
              .backgroundColor(const Color(0xFF111827))
              .color(Colors.white)
              .onPressed(() {
            unawaited(auth.signInWithProvider(provider));
          }),
        ),
      );
}

class DVTheme {
  const DVTheme();
  static ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  void setMode(ThemeMode mode) {
    _mode = mode;
  }
}

class DVBilling {
  const DVBilling();
  static DVBillingProvider _provider = DVLocalBillingProvider();

  void useProvider(DVBillingProvider provider) {
    _provider = provider;
  }

  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) {
    return _provider.checkout(plan: plan, customer: customer);
  }

  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) {
    return _provider.hasEntitlement(customer, entitlement);
  }

  void grantLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _provider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.grant(customer, entitlement);
  }

  void revokeLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _provider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.revoke(customer, entitlement);
  }
}

class DVAI {
  const DVAI();
  static DVAIAdapter _adapter = const LocalDVAIAdapter();
  static const DVAIToolRegistry _tools = DVAIToolRegistry();

  static void configure(DVAIAdapter adapter) {
    _adapter = adapter;
  }

  void registerTool(String name, DVAIToolHandler handler) {
    _tools.register(name, handler);
  }

  bool hasTool(String name) => _tools.contains(name);

  List<String> get toolNames => _tools.names;

  Future<DVJsonValue> callTool(
    String name, [
    DVJsonObject input = const <String, DVJsonValue>{},
  ]) {
    return _tools.call(name, input);
  }

  Future<String> chat(String prompt, {String provider = 'gemini'}) =>
      _adapter.chat(prompt, provider: provider);
  Future<List<double>> embed(String text) => _adapter.embed(text);
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) =>
      _adapter.structuredOutput(prompt, schema);
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) =>
      _adapter.transcribe(
        audioBytes,
        mimeType: mimeType,
        language: language,
      );
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) =>
      _adapter.runAgent(request);
}

abstract class DVAIAdapter {
  Future<String> chat(String prompt, {String provider = 'gemini'});
  Future<List<double>> embed(String text);
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  );
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  });
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request);
}

class LocalDVAIAdapter implements DVAIAdapter {
  const LocalDVAIAdapter();

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final normalized = prompt.trim();
    return normalized.isEmpty
        ? ''
        : '[$provider] ${normalized.split(RegExp(r'\s+')).take(120).join(' ')}';
  }

  @override
  Future<List<double>> embed(String text) async {
    final buckets = List<double>.filled(16, 0);
    for (var i = 0; i < text.length; i++) {
      buckets[i % buckets.length] += text.codeUnitAt(i) / 65535;
    }
    return buckets;
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async =>
      {
        'prompt': DVJsonString(prompt),
        'schema': DVJsonMap(schema),
        'summary': DVJsonString(await chat(prompt, provider: 'local')),
      };

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async {
    final checksum = audioBytes.fold<int>(0, (sum, byte) => sum + byte);
    return DVAITranscript(
      text: 'local transcript ${audioBytes.length} bytes checksum $checksum',
      language: language,
      metadata: <String, DVJsonValue>{
        'mimeType': DVJsonString(mimeType),
        'byteLength': DVJsonNumber(audioBytes.length),
        'checksum': DVJsonNumber(checksum),
      },
    );
  }

  @override
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) async {
    final usedTools = <String>[];
    final data = <String, DVJsonValue>{};
    for (final toolName in request.tools) {
      if (!const DVAIToolRegistry().contains(toolName)) continue;
      usedTools.add(toolName);
      data[toolName] = await const DVAIToolRegistry().call(
        toolName,
        request.context,
      );
    }
    final summary = await chat(request.goal, provider: 'local-agent');
    return DVAIAgentResult(
      output: summary,
      data: Map<String, DVJsonValue>.unmodifiable(data),
      usedTools: List<String>.unmodifiable(usedTools),
    );
  }
}

class DVDatabase {
  const DVDatabase();
  static DVDatabaseAdapter _adapter = MemoryDVDatabaseAdapter();

  static void configure(DVDatabaseAdapter adapter) {
    _adapter = adapter;
  }

  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<Object?>? params,
  ]) =>
      _adapter.query(sql, params);

  Future<int> execute(String sql, [List<Object?>? params]) =>
      _adapter.execute(sql, params);
}

abstract class DVDatabaseAdapter {
  Future<List<Map<String, dynamic>>> query(String sql, [List<Object?>? params]);
  Future<int> execute(String sql, [List<Object?>? params]);
}

class MemoryDVDatabaseAdapter implements DVDatabaseAdapter {
  final Map<String, List<Map<String, dynamic>>> _tables = {};

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lower = normalized.toLowerCase();
    if (lower == 'select 1') {
      return const [
        {'1': 1}
      ];
    }

    final match =
        RegExp(r'^select \* from ([a-zA-Z_][\w]*)$', caseSensitive: false)
            .firstMatch(normalized);
    if (match != null) {
      return List<Map<String, dynamic>>.from(
        _tables[match.group(1)!] ?? const <Map<String, dynamic>>[],
      );
    }
    throw ArgumentError(
        'MemoryDVDatabaseAdapter supports select 1 and select * from <table>.');
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    final insert = RegExp(
      r'^insert into ([a-zA-Z_][\w]*) \(([^)]+)\) values \(([^)]+)\)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (insert != null) {
      final table = insert.group(1)!;
      final columns = insert.group(2)!.split(',').map((c) => c.trim()).toList();
      final values =
          params ?? insert.group(3)!.split(',').map(_literal).toList();
      if (columns.length != values.length) {
        throw ArgumentError('Column count does not match value count.');
      }
      final row = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        row[columns[i]] = values[i];
      }
      (_tables[table] ??= []).add(row);
      return 1;
    }

    final delete =
        RegExp(r'^delete from ([a-zA-Z_][\w]*)$', caseSensitive: false)
            .firstMatch(normalized);
    if (delete != null) {
      final table = delete.group(1)!;
      final count = _tables[table]?.length ?? 0;
      _tables[table] = [];
      return count;
    }
    throw ArgumentError(
        'MemoryDVDatabaseAdapter supports insert and delete statements.');
  }

  static Object? _literal(String value) {
    final trimmed = value.trim();
    if (trimmed == '?') return null;
    if (trimmed.startsWith("'") && trimmed.endsWith("'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return num.tryParse(trimmed) ?? trimmed;
  }
}

class DVCache {
  const DVCache();
  static final Map<String, ({Object? value, DateTime? expiresAt})> _memory = {};
  static const DVCacheTags _tags = DVCacheTags();

  Future<T?> get<T>(String key) async {
    final entry = _memory[key];
    if (entry == null) return null;
    final expiresAt = entry.expiresAt;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _memory.remove(key);
      return null;
    }
    final value = entry.value;
    return value is T ? value : null;
  }

  Future<void> set(String key, Object? value, [Duration? ttl]) async {
    _memory[key] = (
      value: value,
      expiresAt: ttl == null ? null : DateTime.now().add(ttl),
    );
  }

  Future<void> delete(String key) async {
    _memory.remove(key);
  }

  void tag(String key, Iterable<String> tags) {
    _tags.tag(key, tags);
  }

  Set<String> keysForTag(String tag) {
    return _tags.keysForTag(tag);
  }

  Set<String> revalidateTag(String tag) {
    final keys = _tags.revalidateTag(tag);
    for (final key in keys) {
      _memory.remove(key);
    }
    return keys;
  }
}

class DVStorage {
  const DVStorage();
  static final Map<String, List<int>> _memory = {};

  Future<void> put(String key, List<int> bytes) async {
    if (browser_extension_platform.supportsFileStorage()) {
      await browser_extension_platform.fileStoragePut(key, bytes);
      return;
    }
    _memory[key] = List<int>.from(bytes);
  }

  Future<List<int>> get(String key) async {
    if (browser_extension_platform.supportsFileStorage()) {
      return browser_extension_platform.fileStorageGet(key);
    }
    final bytes = _memory[key];
    if (bytes == null) throw StateError('No storage object exists for "$key".');
    return List<int>.from(bytes);
  }

  Future<void> delete(String key) async {
    if (browser_extension_platform.supportsFileStorage()) {
      await browser_extension_platform.fileStorageDelete(key);
      return;
    }
    _memory.remove(key);
  }
}

class DVRustInt {
  final int value;
  const DVRustInt(this.value);

  DVRustInt operator +(DVRustInt other) => DVRustInt(value + other.value);
  DVRustInt operator -(DVRustInt other) => DVRustInt(value - other.value);
  DVRustInt operator *(DVRustInt other) => DVRustInt(value * other.value);

  @override
  String toString() => value.toString();
}

class DVRust {
  const DVRust();
  DVRustInt Int(int value) => DVRustInt(value);
}

class DVObservabilityAndLogging {
  const DVObservabilityAndLogging();

  Future<void> log(
    String message, {
    String level = 'info',
    Map<String, Object>? context,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final payload = <String, Object>{
      'message': message,
      'level': level,
      if (context != null) 'context': context,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };
    debugPrint('[dartvel] $message');
    await Analytics.logEvent('log', payload);
  }

  Future<void> event(String name, [Map<String, Object>? parameters]) {
    return Analytics.logEvent(name, parameters);
  }

  Future<void> screen(String name, {String? screenClass}) {
    return Analytics.logScreenView(name, screenClass: screenClass);
  }

  Future<void> metric(
    String name,
    num value, {
    Map<String, Object>? tags,
  }) {
    return Analytics.logEvent('metric', <String, Object>{
      'name': name,
      'value': value,
      if (tags != null) 'tags': tags,
    });
  }

  Future<T> trace<T>(
    String name,
    FutureOr<T> Function() callback, {
    Map<String, Object>? context,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await callback();
      stopwatch.stop();
      await Analytics.logEvent('trace', <String, Object>{
        'name': name,
        'durationMicroseconds': stopwatch.elapsedMicroseconds,
        'status': 'ok',
        if (context != null) 'context': context,
      });
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      await this.error(
        error,
        stackTrace: stackTrace,
        context: <String, Object>{
          'trace': name,
          'durationMicroseconds': stopwatch.elapsedMicroseconds,
          if (context != null) 'context': context,
        },
      );
      rethrow;
    }
  }

  Future<T> profile<T>(
    String name,
    FutureOr<T> Function() callback, {
    Map<String, Object>? context,
  }) {
    return trace<T>('profile:$name', callback, context: context);
  }

  Future<void> error(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object>? context,
  }) {
    return Analytics.logEvent('error', <String, Object>{
      'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      if (context != null) 'context': context,
    });
  }

  Future<void> diagnostic(
    String name,
    Map<String, Object> data,
  ) {
    return Analytics.logEvent('diagnostic', <String, Object>{
      'name': name,
      'data': data,
    });
  }
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
  static DVBilling get Billing => const DVBilling();
  static DVDatabase get DB => const DVDatabase();
  static DVDatabase get Database => const DVDatabase();
  static DVCache get Cache => const DVCache();
  static DVStorage get Storage => const DVStorage();
  static DVStorage get FileStorage => const DVStorage();
  static DVStorage get BlobStorage => const DVStorage();
  static DVQueues get Queues => const DVQueues();
  static DVQueues get Jobs => const DVQueues();
  static DVNotificationsService get Notifications =>
      const DVNotificationsService();
  static DVUpdates get Updates => const DVUpdates();
  static DVTestHarness get Test => const DVTestHarness();
  static DVCSRF get CSRF => const DVCSRF();
  static DVCSRF get Csrf => const DVCSRF();
  static DVI18n get I18n => const DVI18n();
  static DVAccessibility get Accessibility => const DVAccessibility();
  static DVObservabilityAndLogging get ObservabilityAndLogging =>
      const DVObservabilityAndLogging();
  static DVRust get Rust => const DVRust();
  static String get currentTenant => 'default';

  static Future<DVShellResult> $(
    String command, {
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
  }) {
    return const DVShell().run(
      command,
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  static Future<void> log(
    String message, {
    String level = 'info',
    Map<String, Object>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return ObservabilityAndLogging.log(
      message,
      level: level,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
  }
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

typedef DVSeo = SeoProps;

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

  DVPageScaffoldSpec get pageScaffold => const DVPageScaffoldSpec();

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

class DVPageScaffoldSpec {
  final String? title;
  final DVPageShellMode shell;
  final bool scaffold;
  final bool showAppBar;
  final bool safeArea;
  final bool centerTitle;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final int? backgroundColor;
  final int? appBarBackgroundColor;

  const DVPageScaffoldSpec({
    this.title,
    this.shell = DVPageShellMode.adaptive,
    this.scaffold = true,
    this.showAppBar = false,
    this.safeArea = true,
    this.centerTitle = false,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.appBarBackgroundColor,
  });
}

class DVPageShell extends StatelessWidget {
  final DVPageScaffoldSpec spec;
  final Widget child;

  const DVPageShell({
    super.key,
    required this.spec,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!spec.scaffold || spec.shell == DVPageShellMode.none) {
      return _body(child);
    }

    final mode = spec.shell == DVPageShellMode.adaptive
        ? _adaptiveShellMode(context)
        : spec.shell;
    if (mode == DVPageShellMode.cupertino) {
      return CupertinoPageScaffold(
        backgroundColor: _color(spec.backgroundColor),
        navigationBar: spec.showAppBar || spec.title != null
            ? CupertinoNavigationBar(
                middle: spec.title == null ? null : DVText(spec.title!),
                backgroundColor: _color(spec.appBarBackgroundColor),
              )
            : null,
        child: _body(child),
      );
    }

    return Scaffold(
      appBar: spec.showAppBar || spec.title != null
          ? AppBar(
              title: spec.title == null ? null : DVText(spec.title!),
              centerTitle: spec.centerTitle,
              backgroundColor: _color(spec.appBarBackgroundColor),
            )
          : null,
      body: _body(child),
      backgroundColor: _color(spec.backgroundColor),
      extendBody: spec.extendBody,
      resizeToAvoidBottomInset: spec.resizeToAvoidBottomInset,
    );
  }

  Widget _body(Widget body) {
    return spec.safeArea ? SafeArea(child: body) : body;
  }

  static DVPageShellMode _adaptiveShellMode(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
        ? DVPageShellMode.cupertino
        : DVPageShellMode.material;
  }

  static Color? _color(int? value) => value == null ? null : Color(value);
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
    return const DVBox(
      SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
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
    return DVBox.list([
      const Icon(Icons.error_outline, color: Colors.redAccent),
      const SizedBox(height: 8),
      DVText(text),
    ]);
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

class LocaleTag {
  static const enUS = LocaleTag('en-US');
  static const frFR = LocaleTag('fr-FR');

  final String value;

  const LocaleTag(this.value);

  Locale get locale => DvI18n.parseLocale(value);

  bool get isRightToLeft {
    final language = value.split(RegExp('[-_]')).first.toLowerCase();
    return const <String>{
      'ar',
      'fa',
      'he',
      'ps',
      'ur',
      'yi',
    }.contains(language);
  }

  @override
  String toString() => value;
}

class DVTranslationKey {
  final String value;

  const DVTranslationKey(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DVTranslationKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class DVTranslationCatalog {
  final LocaleTag locale;
  final Map<DVTranslationKey, String> messages;
  final Map<DVTranslationKey, DVPluralForms> plurals;

  const DVTranslationCatalog({
    required this.locale,
    this.messages = const <DVTranslationKey, String>{},
    this.plurals = const <DVTranslationKey, DVPluralForms>{},
  });
}

class DVPluralForms {
  final String zero;
  final String one;
  final String other;

  const DVPluralForms({
    required this.other,
    this.zero = '',
    this.one = '',
  });

  String select(num count) {
    if (count == 0 && zero.isNotEmpty) return zero;
    if (count == 1 && one.isNotEmpty) return one;
    return other;
  }
}

class DVI18n {
  static LocaleTag _currentLocale = LocaleTag.enUS;
  static final Map<String, DVTranslationCatalog> _catalogs =
      <String, DVTranslationCatalog>{};

  const DVI18n();

  LocaleTag get currentLocale => _currentLocale;

  TextDirection get textDirection =>
      _currentLocale.isRightToLeft ? TextDirection.rtl : TextDirection.ltr;

  void useLocale(LocaleTag locale) {
    _currentLocale = locale;
  }

  void load(DVTranslationCatalog catalog) {
    _catalogs[catalog.locale.value] = catalog;
  }

  void loadAll(Iterable<DVTranslationCatalog> catalogs) {
    for (final catalog in catalogs) {
      load(catalog);
    }
  }

  String t(
    DVTranslationKey key, {
    Map<String, String> args = const <String, String>{},
    LocaleTag? locale,
    bool strict = false,
  }) {
    final selected = locale ?? _currentLocale;
    final catalog = _catalogs[selected.value];
    final template = catalog?.messages[key];
    if (template == null) {
      if (strict) {
        throw StateError(
          'Missing Dartvel translation "${key.value}" for ${selected.value}.',
        );
      }
      return key.value;
    }
    return _interpolate(template, args);
  }

  String translate(
    DVTranslationKey key, {
    Map<String, String> args = const <String, String>{},
    LocaleTag? locale,
    bool strict = false,
  }) {
    return t(key, args: args, locale: locale, strict: strict);
  }

  String plural(
    DVTranslationKey key,
    num count, {
    Map<String, String> args = const <String, String>{},
    LocaleTag? locale,
    bool strict = false,
  }) {
    final selected = locale ?? _currentLocale;
    final catalog = _catalogs[selected.value];
    final forms = catalog?.plurals[key];
    if (forms == null) {
      if (strict) {
        throw StateError(
          'Missing Dartvel plural "${key.value}" for ${selected.value}.',
        );
      }
      return key.value;
    }
    final pluralArgs = <String, String>{
      ...args,
      'count': formatNumber(count, locale: selected),
    };
    return _interpolate(forms.select(count), pluralArgs);
  }

  String formatNumber(num value, {LocaleTag? locale}) {
    final selected = locale ?? _currentLocale;
    final raw = value is int ? value.toString() : value.toStringAsFixed(2);
    final parts = raw.split('.');
    final separator = selected.value.startsWith('fr') ? ' ' : ',';
    final whole = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final remaining = whole.length - i;
      buffer.write(whole[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(separator);
      }
    }
    if (parts.length > 1) {
      buffer.write(selected.value.startsWith('fr') ? ',' : '.');
      buffer.write(parts[1]);
    }
    return buffer.toString();
  }

  String formatCurrency(
    num value, {
    String code = 'USD',
    LocaleTag? locale,
  }) {
    final selected = locale ?? _currentLocale;
    final formatted = formatNumber(value, locale: selected);
    if (selected.value.startsWith('fr')) return '$formatted $code';
    return '$code $formatted';
  }

  String formatDate(DateTime value, {LocaleTag? locale}) {
    final selected = locale ?? _currentLocale;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    if (selected.value.startsWith('fr')) return '$day/$month/$year';
    return '$month/$day/$year';
  }

  void reset() {
    _currentLocale = LocaleTag.enUS;
    _catalogs.clear();
  }

  String _interpolate(String template, Map<String, String> args) {
    var result = template;
    for (final entry in args.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

class DVAccessibilityCheck {
  final String name;
  final bool passed;
  final String message;

  const DVAccessibilityCheck({
    required this.name,
    required this.passed,
    required this.message,
  });
}

class DVContrastCheck extends DVAccessibilityCheck {
  final double ratio;
  final double requiredRatio;

  const DVContrastCheck({
    required super.name,
    required super.passed,
    required super.message,
    required this.ratio,
    required this.requiredRatio,
  });
}

class DVTappableTargetCheck extends DVAccessibilityCheck {
  final Size size;
  final Size minimumSize;

  const DVTappableTargetCheck({
    required super.name,
    required super.passed,
    required super.message,
    required this.size,
    required this.minimumSize,
  });
}

class DVAccessibilityReport {
  final List<DVAccessibilityCheck> checks;

  const DVAccessibilityReport(this.checks);

  bool get passed => checks.every((check) => check.passed);

  List<DVAccessibilityCheck> get failures =>
      List<DVAccessibilityCheck>.unmodifiable(
          checks.where((check) => !check.passed));
}

class DVAccessibility {
  static bool _reducedMotion = false;

  const DVAccessibility();

  bool get reducedMotion => _reducedMotion;

  void useReducedMotion(bool value) {
    _reducedMotion = value;
  }

  DVContrastCheck contrast({
    required Color foreground,
    required Color background,
    double requiredRatio = 4.5,
    String name = 'contrast',
  }) {
    final ratio = _contrastRatio(foreground, background);
    final passed = ratio >= requiredRatio;
    return DVContrastCheck(
      name: name,
      passed: passed,
      message: passed
          ? 'Contrast ratio ${ratio.toStringAsFixed(2)} passes.'
          : 'Contrast ratio ${ratio.toStringAsFixed(2)} is below '
              '${requiredRatio.toStringAsFixed(2)}.',
      ratio: ratio,
      requiredRatio: requiredRatio,
    );
  }

  DVTappableTargetCheck tapTarget({
    required Size size,
    Size minimumSize = const Size(48, 48),
    String name = 'tapTarget',
  }) {
    final passed =
        size.width >= minimumSize.width && size.height >= minimumSize.height;
    return DVTappableTargetCheck(
      name: name,
      passed: passed,
      message: passed
          ? 'Tap target ${size.width}x${size.height} passes.'
          : 'Tap target ${size.width}x${size.height} is smaller than '
              '${minimumSize.width}x${minimumSize.height}.',
      size: size,
      minimumSize: minimumSize,
    );
  }

  DVAccessibilityReport report(Iterable<DVAccessibilityCheck> checks) {
    return DVAccessibilityReport(List<DVAccessibilityCheck>.unmodifiable(
      checks,
    ));
  }

  double _contrastRatio(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    final lighter = math.max(first, second);
    final darker = math.min(first, second);
    return (lighter + 0.05) / (darker + 0.05);
  }
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

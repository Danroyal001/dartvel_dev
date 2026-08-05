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
import 'src/display_platform.dart'
    if (dart.library.js_interop) 'src/display_platform_web.dart'
    as display_platform;
import 'src/seo_platform_memory.dart'
    if (dart.library.html) 'src/seo_platform_web.dart' as seo_platform;

export 'package:dartvel_core/dartvel.dart'
    show
        Analytics,
        AnalyticsEvent,
        AnalyticsProvider,
        AnthropicDVAIAdapter,
        DVAIAdapter,
        DVAIAgentRequest,
        DVAIAgentResult,
        DVAITranscript,
        DVAIToolEntry,
        DVAIToolHandler,
        AuthException,
        AuthFailure,
        DVAIToolDefinition,
        DVPasswordHasher,
        DVDatabaseAdapter,
        DVAIToolRegistry,
        DVAIHttpRequest,
        DVAIHttpResponse,
        DVAIHttpSend,
        DVAIProviderException,
        DVHttpAIAdapter,
        DVJsonCodec,
        GeminiDVAIAdapter,
        LocalDVAIAdapter,
        LocalAuthProvider,
        AuthProvider,
        AuthUser,
        AuthState,
        MemoryDVDatabaseAdapter,
        SqliteDVDatabaseAdapter,
        OllamaDVAIAdapter,
        OpenAIDVAIAdapter,
        OpenRouterDVAIAdapter,
        dvSendAIHttpRequest,
        BillingPlan,
        DVCronEntry,
        DVCronTarget,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVFileStorageAdapter,
        DVFileStorageException,
        DVMemoryFileStorageAdapter,
        S3FileStorageAdapter,
        DVFormControls,
        DVFormControlsFactory,
        DVAuthAuthorization,
        DVOAuth2Client,
        DVOAuth2Config,
        DVOAuth2Authorization,
        DVOAuth2Tokens,
        DVOAuth2Exception,
        // Lifecycle
        DVAppLifecycle,
        DVPageLifecycle,
        DVModuleLifecycle,
        DVRequestLifecycle,
        DVTransactionLifecycle,
        DVBuildLifecycle,
        DVLifecycleSignal,
        DVMutableLifecycleSignal,
        DVLifecycleRegistry,
        // Modules
        DVModule,
        DVModuleRegistry,
        DVUnknownModuleException,
        // Transactions
        DVContext,
        DVContextLifecycle,
        DVCompensationException,
        DVTransactionRunner,
        // Model pages and static generation
        DVModelPageDataMode,
        DVStaticPaths,
        DVImage,
        DVImageSource,
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
        DVCacheAdapter,
        DVCacheTags,
        DVDatabaseCacheAdapter,
        DVMemoryCacheAdapter,
        DVInMemorySearchProvider,
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
        DVDatabaseQueueAdapter,
        DVJobPayloadCodec,
        DVJobPayloadCodecs,
        DVJobEnvelope,
        DVJobHandler,
        DVJobPayload,
        DVJobState,
        DVMailAddress,
        DVMailMessage,
        DVMailPriority,
        DVMailProvider,
        DVMailProviderException,
        DVHttpMailProvider,
        DVHttpRequest,
        DVHttpResponse,
        DVHttpSend,
        DVAwsCredentials,
        DVAwsSigV4,
        MailgunMailProvider,
        SesMailProvider,
        SmtpMailProvider,
        DVSmtpClient,
        DVSmtpConnection,
        DVSmtpConnect,
        DVSmtpException,
        PostmarkMailProvider,
        ResendMailProvider,
        SendGridMailProvider,
        dvSendHttpRequest,
        DVNotificationMail,
        DVMemoryMailProvider,
        DVMemoryNotificationProvider,
        DVNotificationChannel,
        DVNotificationMessage,
        DVNotificationProvider,
        DVNotificationProviderKind,
        DVPushProviderException,
        DVAccessTokenSupplier,
        FirebasePushProvider,
        TwilioSmsProvider,
        DVNotificationsService,
        DVPolicyCheck,
        DVQueueAdapter,
        DVQueues,
        DVReportResult,
        DVScheduledReport,
        DVSearchProvider,
        DVSearchProviderException,
        DVHttpSearchProvider,
        DVSearchFacetFilter,
        DVSqliteSearchProvider,
        MeilisearchProvider,
        OpenSearchProvider,
        AlgoliaSearchProvider,
        DVSearchDocument,
        DVSearchFacetMatcher,
        DVSearchResultPage,
        DVUnconfiguredSearchProvider,
        DVSecretNotFoundException,
        DVSecrets,
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

export 'src/media/image_view.dart';

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
  final bool inputValue;
  final String? inputLabelValue;
  final String? inputHintValue;
  final bool inputObscureText;
  final ValueChanged<String>? inputChanged;

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
    this.inputValue = false,
    this.inputLabelValue,
    this.inputHintValue,
    this.inputObscureText = false,
    this.inputChanged,
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
        minimumTapTargetValue = null,
        inputValue = false,
        inputLabelValue = null,
        inputHintValue = null,
        inputObscureText = false,
        inputChanged = null;

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
    bool? inputValue,
    String? inputLabelValue,
    String? inputHintValue,
    bool? inputObscureText,
    ValueChanged<String>? inputChanged,
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
      inputValue: inputValue ?? this.inputValue,
      inputLabelValue: inputLabelValue ?? this.inputLabelValue,
      inputHintValue: inputHintValue ?? this.inputHintValue,
      inputObscureText: inputObscureText ?? this.inputObscureText,
      inputChanged: inputChanged ?? this.inputChanged,
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

  DVModifier input({
    String? label,
    String? hint,
    bool obscureText = false,
    ValueChanged<String>? onChanged,
  }) =>
      _copyWith(
        inputValue: true,
        inputLabelValue: label,
        inputHintValue: hint,
        inputObscureText: obscureText,
        inputChanged: onChanged,
      );

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

  /// Canonical wrap layout for a static collection of [children].
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

  /// Compatibility alias for [DVBox.wrapLine]; prefer `wrapLine` in new code.
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
    final modifier = _modifier;
    Widget result;
    if (modifier?.inputValue == true) {
      result = TextField(
        obscureText: modifier!.inputObscureText,
        decoration: InputDecoration(
          labelText: modifier.inputLabelValue,
          hintText: modifier.inputHintValue ?? text,
        ),
        onChanged: modifier.inputChanged,
      );
    } else {
      result = Text(
        text,
        style: TextStyle(
          color: modifier?.textColor,
          fontSize: modifier?.fontSizeValue,
          fontWeight: modifier?.fontWeightValue,
          letterSpacing: modifier?.letterSpacingValue,
        ),
      );
    }

    if (modifier != null &&
        modifier.onTapCallback != null &&
        modifier.inputValue == false) {
      result = GestureDetector(
        onTap: modifier.onTapCallback,
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

  T global<T>({String namespace = ''}) {
    final key = _DVGlobalKey(namespace, T);
    final provider = _globalProviders.putIfAbsent(
      key,
      () => StateProvider<Object?>((ref) => DV.global<T>(null, namespace)),
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

final _globalProviders = <_DVGlobalKey, StateProvider<Object?>>{};

class _DVGlobalKey {
  const _DVGlobalKey(this.namespace, this.type);

  final String namespace;
  final Type type;

  @override
  bool operator ==(Object other) =>
      other is _DVGlobalKey &&
      other.namespace == namespace &&
      other.type == type;

  @override
  int get hashCode => Object.hash(namespace, type);
}

extension DVModelSignalX<T> on T {
  DVSignal<T> signal(BuildContext context) {
    return context.signal<T>(this);
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

extension DVFormAliasX<T> on T {
  Widget Form() => DVForm<T>(this);
}

class _DVFormState<T> extends State<DVForm<T>> {
  late T formValue;
  late T _initialValue;
  final Map<String, String> _fieldValues = <String, String>{};

  @override
  void initState() {
    super.initState();
    formValue = widget.initialValue ?? _instantiateDefault();
    _initialValue = formValue;
  }

  T _instantiateDefault() {
    final model = createDVModel<T>();
    if (model == null) {
      throw StateError(
        'No generated model factory registered for $T. '
        'Run dartvel build after annotating the model with @DVModel().',
      );
    }
    return model;
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
    final jsonMap = serializeDVModel<T>(formValue);
    if (jsonMap != null) {
      jsonMap.forEach((key, value) {
        final initialText = _fieldValues[key] ?? value?.toString() ?? '';
        fields.add(
          DVText(initialText).modifier(
            const DVModifier().input(
              label: key.toUpperCase(),
              onChanged: (nextValue) {
                setState(() => _fieldValues[key] = nextValue);
              },
            ),
          ),
        );
      });
    } else {
      fields.add(DVText(
        'No generated form controls registered for $T.',
      ));
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
      _fieldValues.clear();
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
        await DVNativeBridge.require<List<Object?>>('camera.takePhoto');
    return bytes.cast<int>();
  }
}

class DVMedia {
  const DVMedia();

  Future<List<Map<String, Object?>>> pick({
    String type = 'image',
    bool multiple = false,
  }) async {
    final items = await DVNativeBridge.invoke<List<Object?>>(
      'media.pick',
      {'type': type, 'multiple': multiple},
    );
    if (items == null) {
      throw StateError(
        'Native binding "media.pick" is not registered. Generate and register an FFI/ffigen or JNI/jnigen binding before calling this API.',
      );
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }
}

class DVFiles {
  const DVFiles();

  Future<void> writeBytes(String path, List<int> bytes) async {
    final handled = await DVNativeBridge.require<bool>(
      'files.writeBytes',
      {'path': path, 'bytes': bytes},
    );
    if (!handled) {
      throw StateError('Native file binding rejected writeBytes.');
    }
  }

  Future<List<int>> readBytes(String path) async {
    final bytes = await DVNativeBridge.require<List<Object?>>(
      'files.readBytes',
      {'path': path},
    );
    return bytes.cast<int>();
  }

  Future<void> delete(String path) async {
    final handled = await DVNativeBridge.require<bool>(
      'files.delete',
      {'path': path},
    );
    if (!handled) {
      throw StateError('Native file binding rejected delete.');
    }
  }
}

class DVLocation {
  const DVLocation();

  Future<Map<String, double>> getCoordinates() async {
    final result =
        await DVNativeBridge.require<Map<Object?, Object?>>('location.current');
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

  factory DVUpdateInfo.fromMap(Map<Object?, Object?> map) {
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
    final result = await DVNativeBridge.require<Map<Object?, Object?>>(
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
        await DVNativeBridge.require<List<Object?>>('bluetooth.scanDevices');
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

  factory DVHardwareCapability.fromMap(Map<Object?, Object?> map) {
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

  factory DVHardwareCapabilityManifest.fromMap(Map<Object?, Object?> map) {
    final rawCapabilities = map['capabilities'];
    return DVHardwareCapabilityManifest(
      deviceId: map['deviceId']?.toString() ?? '',
      capabilities: rawCapabilities is List
          ? rawCapabilities
              .whereType<Map<Object?, Object?>>()
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

  factory DVDeviceHealth.fromMap(Map<Object?, Object?> map) {
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

  factory DVDeviceProvisioningResult.fromMap(Map<Object?, Object?> map) {
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

  factory DVDeviceDiagnosticsBundle.fromMap(Map<Object?, Object?> map) {
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
    final result = await DVNativeBridge.require<Map<Object?, Object?>>(
      'device.capabilityManifest',
    );
    return DVHardwareCapabilityManifest.fromMap(result);
  }

  Future<DVDeviceHealth> health() async {
    final result =
        await DVNativeBridge.require<Map<Object?, Object?>>('device.health');
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
    final result = await DVNativeBridge.require<Map<Object?, Object?>>(
      'device.fleet.provision',
      request.toMap(),
    );
    return DVDeviceProvisioningResult.fromMap(result);
  }

  Future<DVDeviceDiagnosticsBundle> collectDiagnostics() async {
    final result = await DVNativeBridge.require<Map<Object?, Object?>>(
      'device.diagnostics.collect',
    );
    return DVDeviceDiagnosticsBundle.fromMap(result);
  }
}

class DVClipboard {
  const DVClipboard();

  Future<void> copy(String text) async {
    final handled =
        await DVNativeBridge.require<bool>('clipboard.copy', {'text': text});
    if (!handled) {
      throw StateError('Native clipboard binding rejected copy.');
    }
  }

  Future<String?> paste() => DVNativeBridge.require<String?>('clipboard.paste');
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
    final value = await DVNativeBridge.require<Map<Object?, Object?>>(
        'sensors.accelerometer');
    yield _sensorMap(value);
  }

  Stream<Map<String, double>> get gyroscope async* {
    final value = await DVNativeBridge.require<Map<Object?, Object?>>(
        'sensors.gyroscope');
    yield _sensorMap(value);
  }

  Map<String, double> _sensorMap(Map<Object?, Object?>? value) => {
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
        await DVNativeBridge.require<List<Object?>>('contacts.getContacts');
    return contacts
        .whereType<Map<Object?, Object?>>()
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
    final browserHandled = await display_platform.enterFullscreen();
    if (!browserHandled) {
      await _requireDisplayBinding(
        'display.enterFullscreen',
        options.toMap(),
      );
    }
    _isFullscreen = true;
  }

  Future<void> exitFullscreen() async {
    final browserHandled = await display_platform.exitFullscreen();
    if (!browserHandled) {
      await _requireDisplayBinding('display.exitFullscreen');
    }
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
  bool get isSonyELinux => currentPlatform == 'sony-elinux';
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
  bool get isAndroidTV => currentPlatform == 'androidtv';
  bool get isAppleTV => currentPlatform == 'appletv';
  bool get isTV =>
      _deviceTypeOverride == 'tv' ||
      isTizen ||
      isWebOS ||
      isAmazon ||
      isAndroidTV ||
      isAppleTV;
  bool get isWatch =>
      _deviceTypeOverride == 'watch' || currentPlatform.contains('watch');

  List<ui.DisplayFeature> get _foldFeatures {
    final view = _view;
    if (view == null) return const <ui.DisplayFeature>[];
    return view.displayFeatures
        .where(
          (feature) =>
              feature.type == ui.DisplayFeatureType.fold ||
              feature.type == ui.DisplayFeatureType.hinge,
        )
        .toList(growable: false);
  }

  bool get isFoldable =>
      _deviceTypeOverride == 'foldable' || _foldFeatures.isNotEmpty;
  bool get isDualFold => isFoldable && _foldFeatures.length == 1;
  bool get isTriFold => isFoldable && _foldFeatures.length >= 2;

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
    if (isWeb) return 'web';
    if (breakpoint == 'desktop') return 'desktop';
    if (breakpoint == 'tablet') return 'tablet';
    if (isFoldable) return 'foldable';
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

  // The spec names these device namespaces in capitals, matching `Window`,
  // `Tray` and `Menus` above, and `DV` proxies each one at the top level. The
  // lowerCamel getters stay as-is so existing call sites keep working.
  DVCamera get Camera => camera;
  DVLocation get Location => location;
  DVBluetooth get Bluetooth => bluetooth;
  DVNfc get NFC => nfc;
  DVClipboard get Clipboard => clipboard;
  DVShare get Share => share;
  DVSensors get Sensors => sensors;
  DVBiometrics get Biometrics => biometrics;
  DVDeepLinks get DeepLinking => deepLinks;
  DVHaptics get Haptics => haptics;
  DVContacts get Contacts => contacts;

  /// Proxies to [DV.FileStorage], so media and files are one API rather than a
  /// platform-local duplicate of it.
  DVStorage get FileStorage => DV.FileStorage;

  /// Proxies to [DV.Notifications]. Device-local notifications remain on the
  /// lowerCamel [notifications] getter.
  DVNotificationsService get Notifications => DV.Notifications;
}

abstract class DVAuthProvider {
  Future<DVAuthUser> signInAnonymously();

  Future<DVAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<DVAuthUser> signInWithProvider(String provider);

  Future<DVAuthUser> signInWithRawOAuth(Map<String, Object?> oauth);

  Future<DVAuthUser> signInWithPasskey();

  Future<DVAuthUser> signInWithBiometrics();

  Future<DVAuthUser> signInWithWeb3();

  Future<void> signOut();

  Future<DVAuthUser> signUp({
    String? email,
    String? password,
    Map<String, Object?> metadata,
  });
}

/// Explicit local provider for development and tests.
///
/// Production applications must configure a provider backed by their auth
/// service before calling [DV.Auth].
class _DVLocalCredential {
  final DVAuthUser user;
  final String passwordHash;

  const _DVLocalCredential(this.user, this.passwordHash);
}

/// Development and test auth adapter.
///
/// E-mail/password credentials are stored salted and hashed and are really
/// verified. Everything lives in memory with no recovery, verification or
/// session expiry, so this must not be mistaken for production authentication.
class DVLocalAuthProvider implements DVAuthProvider {
  static const int minimumPasswordLength = 8;

  final DVPasswordHasher _hasher;
  final Map<String, _DVLocalCredential> _accounts =
      <String, _DVLocalCredential>{};
  bool _signedIn = false;

  DVLocalAuthProvider({DVPasswordHasher? hasher})
      : _hasher = hasher ?? DVPasswordHasher(iterations: 10000);

  /// Registered account e-mails, for test assertions and dev tooling.
  List<String> get accounts => List<String>.unmodifiable(_accounts.keys);

  /// Removes every registered account. Intended for test teardown.
  void reset() {
    _accounts.clear();
    _signedIn = false;
  }

  @override
  Future<DVAuthUser> signInAnonymously() async {
    return _setUser(provider: 'anonymous');
  }

  @override
  Future<DVAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || password.isEmpty) {
      throw ArgumentError('Email and password are required.');
    }
    final stored = _accounts[key];
    if (stored == null) {
      // Hash anyway so a missing account does not answer faster than a wrong
      // password, which would leak which e-mails are registered.
      _hasher.verify(password, _hasher.hash(password));
      throw const AuthException(
        AuthFailure.unknownAccount,
        'No account exists for that e-mail address. Call signUp first.',
      );
    }
    if (!_hasher.verify(password, stored.passwordHash)) {
      throw const AuthException(
        AuthFailure.invalidPassword,
        'That password is incorrect.',
      );
    }
    _signedIn = true;
    return stored.user;
  }

  @override
  Future<DVAuthUser> signInWithProvider(String provider) async {
    final normalizedProvider = provider.trim();
    if (normalizedProvider.isEmpty) {
      throw ArgumentError('Provider is required.');
    }
    return _setUser(provider: normalizedProvider);
  }

  @override
  Future<DVAuthUser> signInWithRawOAuth(Map<String, Object?> oauth) async {
    return _setUser(
      id: (oauth['id'] ?? oauth['sub'] ?? _newId('oauth')).toString(),
      email: oauth['email']?.toString(),
      provider: oauth['provider']?.toString() ?? 'oauth',
      metadata: Map<String, Object?>.from(oauth),
    );
  }

  @override
  Future<DVAuthUser> signInWithPasskey() async {
    return _setUser(provider: 'passkey');
  }

  @override
  Future<DVAuthUser> signInWithBiometrics() async {
    final authenticated = await DV.Platform.biometrics.authenticate();
    if (!authenticated) {
      throw StateError('Biometric authentication was not completed.');
    }
    return _setUser(provider: 'biometric');
  }

  @override
  Future<DVAuthUser> signInWithWeb3() async {
    return _setUser(provider: 'web3');
  }

  @override
  Future<void> signOut() async {
    if (!_signedIn) return;
    _signedIn = false;
  }

  @override
  Future<DVAuthUser> signUp({
    String? email,
    String? password,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final normalizedEmail = email?.trim().toLowerCase();
    if ((normalizedEmail == null || normalizedEmail.isEmpty) &&
        metadata.isEmpty) {
      throw ArgumentError('Email or metadata is required to create a user.');
    }

    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      if (_accounts.containsKey(normalizedEmail)) {
        throw const AuthException(
          AuthFailure.accountExists,
          'An account already exists for that e-mail address.',
        );
      }
      if (password != null && password.length < minimumPasswordLength) {
        throw const AuthException(
          AuthFailure.weakPassword,
          'Passwords must be at least $minimumPasswordLength characters.',
        );
      }
    }

    final user = _setUser(
      email: normalizedEmail,
      provider: normalizedEmail == null ? 'custom' : 'email',
      metadata: metadata,
    );

    // Only an account created with a password can sign in with one later.
    if (normalizedEmail != null &&
        normalizedEmail.isNotEmpty &&
        password != null) {
      _accounts[normalizedEmail] =
          _DVLocalCredential(user, _hasher.hash(password));
    }
    return user;
  }

  DVAuthUser _setUser({
    String? id,
    String? email,
    required String provider,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final user = DVAuthUser(
      id: id ?? _newId(provider),
      email: email,
      provider: provider,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    _signedIn = true;
    return user;
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
}

class DVAuth {
  const DVAuth();
  static DVAuthProvider? _provider;
  static DVAuthUser? _currentUser;

  DVAuthUser? get currentUser => _currentUser;
  DVAuthAuthorization get authorization => const DVAuthAuthorization();

  void configure(DVAuthProvider provider) {
    _provider = provider;
    _currentUser = null;
  }

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
    await _setCurrentUser(_configuredProvider.signInAnonymously());
  }

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await _setCurrentUser(_configuredProvider.signInWithEmailAndPassword(
      email: email,
      password: password,
    ));
  }

  Future<void> signInWithProvider(String provider) async {
    await _setCurrentUser(_configuredProvider.signInWithProvider(provider));
  }

  Future<void> signInWithRawOAuth(Map<String, Object?> oauth) async {
    await _setCurrentUser(_configuredProvider.signInWithRawOAuth(oauth));
  }

  Future<void> signInWithPasskey() async {
    await _setCurrentUser(_configuredProvider.signInWithPasskey());
  }

  Future<void> signInWithBiometrics() async {
    await _setCurrentUser(_configuredProvider.signInWithBiometrics());
  }

  Future<void> signInWithFingerprint() => signInWithBiometrics();

  Future<void> signInWithFaceRecognition() => signInWithBiometrics();

  Future<void> signInWithWeb3() async {
    await _setCurrentUser(_configuredProvider.signInWithWeb3());
  }

  Future<void> signOut() async {
    await _configuredProvider.signOut();
    _currentUser = null;
  }

  Future<void> signUp({
    String? email,
    String? password,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    await _setCurrentUser(_configuredProvider.signUp(
      email: email,
      password: password,
      metadata: metadata,
    ));
  }

  DVAuthProvider get _configuredProvider {
    final provider = _provider;
    if (provider == null) {
      throw StateError(
        'DV.Auth has no configured provider. Configure an auth adapter before signing in.',
      );
    }
    return provider;
  }

  Future<void> _setCurrentUser(Future<DVAuthUser> operation) async {
    _currentUser = await operation;
  }

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

  void resetAuthProvider() {
    DVAuth._currentUser = null;
    DVAuth._provider = null;
  }

  void resetBillingProvider() {
    DVBilling._provider = null;
  }

  DVMemoryFileStorageAdapter fakeStorage() {
    final adapter = DVMemoryFileStorageAdapter();
    DV.Storage.configure(adapter);
    return adapter;
  }

  MemoryDVDatabaseAdapter fakeDatabase() {
    final adapter = MemoryDVDatabaseAdapter();
    DV.Database.configure(adapter);
    return adapter;
  }

  LocalDVAIAdapter fakeAI() {
    const adapter = LocalDVAIAdapter();
    DV.AI.configure(adapter);
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
    DV.Storage.configure(DVMemoryFileStorageAdapter());
  }

  void refreshDatabase() {
    fakeDatabase();
  }

  void resetDatabaseProvider() {
    DVDatabase._adapter = null;
  }

  void resetAI() {
    DV.AI.configure(const LocalDVAIAdapter());
    const DVAIToolRegistry().clear();
  }

  void resetAIProvider() {
    DVAI._adapter = null;
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
  static DVBillingProvider? _provider;

  void useProvider(DVBillingProvider provider) {
    _provider = provider;
  }

  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) {
    return _configuredProvider.checkout(plan: plan, customer: customer);
  }

  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) {
    return _configuredProvider.hasEntitlement(customer, entitlement);
  }

  void grantLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _configuredProvider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.grant(customer, entitlement);
  }

  void revokeLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _configuredProvider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.revoke(customer, entitlement);
  }

  DVBillingProvider get _configuredProvider {
    final provider = _provider;
    if (provider == null) {
      throw StateError(
        'DV.Billing has no configured provider. Configure Stripe, Paddle, or a store billing adapter before use.',
      );
    }
    return provider;
  }
}

class DVAI {
  const DVAI();
  static DVAIAdapter? _adapter;
  static const DVAIToolRegistry _tools = DVAIToolRegistry();

  void configure(DVAIAdapter adapter) {
    _adapter = adapter;
  }

  void registerTool(
    String name,
    DVAIToolHandler handler, {
    String description = '',
    DVJsonObject parameters = const <String, DVJsonValue>{},
  }) {
    _tools.register(
      name,
      handler,
      description: description,
      parameters: parameters,
    );
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
      _configuredAdapter.chat(prompt, provider: provider);
  Future<List<double>> embed(String text) => _configuredAdapter.embed(text);
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) =>
      _configuredAdapter.structuredOutput(prompt, schema);
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) =>
      _configuredAdapter.transcribe(
        audioBytes,
        mimeType: mimeType,
        language: language,
      );
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) =>
      _configuredAdapter.runAgent(request);

  static DVAIAdapter get _configuredAdapter {
    final adapter = _adapter;
    if (adapter == null) {
      throw StateError(
        'DV.AI has no configured adapter. Configure an AI provider before use.',
      );
    }
    return adapter;
  }
}

class DVDatabase {
  const DVDatabase();
  static DVDatabaseAdapter? _adapter;

  void configure(DVDatabaseAdapter adapter) {
    _adapter = adapter;
  }

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) =>
      _configuredAdapter.query(sql, params);

  Future<int> execute(String sql, [List<Object?>? params]) =>
      _configuredAdapter.execute(sql, params);

  static DVDatabaseAdapter get _configuredAdapter {
    final adapter = _adapter;
    if (adapter == null) {
      throw StateError(
        'DV.Database has no configured adapter. Configure SQLite or another database adapter before use.',
      );
    }
    return adapter;
  }
}

class DVCache {
  const DVCache();
  static DVCacheAdapter _adapter = DVMemoryCacheAdapter();
  static const DVCacheTags _tags = DVCacheTags();

  /// Swaps the storage behind the cache. Defaults to [DVMemoryCacheAdapter];
  /// pass a [DVDatabaseCacheAdapter] to persist entries across restarts.
  void configure(DVCacheAdapter adapter) {
    _adapter = adapter;
  }

  DVCacheAdapter get adapter => _adapter;

  Future<T?> get<T>(String key) async {
    final value = await _adapter.read(key);
    return value is T ? value : null;
  }

  Future<void> set(String key, Object? value, [Duration? ttl]) =>
      _adapter.write(key, value, ttl);

  Future<void> delete(String key) => _adapter.remove(key);

  /// Drops every entry. Tag associations are cleared with it.
  Future<void> clear() async {
    await _adapter.clear();
    _tags.clear();
  }

  /// Removes entries whose TTL has elapsed, reclaiming storage. Reads already
  /// ignore expired entries, so this is housekeeping rather than correctness.
  Future<int> purgeExpired() => _adapter.purgeExpired();

  void tag(String key, Iterable<String> tags) {
    _tags.tag(key, tags);
  }

  Set<String> keysForTag(String tag) {
    return _tags.keysForTag(tag);
  }

  Future<Set<String>> revalidateTag(String tag) async {
    final keys = _tags.revalidateTag(tag);
    for (final key in keys) {
      await _adapter.remove(key);
    }
    return keys;
  }
}

class DVStorage {
  const DVStorage();
  static DVFileStorageAdapter _adapter = DVMemoryFileStorageAdapter();

  /// Swaps the storage behind `DV.FileStorage`. Defaults to
  /// [DVMemoryFileStorageAdapter]; pass an [S3FileStorageAdapter] for an
  /// object store.
  ///
  /// Browser-extension storage still takes precedence where the host provides
  /// it, since that is the only storage such a target can reach.
  void configure(DVFileStorageAdapter adapter) {
    _adapter = adapter;
  }

  DVFileStorageAdapter get adapter => _adapter;

  Future<void> put(String key, List<int> bytes, {String? contentType}) async {
    if (browser_extension_platform.supportsFileStorage()) {
      await browser_extension_platform.fileStoragePut(key, bytes);
      return;
    }
    await _adapter.put(key, bytes, contentType: contentType);
  }

  Future<List<int>> get(String key) async {
    if (browser_extension_platform.supportsFileStorage()) {
      return browser_extension_platform.fileStorageGet(key);
    }
    return _adapter.get(key);
  }

  Future<void> delete(String key) async {
    if (browser_extension_platform.supportsFileStorage()) {
      await browser_extension_platform.fileStorageDelete(key);
      return;
    }
    await _adapter.delete(key);
  }

  Future<bool> exists(String key) => _adapter.exists(key);

  Future<List<String>> list({String prefix = ''}) =>
      _adapter.list(prefix: prefix);
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
  static final _globals = <_DVGlobalKey, Object>{};
  static ProviderContainer? container;

  static T global<T>([T? instance, String namespace = '']) {
    final key = _DVGlobalKey(namespace, T);
    if (instance != null) {
      _globals[key] = instance as Object;
      final provider = _globalProviders[key];
      if (provider != null && container != null) {
        container!.read(provider.notifier).state = instance;
      } else if (provider == null) {
        _globalProviders[key] = StateProvider<Object?>((ref) => instance);
      }
      return instance;
    }
    final inst = _globals[key];
    if (inst == null) {
      final scope = namespace.isEmpty ? 'app' : namespace;
      throw StateError('Global instance of type $T not registered in $scope');
    }
    return inst as T;
  }

  /// Read-only lifecycle signals: `DV.lifecycle.app`, `DV.lifecycle.build`.
  ///
  /// The framework owns the transitions; application code observes them.
  static final DVLifecycleRegistry lifecycle = DVLifecycleRegistry();

  /// Mounted Dartvel modules. The generator emits typed `DV.Modules.<id>`
  /// accessors on top of this registry.
  static final DVModuleRegistry Modules = DVModuleRegistry();

  static final DVTransactionRunner _transactionRunner = DVTransactionRunner();

  /// Runs [body] as a reversible unit of work.
  ///
  /// Use `context.afterCommit(...)` for irreversible effects that must not
  /// happen unless the transaction commits, and `context.compensate(...)` to
  /// register the inverse of an external effect Dartvel cannot reverse itself.
  ///
  /// Nested calls join the active transaction unless [isolated] is set.
  static Future<T> transaction<T>(
    FutureOr<T> Function(DVContext context) body, {
    bool isolated = false,
  }) =>
      _transactionRunner.call<T>(body, isolated: isolated);

  static DVPlatform get Platform => const DVPlatform();
  static DVNavigation get Navigation => const DVNavigation();

  // Top-level proxies onto the `DV.Platform` device namespaces. Everything
  // still lives under `DV.Platform.*`; these only save a hop for the device
  // APIs the spec proxies by name.
  static DVLocation get Location => Platform.Location;
  static DVBluetooth get Bluetooth => Platform.Bluetooth;
  static DVNfc get NFC => Platform.NFC;
  static DVClipboard get Clipboard => Platform.Clipboard;
  static DVShare get Share => Platform.Share;
  static DVSensors get Sensors => Platform.Sensors;
  static DVBiometrics get Biometrics => Platform.Biometrics;
  static DVDeepLinks get DeepLinking => Platform.DeepLinking;
  static DVHaptics get Haptics => Platform.Haptics;
  static DVContacts get Contacts => Platform.Contacts;

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
  static DVSecrets get Secrets => const DVSecrets();
  static DVTestHarness get Test => const DVTestHarness();
  static DVCSRF get CSRF => const DVCSRF();
  static DVCSRF get Csrf => const DVCSRF();
  static DVI18n get I18n => const DVI18n();
  static DVAccessibility get Accessibility => const DVAccessibility();
  static DVObservabilityAndLogging get ObservabilityAndLogging =>
      const DVObservabilityAndLogging();
  static String _activeTenant = 'default';
  static String get currentTenant => _activeTenant;
  static set currentTenant(String tenant) {
    final trimmed = tenant.trim();
    _activeTenant = trimmed.isEmpty ? 'default' : trimmed;
  }

  /// Runs [callback] within the dynamic multi-tenant context of [tenant].
  static R withTenant<R>(String tenant, R Function() callback) {
    final previous = _activeTenant;
    currentTenant = tenant;
    try {
      return callback();
    } finally {
      _activeTenant = previous;
    }
  }

  // --- Runtime backend URL ---------------------------------------------------
  // The generated `dartvel_client` wires the app's backend config into these
  // resolvers via [registerRuntime], so application code uses the short
  // `DV.baseUrl` / `DV.api(...)` API instead of the generated `DartvelRuntime`.
  static String Function()? _baseUrlResolver;
  static String Function()? _apiBasePathResolver;
  static Uri Function(String path)? _apiResolver;

  /// Wires the generated runtime into `DV`. Called automatically by the
  /// generated router/app bootstrap; application code does not call this.
  static void registerRuntime({
    required String Function() baseUrl,
    required String Function() apiBasePath,
    required Uri Function(String path) api,
  }) {
    _baseUrlResolver = baseUrl;
    _apiBasePathResolver = apiBasePath;
    _apiResolver = api;
  }

  static Never _runtimeNotConfigured() => throw StateError(
        'Dartvel runtime is not configured. Ensure the generated '
        'dartvel_client is imported and the app is initialized before '
        'accessing DV.baseUrl / DV.api(...).',
      );

  /// The resolved backend base URL for the current build/target.
  static String get baseUrl => (_baseUrlResolver ?? _runtimeNotConfigured())();

  /// The API base path segment (e.g. `/api`).
  static String get apiBasePath =>
      (_apiBasePathResolver ?? _runtimeNotConfigured())();

  /// Builds a full backend API [Uri] for [path].
  static Uri api(String path) =>
      (_apiResolver ?? _runtimeNotConfigured())(path);

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

/// Context-free navigation over the generated route targets.
///
/// `go_router` is an implementation detail behind this surface: application
/// code navigates with `DV.Navigation` and `DVPages`/`DVRoutes` so the engine
/// can change without breaking call sites.
class DVNavigation {
  const DVNavigation();

  static GoRouter? _router;

  /// Called by the generated `createDartvelRouter()`. Navigation needs a
  /// handle to the live router because [to] is used in callbacks such as
  /// `onPressed`, where no `BuildContext` is in scope.
  static void attach(GoRouter router) {
    _router = router;
  }

  /// Forgets the attached router. Tests that build their own router should
  /// call this in teardown so one test cannot navigate another's.
  static void detach() {
    _router = null;
  }

  static GoRouter get _active {
    final router = _router;
    if (router == null) {
      throw StateError(
        'DV.Navigation has no router. The generated createDartvelRouter() '
        'attaches one; call DVNavigation.attach(router) directly if you build '
        'a router yourself.',
      );
    }
    return router;
  }

  /// Whether a router has been attached. Navigating without one throws, so
  /// widgets built outside a Dartvel app can check first.
  bool get isAttached => _router != null;

  /// A callback that navigates to [target], for use directly in handlers:
  /// `DVBox(...).onPressed(DV.Navigation.to(DVPages.users))`.
  VoidCallback to(DVRouteTarget target) => () => navigate(target);

  /// Navigates to [target] now, replacing the current location.
  void navigate(DVRouteTarget target) => _active.go(target.path);

  /// Pushes [target] onto the navigation stack, keeping the current page.
  Future<T?> push<T extends Object?>(DVRouteTarget target) =>
      _active.push<T>(target.path);

  /// Pops the top page when there is one to pop.
  void back<T extends Object?>([T? result]) {
    final router = _active;
    if (router.canPop()) router.pop<T>(result);
  }

  /// Whether [back] would do anything.
  bool get canGoBack => _active.canPop();

  /// The current location, as the URL the router resolved.
  String get currentPath =>
      _active.routerDelegate.currentConfiguration.uri.toString();
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

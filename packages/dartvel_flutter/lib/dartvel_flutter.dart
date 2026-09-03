library dartvel_flutter;

import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart';

// conditional SEO implementation
import 'src/browser_extension_platform_memory.dart'
    if (dart.library.html) 'src/browser_extension_platform_web.dart'
    as browser_extension_platform;
import 'src/display_platform.dart'
    if (dart.library.js_interop) 'src/display_platform_web.dart'
    as display_platform;
// DV.Updates.applyPages installs page bundles, which are these types.
import 'src/pwa/install_prompt.dart';
import 'src/seo_platform_memory.dart'
    if (dart.library.html) 'src/seo_platform_web.dart' as seo_platform;
import 'src/studio/page_document.dart';
import 'src/windowing/window.dart';

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
        DVDatabase,
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
        DVMemoryAppKeyStore,
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
        DVPublicPathsResolver,
        DVModelPageRole,
        DVPresence,
        DVPresenceEvent,
        DVPresenceEventKind,
        DVPresenceMember,
        DVPresenceTransport,
        DVModelSync,
        DVModelChange,
        DVModelChangeKind,
        DVModelSyncTransport,
        DVModelWatch,
        DVImage,
        DVImageSource,
        DVJob,
        DVExportResult,
        DVExportOptions,
        DVMiddleware,
        DVMiddlewareKey,
        DVMiddlewares,
        DVPluralCategory,
        dvPluralCategoriesFor,
        dvPluralCategory,
        dvLanguageOf,
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
        DVAppKey,
        DVAppKeyCipher,
        DVAppKeyStore,
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
        DVTenants,
        DVTenantIsolation,
        DVTenantSource,
        DVShellCommand,
        DVShellResult,
        DVShellResultFuture,
        DVTestHarness,
        DVLocalBillingProvider,
        Entitlement,
        LocalAnalyticsProvider,
        formControlsFactories,
        registerFormControlsFactory,
        // The model registries a DVForm reads: an application registers
        // through the generated client, and a test registers directly.
        dvModelDeserializers,
        dvModelFactories,
        dvModelSerializers,
        registerDVModelDeserializer,
        registerDVModelFactory,
        registerDVModelSerializer;
export 'package:go_router/go_router.dart';

export 'src/admin/cache_admin.dart';
export 'src/admin/model_admin.dart';
export 'src/admin/outbox_admin.dart';
export 'src/admin/policy_admin.dart';
export 'src/admin/queue_admin.dart';
export 'src/admin/route_admin.dart';
export 'src/admin/route_info.dart';
export 'src/admin/telemetry_admin.dart';
export 'src/media/image_view.dart';
export 'src/platform/android/android_bindings.dart';
export 'src/platform/file_bindings.dart';
export 'src/platform/ios/ios_bindings.dart';
export 'src/platform/linux/linux_bindings.dart';
export 'src/platform/macos/macos_bindings.dart';
export 'src/platform/web/web_bindings.dart';
export 'src/platform/windows/windows_bindings.dart';
export 'src/pwa/install_prompt.dart';
export 'src/routing/nav_link.dart';
export 'src/routing/url_strategy.dart';
export 'src/studio/page_document.dart';
export 'src/studio/studio_editor.dart';
export 'src/studio/studio_screen.dart';
export 'src/table/table.dart';
export 'src/platform/accelerator.dart';
export 'src/windowing/displays.dart';
export 'src/windowing/shared_store.dart';
export 'src/windowing/tab_workspace.dart';
export 'src/windowing/window.dart';
export 'src/windowing/window_state.dart';

// ==========================================
// UI & Styling Primitives (NEW_SPEC.md)
// ==========================================

class DVModifier {
  final EdgeInsetsGeometry? paddingValue;
  final EdgeInsetsGeometry? marginValue;
  final BorderRadiusGeometry? borderRadius;

  /// A border drawn round the box.
  ///
  /// Without this there is no way to draw a rule under a header or a
  /// hairline round a card, so every one of those reaches for a raw
  /// Container and a BoxDecoration -- which is how an application ends up
  /// half Dartvel and half Flutter.
  final BoxBorder? borderValue;
  final Color? textColor;
  final double? fontSizeValue;
  final FontWeight? fontWeightValue;
  final double? letterSpacingValue;
  final Color? boxColor;

  /// A gradient behind the box, painted instead of [boxColor] where both are
  /// set. The one thing a hero band needs that a flat colour cannot give it.
  final Gradient? gradientValue;

  /// A maximum or minimum the box is laid out within.
  ///
  /// Distinct from [widthValue]: a max width lets the box be narrower on a
  /// phone, where a fixed width overflows. A reading column is a constraint,
  /// not a size, and writing it as a size is the single most common way a
  /// desktop layout breaks on mobile.
  final BoxConstraints? constraintsValue;

  /// How long a change to this box's decoration takes to arrive. Null means
  /// no animation at all, which is what almost every box wants.
  final Duration? animateDuration;
  final Curve animateCurve;

  final double? opacityValue;

  /// Whether the box is centred within its parent.
  final bool centeredValue;

  /// Told whether the pointer is over the box.
  ///
  /// [hoverValue] restyles this box; revealing a sibling -- a label beside a
  /// rail indicator, a caption under a card -- needs the fact itself, so
  /// application code can put it in a signal and build from it.
  final ValueChanged<bool>? onHoverChangedCallback;

  /// Applied on top of this modifier while the pointer is over the box.
  ///
  /// A card that lifts under the pointer is the most common interaction on a
  /// page, and expressing it needed a StatefulWidget over MouseRegion in
  /// application code -- which is also where the reduced-motion check had to
  /// be remembered by hand.
  final DVModifier? hoverValue;

  /// Fade and rise into view the first time the box is scrolled to.
  final bool revealValue;

  /// A stagger, so a row of cards does not all arrive at once.
  final Duration revealDelay;
  final double? widthValue;
  final double? heightValue;
  final AlignmentGeometry? alignmentValue;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTapCallback;
  final DecorationImage? bgImage;
  final String? semanticLabelValue;
  final String? semanticHintValue;
  final bool? semanticButtonValue;

  /// 1 to 6, matching HTML's six heading levels and every platform's
  /// accessibility notion of one.
  final int? semanticHeadingValue;

  /// A Dartvel role, namespaced, travelling as the node's identifier.
  final String? semanticRoleValue;
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
    this.borderValue,
    this.textColor,
    this.fontSizeValue,
    this.fontWeightValue,
    this.letterSpacingValue,
    this.boxColor,
    this.gradientValue,
    this.constraintsValue,
    this.animateDuration,
    this.animateCurve = Curves.easeOut,
    this.opacityValue,
    this.centeredValue = false,
    this.onHoverChangedCallback,
    this.hoverValue,
    this.revealValue = false,
    this.revealDelay = Duration.zero,
    this.widthValue,
    this.heightValue,
    this.alignmentValue,
    this.shadows,
    this.onTapCallback,
    this.bgImage,
    this.semanticLabelValue,
    this.semanticHintValue,
    this.semanticButtonValue,
    this.semanticHeadingValue,
    this.semanticRoleValue,
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
        borderValue = null,
        textColor = null,
        fontSizeValue = null,
        fontWeightValue = null,
        letterSpacingValue = null,
        boxColor = null,
        gradientValue = null,
        constraintsValue = null,
        animateDuration = null,
        animateCurve = Curves.easeOut,
        opacityValue = null,
        centeredValue = false,
        onHoverChangedCallback = null,
        hoverValue = null,
        revealValue = false,
        revealDelay = Duration.zero,
        widthValue = null,
        heightValue = null,
        alignmentValue = null,
        shadows = null,
        onTapCallback = null,
        bgImage = null,
        semanticLabelValue = null,
        semanticHintValue = null,
        semanticButtonValue = null,
        semanticHeadingValue = null,
        semanticRoleValue = null,
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
    BoxBorder? borderValue,
    Color? textColor,
    double? fontSizeValue,
    FontWeight? fontWeightValue,
    double? letterSpacingValue,
    Color? boxColor,
    Gradient? gradientValue,
    BoxConstraints? constraintsValue,
    Duration? animateDuration,
    Curve? animateCurve,
    double? opacityValue,
    bool? centeredValue,
    ValueChanged<bool>? onHoverChangedCallback,
    DVModifier? hoverValue,
    bool? revealValue,
    Duration? revealDelay,
    double? widthValue,
    double? heightValue,
    AlignmentGeometry? alignmentValue,
    List<BoxShadow>? shadows,
    VoidCallback? onTapCallback,
    DecorationImage? bgImage,
    String? semanticLabelValue,
    String? semanticHintValue,
    bool? semanticButtonValue,
    int? semanticHeadingValue,
    String? semanticRoleValue,
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
      borderValue: borderValue ?? this.borderValue,
      textColor: textColor ?? this.textColor,
      fontSizeValue: fontSizeValue ?? this.fontSizeValue,
      fontWeightValue: fontWeightValue ?? this.fontWeightValue,
      letterSpacingValue: letterSpacingValue ?? this.letterSpacingValue,
      boxColor: boxColor ?? this.boxColor,
      gradientValue: gradientValue ?? this.gradientValue,
      constraintsValue: constraintsValue ?? this.constraintsValue,
      animateDuration: animateDuration ?? this.animateDuration,
      animateCurve: animateCurve ?? this.animateCurve,
      opacityValue: opacityValue ?? this.opacityValue,
      centeredValue: centeredValue ?? this.centeredValue,
      onHoverChangedCallback:
          onHoverChangedCallback ?? this.onHoverChangedCallback,
      hoverValue: hoverValue ?? this.hoverValue,
      revealValue: revealValue ?? this.revealValue,
      revealDelay: revealDelay ?? this.revealDelay,
      widthValue: widthValue ?? this.widthValue,
      heightValue: heightValue ?? this.heightValue,
      alignmentValue: alignmentValue ?? this.alignmentValue,
      shadows: shadows ?? this.shadows,
      onTapCallback: onTapCallback ?? this.onTapCallback,
      bgImage: bgImage ?? this.bgImage,
      semanticLabelValue: semanticLabelValue ?? this.semanticLabelValue,
      semanticHintValue: semanticHintValue ?? this.semanticHintValue,
      semanticButtonValue: semanticButtonValue ?? this.semanticButtonValue,
      semanticHeadingValue:
          semanticHeadingValue ?? this.semanticHeadingValue,
      semanticRoleValue: semanticRoleValue ?? this.semanticRoleValue,
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

  /// Padding per axis.
  ///
  /// A page gutter is never uniform -- 56 across against 64 down is the whole
  /// shape of a section band -- and [padding] can only say one number, which
  /// is why every band on the site reached for a Container to say two.
  DVModifier paddingSymmetric({double horizontal = 0, double vertical = 0}) =>
      _copyWith(
        paddingValue: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
      );

  /// Padding on named edges.
  DVModifier paddingOnly({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      _copyWith(
        paddingValue: EdgeInsets.only(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
      );

  DVModifier margin(double value) =>
      _copyWith(marginValue: EdgeInsets.all(value));

  DVModifier rounded(double value) =>
      _copyWith(borderRadius: BorderRadius.circular(value));

  /// Draws [value] round the box.
  ///
  /// `Border.all`, `Border(bottom: ...)` and the rest of Flutter's borders all
  /// work; this is the one property a rule or a hairline needs and the only
  /// reason the site still reached for Container.
  DVModifier border(BoxBorder value) => _copyWith(borderValue: value);

  DVModifier color(Color value) => _copyWith(textColor: value);

  DVModifier fontSize(double value) => _copyWith(fontSizeValue: value);

  DVModifier fontWeight(FontWeight value) => _copyWith(fontWeightValue: value);

  DVModifier letterSpacing(double value) =>
      _copyWith(letterSpacingValue: value);

  DVModifier backgroundColor(Color value) => _copyWith(boxColor: value);

  DVModifier width(double value) => _copyWith(widthValue: value);

  /// The widest this box may be laid out, not the width it takes.
  ///
  /// The distinction is the difference between a reading column and an
  /// overflow: `width(1040)` on a 390pt phone paints 650pt off the side of
  /// the screen, `maxWidth(1040)` lays out at 390. Prefer this for anything
  /// whose size follows the window.
  DVModifier maxWidth(double value) => _constrain(maxWidth: value);
  DVModifier minWidth(double value) => _constrain(minWidth: value);
  DVModifier maxHeight(double value) => _constrain(maxHeight: value);
  DVModifier minHeight(double value) => _constrain(minHeight: value);

  /// Merges one bound into whatever bounds are already set, so the four
  /// methods above chain instead of overwriting each other.
  DVModifier _constrain({
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
  }) {
    final BoxConstraints current =
        constraintsValue ?? const BoxConstraints();
    return _copyWith(
      constraintsValue: BoxConstraints(
        minWidth: minWidth ?? current.minWidth,
        maxWidth: maxWidth ?? current.maxWidth,
        minHeight: minHeight ?? current.minHeight,
        maxHeight: maxHeight ?? current.maxHeight,
      ),
    );
  }

  /// Paints [value] behind the box.
  DVModifier gradient(Gradient value) => _copyWith(gradientValue: value);

  /// Fades the whole box, children included.
  DVModifier opacity(double value) => _copyWith(opacityValue: value);

  /// Centres the box within its parent.
  ///
  /// Different from [align], which places the child inside the box. A
  /// 400-wide reading column in a full-width tinted band needs this one; with
  /// [align] it stays pinned to the left of the band.
  DVModifier centered() => _copyWith(centeredValue: true);

  /// Animates changes to this box's decoration and geometry over [duration].
  ///
  /// A card whose border takes the accent on hover snaps without this, which
  /// reads as a glitch rather than a response. Honours the reader's
  /// reduced-motion setting: when that is on the box simply takes its new
  /// appearance, because an animation the reader asked not to see is not a
  /// nicety to keep.
  DVModifier animate(
    Duration duration, {
    Curve curve = Curves.easeOut,
  }) =>
      _copyWith(animateDuration: duration, animateCurve: curve);

  /// What this box looks like while the pointer is over it.
  ///
  /// [whenHovered] is layered on top rather than replacing: a hover state that
  /// says only "blue border" keeps the padding and radius the base modifier
  /// set. Pair it with [animate] so the change arrives rather than snaps.
  DVModifier hover(DVModifier whenHovered) =>
      _copyWith(hoverValue: whenHovered);

  /// Calls [onChanged] when the pointer enters or leaves the box.
  ///
  /// For anything hover has to change that is not this box's own appearance.
  /// Put the value in a `context.signal` and the sibling rebuilds from it.
  DVModifier onHoverChanged(ValueChanged<bool> onChanged) =>
      _copyWith(onHoverChangedCallback: onChanged);

  /// Fades and rises into view the first time the box is scrolled to.
  ///
  /// Honours reduced motion, where the box is simply present from the first
  /// frame -- and it fails open: if the box never gets a position this can
  /// read, it appears anyway. Content that a decoration can hide permanently
  /// is a worse bug than no decoration.
  DVModifier revealOnScroll({Duration delay = Duration.zero}) =>
      _copyWith(revealValue: true, revealDelay: delay);

  /// This modifier with [other]'s set fields layered over it.
  ///
  /// Every field is nullable and every setter is a copyWith, so "set" means
  /// non-null. A field [other] never mentions keeps this one's value.
  DVModifier merge(DVModifier other) => DVModifier(
        paddingValue: other.paddingValue ?? paddingValue,
        marginValue: other.marginValue ?? marginValue,
        borderRadius: other.borderRadius ?? borderRadius,
        borderValue: other.borderValue ?? borderValue,
        textColor: other.textColor ?? textColor,
        fontSizeValue: other.fontSizeValue ?? fontSizeValue,
        fontWeightValue: other.fontWeightValue ?? fontWeightValue,
        letterSpacingValue: other.letterSpacingValue ?? letterSpacingValue,
        boxColor: other.boxColor ?? boxColor,
        gradientValue: other.gradientValue ?? gradientValue,
        constraintsValue: other.constraintsValue ?? constraintsValue,
        animateDuration: other.animateDuration ?? animateDuration,
        animateCurve: other.animateDuration != null
            ? other.animateCurve
            : animateCurve,
        opacityValue: other.opacityValue ?? opacityValue,
        centeredValue: other.centeredValue || centeredValue,
        onHoverChangedCallback:
            other.onHoverChangedCallback ?? onHoverChangedCallback,
        // Not carried over: a hover state describing its own hover state, or
        // re-revealing on every pointer move, is never what was meant.
        widthValue: other.widthValue ?? widthValue,
        heightValue: other.heightValue ?? heightValue,
        alignmentValue: other.alignmentValue ?? alignmentValue,
        shadows: other.shadows ?? shadows,
        onTapCallback: other.onTapCallback ?? onTapCallback,
        bgImage: other.bgImage ?? bgImage,
        semanticLabelValue: other.semanticLabelValue ?? semanticLabelValue,
        semanticHintValue: other.semanticHintValue ?? semanticHintValue,
        semanticButtonValue: other.semanticButtonValue ?? semanticButtonValue,
        semanticHeadingValue:
            other.semanticHeadingValue ?? semanticHeadingValue,
        semanticRoleValue: other.semanticRoleValue ?? semanticRoleValue,
        minimumTapTargetValue:
            other.minimumTapTargetValue ?? minimumTapTargetValue,
        inputValue: other.inputValue || inputValue,
        inputLabelValue: other.inputLabelValue ?? inputLabelValue,
        inputHintValue: other.inputHintValue ?? inputHintValue,
        inputObscureText: other.inputObscureText || inputObscureText,
        inputChanged: other.inputChanged ?? inputChanged,
      );

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

  /// Declare what this is, beyond a label and a heading level.
  ///
  /// Flutter's `Semantics` has roles for the things every platform agrees on
  /// and nothing for `code`, so the role travels as the node's identifier.
  /// Flutter web puts that in the DOM, which is where `dartvel build web`
  /// reads it to decide between a paragraph and a `<pre><code>`.
  ///
  /// Namespaced, because `identifier` is also used for test hooks and
  /// platform integrations: an unprefixed `code` would be indistinguishable
  /// from an application's own.
  ///
  /// The reason this exists: Flutter renders `SelectableText` as a textarea
  /// whose value it manages, so a code block was absent from the tree
  /// entirely -- from the crawler-visible HTML and from what a screen reader
  /// reads.
  DVModifier semanticRole(String role) =>
      _copyWith(semanticRoleValue: 'dartvel:$role');

  /// Mark this as a heading at [level].
  ///
  /// A page's structure is carried by its headings: a screen reader user moves
  /// between them, and a crawler reads the document outline from them. Without
  /// this there was no way to say a piece of text was one, so the semantics
  /// tree contained no headings at all and the generated static HTML had
  /// nothing to build an outline from.
  ///
  /// One to six, because that is what HTML has and what every platform's
  /// accessibility layer can express. A seventh would produce a semantics node
  /// nothing can represent and an `<h7>` that does not exist.
  DVModifier semanticHeading(int level) {
    if (level < 1 || level > 6) {
      throw ArgumentError.value(
        level,
        'level',
        'A heading level is 1 to 6.',
      );
    }
    return _copyWith(semanticHeadingValue: level);
  }

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

/// How a row or list distributes its children along its own axis.
///
/// A header bar -- wordmark and site links at the left, outbound links at the
/// right -- is the most common layout on any page, and DVBox could not say it:
/// a row packed to its content with no alignment leaves a Spacer and a raw
/// Row as the only way.
enum DVAlign {
  /// Packed to the content, the default, and the only one that does not take
  /// the full width available.
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How a row or list places its children across its other axis.
///
/// [stretch] is the default and is why a DVBox.list always took the width it
/// was given: useful for a column of cards filling a page, wrong anywhere the
/// list is measured by its parent -- inside a wrap, a row, or any unbounded
/// box, where a stretched column takes the whole line and a row of figures
/// stacks into a column.
enum DVCrossAlign { stretch, start, center, end }

typedef DVWidgetBuilder<T> = Widget Function(T item);

class DVBox<T> extends StatelessWidget {
  final Widget? _child;
  final List<Widget>? _children;
  final DVModifier? _modifier;
  final _DVBoxLayout _layout;
  final DVAlign _align;
  final DVCrossAlign _crossAlign;
  final int _columns;
  /// Whether [_columns] is a ceiling that steps down on narrow screens, or an
  /// exact count. True everywhere except where a developer opted out.
  final bool _responsive;
  final double _spacing;
  final bool _scrollable;
  final List<T>? _items;
  final Widget Function(BuildContext, T)? _itemBuilder;

  const DVBox([Widget? child, DVModifier? modifier])
      : _child = child,
        _children = null,
        _modifier = modifier,
        _layout = _DVBoxLayout.vertical,
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
        _spacing = 8,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.list(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
    DVAlign align = DVAlign.start,
    DVCrossAlign crossAlign = DVCrossAlign.stretch,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.vertical,
        _align = align,
        _crossAlign = crossAlign,
        _columns = 1,
        _responsive = true,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.row(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
    DVAlign align = DVAlign.start,
    DVCrossAlign crossAlign = DVCrossAlign.stretch,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.row,
        _align = align,
        _crossAlign = crossAlign,
        _columns = 1,
        _responsive = true,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  /// A vertical list that scrolls when its children do not fit.
  ///
  /// [DVBox.list] is a plain column: a collection whose length is not known
  /// in advance — every record, every route, every failed job — overflows it
  /// and the overflowing entries simply cannot be seen.
  const DVBox.scrollableList(
    List<Widget> children, {
    DVModifier? modifier,
    double spacing = 8,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.vertical,
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
        _spacing = spacing,
        _scrollable = true,
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
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
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
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.stack(List<Widget> children, {DVModifier? modifier})
      : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.stack,
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
        _spacing = 8,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.grid(
    List<Widget> children, {
    DVModifier? modifier,
    int columns = 2,
    double spacing = 8,
    bool responsive = true,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.grid,
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = columns,
        _responsive = responsive,
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
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = 1,
        _responsive = true,
        _spacing = spacing,
        _scrollable = false,
        _items = null,
        _itemBuilder = null;

  const DVBox.masonry(
    List<Widget> children, {
    DVModifier? modifier,
    int columns = 2,
    double spacing = 8,
    bool responsive = true,
  })  : _child = null,
        _children = children,
        _modifier = modifier,
        _layout = _DVBoxLayout.masonry,
        _align = DVAlign.start,
        _crossAlign = DVCrossAlign.stretch,
        _columns = columns,
        _responsive = responsive,
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
    bool responsive = true,
    double spacing = 8,
    DVAlign align = DVAlign.start,
    DVCrossAlign crossAlign = DVCrossAlign.stretch,
    bool scrollable = false,
    List<T>? items,
    Widget Function(BuildContext, T)? itemBuilder,
  })  : _child = child,
        _children = children,
        _modifier = modifier,
        _layout = layout,
        _align = align,
        _crossAlign = crossAlign,
        _columns = columns,
        _responsive = responsive,
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

  DVBox<T> row({double spacing = 8, DVAlign align = DVAlign.start}) =>
      _copyWith(layout: _DVBoxLayout.row, spacing: spacing, align: align);

  DVBox<T> grid({
    int columns = 2,
    double spacing = 8,
    bool responsive = true,
  }) =>
      _copyWith(
        layout: _DVBoxLayout.grid,
        columns: columns,
        spacing: spacing,
        responsive: responsive,
      );

  DVBox<T> wrapLine({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.wrap, spacing: spacing);

  DVBox<T> wrap({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.wrap, spacing: spacing);

  DVBox<T> stack() => _copyWith(layout: _DVBoxLayout.stack);

  DVBox<T> horizontalScrollable({double spacing = 8}) =>
      _copyWith(layout: _DVBoxLayout.horizontalScrollable, spacing: spacing);

  DVBox<T> masonry({
    int columns = 2,
    double spacing = 8,
    bool responsive = true,
  }) =>
      _copyWith(
        layout: _DVBoxLayout.masonry,
        columns: columns,
        spacing: spacing,
        responsive: responsive,
      );

  DVBox<T> scrollable() => _copyWith(scrollable: true);

  DVBox<T> _copyWith({
    DVModifier? modifier,
    _DVBoxLayout? layout,
    int? columns,
    double? spacing,
    bool? scrollable,
    bool? responsive,
    DVAlign? align,
    DVCrossAlign? crossAlign,
  }) {
    return DVBox<T>._(
      child: _child,
      children: _children,
      modifier: modifier ?? _modifier,
      layout: layout ?? _layout,
      columns: columns ?? _columns,
      responsive: responsive ?? _responsive,
      align: align ?? _align,
      crossAlign: crossAlign ?? _crossAlign,
      spacing: spacing ?? _spacing,
      scrollable: scrollable ?? _scrollable,
      items: _items,
      itemBuilder: _itemBuilder,
    );
  }

    @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    final DVModifier? mod = _modifier;

    Widget result;
    if (mod?.hoverValue != null || mod?.onHoverChangedCallback != null) {
      // A MouseRegion only where one was asked for. Every box on a page
      // listening for the pointer is a cost nobody asked for, and it makes
      // hit-testing harder to reason about.
      result = _DVHoverRegion(
        onChanged: mod!.onHoverChangedCallback,
        builder: (BuildContext context, bool hovered) => _decorate(
          context,
          hovered && mod.hoverValue != null
              ? mod.merge(mod.hoverValue!)
              : mod,
          content,
        ),
      );
    } else {
      result = _decorate(context, mod, content);
    }

    if (mod?.revealValue ?? false) {
      result = _DVReveal(delay: mod!.revealDelay, child: result);
    }
    return result;
  }

  Widget _decorate(BuildContext context, DVModifier? m, Widget? content) {
    final decoration = BoxDecoration(
      // Null when a gradient is set: Flutter asserts if a BoxDecoration
      // carries both, and the gradient is the more specific instruction.
      color: m?.gradientValue != null ? null : m?.boxColor,
      gradient: m?.gradientValue,
      borderRadius: m?.borderRadius,
      border: m?.borderValue,
      boxShadow: m?.shadows,
      image: m?.bgImage,
    );

    // Animated only when asked, and never when the reader has asked for less
    // movement. An AnimatedContainer on every box would put an implicit
    // animation controller behind the overwhelming majority of them, which
    // never change.
    final Duration? animate = m?.animateDuration;
    final bool animating = animate != null && !context.screen.reducedMotion;

    Widget result = animating
        ? AnimatedContainer(
            duration: animate,
            curve: m?.animateCurve ?? Curves.easeOut,
            width: m?.widthValue,
            height: m?.heightValue,
            alignment: m?.alignmentValue,
            margin: m?.marginValue,
            padding: m?.paddingValue,
            decoration: decoration,
            child: content,
          )
        : Container(
            width: m?.widthValue,
            height: m?.heightValue,
            alignment: m?.alignmentValue,
            margin: m?.marginValue,
            padding: m?.paddingValue,
            decoration: decoration,
            child: content,
          );

    // Outside the box, so padding and decoration are laid out within the
    // bound rather than added to it -- the same way a max-width column
    // behaves anywhere else.
    final BoxConstraints? constraints = m?.constraintsValue;
    if (constraints != null) {
      result = ConstrainedBox(constraints: constraints, child: result);
    }

    if (m?.centeredValue ?? false) {
      result = Center(child: result);
    }

    final double? opacity = m?.opacityValue;
    if (opacity != null) {
      result = Opacity(
        opacity: opacity,
        // Kept in the semantics tree. A fade is decoration, and content
        // should not become unreachable to a screen reader or to the
        // crawler-visible HTML because it happens to be faded.
        alwaysIncludeSemantics: true,
        child: result,
      );
    }

    if (m?.onTapCallback != null) {
      result = GestureDetector(
        onTap: m!.onTapCallback,
        child: result,
      );
    }

    final minimumTapTarget = m?.minimumTapTargetValue;
    if (minimumTapTarget != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumTapTarget.width,
          minHeight: minimumTapTarget.height,
        ),
        child: result,
      );
    }

    if (m?.semanticLabelValue != null ||
        m?.semanticHintValue != null ||
        m?.semanticButtonValue != null ||
        m?.semanticHeadingValue != null ||
        m?.semanticRoleValue != null) {
      result = Semantics(
        label: m?.semanticLabelValue,
        hint: m?.semanticHintValue,
        button: m?.semanticButtonValue,
        headingLevel: m?.semanticHeadingValue,
        identifier: m?.semanticRoleValue,
        excludeSemantics: m?.semanticLabelValue != null,
        child: result,
      );
      if (m?.semanticHeadingValue != null) {
        // Merged, so one node carries both the level and the text. Left
        // unmerged, the heading and its words are two nodes: the level lands
        // on an empty parent, a screen reader announces "heading" and then
        // the text separately, and anything reading the tree sees a heading
        // with no name.
        result = MergeSemantics(child: result);
      }
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
    if (children != null) return _buildStaticCollection(context, children);
    return null;
  }

  Widget _buildStaticCollection(BuildContext context, List<Widget> children) {
    final spaced = _spaced(children);
    final Widget result;
    switch (_layout) {
      case _DVBoxLayout.vertical:
        result = Column(
          crossAxisAlignment: _crossAxisAlignment,
          // Only DVAlign.start stays packed to its content. Every other
          // alignment is a statement about space the box does not have unless
          // it takes all of it, and a max-size column that is still
          // mainAxisSize.min simply ignores the alignment.
          mainAxisSize: _mainAxisSize,
          mainAxisAlignment: _mainAxisAlignment,
          children: spaced,
        );
        break;
      case _DVBoxLayout.row:
        result = Row(
          mainAxisSize: _mainAxisSize,
          mainAxisAlignment: _mainAxisAlignment,
          // A row has no stretch: a full-height row of cards is what
          // CrossAxisAlignment.stretch would mean here, which is never what a
          // header or a button pair wants.
          crossAxisAlignment: _crossAlign == DVCrossAlign.stretch
              ? CrossAxisAlignment.center
              : _crossAxisAlignment,
          children: spaced,
        );
        break;
      case _DVBoxLayout.grid:
        result = GridView.count(
          crossAxisCount: _columnsFor(context, children.length),
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
        result = _buildMasonry(context, children);
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
            crossAxisCount: _columnsFor(context, items.length),
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
          mainAxisSize: _mainAxisSize,
          mainAxisAlignment: _mainAxisAlignment,
          children: _spaced([for (final item in items) builder(context, item)]),
        );
      case _DVBoxLayout.masonry:
        return _buildMasonry(
            context, [for (final item in items) builder(context, item)]);
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

  Widget _buildMasonry(BuildContext context, List<Widget> children) {
    final int count = _columnsFor(context, children.length);
    final columns = List.generate(count, (_) => <Widget>[]);
    for (int i = 0; i < children.length; i++) {
      columns[i % count].add(children[i]);
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

  CrossAxisAlignment get _crossAxisAlignment => switch (_crossAlign) {
        DVCrossAlign.stretch => CrossAxisAlignment.stretch,
        DVCrossAlign.start => CrossAxisAlignment.start,
        DVCrossAlign.center => CrossAxisAlignment.center,
        DVCrossAlign.end => CrossAxisAlignment.end,
      };

  MainAxisSize get _mainAxisSize =>
      _align == DVAlign.start ? MainAxisSize.min : MainAxisSize.max;

  MainAxisAlignment get _mainAxisAlignment => switch (_align) {
        DVAlign.start => MainAxisAlignment.start,
        DVAlign.center => MainAxisAlignment.center,
        DVAlign.end => MainAxisAlignment.end,
        DVAlign.spaceBetween => MainAxisAlignment.spaceBetween,
        DVAlign.spaceAround => MainAxisAlignment.spaceAround,
        DVAlign.spaceEvenly => MainAxisAlignment.spaceEvenly,
      };

  /// How many columns to actually draw, on this screen, for this many items.
  ///
  /// [_columns] is a ceiling rather than a count. Three columns is a good
  /// desktop layout and a broken phone one, and a primitive that cannot tell
  /// the difference pushes the measurement out to every call site -- which is
  /// where responsive layout goes to die, because the call site ships before
  /// anyone opens it on a phone.
  ///
  /// Capped by the number of children as well: two cards in a three-column
  /// grid should occupy the row, not two thirds of it.
  int _columnsFor(BuildContext context, int itemCount) {
    final int ceiling = _columns < 1 ? 1 : _columns;
    if (!_responsive) return ceiling;

    final int forWidth = context.screen.value<int>(
      mobile: 1,
      tablet: 2,
      desktop: ceiling,
    );
    final int columns = forWidth < ceiling ? forWidth : ceiling;
    if (itemCount > 0 && itemCount < columns) return itemCount;
    return columns < 1 ? 1 : columns;
  }
}


/// Rebuilds its child with whether the pointer is over it.
///
/// Framework-internal, and stateful because pointer-over is per-element state
/// with no other home. Application code does not write one of these; it says
/// `DVModifier().hover(...)`.
class _DVHoverRegion extends StatefulWidget {
  const _DVHoverRegion({required this.builder, this.onChanged});

  final Widget Function(BuildContext context, bool hovered) builder;

  /// Told about the change as well as restyling, so one MouseRegion serves
  /// both and asking for one does not lose the other.
  final ValueChanged<bool>? onChanged;

  @override
  State<_DVHoverRegion> createState() => _DVHoverRegionState();
}

class _DVHoverRegionState extends State<_DVHoverRegion> {
  bool _over = false;

  void _set(bool over) {
    if (_over == over) return;
    setState(() => _over = over);
    widget.onChanged?.call(over);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: widget.builder(context, _over),
      );
}

/// Fades and rises its child into view, once.
///
/// Laid out at full size from the first frame: only opacity and offset
/// animate, so nothing reflows and the scrollbar does not jump while the page
/// settles.
class _DVReveal extends StatefulWidget {
  const _DVReveal({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  State<_DVReveal> createState() => _DVRevealState();
}

class _DVRevealState extends State<_DVReveal> {
  bool _shown = false;
  bool _scheduled = false;
  Timer? _failsafe;
  Timer? _stagger;

  void _reveal() {
    if (_scheduled) return;
    _scheduled = true;
    // No timer at all for the common case. A zero delay scheduled through
    // Future.delayed still leaves a pending timer behind, which outlives a
    // disposed tree -- it fails a widget test, and in an application it is a
    // callback holding a State that is already gone.
    if (widget.delay == Duration.zero) {
      setState(() => _shown = true);
      return;
    }
    _stagger?.cancel();
    _stagger = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  void _check() {
    if (_shown || _scheduled) return;
    final RenderObject? box = context.findRenderObject();
    // No size yet. On web the first frames arrive before layout, so this is
    // the normal case on load rather than an edge -- and retrying is what
    // makes it recoverable.
    if (box is! RenderBox || !box.hasSize) return;

    final double top = box.localToGlobal(Offset.zero).dy;
    final double height = MediaQuery.sizeOf(context).height;
    // A little above the bottom edge: any earlier and the animation finishes
    // before it is on screen, any later and the reader watches it happen
    // instead of arriving to it already done.
    if (top < height * 0.88) _reveal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    // Fails open. If the check never gets a usable position -- no scrollable
    // ancestor, a layout it does not anticipate -- the content appears
    // anyway. A decoration that can permanently hide a section is a worse bug
    // than no decoration.
    _failsafe ??= Timer(const Duration(milliseconds: 1600), () {
      if (mounted) _reveal();
    });
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _stagger?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing at all when the reader has asked for less movement: no wrapper,
    // no animation, no delay before the content is there.
    if (context.screen.reducedMotion) return widget.child;

    if (!_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }

    return NotificationListener<ScrollNotification>(
      // False: this is watching, not consuming. True would stop the
      // notification reaching the scrollbar and any reveal above it.
      onNotification: (ScrollNotification notification) {
        _check();
        return false;
      },
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.26),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOut,
          // Load-bearing. Opacity 0 drops its children from the semantics
          // tree, and a reveal starts every section at 0 -- so the
          // crawler-visible HTML, which is built from that tree, loses every
          // section the reader has not reached.
          alwaysIncludeSemantics: true,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The editable form of [DVText], which needs state a stateless widget cannot
/// hold: a controller rebuilt every frame would reset the cursor on each
/// keystroke.
class _DVInputField extends StatefulWidget {
  final String value;
  final DVModifier modifier;

  const _DVInputField({required this.value, required this.modifier});

  @override
  State<_DVInputField> createState() => _DVInputFieldState();
}

class _DVInputFieldState extends State<_DVInputField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_DVInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the value when it changes underneath — a different record was
    // opened, or the model was reset — but never while it already matches
    // what is on screen, which is every keystroke the user makes.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      obscureText: widget.modifier.inputObscureText,
      decoration: InputDecoration(
        labelText: widget.modifier.inputLabelValue,
        hintText: widget.modifier.inputHintValue,
      ),
      onChanged: widget.modifier.inputChanged,
    );
  }
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
      // The text is the field's value, not a placeholder for it. Passing it
      // as a hint drew every populated field as empty grey text, so a form
      // over a stored record looked like a blank record.
      result = _DVInputField(value: text, modifier: modifier!);
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

    // Semantics on the text itself, not only on a DVBox wrapping it. A
    // heading is text, so `DVText(...).modifier(DVModifier().semanticHeading(2))`
    // is where the call naturally goes -- and it did nothing, because this
    // build never looked at the semantic fields. Merged so the level and the
    // words are one node: unmerged, a screen reader announces "heading" and
    // then the text, and anything reading the tree sees a heading with no
    // name.
    if (modifier != null &&
        (modifier.semanticLabelValue != null ||
            modifier.semanticHintValue != null ||
            modifier.semanticButtonValue != null ||
            modifier.semanticHeadingValue != null ||
            modifier.semanticRoleValue != null)) {
      // A role has to name the node itself. Merging the text's own node into
      // it loses the identifier -- Flutter does not carry one through a merge
      // -- so a role with no explicit label takes the text as its label and
      // excludes the child. Otherwise the role arrives on a node with nothing
      // in it, which is how the first version of this reported an empty
      // identifier.
      final bool ownsLabel = modifier.semanticRoleValue != null &&
          modifier.semanticLabelValue == null;
      result = Semantics(
        label: ownsLabel ? text : modifier.semanticLabelValue,
        hint: modifier.semanticHintValue,
        button: modifier.semanticButtonValue,
        headingLevel: modifier.semanticHeadingValue,
        identifier: modifier.semanticRoleValue,
        excludeSemantics: ownsLabel || modifier.semanticLabelValue != null,
        child: result,
      );
      // Merged only when the node does not already own its text. A
      // MergeSemantics around a node carrying an identifier reports the merged
      // node instead, and the identifier is not carried through -- which is
      // how a role that was plainly set arrived as an empty string.
      if (!ownsLabel && modifier.semanticLabelValue == null) {
        result = MergeSemantics(child: result);
      }
    }

    return result;
  }
}

// ==========================================
// Riverpod-powered Signals & State
// ==========================================

final _signalProviders = Expando<List<StateProvider<Object?>>>();

/// Position of the next `context.signal(...)` call within the current build,
/// per element. Rewound by a post-frame callback so each build walks the
/// provider list from the top in call order.
final _signalCursor = Expando<int>();
final _signalListeners =
    Expando<Map<StateProvider<Object?>, ProviderSubscription<Object?>>>();

/// A reactive value that can be read, whether it stores its own state or is
/// derived from signals that do.
///
/// Exists so that a derivation can take signals and other derivations without
/// caring which it was handed: `(a + b) * c` is the same shape at every step.
abstract class DVReadableSignal<T> {
  /// The current value, subscribing the reading element to changes.
  T get value;

  /// The current value without subscribing.
  T read();
}

class DVSignal<T> implements DVReadableSignal<T> {
  final ProviderContainer container;
  final StateProvider<T> provider;
  final Element element;

  DVSignal(this.container, this.provider, this.element);

  @override
  T read() => container.read(provider);

  @override
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

/// A signal produced by operating on other signals.
///
/// Never constructed directly and never named in application code — it is what
/// `a + b`, `price * quantity` or `first + last` evaluate to. Operating on
/// signals yields a signal, so a derived value is simply a value, and there is
/// no separate derived-value constructor to reach for.
///
/// Reactivity rides on the sources. Reading `a.value` inside the derivation
/// subscribes the element exactly as it would in a build method, so a derived
/// signal stays current without subscription bookkeeping of its own — and
/// derivations compose, because a derivation over a derivation still bottoms
/// out in stored signals.
class DVDerivedSignal<T> implements DVReadableSignal<T> {
  final T Function() _derive;

  const DVDerivedSignal(this._derive);

  @override
  T get value => _derive();

  @override
  T read() => _derive();
}

/// Resolves an operand that may be a signal or a plain value.
///
/// Reading happens at derivation time rather than when the operator runs, so
/// `total * rate` tracks `rate` rather than capturing whatever it held once.
num _dvNum(Object other) {
  if (other is DVReadableSignal<num>) return other.value;
  if (other is num) return other;
  throw ArgumentError.value(other, 'other',
      'Expected a numeric signal or a num');
}

bool _dvBool(Object other) {
  if (other is DVReadableSignal<bool>) return other.value;
  if (other is bool) return other;
  throw ArgumentError.value(other, 'other',
      'Expected a boolean signal or a bool');
}

Object? _dvAny(Object? other) =>
    other is DVReadableSignal<Object?> ? other.value : other;

/// Arithmetic and comparison over numeric signals.
///
/// Each operator returns a [DVDerivedSignal] rather than a number, so the
/// result is itself reactive and can be operated on again. The right-hand side
/// may be another signal or a plain number.
extension DVNumericSignalX on DVReadableSignal<num> {
  DVDerivedSignal<num> operator +(Object other) =>
      DVDerivedSignal<num>(() => value + _dvNum(other));

  DVDerivedSignal<num> operator -(Object other) =>
      DVDerivedSignal<num>(() => value - _dvNum(other));

  DVDerivedSignal<num> operator *(Object other) =>
      DVDerivedSignal<num>(() => value * _dvNum(other));

  DVDerivedSignal<double> operator /(Object other) =>
      DVDerivedSignal<double>(() => value / _dvNum(other));

  DVDerivedSignal<int> operator ~/(Object other) =>
      DVDerivedSignal<int>(() => value ~/ _dvNum(other));

  DVDerivedSignal<num> operator %(Object other) =>
      DVDerivedSignal<num>(() => value % _dvNum(other));

  DVDerivedSignal<bool> operator <(Object other) =>
      DVDerivedSignal<bool>(() => value < _dvNum(other));

  DVDerivedSignal<bool> operator <=(Object other) =>
      DVDerivedSignal<bool>(() => value <= _dvNum(other));

  DVDerivedSignal<bool> operator >(Object other) =>
      DVDerivedSignal<bool>(() => value > _dvNum(other));

  DVDerivedSignal<bool> operator >=(Object other) =>
      DVDerivedSignal<bool>(() => value >= _dvNum(other));
}

/// Concatenation over string signals.
extension DVStringSignalX on DVReadableSignal<String> {
  DVDerivedSignal<String> operator +(Object other) =>
      DVDerivedSignal<String>(() => '$value${_dvAny(other)}');
}

/// Logic over boolean signals.
///
/// `&` and `|` are Dart's non-short-circuiting operators, which is what a
/// derivation wants: both sides are read, so both stay tracked.
extension DVBooleanSignalX on DVReadableSignal<bool> {
  DVDerivedSignal<bool> operator &(Object other) =>
      DVDerivedSignal<bool>(() => value && _dvBool(other));

  DVDerivedSignal<bool> operator |(Object other) =>
      DVDerivedSignal<bool>(() => value || _dvBool(other));

  DVDerivedSignal<bool> operator ^(Object other) =>
      DVDerivedSignal<bool>(() => value ^ _dvBool(other));
}

/// The Riverpod container backing signals reached through [context].
///
/// Riverpod being an implementation detail means the application never has to
/// know it is there, and that includes not having to mount its scope. This
/// used to call `ProviderScope.containerOf` directly, which asserts one is
/// above it -- and nothing in Dartvel puts one there. A generated app is
/// `runApp(createDartvelApp())` over a MaterialApp.router, so the spec's
/// headline state primitive, `final counter = context.signal(0)`, threw with
/// "No ProviderScope found" in the exact application shape Dartvel generates.
///
/// An application that does mount its own scope still gets that one: the
/// fallback must not shadow a real scope, or provider overrides installed for
/// a test would be silently ignored.
ProviderContainer dvSignalContainerOf(BuildContext context) {
  final InheritedElement? scope = context
      .getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>();
  if (scope != null) return ProviderScope.containerOf(context);
  return _dvAmbientContainer ??= ProviderContainer();
}

/// One container for the whole process when the tree has no scope.
///
/// Not per-element: signals are keyed by element already, and a container per
/// element would make DV.global -- which is keyed by type across the whole
/// application -- resolve differently in every widget that read it.
ProviderContainer? _dvAmbientContainer;

/// Drops the ambient container, so a test starts from nothing.
void dvResetAmbientSignals() {
  _dvAmbientContainer?.dispose();
  _dvAmbientContainer = null;
}

extension DVSignalContextX on BuildContext {
  DVSignal<T> signal<T>(T initialValue) {
    final element = this as Element;
    final container = dvSignalContainerOf(this);

    final list = _signalProviders[element] ??= [];

    // Signals map to providers by call order within a build, the same
    // contract hooks use. Matching by type — the previous behaviour — made
    // the spec's own example impossible: `context.signal(1)` and
    // `context.signal(2)` in one build collapsed into a single int signal.
    final index = _signalCursor[element] ?? 0;
    _signalCursor[element] = index + 1;
    if (index == 0) {
      // First signal call of this build: rewind the cursor when the frame
      // ends so the next build walks the provider list from the top again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _signalCursor[element] = null;
      });
    }

    if (index < list.length && list[index] is StateProvider<T>) {
      return DVSignal<T>(
        container,
        list[index] as StateProvider<T>,
        element,
      );
    }

    final provider = StateProvider<T>((ref) => initialValue);
    if (index < list.length) {
      // The call at this position changed type — a hot-reload edit. Keep the
      // positions behind it intact and replace just this slot.
      list[index] = provider;
    } else {
      list.add(provider);
    }
    return DVSignal<T>(container, provider, element);
  }

  T global<T>({String namespace = ''}) {
    final key = _DVGlobalKey(namespace, T);
    // The registry stores Object?, because one map holds every type. The cast
    // therefore belongs on the value that comes out, not on the provider:
    // casting a StateProvider<Object?> to StateProvider<T> is not a widening
    // Dart permits, so `context.global<Cart>()` threw a TypeError for every T
    // that was not Object? -- which is every real use of it.
    final provider = _globalProviders.putIfAbsent(
      key,
      () => StateProvider<Object?>((ref) => DV.global<T>(null, namespace)),
    );

    final container = dvSignalContainerOf(this);
    DV.container = container;
    final element = this as Element;
    final listeners = _signalListeners[element] ??= {};
    if (!listeners.containsKey(provider)) {
      final sub = container.listen<Object?>(provider, (prev, next) {
        if (element.mounted) {
          element.markNeedsBuild();
        }
      });
      listeners[provider] = sub;
    }
    return container.read(provider) as T;
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

  /// Called on submit with the model the fields describe.
  ///
  /// Without this a form is display-only: the edits live in the widget and
  /// nothing else can see them.
  final void Function(T value)? onSubmit;

  const DVForm([this.initialValue, this.onSubmit]) : builder = null;

  const DVForm.builder(Widget Function(DVFormControls) this.builder,
      [this.initialValue, Key? key, this.onSubmit])
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

    // Fields with nothing to press are a display, not a form. The controls
    // appear once a caller has asked for the value, because that is the only
    // point at which submitting means anything.
    if (widget.onSubmit != null) {
      fields.add(
        const DVText('Save').modifier(
          const DVModifier()
              .semanticButton()
              .onTap(_submit)
              .minimumTapTarget(width: 48, height: 48),
        ),
      );
      fields.add(
        const DVText('Reset').modifier(
          const DVModifier()
              .semanticButton()
              .onTap(_reset)
              .minimumTapTarget(width: 48, height: 48),
        ),
      );
    }

    return Form(
      key: const ValueKey<String>('dv-form'),
      child: DVBox.list(fields),
    );
  }

  /// The model the fields currently describe.
  ///
  /// The typed values live in [_fieldValues] as text, so the edited model is
  /// built by writing them over the serialized form and reading it back —
  /// which is also what makes the field types the model's own rather than
  /// strings.
  T _edited() {
    if (_fieldValues.isEmpty) return formValue;
    final serialized = serializeDVModel<T>(formValue);
    if (serialized == null) {
      throw StateError(
        'No generated serializer registered for $T, so the edits to this '
        'form cannot be read back. Run dartvel build after annotating the '
        'model with @DVModel().',
      );
    }
    final json = Map<String, Object?>.of(serialized);
    for (final entry in _fieldValues.entries) {
      json[entry.key] = entry.value;
    }
    try {
      final value = deserializeDVModel<T>(json);
      if (value == null) {
        throw StateError(
          'No generated deserializer registered for $T, so this form can '
          'show a $T but cannot return an edited one. Run dartvel build '
          'after annotating the model with @DVModel().',
        );
      }
      return value;
    } on FormatException catch (error) {
      // A half-typed number reaches here as text the model cannot hold.
      // Naming the field beats a bare "Invalid radix-10 number" — but which
      // field is only inferable from the value, and parsers disagree about
      // where they put it: num.parse reports the input as the message and
      // leaves source null, while int.parse sets source.
      final reported = <String>{
        if (error.source is String) error.source! as String,
        error.message,
      };
      final offending = _fieldValues.entries
          .where((MapEntry<String, String> e) => reported.contains(e.value))
          .toList(growable: false);
      final where =
          offending.map((MapEntry<String, String> e) => e.key).join(', ');
      final value = offending.isEmpty ? error.message : offending.first.value;
      throw StateError(
        'Cannot build $T from this form: '
        '${where.isEmpty ? 'a field' : where} '
        'holds "$value", which is not a valid value for it.',
      );
    }
  }

  void _submit() {
    final value = _edited();
    setState(() {
      formValue = value;
      _initialValue = value;
      _fieldValues.clear();
    });
    widget.onSubmit?.call(value);
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

  /// Whether [method] has a registered binding.
  ///
  /// For deciding what to advertise, not for deciding whether to call: an
  /// API that degrades still calls, and one that cannot still throws through
  /// [require]. Windowing capability reads this because Flutter's desktop
  /// windowing is experimental, so claiming the capability before the binding
  /// exists would be a promise the next call breaks.
  static bool isRegistered(String method) => _handlers.containsKey(method);
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

  static String? _lockedVersion;
  static String? _skippedVersion;

  /// The version [check] and [apply] are pinned to, or null when unpinned.
  String? get lockedVersion => _lockedVersion;

  /// Pins the application to [version]: [apply] refuses any other update
  /// until [unlockVersion] is called. A kiosk fleet mid-audit is the use
  /// case — updates keep arriving, the device keeps declining them.
  void lockVersion(String version) {
    _lockedVersion = version.trim().isEmpty ? null : version.trim();
  }

  /// Removes the version pin.
  void unlockVersion() => _lockedVersion = null;

  /// Skips [version]: [shouldApply] declines exactly that version and no
  /// other, so "remind me next release" means what it says.
  void skipImmediateNextVersion(String version) {
    _skippedVersion = version.trim().isEmpty ? null : version.trim();
  }

  /// Whether [update] should be applied under the current lock and skip
  /// state. The generated update UI consults this before prompting.
  bool shouldApply(DVUpdateInfo update) {
    if (!update.available) return false;
    final version = update.version;
    if (_lockedVersion != null && version != _lockedVersion) return false;
    if (_skippedVersion != null && version == _skippedVersion) {
      // A required update overrides a user's skip; a skip is a preference,
      // a minimum supported version is not.
      return update.required;
    }
    return true;
  }

  /// What [applyPages] did, so a caller can report it rather than guess.
  ///
  /// A no-op is not a failure: an OTA patch can be delivered more than once,
  /// and a device under a version lock is declining on purpose.
  Future<DVPageUpdateResult> applyPages({
    required Uri from,
    Map<String, String> headers = const <String, String>{},
    DVPageBundleInstaller installer = const DVPageBundleInstaller(),
  }) async {
    final response = await dvSendHttpRequest(
      DVHttpRequest(url: from, method: 'GET', headers: headers),
    );
    if (response.statusCode == 404) {
      return const DVPageUpdateResult._(DVPageUpdateOutcome.none);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Fetching the page bundle from $from failed with HTTP '
        '${response.statusCode}.',
      );
    }

    final DVPageBundle bundle;
    try {
      bundle = DVPageBundle.decode(response.body);
    } on FormatException catch (error) {
      throw StateError('$from did not return a page bundle: ${error.message}');
    }

    // Page bundles obey the same lock and skip the code path does. A kiosk
    // pinned mid-audit is declining *this release*, and content is part of a
    // release; two independent notions of "pinned" would be a trap.
    if (_lockedVersion != null && bundle.version != _lockedVersion) {
      return DVPageUpdateResult._(
        DVPageUpdateOutcome.declined,
        version: bundle.version,
      );
    }

    final applied = await installer.apply(bundle);
    return DVPageUpdateResult._(
      applied ? DVPageUpdateOutcome.applied : DVPageUpdateOutcome.alreadyApplied,
      version: bundle.version,
      pages: bundle.pages.length,
      removedRoutes: bundle.removedRoutes.length,
    );
  }

  /// Versions of page bundles this installation has applied, newest last.
  Future<List<String>> appliedPageVersions({
    DVPageBundleInstaller installer = const DVPageBundleInstaller(),
  }) =>
      installer.appliedVersions();
}

/// What a page bundle fetch resulted in.
enum DVPageUpdateOutcome {
  /// The bundle was applied and its documents are now live.
  applied,

  /// The bundle's version had already been applied, so nothing was written.
  /// Re-applying would undo edits made since.
  alreadyApplied,

  /// A version lock is in force and this bundle is not the pinned version.
  declined,

  /// The source has no bundle to serve.
  none,
}

class DVPageUpdateResult {
  final DVPageUpdateOutcome outcome;
  final String? version;
  final int pages;
  final int removedRoutes;

  const DVPageUpdateResult._(
    this.outcome, {
    this.version,
    this.pages = 0,
    this.removedRoutes = 0,
  });

  bool get changedAnything => outcome == DVPageUpdateOutcome.applied;

  @override
  String toString() => 'DVPageUpdateResult(${outcome.name}'
      '${version == null ? '' : ', version: $version'}'
      '${pages == 0 ? '' : ', pages: $pages'}'
      '${removedRoutes == 0 ? '' : ', removedRoutes: $removedRoutes'})';
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

/// The width bands Dartvel lays out against.
///
/// One ladder for the whole framework. When a grid, a page shell and an
/// application component each decide "small" for themselves, they disagree at
/// the edges and the layout comes apart at exactly the widths nobody tests.
enum DVBreakpoint { mobile, tablet, desktop, wide }

/// The breakpoint a logical [width] falls in.
DVBreakpoint dvBreakpointFor(double width) {
  if (width >= 1600) return DVBreakpoint.wide;
  if (width >= 1200) return DVBreakpoint.desktop;
  if (width >= 840) return DVBreakpoint.tablet;
  return DVBreakpoint.mobile;
}

/// The shape of the surface being drawn on.
///
/// Watches are round and embedded panels are often taller than they are wide;
/// a layout that assumes a landscape rectangle is wrong on both.
enum DVScreenShape {
  square,
  verticalRectangle,
  horizontalRectangle,
  round,
  custom,
}

/// What the current surface looks like, as a value.
///
/// Obtained from `context.screen`, which reads MediaQuery and therefore
/// registers a dependency: a widget that asks about the screen is rebuilt when
/// the screen changes. `DV.Platform.screen` answers the same questions without
/// a context, but it reads the raw window and cannot rebuild anything, so it is
/// for code that has no context to offer -- not for build methods.
class DVScreenInfo {
  const DVScreenInfo({
    required this.size,
    required this.safeArea,
    required this.orientation,
    required this.reducedMotion,
    required this.textScale,
  });

  /// Logical size of the surface, honouring any MediaQuery an ancestor
  /// narrowed -- a pane or a dialog, not necessarily the whole window.
  final Size size;

  /// Notches, home indicators, and rounded corners to keep content clear of.
  final EdgeInsets safeArea;

  final Orientation orientation;

  /// True when the reader has asked for less movement, either through the
  /// platform setting or an explicit [DVAccessibility.useReducedMotion].
  final bool reducedMotion;

  final double textScale;

  double get width => size.width;
  double get height => size.height;

  DVBreakpoint get breakpoint => dvBreakpointFor(size.width);

  /// The spec spelling, as a plain string, matching `DVScreen.breakPoints`.
  String get breakPoints => breakpoint.name;

  bool get isMobile => breakpoint == DVBreakpoint.mobile;
  bool get isTablet => breakpoint == DVBreakpoint.tablet;
  bool get isDesktop =>
      breakpoint == DVBreakpoint.desktop || breakpoint == DVBreakpoint.wide;
  bool get isWide => breakpoint == DVBreakpoint.wide;

  /// True from [DVBreakpoint.tablet] upward. The common test: "is there room
  /// for two columns", which a tablet answers yes to and a phone does not.
  bool get isAtLeastTablet => !isMobile;

  bool get isPortrait => orientation == Orientation.portrait;
  bool get isLandscape => orientation == Orientation.landscape;

  DVScreenShape get shape {
    if (size.width <= 0 || size.height <= 0) return DVScreenShape.custom;
    final double ratio = size.width / size.height;
    if ((ratio - 1).abs() <= 0.05) return DVScreenShape.square;
    return ratio > 1
        ? DVScreenShape.horizontalRectangle
        : DVScreenShape.verticalRectangle;
  }

  /// Safe areas in the map shape `DV.Platform.screen.safeAreaBounds` uses.
  Map<String, double> get safeAreaBounds => <String, double>{
        'top': safeArea.top,
        'bottom': safeArea.bottom,
        'left': safeArea.left,
        'right': safeArea.right,
      };

  /// Picks the value for the current breakpoint.
  ///
  /// Only [mobile] is required, and larger breakpoints fall back down the
  /// ladder to it. Falling *down* rather than up is deliberate: an unset
  /// tablet value takes the phone's, because laying a phone-sized column out
  /// with desktop measurements is what overflows, while the reverse merely
  /// looks roomy.
  T value<T>({required T mobile, T? tablet, T? desktop, T? wide}) {
    switch (breakpoint) {
      case DVBreakpoint.wide:
        return wide ?? desktop ?? tablet ?? mobile;
      case DVBreakpoint.desktop:
        return desktop ?? tablet ?? mobile;
      case DVBreakpoint.tablet:
        return tablet ?? mobile;
      case DVBreakpoint.mobile:
        return mobile;
    }
  }
}

/// `context.screen` -- the reactive screen surface.
extension DVScreenContextX on BuildContext {
  /// What the surface this widget is being built on looks like.
  ///
  /// Every field is read through a targeted MediaQuery aspect, so the widget
  /// depends on size, padding, orientation, animation and text-scale changes
  /// and is rebuilt when they change. View insets are deliberately not among
  /// them: depending on the keyboard would rebuild every widget on a page the
  /// moment a field is focused, which is a heavy default for a value most
  /// layouts never read.
  DVScreenInfo get screen => DVScreenInfo(
        size: MediaQuery.sizeOf(this),
        safeArea: MediaQuery.paddingOf(this),
        orientation: MediaQuery.orientationOf(this),
        reducedMotion: MediaQuery.disableAnimationsOf(this) ||
            const DVAccessibility().reducedMotion,
        textScale: MediaQuery.textScalerOf(this).scale(1),
      );
}

class DVScreen {
  final DVPlatform _platform;
  const DVScreen(this._platform);

  Size get size => Size(_platform.screenWidth, _platform.screenHeight);
  Map<String, double> get safeAreaBounds => _platform.safeAreas;
  String get breakPoints => _platform.breakpoint;
  String get shape => _platform.screenShape;
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

/// What a dual-mode application should do at startup.
///
/// Returned rather than performed: the prompt is an outcome the caller acts
/// on, which keeps every branch testable without a TTY and keeps the policy in
/// one readable place instead of spread through a main().
enum DVLaunchOutcome {
  gui,
  terminal,

  /// Offer the terminal and let the person decide. See
  /// [dvTerminalFallbackPrompt].
  askToUseTerminal,
}

/// What the application says when it has no display but can use a terminal.
///
/// The wording is part of the feature. A prompt nobody understands is a worse
/// outcome than either silent answer, so it names what is missing, what is on
/// offer, and which way Enter goes.
const String dvTerminalFallbackPrompt =
    'No display server is available.\n'
    'This app can run in your terminal instead. Continue in TUI mode? [Y/n]';

/// Decides where a launch should start.
///
/// [linked] is what the build actually contains — resolved at build time from
/// the `-cli`/`-tui` suffix or a `dartvel.terminal` opt-in, never probed here.
///
/// The rules, in order:
///
/// 1. One backend means no decision. A GUI-only build starts the GUI and fails
///    to find a display exactly as it does today; an application that opted
///    into nothing gains no prompt, no flag and no branch.
/// 2. `--tui` starts the terminal. The explicit path, and the one to reach for
///    over SSH.
/// 3. A display means the GUI. A terminal is where the command was typed, not
///    necessarily where the application belongs.
/// 4. No display, and someone is there to answer: ask. Both silent answers are
///    wrong — quietly redrawing as text is indistinguishable from a bug at the
///    moment it happens, and failing outright wastes a capability the
///    application was built with.
/// 5. No display and nobody to ask: take the terminal. A prompt with no human
///    at the other end is a hang, and the terminal is the only surface that
///    can work.
DVLaunchOutcome resolveLaunchSurface({
  required Set<DVRenderSurface> linked,
  required List<String> arguments,
  required bool displayAvailable,
  bool interactive = true,
}) {
  if (linked.isEmpty) {
    throw ArgumentError.value(
      linked,
      'linked',
      'A build must contain at least one rendering backend. An empty set is a '
          'build configuration error, not a runtime condition.',
    );
  }

  final hasTerminal = linked.contains(DVRenderSurface.terminal);
  final hasGui = linked.contains(DVRenderSurface.gui);

  if (!hasTerminal) return DVLaunchOutcome.gui;
  if (!hasGui) return DVLaunchOutcome.terminal;

  if (arguments.contains('--tui')) return DVLaunchOutcome.terminal;
  if (displayAvailable) return DVLaunchOutcome.gui;
  return interactive
      ? DVLaunchOutcome.askToUseTerminal
      : DVLaunchOutcome.terminal;
}

/// Where an application's frames are landing.
///
/// Decided at build time from what was linked — the `-cli`/`-tui` suffix or a
/// `dartvel.terminal` opt-in — and never by probing at startup. Probing would
/// make the presentation a runtime question, which is exactly what would force
/// every application to ship both backends.
enum DVRenderSurface { gui, terminal }

/// How faithfully a terminal can draw.
///
/// Kitty's graphics protocol carries real pixels; ANSI carries cells and is
/// coarser. Which one is active is reported rather than inferred from a
/// terminal's name, because the name is a poor predictor and a wrong guess
/// changes what a layout can reasonably draw.
enum DVTerminalGraphics { kitty, ansi }

/// The terminal an application is drawing into.
///
/// Null whenever the surface is a GUI: asking a window for its column count is
/// a question with no answer, and a fabricated one would be worse than none.
class DVTerminalSurface {
  const DVTerminalSurface({
    required this.columns,
    required this.rows,
    required this.graphics,
  });

  final int columns;
  final int rows;
  final DVTerminalGraphics graphics;

  @override
  String toString() =>
      'DVTerminalSurface(${columns}x$rows, ${graphics.name})';
}

class DVPlatform {
  const DVPlatform();

  static DVRenderSurface? _surfaceOverride;
  static DVTerminalSurface? _terminal;

  /// Where this application's frames are landing.
  ///
  /// The GUI unless a terminal backend was linked and installed itself at
  /// startup. An application that opted into nothing sees exactly what it
  /// always saw.
  DVRenderSurface get surface => _surfaceOverride ?? DVRenderSurface.gui;

  /// The terminal being drawn into, or null when this is a GUI.
  DVTerminalSurface? get terminal =>
      surface == DVRenderSurface.terminal ? _terminal : null;

  /// Installs the surface the runtime actually started on.
  ///
  /// Called by the terminal backend during startup, and by tests. Passing null
  /// restores the default. Setting a GUI surface clears any terminal details,
  /// so a stale terminal can never end up describing a window.
  void useRenderSurface(
    DVRenderSurface? surface, {
    DVTerminalSurface? terminal,
  }) {
    _surfaceOverride = surface;
    _terminal = surface == DVRenderSurface.terminal ? terminal : null;
  }

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
  /// Both spellings, because the build reports `tvos` and this getter has
  /// always compared against `appletv` — a value nothing produced, so it was
  /// never true on an actual Apple TV.
  bool get isAppleTV =>
      currentPlatform == 'appletv' || currentPlatform == 'tvos';
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
    return dvDeviceTypeFor(
      platform: currentPlatform,
      breakpoint: breakpoint,
      isTV: isTV,
      isWatch: isWatch,
      isWeb: isWeb,
      isFoldable: isFoldable,
    );
  }

  String get screenShape => isWatch ? 'round' : 'rectangle';
  String get type => deviceType;
  Orientation get deviceOrientation => orientation;
  DVScreen get screen => DVScreen(this);
  DVWindowManager get Window => DVWindowManager(this);
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

  /// The PWA install prompt, where the platform offers one.
  DVInstall get install => const DVInstall();
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
  /// Installs [capability] as the windowing capability for this test.
  ///
  /// Explicit on purpose. Without it a test asserting that a route presents as
  /// a page passes on a CI runner for the wrong reason: not because the
  /// degradation logic works, but because nothing registered `window.open` and
  /// the capability was false anyway -- the same assertion would pass with
  /// that logic deleted.
  ///
  /// Replaces detection rather than merging with it, so what a test declares
  /// is all it gets. Cleared by [DVWindowManager.reset], which a test should
  /// call in tearDown: a capability that survived would make the next test
  /// pass or fail on this one's setup.
  void fakeWindowing(DVWindowingCapability capability) {
    DVWindowManager.capabilityOverride = capability;
  }

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
    const DVDatabase().unconfigure();
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

/// A held cache lock. Release it when the guarded work completes.
class DVCacheLock {
  final String _key;
  final String _token;
  final DVCacheAdapter _adapter;
  bool _released = false;

  DVCacheLock._(this._key, this._token, this._adapter);

  /// Releases the lock, but only if this holder still owns it — a lock that
  /// expired and was re-acquired by someone else must not be torn down by the
  /// previous owner.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    final current = await _adapter.read(_key);
    if (current == _token) await _adapter.remove(_key);
  }
}

class DVCache {
  const DVCache();
  static DVCacheAdapter _adapter = DVMemoryCacheAdapter();
  static DVCacheAdapter? _globalAdapter;
  static const DVCacheTags _tags = DVCacheTags();
  static const DVCacheTags _globalTags = DVCacheTags();

  /// In-flight computations, so concurrent callers of the same key share one
  /// compute instead of stampeding it.
  static final Map<String, Future<Object?>> _inFlight = {};

  /// Swaps the storage behind the cache. Defaults to [DVMemoryCacheAdapter];
  /// pass a [DVDatabaseCacheAdapter] to persist entries across restarts.
  void configure(DVCacheAdapter adapter) {
    _adapter = adapter;
  }

  /// Configures the backend/global cache used by the `global*` helpers.
  void configureGlobal(DVCacheAdapter adapter) {
    _globalAdapter = adapter;
  }

  DVCacheAdapter get adapter => _adapter;

  static DVCacheAdapter get _global {
    final adapter = _globalAdapter;
    if (adapter == null) {
      throw StateError(
        'No global cache is configured. Call DV.Cache.configureGlobal(...) '
        'with the backend/shared cache adapter before using the global '
        'helpers.',
      );
    }
    return adapter;
  }

  /// Scopes [key] to the current tenant, so tenants cannot read each other's
  /// entries through a shared adapter. The default tenant stays unprefixed:
  /// single-tenant applications keep plain keys.
  static String _scoped(String key) {
    final tenant = const DVTenants().currentTenant;
    return tenant == DVTenants.defaultTenant ? key : 'tenant:$tenant:$key';
  }

  Future<T?> get<T>(String key) async {
    final value = await _adapter.read(_scoped(key));
    return value is T ? value : null;
  }

  Future<void> set(String key, Object? value, [Duration? ttl]) =>
      _adapter.write(_scoped(key), value, ttl);

  Future<void> delete(String key) => _adapter.remove(_scoped(key));

  // --- global (backend/shared) cache ---------------------------------------

  Future<T?> globalGet<T>(String key) async {
    final value = await _global.read(_scoped(key));
    return value is T ? value : null;
  }

  Future<void> globalSet(String key, Object? value, [Duration? ttl]) =>
      _global.write(_scoped(key), value, ttl);

  Future<void> globalDelete(String key) => _global.remove(_scoped(key));

  void globalTag(String key, Iterable<String> tags) {
    _globalTags.tag(_scoped(key), tags);
  }

  Future<Set<String>> globalRevalidateTag(String tag) async {
    final keys = _globalTags.revalidateTag(tag);
    for (final key in keys) {
      await _global.remove(key);
    }
    return keys;
  }

  // --- locks and stampede protection ---------------------------------------

  /// Tries to take the lock named [key] for [ttl]. Returns null when another
  /// holder has it.
  ///
  /// The TTL bounds how long a crashed holder can wedge the lock. Acquisition
  /// is atomic only as far as the adapter is: in-memory and SQLite adapters
  /// serve one process, which is; a distributed adapter must provide
  /// compare-and-set before its locks mean anything, as the spec requires.
  Future<DVCacheLock?> lock(
    String key, {
    Duration ttl = const Duration(seconds: 30),
  }) async {
    final lockKey = _scoped('lock:$key');
    final token =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final adapter = _adapter;
    if (adapter is DVAtomicCacheAdapter) {
      // The adapter offers real compare-and-set (Redis SET NX); use it.
      final acquired = await (adapter as DVAtomicCacheAdapter)
          .writeIfAbsent(lockKey, token, ttl);
      return acquired ? DVCacheLock._(lockKey, token, adapter) : null;
    }
    final existing = await adapter.read(lockKey);
    if (existing != null) return null;
    await adapter.write(lockKey, token, ttl);
    // Read back: if two acquirers raced, exactly one token survived the
    // second write and only its owner proceeds.
    final winner = await adapter.read(lockKey);
    if (winner != token) return null;
    return DVCacheLock._(lockKey, token, adapter);
  }

  /// Returns the cached value for [key], computing and storing it on a miss.
  ///
  /// Concurrent callers of the same key share one [compute] — the stampede a
  /// cold cache otherwise sends at an expensive query.
  Future<T> remember<T>(
    String key,
    Duration? ttl,
    Future<T> Function() compute,
  ) async {
    final scoped = _scoped(key);
    final cached = await _adapter.read(scoped);
    if (cached is T && cached != null) return cached;

    final pending = _inFlight[scoped];
    if (pending != null) return await pending as T;

    final future = () async {
      try {
        final value = await compute();
        await _adapter.write(scoped, value, ttl);
        return value as Object?;
      } finally {
        // The removed value is this very future; nothing awaits it here.
        _inFlight.remove(scoped)?.ignore();
      }
    }();
    _inFlight[scoped] = future;
    return await future as T;
  }

  /// Stale-while-revalidate: a value older than [ttl] but within [staleFor]
  /// is returned immediately while one background [compute] refreshes it.
  ///
  /// The entry lives in the adapter for `ttl + staleFor`; freshness is this
  /// wrapper's bookkeeping, since adapters treat expiry as absence.
  Future<T> staleWhileRevalidate<T>(
    String key, {
    required Duration ttl,
    Duration staleFor = const Duration(minutes: 5),
    required Future<T> Function() compute,
  }) async {
    final scoped = _scoped('swr:$key');

    Future<T> refresh() async {
      final pending = _inFlight[scoped];
      if (pending != null) {
        final entry = await pending;
        return (entry! as Map)['v'] as T;
      }
      final future = () async {
        try {
          final value = await compute();
          final entry = <String, Object?>{
            'v': value,
            'freshUntil':
                DateTime.now().add(ttl).millisecondsSinceEpoch,
          };
          await _adapter.write(scoped, entry, ttl + staleFor);
          return entry as Object?;
        } finally {
          // The removed value is this very future; nothing awaits it here.
          _inFlight.remove(scoped)?.ignore();
        }
      }();
      _inFlight[scoped] = future;
      final entry = await future;
      return (entry! as Map)['v'] as T;
    }

    final raw = await _adapter.read(scoped);
    if (raw is! Map) return refresh();

    final freshUntil = raw['freshUntil'];
    final stale = freshUntil is int &&
        DateTime.now().millisecondsSinceEpoch >= freshUntil;
    if (stale) {
      // Serve the stale value now; exactly one refresh runs behind it.
      unawaited(refresh());
    }
    return raw['v'] as T;
  }

  /// Drops every entry. Tag associations are cleared with it.
  Future<void> clear() async {
    await _adapter.clear();
    _tags.clear();
  }

  /// Removes entries whose TTL has elapsed, reclaiming storage. Reads already
  /// ignore expired entries, so this is housekeeping rather than correctness.
  Future<int> purgeExpired() => _adapter.purgeExpired();

  void tag(String key, Iterable<String> tags) {
    // Tags record the scoped key: revalidation removes exactly the entries
    // the tenant that tagged them can see.
    _tags.tag(_scoped(key), tags);
  }

  Set<String> keysForTag(String tag) {
    return _tags.keysForTag(tag);
  }

  /// Every tag that currently has keys under it.
  Set<String> get tags => _tags.tags;

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
  static DVTenants get Tenants => const DVTenants();

  /// Alias for `DV.Tenants.currentTenant`, as the spec defines it. Both read
  /// and write the same state, so setting one is visible through the other.
  static String get currentTenant => Tenants.currentTenant;
  static set currentTenant(String tenant) {
    Tenants.currentTenant = tenant;
  }

  /// Runs [callback] within the dynamic multi-tenant context of [tenant].
  static R withTenant<R>(String tenant, R Function() callback) =>
      Tenants.withTenant(tenant, callback);

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
  /// A callback that navigates to [target] when called.
  ///
  /// Built for the position it is usually written in --
  /// `onPressed: DV.Navigation.to(target)` -- where the handler wants a
  /// callback rather than a call.
  ///
  /// It does not navigate by itself, and that is the trap. Written as
  /// `onTap: () => DV.Navigation.to(target)` it compiles, runs, discards the
  /// callback it built and goes nowhere. The dartvel.dev header shipped
  /// exactly that: links that looked right and did nothing.
  ///
  /// `@useResult` makes the analyzer say so, so the next one is caught at the
  /// keyboard rather than in a browser. Use [navigate] where you want the
  /// call itself to move.
  @useResult
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

  /// Explicit JSON-LD structured data. When null, [structuredDataJson]
  /// derives a schema.org WebPage from the other properties.
  final Map<String, Object?>? structuredData;

  const SeoProps({
    this.title,
    this.description,
    this.canonicalUrl,
    this.imageUrl,
    this.siteName,
    this.twitterHandle,
    this.extraMeta = const {},
    this.structuredData,
  });

  SeoProps merge(SeoProps other) => SeoProps(
        title: other.title ?? title,
        description: other.description ?? description,
        canonicalUrl: other.canonicalUrl ?? canonicalUrl,
        imageUrl: other.imageUrl ?? imageUrl,
        siteName: other.siteName ?? siteName,
        twitterHandle: other.twitterHandle ?? twitterHandle,
        extraMeta: {...extraMeta, ...other.extraMeta},
        structuredData: other.structuredData ?? structuredData,
      );

  /// The JSON-LD document for this page, or null when there is nothing to
  /// say. Explicit [structuredData] wins (with `@context` filled in when
  /// omitted); otherwise a schema.org WebPage derives from the properties
  /// the page already declares — the spec's "structured data and content
  /// schema" without per-page authoring.
  String? structuredDataJson() {
    final explicit = structuredData;
    if (explicit != null) {
      return jsonEncode(<String, Object?>{
        '@context': 'https://schema.org',
        ...explicit,
      });
    }
    if (title == null && description == null && canonicalUrl == null) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      if (title != null) 'name': title,
      if (description != null) 'description': description,
      if (canonicalUrl != null) 'url': canonicalUrl,
      if (imageUrl != null) 'image': imageUrl,
      if (siteName != null)
        'isPartOf': <String, Object?>{
          '@type': 'WebSite',
          'name': siteName,
        },
    });
  }

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

/// Every generated page's cached deferred-library future, so a test can drop
/// them all.
///
/// A generated page caches `loadLibrary()` in a static, which is right in
/// production -- the library is loaded once. In a widget test each case runs
/// in its own FakeAsync zone, so the future cached by the first test has its
/// completion callbacks scheduled in a zone that no longer exists. Every later
/// test then subscribes to a future that never delivers, the page sits on its
/// loading state, and the failure reads as "this page renders nothing" rather
/// than as a stale cache.
///
/// The first test passes and every one after it fails, which is the most
/// misleading shape a test failure has.
final List<void Function()> _dvDeferredPageResets = <void Function()>[];

/// Registers [reset], returning a function that unregisters it.
///
/// Generated pages call this; application code calls [dvResetDeferredPages].
void Function() dvRegisterDeferredPageReset(void Function() reset) {
  _dvDeferredPageResets.add(reset);
  return () => _dvDeferredPageResets.remove(reset);
}

/// Drops every generated page's cached library future.
///
/// Call it in a test `setUp` when widget-testing more than one generated page.
void dvResetDeferredPages() {
  // Over a copy: a reset that unregisters itself would otherwise mutate the
  // list being walked.
  for (final void Function() reset
      in List<void Function()>.of(_dvDeferredPageResets)) {
    reset();
  }
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

  /// Whether the page's text can be selected.
  ///
  /// True, because a page whose text cannot be copied is a defect rather than
  /// a style: on a website the install command is the one thing a visitor
  /// needs off the page. Flutter has a widget for this and not using it was
  /// the bug.
  ///
  /// An app with its own drag gestures over text has reason to turn it off,
  /// which is why the escape hatch exists.
  final bool selectable;

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
    this.selectable = true,
  });
}

class DVPageShell extends StatefulWidget {
  final DVPageScaffoldSpec spec;
  final Widget child;

  const DVPageShell({
    super.key,
    required this.spec,
    required this.child,
  });

  @override
  State<DVPageShell> createState() => _DVPageShellState();
}

class _DVPageShellState extends State<DVPageShell> {
  /// The selection area's focus node, kept out of the tab order.
  final FocusNode _selectionFocusNode =
      FocusNode(skipTraversal: true, debugLabel: 'DVPageShell selection');

  DVPageScaffoldSpec get spec => widget.spec;
  Widget get child => widget.child;

  @override
  void dispose() {
    _selectionFocusNode.dispose();
    super.dispose();
  }

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
        // showAppBar alone. The title is what the browser tab and the SEO
        // head use, so every page has one; treating it as a request for a
        // bar meant showAppBar: false never took effect, and the site shipped
        // with a grey strip above its own header.
        navigationBar: spec.showAppBar
            ? CupertinoNavigationBar(
                middle: spec.title == null ? null : DVText(spec.title!),
                backgroundColor: _color(spec.appBarBackgroundColor),
              )
            : null,
        // CupertinoPageScaffold provides no Material, and on Material it is
        // Material that establishes the DefaultTextStyle. Without one, every
        // DVText under this shell falls back to Flutter's built-in default —
        // oversized, with the yellow double underline it uses to say there is
        // no text style here.
        //
        // It shipped that way on macOS, iOS and tvOS because nothing rendered
        // on an Apple platform until the runtime-verification screenshots.
        // Material's widgets assert a Material ancestor, and
        // CupertinoPageScaffold is not one. Dartvel's own primitives are
        // built on several of them -- a DVModifier input is a TextField --
        // so without this a page carrying a form threw "No Material widget
        // found" before its first frame on macOS, iOS and tvOS, while
        // working everywhere else.
        //
        // Transparency rather than a surface: this supplies the ancestor
        // those widgets look for without painting anything over the
        // Cupertino background.
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: _body(child),
          ),
        ),
      );
    }

    return Scaffold(
      // showAppBar alone; see the Cupertino branch above. The condition was
      // duplicated, so the bug was too.
      appBar: spec.showAppBar
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
    // Inside the safe area, not outside it: a SelectionArea above would let a
    // drag begin in the notch or over the home indicator.
    final content = spec.selectable
        ? SelectionArea(
            // skipTraversal, because a SelectionArea is focusable and would
            // otherwise take the first tab stop on every page: the first Tab
            // went to the page instead of the first link, and every
            // subsequent one was off by one. It still takes focus when a
            // selection starts; it is simply not somewhere Tab stops.
            focusNode: _selectionFocusNode,
            child: body,
          )
        : body;
    return spec.safeArea ? SafeArea(child: content) : content;
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

  /// The tag as a [Locale].
  ///
  /// Delegates rather than parsing again: this had its own copy, so the same
  /// tag could resolve one way here and another through [DvI18n].
  Locale get locale => DvI18n.parseLocale(localeTag);

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

/// A translation key, typed rather than a bare string.
///
/// No `==` override, and that is load-bearing rather than an omission. Dart
/// refuses a key without primitive equality in a const map -- "does not have a
/// primitive equality" -- so overriding it made the catalogue shape the spec
/// documents impossible to write:
///
///     const DVTranslationCatalog(
///       messages: <DVTranslationKey, String>{AppText.settingsTitle: '...'},
///     )
///
/// Const instances canonicalise, so two `const DVTranslationKey('a')` are
/// identical and compare equal anyway. Keys built at runtime are matched by
/// value instead, because the catalogue is indexed by [value] when it is
/// loaded rather than looked up by object.
class DVTranslationKey {
  final String value;

  const DVTranslationKey(this.value);

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

/// The plural forms a message has, in one language.
///
/// The CLDR categories, not English's. This used to offer zero/one/other and
/// select with `count == 1`, so every catalogue was really an English
/// catalogue: a French app rendered "0 messages" where French writes "0
/// message", and Polish -- which needs one, few and many chosen by the last
/// one or two digits -- could not be written correctly at all.
class DVPluralForms {
  /// An explicit override for "no messages", not a CLDR category in most
  /// languages. Left unset, 0 takes whatever the language's rule says.
  final String zero;

  final String one;
  final String two;
  final String few;
  final String many;
  final String other;

  const DVPluralForms({
    required this.other,
    this.zero = '',
    this.one = '',
    this.two = '',
    this.few = '',
    this.many = '',
  });

  /// The form for [count] in [locale].
  ///
  /// Falls back to [other] when the catalogue has no string for the category
  /// the language selected. A Polish catalogue written before anyone knew
  /// about `few` should read awkwardly rather than render nothing --
  /// [missingFor] is how a build finds that instead.
  String select(num count, {String locale = 'en'}) {
    // Checked before the language rule, because it is an override rather than
    // a category: "no messages" is a nicer English string than "0 messages",
    // and a catalogue that asks for it means it.
    if (count == 0 && zero.isNotEmpty) return zero;

    final DVPluralCategory category =
        dvPluralCategory(locale: locale, count: count);

    final String selected = switch (category) {
      DVPluralCategory.zero => zero,
      DVPluralCategory.one => one,
      DVPluralCategory.two => two,
      DVPluralCategory.few => few,
      DVPluralCategory.many => many,
      DVPluralCategory.other => other,
    };
    return selected.isNotEmpty ? selected : other;
  }

  /// The categories [locale] needs that this catalogue does not provide.
  ///
  /// So strict mode can fail a build rather than shipping a Polish string that
  /// silently reads as the wrong word on most numbers.
  Set<DVPluralCategory> missingFor(String locale) {
    final Set<DVPluralCategory> missing = <DVPluralCategory>{};
    for (final DVPluralCategory category in dvPluralCategoriesFor(locale)) {
      final String form = switch (category) {
        DVPluralCategory.zero => zero,
        DVPluralCategory.one => one,
        DVPluralCategory.two => two,
        DVPluralCategory.few => few,
        DVPluralCategory.many => many,
        DVPluralCategory.other => other,
      };
      // `other` is required by the constructor, so it is never missing; every
      // language uses it, and reporting it would make every catalogue look
      // incomplete.
      if (form.isEmpty && category != DVPluralCategory.other) {
        missing.add(category);
      }
    }
    return missing;
  }
}

class DVI18n {
  static LocaleTag _currentLocale = LocaleTag.enUS;

  /// Indexed by the key's string, not by the key object.
  ///
  /// DVTranslationKey has no `==` override, so two instances with the same
  /// string are equal only when both are const. Indexing by value means a key
  /// read from a config file or a database column resolves like a generated
  /// one, instead of silently missing every lookup and rendering its own name.
  static final Map<String, Map<String, String>> _messages =
      <String, Map<String, String>>{};
  static final Map<String, Map<String, DVPluralForms>> _plurals =
      <String, Map<String, DVPluralForms>>{};

  const DVI18n();

  LocaleTag get currentLocale => _currentLocale;

  TextDirection get textDirection =>
      _currentLocale.isRightToLeft ? TextDirection.rtl : TextDirection.ltr;

  void useLocale(LocaleTag locale) {
    _currentLocale = locale;
  }

  void load(DVTranslationCatalog catalog) {
    _messages[catalog.locale.value] = <String, String>{
      for (final MapEntry<DVTranslationKey, String> entry
          in catalog.messages.entries)
        entry.key.value: entry.value,
    };
    _plurals[catalog.locale.value] = <String, DVPluralForms>{
      for (final MapEntry<DVTranslationKey, DVPluralForms> entry
          in catalog.plurals.entries)
        entry.key.value: entry.value,
    };
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
    final template = _messages[selected.value]?[key.value];
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
    final forms = _plurals[selected.value]?[key.value];
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
    // The locale goes in, or the CLDR rules cannot be applied and every
    // catalogue falls back to English's one/other.
    return _interpolate(
      forms.select(count, locale: selected.value),
      pluralArgs,
    );
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
    _messages.clear();
    _plurals.clear();
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
  /// Null means "no application override", not "off".
  ///
  /// This used to be a plain `false`, which made the getter report that the
  /// reader wanted motion unless the application had remembered to say
  /// otherwise -- so an operating-system reduce-motion setting was ignored by
  /// every app that did not explicitly wire it up. The platform is the source
  /// of truth; an application may override it, and can now take that override
  /// back off again.
  static bool? _reducedMotionOverride;

  const DVAccessibility();

  bool get reducedMotion =>
      _reducedMotionOverride ??
      ui.PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  void useReducedMotion(bool value) {
    _reducedMotionOverride = value;
  }

  /// Drops the override and goes back to following the platform.
  void clearReducedMotion() {
    _reducedMotionOverride = null;
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

  /// A BCP 47 language tag as a [Locale].
  ///
  /// The subtag after the language is not always a region. Four letters make
  /// it a script -- `zh-Hant`, `sr-Latn` -- while a region is two letters or
  /// three digits. Reading a script as a region produces a locale whose
  /// country code is `Hant`, which throws nothing and quietly fails to match
  /// any supported locale, so the app falls back to its default language
  /// looking as though it resolved one.
  ///
  /// Case is normalised to the conventional spelling because Flutter compares
  /// locales by exact subtag, so `en-us` has to land where `en-US` does.
  static Locale parseLocale(String tag) {
    final parts = tag
        .replaceAll('_', '-')
        .split('-')
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const Locale('en');

    final language = parts.first.toLowerCase();
    String? script;
    String? country;

    for (final String part in parts.skip(1)) {
      if (script == null && part.length == 4 && _isAlpha(part)) {
        script = '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      } else if (country == null &&
          ((part.length == 2 && _isAlpha(part)) ||
              (part.length == 3 && _isDigits(part)))) {
        country = part.toUpperCase();
      }
      // Anything else is a variant or extension, which a Locale cannot hold.
    }

    if (script == null && country == null) return Locale(language);
    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static bool _isAlpha(String value) =>
      value.codeUnits.every((int unit) =>
          (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A));

  static bool _isDigits(String value) =>
      value.codeUnits.every((int unit) => unit >= 0x30 && unit <= 0x39);

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


/// Desktop operating systems, where the machine is a desktop whatever size its
/// window is.
const Set<String> _dvDesktopPlatforms = <String>{'linux', 'macos', 'windows'};

/// Platforms that are televisions, whatever their screen reports.
///
/// A 4K television is wide, so a width-derived answer calls it a desktop — or,
/// on tvOS, a tablet. It is neither: it is driven by a remote control, and an
/// application that takes the touch path there has no focus traversal and tap
/// targets sized for fingers.
///
/// `appletv` is here as well as `tvos` because the platform getters compare
/// against that spelling. Nothing ever produced it, which is part of why a
/// tvOS build reported itself as an iOS tablet.
const Set<String> _dvTelevisionPlatforms = <String>{
  'tvos',
  'appletv',
  'androidtv',
  'tizen',
  'webos',
  'fireos',
};

/// What kind of device this is.
///
/// Separated from [DVPlatform] so it can be asserted on directly, and because
/// getting it wrong is invisible until an application takes a layout branch on
/// the wrong platform.
///
/// It used to answer from [breakpoint] alone, which meant the same desktop
/// application reported a different device depending on how wide its window
/// was. Running the example on two platforms and comparing the screenshots
/// showed it plainly: Linux at 1280px said `desktop`, Windows at 1024px said
/// `tablet`. Same framework, same app, same class of machine — the only
/// difference was the window, and anything branching on the result took the
/// tablet path on Windows.
///
/// Width is the right input for *layout*, which is what [breakpoint] remains
/// for and which is unchanged. It is the wrong input for what the device is.
String dvDeviceTypeFor({
  required String platform,
  required String breakpoint,
  bool isTV = false,
  bool isWatch = false,
  bool isWeb = false,
  bool isFoldable = false,
}) {
  // The explicit kinds first: a television is a television at any width, and
  // calling it a desktop would send an application down the pointer-and-window
  // path on a device driven by a remote control.
  if (isTV || _dvTelevisionPlatforms.contains(platform)) return 'tv';
  if (isWatch) return 'watch';
  if (isWeb) return 'web';

  // The platform, before the window. A desktop OS is a desktop however narrow
  // the window has been dragged.
  if (_dvDesktopPlatforms.contains(platform)) return 'desktop';

  // On a mobile OS the screen genuinely is the signal, because the same system
  // runs on both phones and tablets.
  if (breakpoint == 'desktop' || breakpoint == 'tablet') return 'tablet';
  if (isFoldable) return 'foldable';
  return 'phone';
}

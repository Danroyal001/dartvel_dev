import 'package:meta/meta.dart';

/// Global application settings managed through Studio.
@immutable
class DVStudioSettings {
  final String siteTitle;
  final String tagline;
  final String siteUrl;
  final String timezone;
  final String dateFormat;
  final String? favicon;
  final String? defaultSeoTitle;
  final String? defaultSeoDescription;
  final String? defaultSeoImage;
  final Map<String, String> socialLinks;
  final bool maintenanceMode;
  final String? maintenanceMessage;
  final DateTime? updatedAt;

  const DVStudioSettings({
    this.siteTitle = '',
    this.tagline = '',
    this.siteUrl = '',
    this.timezone = 'UTC',
    this.dateFormat = 'YYYY-MM-DD',
    this.favicon,
    this.defaultSeoTitle,
    this.defaultSeoDescription,
    this.defaultSeoImage,
    this.socialLinks = const <String, String>{},
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.updatedAt,
  });

  factory DVStudioSettings.fromJson(Map<String, Object?> json) {
    final Map<String, String> social = <String, String>{};
    final Object? rawSocial = json['socialLinks'];
    if (rawSocial is Map) {
      for (final MapEntry<Object?, Object?> entry in rawSocial.entries) {
        if (entry.key != null && entry.value != null) {
          social['${entry.key}'] = '${entry.value}';
        }
      }
    }

    DateTime? updated;
    final Object? rawUpdated = json['updatedAt'];
    if (rawUpdated is String && rawUpdated.isNotEmpty) {
      updated = DateTime.tryParse(rawUpdated)?.toUtc();
    }

    return DVStudioSettings(
      siteTitle: (json['siteTitle'] as String?)?.trim().isNotEmpty == true
          ? (json['siteTitle'] as String).trim()
          : '',
      tagline: (json['tagline'] as String?)?.trim() ?? '',
      siteUrl: (json['siteUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['siteUrl'] as String).trim()
          : '',
      timezone: (json['timezone'] as String?)?.trim().isNotEmpty == true
          ? (json['timezone'] as String).trim()
          : 'UTC',
      dateFormat: (json['dateFormat'] as String?)?.trim().isNotEmpty == true
          ? (json['dateFormat'] as String).trim()
          : 'YYYY-MM-DD',
      favicon: (json['favicon'] as String?)?.trim(),
      defaultSeoTitle: (json['defaultSeoTitle'] as String?)?.trim(),
      defaultSeoDescription: (json['defaultSeoDescription'] as String?)?.trim(),
      defaultSeoImage: (json['defaultSeoImage'] as String?)?.trim(),
      socialLinks: social,
      maintenanceMode: json['maintenanceMode'] == true,
      maintenanceMessage: (json['maintenanceMessage'] as String?)?.trim(),
      updatedAt: updated,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'siteTitle': siteTitle,
        'tagline': tagline,
        'siteUrl': siteUrl,
        'timezone': timezone,
        'dateFormat': dateFormat,
        if (favicon != null && favicon!.isNotEmpty) 'favicon': favicon,
        if (defaultSeoTitle != null && defaultSeoTitle!.isNotEmpty)
          'defaultSeoTitle': defaultSeoTitle,
        if (defaultSeoDescription != null && defaultSeoDescription!.isNotEmpty)
          'defaultSeoDescription': defaultSeoDescription,
        if (defaultSeoImage != null && defaultSeoImage!.isNotEmpty)
          'defaultSeoImage': defaultSeoImage,
        'socialLinks': socialLinks,
        'maintenanceMode': maintenanceMode,
        if (maintenanceMessage != null && maintenanceMessage!.isNotEmpty)
          'maintenanceMessage': maintenanceMessage,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  DVStudioSettings copyWith({
    String? siteTitle,
    String? tagline,
    String? siteUrl,
    String? timezone,
    String? dateFormat,
    String? favicon,
    String? defaultSeoTitle,
    String? defaultSeoDescription,
    String? defaultSeoImage,
    Map<String, String>? socialLinks,
    bool? maintenanceMode,
    String? maintenanceMessage,
    DateTime? updatedAt,
  }) {
    return DVStudioSettings(
      siteTitle: siteTitle ?? this.siteTitle,
      tagline: tagline ?? this.tagline,
      siteUrl: siteUrl ?? this.siteUrl,
      timezone: timezone ?? this.timezone,
      dateFormat: dateFormat ?? this.dateFormat,
      favicon: favicon ?? this.favicon,
      defaultSeoTitle: defaultSeoTitle ?? this.defaultSeoTitle,
      defaultSeoDescription:
          defaultSeoDescription ?? this.defaultSeoDescription,
      defaultSeoImage: defaultSeoImage ?? this.defaultSeoImage,
      socialLinks: socialLinks ?? this.socialLinks,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DVStudioSettings &&
          runtimeType == other.runtimeType &&
          siteTitle == other.siteTitle &&
          tagline == other.tagline &&
          siteUrl == other.siteUrl &&
          timezone == other.timezone &&
          dateFormat == other.dateFormat &&
          favicon == other.favicon &&
          defaultSeoTitle == other.defaultSeoTitle &&
          defaultSeoDescription == other.defaultSeoDescription &&
          defaultSeoImage == other.defaultSeoImage &&
          maintenanceMode == other.maintenanceMode &&
          maintenanceMessage == other.maintenanceMessage &&
          _sameLinks(socialLinks, other.socialLinks);

  /// Whether [a] and [b] hold the same links. Without this, settings that
  /// differ only in their social links compared equal, so an edit to them
  /// alone was never seen as a change to save.
  static bool _sameLinks(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry<String, String> link in a.entries) {
      if (b[link.key] != link.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        siteTitle,
        tagline,
        siteUrl,
        timezone,
        dateFormat,
        favicon,
        defaultSeoTitle,
        defaultSeoDescription,
        defaultSeoImage,
        maintenanceMode,
        maintenanceMessage,
      );
}

/// The settings of a project nobody has configured yet: nothing of anybody
/// else's. No title, tagline, address or SEO copy, no social links, UTC, and a
/// maintenance message that names no product.
DVStudioSettings dvStudioDefaultSettings() => const DVStudioSettings(
      maintenanceMessage:
          'This site is undergoing scheduled maintenance. Please check back shortly.',
    );

import 'dart:async' show unawaited;

import 'package:dartvel_core/dartvel.dart' show DVStudioSettings;
import 'package:flutter/material.dart';

import 'studio_server.dart' show DVStudioClient;
import 'studio_style.dart';

/// The global application settings section in Studio.
class DVStudioSettingsSection extends StatefulWidget {
  const DVStudioSettingsSection({
    super.key,
    required this.client,
  });

  final DVStudioClient client;

  @override
  State<DVStudioSettingsSection> createState() =>
      _DVStudioSettingsSectionState();
}

class _DVStudioSettingsSectionState extends State<DVStudioSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  DVStudioSettings? _savedSettings;
  DVStudioSettings? _workingSettings;
  int _selectedTab = 0;
  int _revision = 0;

  /// The social links being edited, in order: the project's own labels and
  /// addresses, stored as the settings' `socialLinks` map (label to URL). A
  /// row whose label is still empty is kept here until it has one.
  List<_SocialRow> _socialRows = <_SocialRow>[];
  int _nextSocialRow = 0;

  void _syncSocialRows(DVStudioSettings settings) {
    _socialRows = <_SocialRow>[
      for (final MapEntry<String, String> link in settings.socialLinks.entries)
        _SocialRow(_nextSocialRow++, link.key, link.value),
    ];
  }

  void _writeSocialRows() {
    final Map<String, String> links = <String, String>{
      for (final _SocialRow row in _socialRows)
        if (row.label.trim().isNotEmpty) row.label.trim(): row.url.trim(),
    };
    _updateWorking((s) => s.copyWith(socialLinks: links));
  }

  static const List<String> _tabs = <String>[
    'General Identity',
    'Localization',
    'SEO & Social',
    'Maintenance Mode',
  ];

  static const List<String> _commonTimezones = <String>[
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Tokyo',
    'Asia/Singapore',
    'Asia/Dubai',
    'Australia/Sydney',
  ];

  static const List<String> _commonDateFormats = <String>[
    'YYYY-MM-DD',
    'DD/MM/YYYY',
    'MM/DD/YYYY',
    'D MMM YYYY',
    'MMMM D, YYYY',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final DVStudioSettings s = await widget.client.settings();
      if (mounted) {
        setState(() {
          _savedSettings = s;
          _workingSettings = s;
          _syncSocialRows(s);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load settings: $e';
          _loading = false;
        });
      }
    }
  }

  bool get _isDirty {
    if (_savedSettings == null || _workingSettings == null) return false;
    return _workingSettings != _savedSettings;
  }

  Future<void> _saveSettings() async {
    final DVStudioSettings? working = _workingSettings;
    if (working == null || !_isDirty || _saving) return;

    if (working.siteTitle.trim().isEmpty) {
      setState(() => _error = 'Site title cannot be empty.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });

    try {
      final DVStudioSettings saved = await widget.client.saveSettings(working);
      if (mounted) {
        setState(() {
          _savedSettings = saved;
          _workingSettings = saved;
          _syncSocialRows(saved);
          _saving = false;
          _notice = 'Settings saved successfully.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save settings: $e';
          _saving = false;
        });
      }
    }
  }

  void _discardChanges() {
    if (_savedSettings == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _workingSettings = _savedSettings;
      _syncSocialRows(_savedSettings!);
      _revision++;
      _error = null;
      _notice = null;
    });
  }

  void _updateWorking(DVStudioSettings Function(DVStudioSettings s) updater) {
    final DVStudioSettings? current = _workingSettings;
    if (current == null) return;
    setState(() {
      _workingSettings = updater(current);
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DVStudioStyle.accent,
          ),
        ),
      );
    }

    final DVStudioSettings settings = _workingSettings ?? const DVStudioSettings();

    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _buildHeader(),
        if (_error != null) _buildBanner(_error!, isError: true),
        if (_notice != null) _buildBanner(_notice!, isError: false),
        if (settings.maintenanceMode) _buildMaintenanceAlertBanner(),
        _buildTabBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const .all(DVStudioStyle.space4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: _buildTabContent(settings),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const .all(DVStudioStyle.space4),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            DVStudioIcons.settings,
            size: 20,
            color: DVStudioStyle.accent,
          ),
          const SizedBox(width: DVStudioStyle.space2),
          const Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                'Global Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DVStudioStyle.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Site identity, default SEO, localization, social profiles, and maintenance mode.',
                style: TextStyle(
                  fontSize: 12,
                  color: DVStudioStyle.muted,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_isDirty) ...<Widget>[
            DVStudioControl(
              label: 'Discard',
              enabled: !_saving,
              onTap: _discardChanges,
            ),
            const SizedBox(width: DVStudioStyle.space2),
          ],
          DVStudioControl(
            label: _saving ? 'Saving...' : 'Save Settings',
            enabled: _isDirty && !_saving,
            primary: true,
            icon: Icons.check,
            onTap: _saveSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(String text, {required bool isError}) {
    final Color tone = isError ? DVStudioStyle.danger : DVStudioStyle.accent;
    return Container(
      padding: const .symmetric(
        horizontal: DVStudioStyle.space4,
        vertical: DVStudioStyle.space2,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: tone.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: <Widget>[
          Icon(isError ? Icons.error_outline : Icons.info_outline,
              size: 16, color: tone),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: tone, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceAlertBanner() {
    const Color tone = DVStudioStyle.danger;
    return Container(
      padding: const .symmetric(
        horizontal: DVStudioStyle.space4,
        vertical: DVStudioStyle.space2,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        border: const Border(bottom: BorderSide(color: tone)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 18, color: tone),
          SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: Text(
              'Maintenance mode is active. Public visitors see the maintenance page while administrators can still access Studio.',
              style: TextStyle(
                fontSize: 12,
                color: tone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      padding: const .symmetric(horizontal: DVStudioStyle.space4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _tabs.length; i++) ...<Widget>[
            InkWell(
              onTap: () => setState(() => _selectedTab = i),
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
              child: Container(
                padding: const .symmetric(
                  horizontal: DVStudioStyle.space3,
                  vertical: DVStudioStyle.space2 + 2,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTab == i
                          ? DVStudioStyle.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  _tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        _selectedTab == i ? FontWeight.w600 : FontWeight.w500,
                    color: _selectedTab == i
                        ? DVStudioStyle.ink
                        : DVStudioStyle.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: DVStudioStyle.space2),
          ],
        ],
      ),
    );
  }

  Widget _buildTabContent(DVStudioSettings settings) {
    return KeyedSubtree(
      key: ValueKey<int>(_revision),
      child: Builder(
        builder: (BuildContext context) {
          switch (_selectedTab) {
            case 0:
              return _buildGeneralTab(settings);
            case 1:
              return _buildLocalizationTab(settings);
            case 2:
              return _buildSeoTab(settings);
            case 3:
              return _buildMaintenanceTab(settings);
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
        border: Border.all(color: DVStudioStyle.line),
      ),
      padding: const .all(DVStudioStyle.space4),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DVStudioStyle.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: DVStudioStyle.muted,
            ),
          ),
          const SizedBox(height: DVStudioStyle.space4),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label, {String? hint}) {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DVStudioStyle.ink,
          ),
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              color: DVStudioStyle.muted,
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0: General Identity
  // ---------------------------------------------------------------------------
  Widget _buildGeneralTab(DVStudioSettings settings) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _buildCard(
          title: 'Site Identity',
          subtitle:
              'The primary name, tagline and public URL of this application.',
          children: <Widget>[
            _buildFieldLabel('Site Title',
                hint: 'Appears in browser tabs and public header areas.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.siteTitle,
              placeholder: 'e.g. My Awesome App',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(siteTitle: v)),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Tagline',
                hint: 'In a few words, explain what this site is about.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.tagline,
              placeholder: 'e.g. Fast full-stack platform for Flutter & Dart',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(tagline: v)),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Public Site URL',
                hint: 'The canonical address where this site is reachable.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.siteUrl,
              placeholder: 'e.g. https://mycompany.com',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(siteUrl: v)),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Site Favicon / Icon URL',
                hint: 'Recommended 32×32 or 64×64 PNG or ICO image.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.favicon ?? '',
              placeholder: 'e.g. /favicon.ico or https://.../icon.png',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(favicon: v)),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Localization
  // ---------------------------------------------------------------------------
  Widget _buildLocalizationTab(DVStudioSettings settings) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _buildCard(
          title: 'Time & Date Localization',
          subtitle:
              'Configure the timezone and date format used across dashboard displays and public timestamps.',
          children: <Widget>[
            _buildFieldLabel('Timezone',
                hint: 'Standard IANA timezone identifier for schedules and display.'),
            const SizedBox(height: DVStudioStyle.space1),
            Container(
              padding: const .symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: DVStudioStyle.surface,
                borderRadius: .circular(DVStudioStyle.radiusSmall),
                border: Border.all(color: DVStudioStyle.line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _commonTimezones.contains(settings.timezone)
                      ? settings.timezone
                      : 'UTC',
                  isExpanded: true,
                  dropdownColor: DVStudioStyle.surface,
                  items: _commonTimezones
                      .map((String tz) => DropdownMenuItem<String>(
                            value: tz,
                            child: Text(tz,
                                style: const TextStyle(
                                    fontSize: 13, color: DVStudioStyle.ink)),
                          ))
                      .toList(),
                  onChanged: (String? val) {
                    if (val != null) {
                      _updateWorking((s) => s.copyWith(timezone: val));
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Date Format',
                hint: 'Formatting pattern used for displayed dates.'),
            const SizedBox(height: DVStudioStyle.space1),
            Container(
              padding: const .symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: DVStudioStyle.surface,
                borderRadius: .circular(DVStudioStyle.radiusSmall),
                border: Border.all(color: DVStudioStyle.line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _commonDateFormats.contains(settings.dateFormat)
                      ? settings.dateFormat
                      : 'YYYY-MM-DD',
                  isExpanded: true,
                  dropdownColor: DVStudioStyle.surface,
                  items: _commonDateFormats
                      .map((String df) => DropdownMenuItem<String>(
                            value: df,
                            child: Text(df,
                                style: const TextStyle(
                                    fontSize: 13, color: DVStudioStyle.ink)),
                          ))
                      .toList(),
                  onChanged: (String? val) {
                    if (val != null) {
                      _updateWorking((s) => s.copyWith(dateFormat: val));
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            Container(
              padding: const .all(DVStudioStyle.space3),
              decoration: BoxDecoration(
                color: DVStudioStyle.canvas,
                borderRadius: .circular(DVStudioStyle.radiusSmall),
                border: Border.all(color: DVStudioStyle.line),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: DVStudioStyle.muted),
                  const SizedBox(width: DVStudioStyle.space2),
                  Text(
                    'Preview: ${settings.dateFormat} in timezone ${settings.timezone}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DVStudioStyle.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: SEO & Social
  // ---------------------------------------------------------------------------
  Widget _buildSeoTab(DVStudioSettings settings) {
    final String serpTitle = (settings.defaultSeoTitle?.isNotEmpty == true)
        ? settings.defaultSeoTitle!
        : settings.siteTitle;
    final String serpDesc = (settings.defaultSeoDescription?.isNotEmpty == true)
        ? settings.defaultSeoDescription!
        : (settings.tagline.isNotEmpty
            ? settings.tagline
            : 'Welcome to ${settings.siteTitle}.');
    final String siteHost = Uri.tryParse(settings.siteUrl)?.host.isNotEmpty == true
        ? Uri.parse(settings.siteUrl).host
        : 'example.com';

    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _buildCard(
          title: 'Default Search Engine Optimization (SEO)',
          subtitle:
              'Global metadata fallbacks used for search engine indexing when individual pages omit specific overrides.',
          children: <Widget>[
            _buildFieldLabel('Default SEO Title',
                hint: 'Recommended 50–60 characters.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.defaultSeoTitle ?? '',
              placeholder: 'e.g. Acme Corp — High Performance Flutter Platform',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(defaultSeoTitle: v)),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Default Meta Description',
                hint: 'Recommended 120–160 characters summary of your site.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.defaultSeoDescription ?? '',
              placeholder:
                  'e.g. What this site offers, in a sentence or two.',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(defaultSeoDescription: v)),
            ),
            const SizedBox(height: DVStudioStyle.space3),
            _buildFieldLabel('Default OpenGraph Social Image URL',
                hint: 'Recommended 1200×630 pixels image displayed when sharing links.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.defaultSeoImage ?? '',
              placeholder: 'e.g. https://example.com/assets/og-cover.png',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(defaultSeoImage: v)),
            ),
            const SizedBox(height: DVStudioStyle.space4),
            const Text(
              'Google Search Snippet Preview',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DVStudioStyle.ink,
              ),
            ),
            const SizedBox(height: DVStudioStyle.space2),
            Container(
              padding: const .all(DVStudioStyle.space3),
              decoration: BoxDecoration(
                color: DVStudioStyle.canvas,
                borderRadius: .circular(DVStudioStyle.radiusSmall),
                border: Border.all(color: DVStudioStyle.line),
              ),
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text(
                    '${settings.siteUrl} › ...',
                    style: const TextStyle(
                      fontSize: 11,
                      color: DVStudioStyle.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serpTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A0DAB), // Standard SERP title blue
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    serpDesc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DVStudioStyle.ink,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (settings.defaultSeoImage?.isNotEmpty == true) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space4),
              const Text(
                'Social Share Card Preview',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              const SizedBox(height: DVStudioStyle.space2),
              Container(
                decoration: BoxDecoration(
                  color: DVStudioStyle.canvas,
                  borderRadius: .circular(DVStudioStyle.radiusSmall),
                  border: Border.all(color: DVStudioStyle.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Container(
                      height: 140,
                      width: double.infinity,
                      color: DVStudioStyle.line,
                      child: Image.network(
                        settings.defaultSeoImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image,
                              color: DVStudioStyle.muted),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const .all(DVStudioStyle.space3),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          Text(
                            siteHost.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serpTitle,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: DVStudioStyle.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serpDesc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DVStudioStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: DVStudioStyle.space4),
        _buildCard(
          title: 'Social Profiles',
          subtitle:
              'The places this site is found elsewhere: each one a label and '
              'its address.',
          children: <Widget>[
            if (_socialRows.isEmpty)
              const Text(
                'No social links yet.',
                style: TextStyle(fontSize: 12, color: DVStudioStyle.muted),
              ),
            for (final _SocialRow row in _socialRows) ...<Widget>[
              _buildSocialRow(row),
              const SizedBox(height: DVStudioStyle.space2),
            ],
            const SizedBox(height: DVStudioStyle.space1),
            Align(
              alignment: .centerLeft,
              child: DVStudioControl(
                label: 'Add social link',
                enabled: true,
                icon: DVStudioIcons.add,
                onTap: () => setState(() {
                  _socialRows = <_SocialRow>[
                    ..._socialRows,
                    _SocialRow(_nextSocialRow++, '', ''),
                  ];
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialRow(_SocialRow row) {
    final String name = row.label.trim().isEmpty ? 'this link' : row.label.trim();
    final bool duplicate = row.label.trim().isNotEmpty &&
        _socialRows
                .where((_SocialRow r) => r.label.trim() == row.label.trim())
                .length >
            1;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: DVStudioTextInput(
                key: ValueKey<String>('dv-studio-social-label-${row.id}'),
                value: row.label,
                placeholder: 'Label, e.g. Instagram',
                semanticLabel: 'Social link label',
                onChanged: (String v) {
                  row.label = v;
                  _writeSocialRows();
                },
              ),
            ),
            const SizedBox(width: DVStudioStyle.space2),
            Expanded(
              flex: 3,
              child: DVStudioTextInput(
                key: ValueKey<String>('dv-studio-social-url-${row.id}'),
                value: row.url,
                placeholder: 'https://…',
                icon: DVStudioIcons.link,
                semanticLabel: 'Address of $name',
                onChanged: (String v) {
                  row.url = v;
                  _writeSocialRows();
                },
              ),
            ),
            const SizedBox(width: DVStudioStyle.space1),
            DVStudioIconButton(
              icon: DVStudioIcons.delete,
              tooltip: 'Remove $name',
              onTap: () {
                _socialRows = <_SocialRow>[
                  for (final _SocialRow r in _socialRows)
                    if (r.id != row.id) r,
                ];
                _writeSocialRows();
              },
            ),
          ],
        ),
        if (duplicate)
          const Padding(
            padding: .only(top: 4),
            child: Text(
              'Another link has this label; only one of them is kept.',
              style: TextStyle(fontSize: 11, color: DVStudioStyle.danger),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Maintenance Mode
  // ---------------------------------------------------------------------------
  Widget _buildMaintenanceTab(DVStudioSettings settings) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _buildCard(
          title: 'Maintenance Mode',
          subtitle:
              'Temporarily disable public access while performing upgrades or data migrations.',
          children: <Widget>[
            Row(
              mainAxisAlignment: .spaceBetween,
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        'Enable Maintenance Mode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DVStudioStyle.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'When active, non-administrator visitors receive a 503 Service Unavailable page.',
                        style: TextStyle(
                          fontSize: 11,
                          color: DVStudioStyle.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                DVStudioSwitch(
                  key: const ValueKey<String>('dv-studio-settings-maintenance-switch'),
                  label: 'Maintenance Mode',
                  on: settings.maintenanceMode,
                  onTap: () {
                    _updateWorking((s) =>
                        s.copyWith(maintenanceMode: !settings.maintenanceMode));
                  },
                  builder: (BuildContext context, bool value, Color track) =>
                      AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 36,
                    height: 20,
                    padding: const .all(2),
                    alignment: value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: value
                          ? DVStudioStyle.danger
                          : DVStudioStyle.lineStrong,
                      borderRadius: .circular(99),
                    ),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DVStudioStyle.space4),
            _buildFieldLabel('Custom Maintenance Message',
                hint: 'Displayed to public visitors on the maintenance screen.'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioTextInput(
              value: settings.maintenanceMessage ?? '',
              placeholder:
                  'We are currently undergoing scheduled maintenance. Please check back shortly.',
              onChanged: (String v) =>
                  _updateWorking((s) => s.copyWith(maintenanceMessage: v)),
            ),
          ],
        ),
      ],
    );
  }
}

/// One social link being edited: a label of the project's choosing and its
/// address.
class _SocialRow {
  _SocialRow(this.id, this.label, this.url);

  final int id;
  String label;
  String url;
}

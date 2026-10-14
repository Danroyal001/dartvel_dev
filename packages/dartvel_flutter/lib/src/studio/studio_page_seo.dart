import 'package:flutter/material.dart'
    show
        AlertDialog,
        BorderRadius,
        BoxFit,
        DropdownButton,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        Icons,
        Image,
        RoundedRectangleBorder,
        showDialog;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The page settings and SEO inspection panel.
///
/// Provides visual controls for page title, meta description, OpenGraph social card
/// image and preview, search engine robots directives, canonical URL,
/// schema.org type, and sitemap inclusion.
class DVStudioPageSeoPanel extends StatefulWidget {
  final DVStudioEditorController controller;

  const DVStudioPageSeoPanel({
    super.key,
    required this.controller,
  });

  @override
  State<DVStudioPageSeoPanel> createState() => _DVStudioPageSeoPanelState();
}

class _DVStudioPageSeoPanelState extends State<DVStudioPageSeoPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(DVStudioPageSeoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _guard(VoidCallback edit) {
    try {
      edit();
    } on StateError {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DVPageDocument doc = widget.controller.document;
    final String title = doc.title;
    final String description = doc.description ?? '';
    final String image = doc.image ?? '';
    final String robots = doc.robots ?? 'index, follow';
    final String schemaType = doc.schemaType ?? 'WebPage';
    final String canonicalUrl = doc.canonicalUrl ?? '';
    final bool sitemap = doc.sitemap;

    return Container(
      key: const ValueKey<String>('dv-studio-page-seo-panel'),
      color: DVStudioStyle.surface,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _header(doc),
          Expanded(
            child: SingleChildScrollView(
              padding: const .all(DVStudioStyle.space4),
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  // 1. General Page Settings & Search Appearance
                  _sectionHeader(
                    'Search Appearance',
                    'How this page is displayed in search engine results.',
                    icon: Icons.search,
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  // Title field
                  Row(
                    mainAxisAlignment: .spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Page Title',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DVStudioStyle.ink,
                        ),
                      ),
                      Text(
                        '${title.length} / 60',
                        key: const ValueKey<String>(
                            'dv-studio-page-seo-title-count'),
                        style: TextStyle(
                          fontSize: 11,
                          color: title.length > 60
                              ? DVStudioStyle.warning
                              : DVStudioStyle.faint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  DVStudioTextInput(
                    key: const ValueKey<String>('dv-studio-page-seo-title'),
                    value: title,
                    placeholder: 'Enter page title…',
                    onChanged: (String value) => _guard(() {
                      widget.controller.updatePageSeo(title: value);
                    }),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Search engines typically display the first 50–60 characters.',
                    style: TextStyle(fontSize: 11, color: DVStudioStyle.faint),
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  // Meta Description field
                  Row(
                    mainAxisAlignment: .spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Meta Description',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DVStudioStyle.ink,
                        ),
                      ),
                      Text(
                        '${description.length} / 160',
                        key: const ValueKey<String>(
                            'dv-studio-page-seo-desc-count'),
                        style: TextStyle(
                          fontSize: 11,
                          color: description.length > 160
                              ? DVStudioStyle.warning
                              : DVStudioStyle.faint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  DVStudioTextInput(
                    key: const ValueKey<String>(
                        'dv-studio-page-seo-description'),
                    value: description,
                    placeholder: 'Brief summary of the page for search results…',
                    onChanged: (String value) => _guard(() {
                      widget.controller.updatePageSeo(description: value);
                    }),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Keep description concise between 120 and 160 characters.',
                    style: TextStyle(fontSize: 11, color: DVStudioStyle.faint),
                  ),
                  const SizedBox(height: DVStudioStyle.space4),

                  // Google SERP Snippet Preview
                  _searchPreview(doc),
                  const SizedBox(height: DVStudioStyle.space6),

                  // 2. Social Media & OpenGraph
                  _sectionHeader(
                    'Social Share Preview (OpenGraph)',
                    'How this page appears when shared on Twitter, Facebook, LinkedIn and Slack.',
                    icon: Icons.share_outlined,
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  const Text(
                    'Social Share Image URL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  DVStudioTextInput(
                    key: const ValueKey<String>('dv-studio-page-seo-image'),
                    icon: Icons.image_outlined,
                    value: image,
                    placeholder: 'https://example.com/social-preview.png',
                    onChanged: (String value) => _guard(() {
                      widget.controller.updatePageSeo(image: value);
                    }),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Recommended dimension: 1200 × 630 pixels (1.91:1 ratio).',
                    style: TextStyle(fontSize: 11, color: DVStudioStyle.faint),
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  // OpenGraph Card Preview
                  _socialCardPreview(doc),
                  const SizedBox(height: DVStudioStyle.space6),

                  // 3. Indexing & Robots Directives
                  _sectionHeader(
                    'Indexing & Robots Directives',
                    'Control how web crawlers and indexers interact with this page.',
                    icon: Icons.policy_outlined,
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  const Text(
                    'Robots Meta Tag',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  Container(
                    key: const ValueKey<String>('dv-studio-page-seo-robots'),
                    padding: const .symmetric(horizontal: DVStudioStyle.space3),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.surface,
                      borderRadius: .circular(DVStudioStyle.radius),
                      border: Border.all(color: DVStudioStyle.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: robots,
                        isExpanded: true,
                        dropdownColor: DVStudioStyle.surface,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'index, follow',
                            child: Text(
                              'index, follow (Allow indexing and follow links)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'noindex, nofollow',
                            child: Text(
                              'noindex, nofollow (Do not index and do not follow)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'noindex, follow',
                            child: Text(
                              'noindex, follow (Do not index, but follow links)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'index, nofollow',
                            child: Text(
                              'index, nofollow (Index page, do not follow links)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                        ],
                        onChanged: (String? val) {
                          if (val != null) {
                            _guard(() {
                              widget.controller.updatePageSeo(robots: val);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  // Canonical URL
                  const Text(
                    'Canonical URL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  DVStudioTextInput(
                    key: const ValueKey<String>(
                        'dv-studio-page-seo-canonical'),
                    icon: Icons.link,
                    value: canonicalUrl,
                    placeholder: 'https://example.com/canonical-url',
                    onChanged: (String value) => _guard(() {
                      widget.controller.updatePageSeo(canonicalUrl: value);
                    }),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Specify the preferred URL if this content is duplicate or syndicated.',
                    style: TextStyle(fontSize: 11, color: DVStudioStyle.faint),
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  // Sitemap toggle
                  Container(
                    padding: const .all(DVStudioStyle.space3),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.canvas,
                      borderRadius: .circular(DVStudioStyle.radius),
                      border: Border.all(color: DVStudioStyle.line),
                    ),
                    child: Row(
                      mainAxisAlignment: .spaceBetween,
                      children: <Widget>[
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: .start,
                            children: <Widget>[
                              Text(
                                'Include in sitemap.xml',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DVStudioStyle.ink,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Enable search engines to discover this page automatically in the sitemap.',
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
                          key: const ValueKey<String>(
                              'dv-studio-page-seo-sitemap'),
                          label: 'Include in sitemap.xml',
                          on: sitemap,
                          onTap: () => _guard(() {
                            widget.controller.updatePageSeo(sitemap: !sitemap);
                          }),
                          builder: (BuildContext context, bool value,
                              Color track) =>
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
                                  ? DVStudioStyle.accent
                                  : DVStudioStyle.lineStrong,
                              borderRadius: .circular(99),
                            ),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFFFFF),
                                shape: BoxShape.circle,
                                boxShadow: DVStudioStyle.shadow,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space6),

                  // 4. Structured Data (Schema.org)
                  _sectionHeader(
                    'Structured Data (Schema.org)',
                    'Provide explicit semantic clues about the meaning of this page.',
                    icon: Icons.data_object_outlined,
                  ),
                  const SizedBox(height: DVStudioStyle.space3),

                  const Text(
                    'Schema.org Type',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink,
                    ),
                  ),
                  const SizedBox(height: DVStudioStyle.space1),
                  Container(
                    key: const ValueKey<String>('dv-studio-page-seo-schema'),
                    padding: const .symmetric(horizontal: DVStudioStyle.space3),
                    decoration: BoxDecoration(
                      color: DVStudioStyle.surface,
                      borderRadius: .circular(DVStudioStyle.radius),
                      border: Border.all(color: DVStudioStyle.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: schemaType,
                        isExpanded: true,
                        dropdownColor: DVStudioStyle.surface,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'WebPage',
                            child: Text(
                              'WebPage (Standard webpage)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'Article',
                            child: Text(
                              'Article (Blog post, news, article)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'Product',
                            child: Text(
                              'Product (Item for sale)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'AboutPage',
                            child: Text(
                              'AboutPage (About us or personal page)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'ContactPage',
                            child: Text(
                              'ContactPage (Contact information)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'FAQPage',
                            child: Text(
                              'FAQPage (Frequently asked questions)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: DVStudioStyle.ink),
                            ),
                          ),
                        ],
                        onChanged: (String? val) {
                          if (val != null) {
                            _guard(() {
                              widget.controller.updatePageSeo(schemaType: val);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Generates JSON-LD metadata for rich search results.',
                    style: TextStyle(fontSize: 11, color: DVStudioStyle.faint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(DVPageDocument doc) {
    return Container(
      padding: const .fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: DVStudioStyle.accentSoft,
              borderRadius: .circular(DVStudioStyle.radius),
            ),
            child: const Icon(
              Icons.manage_search_outlined,
              size: 18,
              color: DVStudioStyle.accent,
            ),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                const Text(
                  'Page Settings & SEO',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DVStudioStyle.ink,
                  ),
                ),
                Text(
                  doc.route,
                  key: const ValueKey<String>('dv-studio-page-seo-route'),
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
    );
  }

  Widget _sectionHeader(String title, String subtitle, {required IconData icon}) {
    return Row(
      crossAxisAlignment: .start,
      children: <Widget>[
        Icon(icon, size: 16, color: DVStudioStyle.muted),
        const SizedBox(width: DVStudioStyle.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: DVStudioStyle.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchPreview(DVPageDocument doc) {
    final String title =
        doc.title.trim().isEmpty ? 'Untitled Page' : doc.title.trim();
    final String desc = doc.description?.trim().isNotEmpty == true
        ? doc.description!.trim()
        : 'Add a meta description to see how your page will appear in Google search results.';
    final String domain = 'example.com';
    final String path = doc.route == '/' ? '' : doc.route;

    return Container(
      key: const ValueKey<String>('dv-studio-page-seo-search-preview'),
      padding: const .all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        borderRadius: .circular(DVStudioStyle.radius),
        border: Border.all(color: DVStudioStyle.line),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.travel_explore_outlined,
                  size: 14, color: DVStudioStyle.muted),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Google Search Snippet Preview',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DVStudioStyle.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          Text(
            'https://$domain$path',
            key: const ValueKey<String>('dv-studio-page-seo-search-preview-url'),
            style: const TextStyle(
              fontSize: 11,
              color: DVStudioStyle.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            key: const ValueKey<String>(
                'dv-studio-page-seo-search-preview-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A0DAB),
              decoration: TextDecoration.underline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            key: const ValueKey<String>(
                'dv-studio-page-seo-search-preview-desc'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: DVStudioStyle.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialCardPreview(DVPageDocument doc) {
    final String title =
        doc.title.trim().isEmpty ? 'Untitled Page' : doc.title.trim();
    final String desc = doc.description?.trim().isNotEmpty == true
        ? doc.description!.trim()
        : 'No description provided.';
    final String? img = doc.image?.trim().isNotEmpty == true ? doc.image!.trim() : null;

    return Container(
      key: const ValueKey<String>('dv-studio-page-seo-social-preview'),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        borderRadius: .circular(DVStudioStyle.radius),
        border: Border.all(color: DVStudioStyle.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          // Social image box
          Container(
            key: const ValueKey<String>('dv-studio-page-seo-social-card'),
            height: 130,
            color: DVStudioStyle.hover,
            child: img != null
                ? Image.network(
                    img,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext context, Object error,
                        StackTrace? stackTrace) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 32, color: DVStudioStyle.faint),
                      );
                    },
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.image_outlined,
                            size: 28, color: DVStudioStyle.faint),
                        SizedBox(height: 4),
                        Text(
                          '1200 × 630 px preview',
                          style: TextStyle(
                            fontSize: 11,
                            color: DVStudioStyle.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          // Social metadata
          Padding(
            padding: const .all(DVStudioStyle.space3),
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                const Text(
                  'EXAMPLE.COM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: DVStudioStyle.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  key: const ValueKey<String>(
                      'dv-studio-page-seo-social-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DVStudioStyle.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  key: const ValueKey<String>(
                      'dv-studio-page-seo-social-desc'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: DVStudioStyle.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the Page Settings & SEO modal dialog.
Future<void> dvShowStudioPageSeoDialog(
  BuildContext context,
  DVStudioEditorController controller,
) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: DVStudioStyle.surface,
          contentPadding: .zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            side: const BorderSide(color: DVStudioStyle.line),
          ),
          content: SizedBox(
            width: 520,
            height: 600,
            child: DVStudioPageSeoPanel(controller: controller),
          ),
        );
      },
    );

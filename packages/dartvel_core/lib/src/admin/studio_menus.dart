library;

/// A single item in a navigation menu.
class DVStudioMenuItem {
  const DVStudioMenuItem({
    required this.id,
    required this.label,
    required this.url,
    this.target = '_self',
    this.children = const <DVStudioMenuItem>[],
    this.route,
  });

  /// Unique identifier within the menu.
  final String id;

  /// Visible text of the navigation link.
  final String label;

  /// Target URL or path (e.g. `/`, `/about`, `https://...`).
  final String url;

  /// Link target: `_self` (same window) or `_blank` (new tab).
  final String target;

  /// Nested sub-menu items (dropdown / child links).
  final List<DVStudioMenuItem> children;

  /// Optional typed route identifier if bound to an application route.
  final String? route;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'url': url,
        'target': target,
        'children': <Map<String, Object?>>[
          for (final DVStudioMenuItem child in children) child.toJson(),
        ],
        if (route != null) 'route': route,
      };

  factory DVStudioMenuItem.fromJson(Map<String, Object?> json) {
    return DVStudioMenuItem(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? ''}',
      url: '${json['url'] ?? ''}',
      target: '${json['target'] ?? '_self'}',
      children: <DVStudioMenuItem>[
        for (final Object? c
            in (json['children'] as List?) ?? const <Object?>[])
          if (c is Map) DVStudioMenuItem.fromJson(c.cast<String, Object?>()),
      ],
      route: json['route'] as String?,
    );
  }

  DVStudioMenuItem copyWith({
    String? id,
    String? label,
    String? url,
    String? target,
    List<DVStudioMenuItem>? children,
    String? route,
  }) {
    return DVStudioMenuItem(
      id: id ?? this.id,
      label: label ?? this.label,
      url: url ?? this.url,
      target: target ?? this.target,
      children: children ?? this.children,
      route: route ?? this.route,
    );
  }
}

/// A named navigation menu assigned to a location (e.g. `header`, `footer`, `sidebar`).
class DVStudioMenu {
  const DVStudioMenu({
    required this.id,
    required this.name,
    this.location = 'header',
    this.items = const <DVStudioMenuItem>[],
    required this.updatedAt,
  });

  /// Unique menu identifier (e.g. `primary-menu`).
  final String id;

  /// Display name of the menu (e.g. `Primary Navigation`).
  final String name;

  /// Theme location this menu is bound to (`header`, `footer`, `sidebar`, `mobile`, `custom`).
  final String location;

  /// Top-level menu items.
  final List<DVStudioMenuItem> items;

  /// When the menu was last saved.
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'location': location,
        'items': <Map<String, Object?>>[
          for (final DVStudioMenuItem item in items) item.toJson(),
        ],
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DVStudioMenu.fromJson(Map<String, Object?> json) {
    return DVStudioMenu(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      location: '${json['location'] ?? 'header'}',
      items: <DVStudioMenuItem>[
        for (final Object? item
            in (json['items'] as List?) ?? const <Object?>[])
          if (item is Map)
            DVStudioMenuItem.fromJson(item.cast<String, Object?>()),
      ],
      updatedAt: json['updatedAt'] is String
          ? (DateTime.tryParse(json['updatedAt']! as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  DVStudioMenu copyWith({
    String? id,
    String? name,
    String? location,
    List<DVStudioMenuItem>? items,
    DateTime? updatedAt,
  }) {
    return DVStudioMenu(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Default menus initialized when a new project has no stored navigation yet.
List<DVStudioMenu> dvStudioDefaultMenus() => <DVStudioMenu>[
      DVStudioMenu(
        id: 'primary-menu',
        name: 'Primary Navigation',
        location: 'header',
        updatedAt: DateTime.parse('2026-10-14T12:00:00Z'),
        items: const <DVStudioMenuItem>[
          DVStudioMenuItem(
            id: 'item-home',
            label: 'Home',
            url: '/',
            target: '_self',
          ),
          DVStudioMenuItem(
            id: 'item-about',
            label: 'About',
            url: '/about',
            target: '_self',
          ),
          DVStudioMenuItem(
            id: 'item-contact',
            label: 'Contact',
            url: '/contact',
            target: '_self',
          ),
        ],
      ),
      DVStudioMenu(
        id: 'footer-menu',
        name: 'Footer Links',
        location: 'footer',
        updatedAt: DateTime.parse('2026-10-14T12:00:00Z'),
        items: const <DVStudioMenuItem>[
          DVStudioMenuItem(
            id: 'item-privacy',
            label: 'Privacy Policy',
            url: '/privacy',
            target: '_self',
          ),
          DVStudioMenuItem(
            id: 'item-terms',
            label: 'Terms of Service',
            url: '/terms',
            target: '_self',
          ),
        ],
      ),
    ];

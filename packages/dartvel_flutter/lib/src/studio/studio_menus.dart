/// Studio Menus and Navigation section: visual hierarchy editor,
/// location assignment, nested items, route linking, and reordering.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show DVStudioMenu, DVStudioMenuItem;
import 'package:flutter/material.dart';

import 'studio_server.dart';
import 'studio_style.dart';

/// The Menus & Navigation section in Studio.
class DVStudioMenusSection extends StatefulWidget {
  const DVStudioMenusSection({
    super.key,
    required this.client,
    this.selectedMenuId,
    this.onSelect,
  });

  final DVStudioClient client;
  final String? selectedMenuId;
  final void Function(String? id)? onSelect;

  @override
  State<DVStudioMenusSection> createState() => _DVStudioMenusSectionState();
}

class _DVStudioMenusSectionState extends State<DVStudioMenusSection> {
  late Future<({List<DVStudioMenu> menus, List<String> locations})> _data =
      _load();
  String? _selectedId;
  DVStudioMenu? _workingMenu;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  String? _statusMessage;

  Future<({List<DVStudioMenu> menus, List<String> locations})> _load() async {
    final ({List<DVStudioMenu> menus, List<String> locations}) res =
        await widget.client.menus();
    if (_selectedId == null ||
        !res.menus.any((DVStudioMenu m) => m.id == _selectedId)) {
      if (res.menus.isNotEmpty) {
        _selectedId = widget.selectedMenuId != null &&
                res.menus.any((DVStudioMenu m) => m.id == widget.selectedMenuId)
            ? widget.selectedMenuId
            : res.menus.first.id;
        _workingMenu =
            res.menus.firstWhere((DVStudioMenu m) => m.id == _selectedId);
      }
    } else {
      _workingMenu =
          res.menus.firstWhere((DVStudioMenu m) => m.id == _selectedId);
    }
    _dirty = false;
    return res;
  }

  void _reload([String? selectId]) {
    setState(() {
      if (selectId != null) {
        _selectedId = selectId;
        widget.onSelect?.call(selectId);
      }
      _data = _load();
    });
  }

  void _selectMenu(DVStudioMenu menu) {
    if (_selectedId == menu.id) return;
    setState(() {
      _selectedId = menu.id;
      _workingMenu = menu;
      _dirty = false;
      _statusMessage = null;
      _error = null;
    });
    widget.onSelect?.call(menu.id);
  }

  void _updateWorkingMenu(DVStudioMenu updated) {
    setState(() {
      _workingMenu = updated;
      _dirty = true;
      _statusMessage = null;
    });
  }

  Future<void> _save() async {
    final DVStudioMenu? menu = _workingMenu;
    if (menu == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final DVStudioMenu saved = await widget.client.saveMenu(menu);
      setState(() {
        _workingMenu = saved;
        _dirty = false;
        _saving = false;
        _statusMessage = 'Menu "${saved.name}" saved successfully.';
      });
      _reload(saved.id);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Failed to save menu: $e';
      });
    }
  }

  Future<void> _deleteCurrentMenu() async {
    final DVStudioMenu? menu = _workingMenu;
    if (menu == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: DVStudioStyle.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            side: const BorderSide(color: DVStudioStyle.line),
          ),
          title: const Text(
            'Delete Menu',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DVStudioStyle.ink,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${menu.name}"? This cannot be undone.',
            style: const TextStyle(fontSize: 13, color: DVStudioStyle.muted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: DVStudioStyle.muted)),
            ),
            DVStudioControl(
              label: 'Delete permanently',
              enabled: true,
              primary: true,
              icon: DVStudioIcons.delete,
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await widget.client.deleteMenu(menu.id);
        _selectedId = null;
        _workingMenu = null;
        _reload();
      } catch (e) {
        setState(() {
          _error = 'Failed to delete menu: $e';
        });
      }
    }
  }

  Future<void> _openNewMenuDialog(List<String> locations) async {
    String name = '';
    String id = '';
    String location = locations.isNotEmpty ? locations.first : 'header';
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                side: const BorderSide(color: DVStudioStyle.line),
              ),
              title: const Text(
                'New Navigation Menu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    const Text(
                      'Create a new navigation menu for your header, footer, or custom layout.',
                      style:
                          TextStyle(fontSize: 13, color: DVStudioStyle.muted),
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('Menu Name',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    DVStudioTextInput(
                      placeholder: 'e.g. Header Navigation',
                      onChanged: (String v) {
                        setDialogState(() {
                          name = v;
                          if (id.isEmpty ||
                              id == _slugify(name.substring(0, name.length - 1))) {
                            id = _slugify(name);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('Menu ID (Key)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    DVStudioTextInput(
                      placeholder: 'e.g. header-nav',
                      value: id,
                      onChanged: (String v) => id = v.trim(),
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('Theme Location',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    Container(
                      padding: const .symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: DVStudioStyle.surface,
                        borderRadius:
                            BorderRadius.circular(DVStudioStyle.radius),
                        border: Border.all(color: DVStudioStyle.line),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: location,
                          isExpanded: true,
                          dropdownColor: DVStudioStyle.surface,
                          items: <DropdownMenuItem<String>>[
                            for (final String loc in locations)
                              DropdownMenuItem<String>(
                                value: loc,
                                child: Text(_capitalize(loc),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: DVStudioStyle.ink)),
                              ),
                            const DropdownMenuItem<String>(
                              value: 'custom',
                              child: Text('Custom',
                                  style: TextStyle(
                                      fontSize: 13, color: DVStudioStyle.ink)),
                            ),
                          ],
                          onChanged: (String? val) {
                            if (val != null) {
                              setDialogState(() => location = val);
                            }
                          },
                        ),
                      ),
                    ),
                    if (dialogError != null) ...<Widget>[
                      const SizedBox(height: DVStudioStyle.space3),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: DVStudioStyle.muted)),
                ),
                DVStudioControl(
                  label: 'Create menu',
                  enabled: name.trim().isNotEmpty && id.trim().isNotEmpty,
                  primary: true,
                  icon: DVStudioIcons.add,
                  onTap: () async {
                    if (name.trim().isEmpty || id.trim().isEmpty) {
                      setDialogState(() {
                        dialogError = 'Please provide both a name and an id.';
                      });
                      return;
                    }
                    final DVStudioMenu newMenu = DVStudioMenu(
                      id: id.trim(),
                      name: name.trim(),
                      location: location,
                      items: const <DVStudioMenuItem>[],
                      updatedAt: DateTime.now().toUtc(),
                    );
                    try {
                      final DVStudioMenu created =
                          await widget.client.saveMenu(newMenu);
                      if (context.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      _reload(created.id);
                    } catch (err) {
                      setDialogState(() {
                        dialogError = '$err';
                      });
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAddLinkDialog({
    DVStudioMenuItem? itemToEdit,
    String? defaultParentId,
  }) async {
    final DVStudioMenu? menu = _workingMenu;
    if (menu == null) return;

    String label = itemToEdit?.label ?? '';
    String url = itemToEdit?.url ?? '/';
    String target = itemToEdit?.target ?? '_self';
    String? parentId = defaultParentId;
    String? dialogError;

    final List<DVStudioMenuItem> allItemsFlat = _flattenItems(menu.items);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: DVStudioStyle.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                side: const BorderSide(color: DVStudioStyle.line),
              ),
              title: Text(
                itemToEdit == null ? 'Add Navigation Link' : 'Edit Link',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink,
                ),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    const Text('Link Text (Label)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    DVStudioTextInput(
                      placeholder: 'e.g. Products, About, Docs',
                      value: label,
                      onChanged: (String v) => label = v,
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('URL or Route',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    DVStudioTextInput(
                      placeholder: 'e.g. /products or https://...',
                      value: url,
                      icon: DVStudioIcons.link,
                      onChanged: (String v) => url = v,
                    ),
                    const SizedBox(height: DVStudioStyle.space2),
                    // Quick presets
                    Wrap(
                      spacing: DVStudioStyle.space1,
                      runSpacing: DVStudioStyle.space1,
                      children: <Widget>[
                        for (final ({String name, String path}) preset in const [
                          (name: 'Home', path: '/'),
                          (name: 'About', path: '/about'),
                          (name: 'Docs', path: '/docs'),
                          (name: 'Blog', path: '/blog'),
                          (name: 'Contact', path: '/contact'),
                        ])
                          InkWell(
                            borderRadius:
                                BorderRadius.circular(DVStudioStyle.radius),
                            onTap: () {
                              setDialogState(() {
                                url = preset.path;
                                if (label.isEmpty) label = preset.name;
                              });
                            },
                            child: Container(
                              padding: const .symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: DVStudioStyle.canvas,
                                borderRadius:
                                    BorderRadius.circular(DVStudioStyle.radius),
                                border: Border.all(color: DVStudioStyle.line),
                              ),
                              child: Text(
                                preset.name,
                                style: const TextStyle(
                                    fontSize: 11, color: DVStudioStyle.muted),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('Open Target',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.ink)),
                    const SizedBox(height: DVStudioStyle.space1),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(DVStudioStyle.radius),
                            onTap: () => setDialogState(() => target = '_self'),
                            child: Container(
                              padding: const .symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: target == '_self'
                                    ? DVStudioStyle.hover
                                    : DVStudioStyle.surface,
                                borderRadius:
                                    BorderRadius.circular(DVStudioStyle.radius),
                                border: Border.all(
                                  color: target == '_self'
                                      ? DVStudioStyle.ink
                                      : DVStudioStyle.line,
                                ),
                              ),
                              alignment: .center,
                              child: const Text('Same tab (_self)',
                                  style: TextStyle(
                                      fontSize: 12, color: DVStudioStyle.ink)),
                            ),
                          ),
                        ),
                        const SizedBox(width: DVStudioStyle.space2),
                        Expanded(
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(DVStudioStyle.radius),
                            onTap: () =>
                                setDialogState(() => target = '_blank'),
                            child: Container(
                              padding: const .symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: target == '_blank'
                                    ? DVStudioStyle.hover
                                    : DVStudioStyle.surface,
                                borderRadius:
                                    BorderRadius.circular(DVStudioStyle.radius),
                                border: Border.all(
                                  color: target == '_blank'
                                      ? DVStudioStyle.ink
                                      : DVStudioStyle.line,
                                ),
                              ),
                              alignment: .center,
                              child: const Text('New tab (_blank)',
                                  style: TextStyle(
                                      fontSize: 12, color: DVStudioStyle.ink)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (itemToEdit == null && allItemsFlat.isNotEmpty) ...<Widget>[
                      const SizedBox(height: DVStudioStyle.space3),
                      const Text('Parent Menu Item',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink)),
                      const SizedBox(height: DVStudioStyle.space1),
                      Container(
                        padding: const .symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: DVStudioStyle.surface,
                          borderRadius:
                              BorderRadius.circular(DVStudioStyle.radius),
                          border: Border.all(color: DVStudioStyle.line),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: parentId,
                            isExpanded: true,
                            dropdownColor: DVStudioStyle.surface,
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Top level (no parent)',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: DVStudioStyle.ink)),
                              ),
                              for (final DVStudioMenuItem i in allItemsFlat)
                                DropdownMenuItem<String?>(
                                  value: i.id,
                                  child: Text('Under "${i.label}"',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: DVStudioStyle.ink)),
                                ),
                            ],
                            onChanged: (String? val) {
                              setDialogState(() => parentId = val);
                            },
                          ),
                        ),
                      ),
                    ],
                    if (dialogError != null) ...<Widget>[
                      const SizedBox(height: DVStudioStyle.space3),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: DVStudioStyle.muted)),
                ),
                DVStudioControl(
                  label: itemToEdit == null ? 'Add to menu' : 'Save changes',
                  enabled: label.trim().isNotEmpty && url.trim().isNotEmpty,
                  primary: true,
                  icon: itemToEdit == null
                      ? DVStudioIcons.add
                      : Icons.check,
                  onTap: () {
                    if (label.trim().isEmpty || url.trim().isEmpty) {
                      setDialogState(() {
                        dialogError = 'Label and URL are required.';
                      });
                      return;
                    }
                    if (itemToEdit == null) {
                      // Add new item
                      final DVStudioMenuItem newItem = DVStudioMenuItem(
                        id: 'link-${DateTime.now().millisecondsSinceEpoch}',
                        label: label.trim(),
                        url: url.trim(),
                        target: target,
                      );
                      final List<DVStudioMenuItem> updatedItems =
                          _addItemToTree(menu.items, newItem, parentId);
                      _updateWorkingMenu(menu.copyWith(items: updatedItems));
                    } else {
                      // Edit existing item
                      final DVStudioMenuItem updatedItem = itemToEdit.copyWith(
                        label: label.trim(),
                        url: url.trim(),
                        target: target,
                      );
                      final List<DVStudioMenuItem> updatedItems =
                          _updateItemInTree(menu.items, updatedItem);
                      _updateWorkingMenu(menu.copyWith(items: updatedItems));
                    }
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Tree manipulation helpers --------------------------------------------

  List<DVStudioMenuItem> _addItemToTree(
    List<DVStudioMenuItem> list,
    DVStudioMenuItem item,
    String? parentId,
  ) {
    if (parentId == null) {
      return <DVStudioMenuItem>[...list, item];
    }
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        if (m.id == parentId)
          m.copyWith(children: <DVStudioMenuItem>[...m.children, item])
        else
          m.copyWith(children: _addItemToTree(m.children, item, parentId)),
    ];
  }

  List<DVStudioMenuItem> _updateItemInTree(
    List<DVStudioMenuItem> list,
    DVStudioMenuItem updated,
  ) {
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        if (m.id == updated.id)
          updated.copyWith(children: m.children)
        else
          m.copyWith(children: _updateItemInTree(m.children, updated)),
    ];
  }

  List<DVStudioMenuItem> _removeItemFromTree(
    List<DVStudioMenuItem> list,
    String id,
  ) {
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        if (m.id != id)
          m.copyWith(children: _removeItemFromTree(m.children, id)),
    ];
  }

  List<DVStudioMenuItem> _moveItemUp(
    List<DVStudioMenuItem> list,
    String targetId,
  ) {
    final int index = list.indexWhere((DVStudioMenuItem m) => m.id == targetId);
    if (index > 0) {
      final List<DVStudioMenuItem> copy = List<DVStudioMenuItem>.of(list);
      final DVStudioMenuItem temp = copy[index - 1];
      copy[index - 1] = copy[index];
      copy[index] = temp;
      return copy;
    }
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        m.copyWith(children: _moveItemUp(m.children, targetId)),
    ];
  }

  List<DVStudioMenuItem> _moveItemDown(
    List<DVStudioMenuItem> list,
    String targetId,
  ) {
    final int index = list.indexWhere((DVStudioMenuItem m) => m.id == targetId);
    if (index >= 0 && index < list.length - 1) {
      final List<DVStudioMenuItem> copy = List<DVStudioMenuItem>.of(list);
      final DVStudioMenuItem temp = copy[index + 1];
      copy[index + 1] = copy[index];
      copy[index] = temp;
      return copy;
    }
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        m.copyWith(children: _moveItemDown(m.children, targetId)),
    ];
  }

  List<DVStudioMenuItem> _indentItem(
    List<DVStudioMenuItem> list,
    String targetId,
  ) {
    final int index = list.indexWhere((DVStudioMenuItem m) => m.id == targetId);
    if (index > 0) {
      final DVStudioMenuItem target = list[index];
      final DVStudioMenuItem prev = list[index - 1];
      final DVStudioMenuItem newPrev = prev.copyWith(
        children: <DVStudioMenuItem>[...prev.children, target],
      );
      final List<DVStudioMenuItem> copy = List<DVStudioMenuItem>.of(list);
      copy.removeAt(index);
      copy[index - 1] = newPrev;
      return copy;
    }
    return <DVStudioMenuItem>[
      for (final DVStudioMenuItem m in list)
        m.copyWith(children: _indentItem(m.children, targetId)),
    ];
  }

  List<DVStudioMenuItem> _outdentItem(
    List<DVStudioMenuItem> list,
    String targetId,
  ) {
    for (int i = 0; i < list.length; i++) {
      final DVStudioMenuItem parent = list[i];
      final int childIndex =
          parent.children.indexWhere((DVStudioMenuItem c) => c.id == targetId);
      if (childIndex >= 0) {
        final DVStudioMenuItem child = parent.children[childIndex];
        final List<DVStudioMenuItem> newChildren =
            List<DVStudioMenuItem>.of(parent.children)..removeAt(childIndex);
        final DVStudioMenuItem newParent = parent.copyWith(children: newChildren);
        final List<DVStudioMenuItem> copy = List<DVStudioMenuItem>.of(list);
        copy[i] = newParent;
        copy.insert(i + 1, child);
        return copy;
      }
      final List<DVStudioMenuItem> sub =
          _outdentItem(parent.children, targetId);
      if (sub != parent.children) {
        final List<DVStudioMenuItem> copy = List<DVStudioMenuItem>.of(list);
        copy[i] = parent.copyWith(children: sub);
        return copy;
      }
    }
    return list;
  }

  List<DVStudioMenuItem> _flattenItems(List<DVStudioMenuItem> items) {
    final List<DVStudioMenuItem> result = <DVStudioMenuItem>[];
    for (final DVStudioMenuItem item in items) {
      result.add(item);
      result.addAll(_flattenItems(item.children));
    }
    return result;
  }

  List<_FlatNode> _buildFlatNodes(
    List<DVStudioMenuItem> items, [
    int depth = 0,
    DVStudioMenuItem? parent,
  ]) {
    final List<_FlatNode> nodes = <_FlatNode>[];
    for (int i = 0; i < items.length; i++) {
      final DVStudioMenuItem item = items[i];
      nodes.add(_FlatNode(
        item: item,
        depth: depth,
        parent: parent,
        index: i,
        count: items.length,
      ));
      if (item.children.isNotEmpty) {
        nodes.addAll(_buildFlatNodes(item.children, depth + 1, item));
      }
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<DVStudioMenu> menus, List<String> locations})>(
      future: _data,
      builder: (
        BuildContext context,
        AsyncSnapshot<({List<DVStudioMenu> menus, List<String> locations})>
            snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _workingMenu == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && _workingMenu == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Error loading menus: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: DVStudioStyle.space2),
                DVStudioControl(
                  label: 'Retry',
                  enabled: true,
                  onTap: () => _reload(),
                ),
              ],
            ),
          );
        }

        final List<DVStudioMenu> menus = snapshot.data?.menus ?? <DVStudioMenu>[];
        final List<String> locations =
            snapshot.data?.locations ?? const <String>['header', 'footer'];

        return Container(
          color: DVStudioStyle.canvas,
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              // Section Header
              _buildTopHeader(menus, locations),
              if (_statusMessage != null)
                Container(
                  color: Colors.green.withValues(alpha: 0.15),
                  padding: const .symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () => setState(() => _statusMessage = null),
                        tooltip: 'Dismiss message',
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Container(
                  color: Colors.red.withValues(alpha: 0.15),
                  padding: const .symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () => setState(() => _error = null),
                        tooltip: 'Dismiss error',
                      ),
                    ],
                  ),
                ),
              // Body editor
              Expanded(
                child: _workingMenu == null
                    ? _buildEmptyState(locations)
                    : _buildMenuEditor(locations),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(List<DVStudioMenu> menus, List<String> locations) {
    return Container(
      padding: const .symmetric(
          horizontal: DVStudioStyle.space4, vertical: DVStudioStyle.space3),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(DVStudioIcons.menus,
              size: 20, color: DVStudioStyle.ink),
          const SizedBox(width: DVStudioStyle.space2),
          const Text(
            'Menus & Navigation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DVStudioStyle.ink,
            ),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          // Menu Switcher Dropdown
          if (menus.isNotEmpty)
            Container(
              height: 34,
              padding: const .symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: DVStudioStyle.canvas,
                borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                border: Border.all(color: DVStudioStyle.line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedId,
                  dropdownColor: DVStudioStyle.surface,
                  items: <DropdownMenuItem<String>>[
                    for (final DVStudioMenu m in menus)
                      DropdownMenuItem<String>(
                        value: m.id,
                        child: Text(
                          '${m.name} (${_capitalize(m.location)})',
                          style: const TextStyle(
                              fontSize: 13, color: DVStudioStyle.ink),
                        ),
                      ),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      final DVStudioMenu? chosen = menus
                          .where((DVStudioMenu m) => m.id == val)
                          .firstOrNull;
                      if (chosen != null) _selectMenu(chosen);
                    }
                  },
                ),
              ),
            ),
          const Spacer(),
          // Action Buttons
          DVStudioControl(
            label: 'New menu',
            enabled: true,
            icon: DVStudioIcons.add,
            onTap: () => _openNewMenuDialog(locations),
          ),
          if (_workingMenu != null) ...<Widget>[
            const SizedBox(width: DVStudioStyle.space2),
            DVStudioControl(
              label: 'Delete menu',
              enabled: true,
              icon: DVStudioIcons.delete,
              onTap: _deleteCurrentMenu,
            ),
            const SizedBox(width: DVStudioStyle.space2),
            DVStudioControl(
              label: _saving ? 'Saving...' : 'Save menu',
              enabled: _dirty && !_saving,
              primary: true,
              icon: Icons.save_outlined,
              onTap: _save,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(List<String> locations) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(DVStudioIcons.menus,
              size: 48, color: DVStudioStyle.faint),
          const SizedBox(height: DVStudioStyle.space3),
          const Text('No menus created yet.',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DVStudioStyle.ink)),
          const SizedBox(height: DVStudioStyle.space1),
          const Text(
              'Create a navigation menu to manage header and footer links.',
              style: TextStyle(fontSize: 13, color: DVStudioStyle.muted)),
          const SizedBox(height: DVStudioStyle.space4),
          DVStudioControl(
            label: 'Create menu',
            enabled: true,
            primary: true,
            icon: DVStudioIcons.add,
            onTap: () => _openNewMenuDialog(locations),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuEditor(List<String> locations) {
    final DVStudioMenu menu = _workingMenu!;
    final List<_FlatNode> flatNodes = _buildFlatNodes(menu.items);

    return SingleChildScrollView(
      padding: const .all(DVStudioStyle.space4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              // Settings card: Name & Location
              Container(
                padding: const .all(DVStudioStyle.space4),
                decoration: BoxDecoration(
                  color: DVStudioStyle.surface,
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                  border: Border.all(color: DVStudioStyle.line),
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: .start,
                            children: <Widget>[
                              const Text('Menu Name',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DVStudioStyle.ink)),
                              const SizedBox(height: DVStudioStyle.space1),
                              DVStudioTextInput(
                                value: menu.name,
                                placeholder: 'Menu Name',
                                onChanged: (String v) {
                                  _updateWorkingMenu(menu.copyWith(name: v));
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: DVStudioStyle.space4),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: .start,
                            children: <Widget>[
                              const Text('Display Location',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DVStudioStyle.ink)),
                              const SizedBox(height: DVStudioStyle.space1),
                              Container(
                                height: 38,
                                padding: const .symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: DVStudioStyle.surface,
                                  borderRadius: BorderRadius.circular(
                                      DVStudioStyle.radius),
                                  border: Border.all(color: DVStudioStyle.line),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: locations.contains(menu.location)
                                        ? menu.location
                                        : 'custom',
                                    isExpanded: true,
                                    dropdownColor: DVStudioStyle.surface,
                                    items: <DropdownMenuItem<String>>[
                                      for (final String loc in locations)
                                        DropdownMenuItem<String>(
                                          value: loc,
                                          child: Text(_capitalize(loc),
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: DVStudioStyle.ink)),
                                        ),
                                      const DropdownMenuItem<String>(
                                        value: 'custom',
                                        child: Text('Custom',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: DVStudioStyle.ink)),
                                      ),
                                    ],
                                    onChanged: (String? val) {
                                      if (val != null) {
                                        _updateWorkingMenu(
                                            menu.copyWith(location: val));
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DVStudioStyle.space4),

              // Menu Structure Card
              Container(
                decoration: BoxDecoration(
                  color: DVStudioStyle.surface,
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                  border: Border.all(color: DVStudioStyle.line),
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    // Structure Header
                    Padding(
                      padding: const .all(DVStudioStyle.space4),
                      child: Row(
                        children: <Widget>[
                          const Text(
                            'Menu Structure',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DVStudioStyle.ink,
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                          Container(
                            padding: const .symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: DVStudioStyle.canvas,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${flatNodes.length} items',
                              style: const TextStyle(
                                  fontSize: 11, color: DVStudioStyle.muted),
                            ),
                          ),
                          const Spacer(),
                          DVStudioControl(
                            label: 'Add link',
                            enabled: true,
                            icon: DVStudioIcons.add,
                            onTap: () => _openAddLinkDialog(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: DVStudioStyle.line),

                    if (flatNodes.isEmpty)
                      Padding(
                        padding: const .all(DVStudioStyle.space6),
                        child: Center(
                          child: Column(
                            children: <Widget>[
                              const Icon(Icons.link_off,
                                  size: 32, color: DVStudioStyle.faint),
                              const SizedBox(height: DVStudioStyle.space2),
                              const Text(
                                'This menu has no navigation links.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: DVStudioStyle.muted),
                              ),
                              const SizedBox(height: DVStudioStyle.space3),
                              DVStudioControl(
                                label: 'Add first link',
                                enabled: true,
                                icon: DVStudioIcons.add,
                                onTap: () => _openAddLinkDialog(),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: flatNodes.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1, color: DVStudioStyle.line),
                        itemBuilder: (BuildContext context, int index) {
                          final _FlatNode node = flatNodes[index];
                          return _buildMenuItemRow(node, menu);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemRow(_FlatNode node, DVStudioMenu menu) {
    final DVStudioMenuItem item = node.item;
    final double indent = node.depth * 28.0;

    return Container(
      color: DVStudioStyle.surface,
      padding: EdgeInsets.only(
        left: DVStudioStyle.space4 + indent,
        right: DVStudioStyle.space4,
        top: 8,
        bottom: 8,
      ),
      child: Row(
        children: <Widget>[
          if (node.depth > 0)
            const Padding(
              padding: .only(right: 8),
              child: Icon(Icons.subdirectory_arrow_right,
                  size: 16, color: DVStudioStyle.faint),
            )
          else
            const Padding(
              padding: .only(right: 8),
              child: Icon(Icons.drag_indicator,
                  size: 16, color: DVStudioStyle.faint),
            ),
          // Label and URL
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DVStudioStyle.ink,
                      ),
                    ),
                    if (item.target == '_blank') ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const .symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: DVStudioStyle.canvas,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: DVStudioStyle.line),
                        ),
                        child: const Text(
                          'New tab',
                          style: TextStyle(
                              fontSize: 10, color: DVStudioStyle.muted),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.url,
                  style: const TextStyle(
                      fontSize: 12, color: DVStudioStyle.muted),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            tooltip: 'Move up',
            onPressed: node.index > 0
                ? () {
                    _updateWorkingMenu(menu.copyWith(
                      items: _moveItemUp(menu.items, item.id),
                    ));
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 16),
            tooltip: 'Move down',
            onPressed: node.index < node.count - 1
                ? () {
                    _updateWorkingMenu(menu.copyWith(
                      items: _moveItemDown(menu.items, item.id),
                    ));
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.format_indent_increase, size: 16),
            tooltip: 'Indent (nest under previous)',
            onPressed: node.index > 0
                ? () {
                    _updateWorkingMenu(menu.copyWith(
                      items: _indentItem(menu.items, item.id),
                    ));
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.format_indent_decrease, size: 16),
            tooltip: 'Outdent',
            onPressed: node.depth > 0
                ? () {
                    _updateWorkingMenu(menu.copyWith(
                      items: _outdentItem(menu.items, item.id),
                    ));
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: 'Edit link',
            onPressed: () => _openAddLinkDialog(itemToEdit: item),
          ),
          IconButton(
            icon: const Icon(DVStudioIcons.delete,
                size: 16, color: Colors.redAccent),
            tooltip: 'Delete item',
            onPressed: () {
              _updateWorkingMenu(menu.copyWith(
                items: _removeItemFromTree(menu.items, item.id),
              ));
            },
          ),
        ],
      ),
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  static String _slugify(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

class _FlatNode {
  const _FlatNode({
    required this.item,
    required this.depth,
    this.parent,
    required this.index,
    required this.count,
  });

  final DVStudioMenuItem item;
  final int depth;
  final DVStudioMenuItem? parent;
  final int index;
  final int count;
}

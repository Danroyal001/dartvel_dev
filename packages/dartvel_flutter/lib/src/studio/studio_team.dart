/// Studio Team and Access section: teammates directory, roles, permissions,
/// role editing, invite dialog, and configurable entitlement gate.
import 'dart:async';

import 'package:flutter/material.dart';

import 'studio_server.dart';
import 'studio_style.dart';

/// The Team and Access control section in Studio.
class DVStudioTeamSection extends StatefulWidget {
  const DVStudioTeamSection({super.key, required this.client});

  final DVStudioClient client;

  @override
  State<DVStudioTeamSection> createState() => _DVStudioTeamSectionState();
}

class _DVStudioTeamSectionState extends State<DVStudioTeamSection> {
  late Future<Map<String, Object?>> _data = _load();
  String _activeTab = 'teammates'; // 'teammates' | 'roles'
  String _searchQuery = '';
  String _roleFilter = 'all';
  bool _busy = false;
  String? _error;

  /// Grant waiting for confirmation with warning reason.
  ({String userId, String tenant, String message, String action, String? newRole})?
      _confirming;

  Future<Map<String, Object?>> _load() async {
    try {
      final Map<String, Object?> teamData = await widget.client.team();
      if (teamData.isNotEmpty) return teamData;
    } on DVStudioRemoteError catch (error) {
      if (error.status != 404) rethrow;
    }
    // A server from before roles answers only who holds a grant: everybody
    // on it is an administrator, and there is no role to choose or make.
    return <String, Object?>{
      'grants': await widget.client.grants(),
      'roles': const <Map<String, Object?>>[
        <String, Object?>{'id': 'admin', 'name': 'Administrator', 'isBuiltIn': true},
      ],
      'entitlements': const <String, Object?>{
        'rolesEnabled': false,
        'customRolesEnabled': false,
      },
    };
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _openInviteDialog(List<Map<String, Object?>> availableRoles) async {
    String account = '';
    // The least a teammate can be given, until somebody chooses more.
    String selectedRole = availableRoles.any((Map<String, Object?> r) => r['id'] == 'viewer')
        ? 'viewer'
        : (availableRoles.isNotEmpty ? '${availableRoles.first['id']}' : 'viewer');
    String? dialogError;
    bool dialogBusy = false;

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
              title: const Text('Invite Teammate',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink)),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    const Text(
                      'Enter their email address or account ID to grant Studio access.',
                      style:
                          TextStyle(fontSize: 13, color: DVStudioStyle.muted),
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    DVStudioTextInput(
                      key: const ValueKey<String>('dv-studio-grant-account'),
                      semanticLabel: 'Email address or account ID',
                      placeholder: 'teammate@example.com or user_123',
                      icon: Icons.person_add_alt_1_outlined,
                      onChanged: (String v) => account = v,
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    const Text('Assigned Role',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DVStudioStyle.muted)),
                    const SizedBox(height: DVStudioStyle.space1),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const .symmetric(
                            horizontal: DVStudioStyle.space2, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(DVStudioStyle.radiusSmall),
                          borderSide: const BorderSide(color: DVStudioStyle.line),
                        ),
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final Map<String, Object?> r in availableRoles)
                          DropdownMenuItem<String>(
                            value: '${r['id']}',
                            child: Text('${r['name'] ?? r['id']}',
                                style: const TextStyle(
                                    fontSize: 13, color: DVStudioStyle.ink)),
                          ),
                      ],
                      onChanged: (String? v) {
                        if (v != null) setDialogState(() => selectedRole = v);
                      },
                    ),
                    if (dialogError != null) ...<Widget>[
                      const SizedBox(height: DVStudioStyle.space2),
                      Text(dialogError!,
                          style: const TextStyle(
                              fontSize: 12, color: DVStudioStyle.danger)),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: dialogBusy
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                DVStudioControl(
                  key: const ValueKey<String>('dv-studio-grant-submit'),
                  label: dialogBusy ? 'Granting...' : 'Grant access',
                  enabled: !dialogBusy,
                  primary: true,
                  onTap: dialogBusy
                      ? null
                      : () async {
                          final String cleanAccount = account.trim();
                          if (cleanAccount.isEmpty) {
                            setDialogState(() =>
                                dialogError = 'Please enter an account address or ID.');
                            return;
                          }
                          setDialogState(() {
                            dialogBusy = true;
                            dialogError = null;
                          });
                          try {
                            await widget.client.grant(cleanAccount,
                                role: selectedRole);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            _reload();
                          } catch (e) {
                            setDialogState(() {
                              dialogBusy = false;
                              dialogError = e.toString();
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

  Future<void> _changeRole(
      String userId, String tenant, String currentRole, List<Map<String, Object?>> roles) async {
    String selectedRole = currentRole;
    String? dialogError;
    bool dialogBusy = false;

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
              title: Text('Change Role for $userId',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  const Text('Select the new permission level for this teammate:',
                      style: TextStyle(fontSize: 13, color: DVStudioStyle.muted)),
                  const SizedBox(height: DVStudioStyle.space3),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const .symmetric(
                          horizontal: DVStudioStyle.space2, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DVStudioStyle.radiusSmall),
                        borderSide: const BorderSide(color: DVStudioStyle.line),
                      ),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Map<String, Object?> r in roles)
                        DropdownMenuItem<String>(
                          value: '${r['id']}',
                          child: Text('${r['name'] ?? r['id']}',
                              style: const TextStyle(
                                  fontSize: 13, color: DVStudioStyle.ink)),
                        ),
                    ],
                    onChanged: (String? v) {
                      if (v != null) setDialogState(() => selectedRole = v);
                    },
                  ),
                  if (dialogError != null) ...<Widget>[
                    const SizedBox(height: DVStudioStyle.space2),
                    Text(dialogError!,
                        style: const TextStyle(
                            fontSize: 12, color: DVStudioStyle.danger)),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: dialogBusy
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                DVStudioControl(
                  key: const ValueKey<String>('dv-studio-role-save'),
                  label: dialogBusy ? 'Saving...' : 'Save role',
                  enabled: !dialogBusy,
                  primary: true,
                  onTap: dialogBusy
                      ? null
                      : () async {
                          if (selectedRole == currentRole) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }
                          setDialogState(() {
                            dialogBusy = true;
                            dialogError = null;
                          });
                          try {
                            await widget.client.updateRole(userId, selectedRole,
                                tenant: tenant);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            _reload();
                          } on DVStudioRemoteError catch (e) {
                            if (e.status == 409) {
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                              setState(() {
                                _confirming = (
                                  userId: userId,
                                  tenant: tenant,
                                  message: e.message,
                                  action: 'demote',
                                  newRole: selectedRole,
                                );
                              });
                            } else {
                              setDialogState(() {
                                dialogBusy = false;
                                dialogError = e.message;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              dialogBusy = false;
                              dialogError = e.toString();
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

  Future<void> _revoke(String userId, String tenant, {bool confirm = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.revoke(userId, tenant: tenant, confirm: confirm);
      if (!mounted) return;
      setState(() => _confirming = null);
      _reload();
    } on DVStudioRemoteError catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.status == 409 && !confirm) {
          _confirming = (
            userId: userId,
            tenant: tenant,
            message: error.message,
            action: 'revoke',
            newRole: null,
          );
        } else {
          _error = error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<Map<String, Object?>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Error loading team data: ${snapshot.error}',
                    style: const TextStyle(color: DVStudioStyle.danger)),
                const SizedBox(height: DVStudioStyle.space2),
                DVStudioControl(label: 'Retry', enabled: true, onTap: _reload),
              ],
            ),
          );
        }

        final Map<String, Object?> data = snapshot.data ?? const <String, Object?>{};
        final List<Map<String, Object?>> grants = <Map<String, Object?>>[
          for (final Object? g in (data['grants'] as List?) ?? const <Object?>[])
            if (g is Map) g.cast<String, Object?>(),
        ];
        final List<Map<String, Object?>> roles = <Map<String, Object?>>[
          for (final Object? r in (data['roles'] as List?) ?? const <Object?>[])
            if (r is Map) r.cast<String, Object?>(),
        ];

        return Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            _buildHeader(roles),
            _buildConfirmationBanner(),
            if (_error != null)
              Container(
                margin: const .symmetric(horizontal: DVStudioStyle.space5),
                padding: const .all(DVStudioStyle.space3),
                decoration: BoxDecoration(
                  color: DVStudioStyle.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        color: DVStudioStyle.danger, fontSize: 13)),
              ),
            Expanded(
              child: _activeTab == 'teammates'
                  ? _buildTeammatesTab(grants, roles)
                  : _buildRolesTab(roles),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<Map<String, Object?>> roles) {
    return Container(
      padding: const .all(DVStudioStyle.space5),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Team & Access',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: DVStudioStyle.ink)),
                SizedBox(height: 2),
                Text(
                    'Manage teammates, assign roles, and configure administrative access.',
                    style: TextStyle(fontSize: 13, color: DVStudioStyle.muted)),
              ],
            ),
          ),
          // View Switcher (Teammates vs Roles)
          Container(
            padding: const .all(2),
            decoration: BoxDecoration(
              color: DVStudioStyle.canvas,
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
              border: Border.all(color: DVStudioStyle.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _tabButton('teammates', 'Teammates', Icons.people_outline),
                _tabButton('roles', 'Roles & Permissions', Icons.badge_outlined),
              ],
            ),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          DVStudioControl(
            key: const ValueKey<String>('dv-studio-invite-teammate'),
            label: 'Invite teammate',
            enabled: true,
            primary: true,
            icon: Icons.person_add_alt_1_outlined,
            onTap: () => unawaited(_openInviteDialog(roles)),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String id, String label, IconData icon) {
    final bool isSelected = _activeTab == id;
    return InkWell(
      key: ValueKey<String>('dv-studio-tab-$id'),
      onTap: () => setState(() => _activeTab = id),
      borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      child: Container(
        padding: const .symmetric(horizontal: DVStudioStyle.space3, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DVStudioStyle.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon,
                size: 16,
                color: isSelected ? DVStudioStyle.accent : DVStudioStyle.muted),
            const SizedBox(width: DVStudioStyle.space1),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? DVStudioStyle.ink : DVStudioStyle.muted,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationBanner() {
    final confirming = _confirming;
    if (confirming == null) return const SizedBox.shrink();

    return Container(
      margin: const .all(DVStudioStyle.space5),
      padding: const .all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          DVStudioStyle.warning.withValues(alpha: 0.1),
          DVStudioStyle.surface,
        ),
        border: Border.all(color: DVStudioStyle.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded,
              size: 20, color: DVStudioStyle.warning),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: Text(confirming.message,
                style: const TextStyle(
                    fontSize: 13,
                    color: DVStudioStyle.ink,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          DVStudioControl(
            key: const ValueKey<String>('dv-studio-revoke-cancel'),
            label: 'Keep it',
            enabled: true,
            onTap: () => setState(() => _confirming = null),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          DVStudioControl(
            key: const ValueKey<String>('dv-studio-revoke-confirm'),
            label: confirming.action == 'demote' ? 'Demote anyway' : 'Revoke anyway',
            enabled: !_busy,
            primary: true,
            icon: Icons.check,
            onTap: _busy
                ? null
                : () async {
                    if (confirming.action == 'demote' && confirming.newRole != null) {
                      await widget.client.updateRole(
                          confirming.userId, confirming.newRole!,
                          tenant: confirming.tenant, confirm: true);
                      setState(() => _confirming = null);
                      _reload();
                    } else {
                      await _revoke(confirming.userId, confirming.tenant,
                          confirm: true);
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTeammatesTab(
      List<Map<String, Object?>> grants, List<Map<String, Object?>> roles) {
    final List<Map<String, Object?>> filtered = grants.where((Map<String, Object?> g) {
      final String email = '${g['email'] ?? ''}'.toLowerCase();
      final String user = '${g['userId'] ?? ''}'.toLowerCase();
      final String role = '${g['role'] ?? 'admin'}'.toLowerCase();
      final String q = _searchQuery.toLowerCase();

      final bool matchesQuery =
          q.isEmpty || email.contains(q) || user.contains(q) || role.contains(q);
      final bool matchesRole =
          _roleFilter == 'all' || role == _roleFilter.toLowerCase();
      return matchesQuery && matchesRole;
    }).toList();

    return Column(
      children: <Widget>[
        // Filter bar
        Padding(
          padding: const .symmetric(
              horizontal: DVStudioStyle.space5, vertical: DVStudioStyle.space3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DVStudioTextInput(
                  key: const ValueKey<String>('dv-studio-team-search'),
                  placeholder: 'Search teammates by name, email, or role...',
                  icon: Icons.search,
                  onChanged: (String v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              DropdownButton<String>(
                key: const ValueKey<String>('dv-studio-role-filter'),
                value: _roleFilter,
                underline: const SizedBox.shrink(),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('All roles', style: TextStyle(fontSize: 13)),
                  ),
                  for (final Map<String, Object?> r in roles)
                    DropdownMenuItem<String>(
                      value: '${r['id']}',
                      child: Text('${r['name'] ?? r['id']}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (String? v) {
                  if (v != null) setState(() => _roleFilter = v);
                },
              ),
            ],
          ),
        ),
        // Table view
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.people_outline,
                          size: 40, color: DVStudioStyle.muted),
                      const SizedBox(height: DVStudioStyle.space2),
                      const Text('No teammates found matching your search.',
                          style: TextStyle(
                              fontSize: 14, color: DVStudioStyle.muted)),
                      const SizedBox(height: DVStudioStyle.space2),
                      DVStudioControl(
                        label: 'Clear filters',
                        enabled: true,
                        onTap: () => setState(() {
                          _searchQuery = '';
                          _roleFilter = 'all';
                        }),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const .symmetric(horizontal: DVStudioStyle.space5),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: DVStudioStyle.line),
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, Object?> grant = filtered[index];
                    final String userId = '${grant['userId'] ?? ''}';
                    final String? email = grant['email'] as String?;
                    final String role = '${grant['role'] ?? 'admin'}';
                    final String tenant = '${grant['tenant'] ?? 'default'}';
                    final bool isYou = grant['you'] == true;
                    final String grantedDate = _formatDate(grant['grantedAt']);

                    final String initial = (email ?? userId).isNotEmpty
                        ? (email ?? userId).substring(0, 1).toUpperCase()
                        : '?';

                    return Padding(
                      key: ValueKey<String>('dv-studio-teammate-$userId'),
                      padding: const .symmetric(vertical: DVStudioStyle.space3),
                      child: Row(
                        children: <Widget>[
                          // Avatar bubble
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isYou
                                  ? DVStudioStyle.accent
                                  : DVStudioStyle.canvas,
                              shape: BoxShape.circle,
                              border: Border.all(color: DVStudioStyle.line),
                            ),
                            child: Text(
                              initial,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isYou ? Colors.white : DVStudioStyle.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space3),
                          // User info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Text(
                                      email ?? userId,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: DVStudioStyle.ink),
                                    ),
                                    if (isYou) ...<Widget>[
                                      const SizedBox(width: DVStudioStyle.space1),
                                      Container(
                                        padding: const .symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: DVStudioStyle.accentSoft,
                                          borderRadius: BorderRadius.circular(
                                              DVStudioStyle.radiusSmall),
                                        ),
                                        child: const Text('You',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: DVStudioStyle.accent)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (email != null && email != userId)
                                  Text(userId,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: DVStudioStyle.muted)),
                              ],
                            ),
                          ),
                          // Role badge
                          InkWell(
                            key: ValueKey<String>('dv-studio-change-role-$userId'),
                            onTap: () => unawaited(
                                _changeRole(userId, tenant, role, roles)),
                            borderRadius:
                                BorderRadius.circular(DVStudioStyle.radiusSmall),
                            child: Container(
                              padding: const .symmetric(
                                  horizontal: DVStudioStyle.space2, vertical: 4),
                              decoration: BoxDecoration(
                                color: _roleBadgeColor(role).withValues(alpha: 0.1),
                                border: Border.all(
                                    color: _roleBadgeColor(role)
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(
                                    DVStudioStyle.radiusSmall),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    _roleLabel(role, roles),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _roleBadgeColor(role),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_drop_down,
                                      size: 16, color: _roleBadgeColor(role)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space4),
                          // Tenant
                          Text(tenant,
                              style: const TextStyle(
                                  fontSize: 12, color: DVStudioStyle.muted)),
                          const SizedBox(width: DVStudioStyle.space4),
                          // Date
                          Text(grantedDate,
                              style: const TextStyle(
                                  fontSize: 12, color: DVStudioStyle.muted)),
                          const SizedBox(width: DVStudioStyle.space4),
                          // Actions
                          DVStudioIconButton(
                            key: ValueKey<String>('dv-studio-revoke-$userId'),
                            icon: Icons.person_remove_outlined,
                            tooltip: 'Revoke access',
                            onTap: _busy
                                ? null
                                : () => unawaited(_revoke(userId, tenant)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRolesTab(List<Map<String, Object?>> roles) {
    return ListView.separated(
      padding: const .all(DVStudioStyle.space5),
      itemCount: roles.length,
      separatorBuilder: (_, __) => const SizedBox(height: DVStudioStyle.space3),
      itemBuilder: (BuildContext context, int index) {
        final Map<String, Object?> role = roles[index];
        final String id = '${role['id']}';
        final String name = '${role['name'] ?? id}';
        final String desc = '${role['description'] ?? ''}';
        final List<Object?> perms = (role['permissions'] as List?) ?? const <Object?>[];
        final bool isBuiltIn = role['isBuiltIn'] != false;

        return Container(
          key: ValueKey<String>('dv-studio-role-card-$id'),
          padding: const .all(DVStudioStyle.space4),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            border: Border.all(color: DVStudioStyle.line),
          ),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DVStudioStyle.ink)),
                  const SizedBox(width: DVStudioStyle.space2),
                  Container(
                    padding:
                        const .symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isBuiltIn
                          ? DVStudioStyle.canvas
                          : DVStudioStyle.accentSoft,
                      borderRadius:
                          BorderRadius.circular(DVStudioStyle.radiusSmall),
                      border: Border.all(
                          color: isBuiltIn
                              ? DVStudioStyle.line
                              : DVStudioStyle.accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(isBuiltIn ? 'Built-in' : 'Custom',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isBuiltIn
                                ? DVStudioStyle.muted
                                : DVStudioStyle.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 13, color: DVStudioStyle.muted)),
              const SizedBox(height: DVStudioStyle.space3),
              const Text('Granted Permissions:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DVStudioStyle.ink)),
              const SizedBox(height: DVStudioStyle.space1),
              Wrap(
                spacing: DVStudioStyle.space1,
                runSpacing: DVStudioStyle.space1,
                children: <Widget>[
                  for (final Object? p in perms)
                    Container(
                      padding: const .symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DVStudioStyle.canvas,
                        borderRadius:
                            BorderRadius.circular(DVStudioStyle.radiusSmall),
                        border: Border.all(color: DVStudioStyle.line),
                      ),
                      child: Text('$p',
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: DVStudioStyle.ink)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _roleBadgeColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return DVStudioStyle.accent;
      case 'editor':
        return DVStudioStyle.success;
      case 'author':
        return const Color(0xFFE67E22);
      case 'viewer':
      default:
        return DVStudioStyle.muted;
    }
  }

  String _roleLabel(String roleId, List<Map<String, Object?>> roles) {
    for (final Map<String, Object?> r in roles) {
      if (r['id'] == roleId) return '${r['name'] ?? roleId}';
    }
    return roleId.substring(0, 1).toUpperCase() + roleId.substring(1);
  }

  String _formatDate(Object? value) {
    if (value is! String) return '';
    try {
      final DateTime dt = DateTime.parse(value);
      return '${dt.year}-${_twoDigits(dt.month)}-${_twoDigits(dt.day)}';
    } catch (_) {
      return value.toString();
    }
  }

  String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';
}

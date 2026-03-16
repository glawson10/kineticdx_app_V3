// lib/features/shell/clinician_shell.dart
//
// Clinician app shell: sidebar (expanded/collapsed) on wide screens,
// bottom nav on narrow. Sidebar spec: 232px expanded, 72px collapsed,
// 220ms animation, grouped nav (Primary, Finance, Admin), active/hover states.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/clinic_context.dart';
import '../../app/clinic_session.dart';
import '../../data/repositories/clinic_repository.dart';
import '../../config/permission_keys.dart';
import '../../staff/screens/staff_member_screen.dart';
import '../../features/clinic/settings/ui/clinic_opening_hours_screen.dart';
import '../../ui/design_tokens.dart';

import '../home/clinic_home_shell.dart';
import '../public/ui/intro_screen.dart';
import 'shell_overlay_scope.dart';

// Screens (tab content is built by ClinicHomeShell; only profile menu screens here)
import '/features/clinic_settings/clinic_profile_screen.dart';

import 'shell_nav_model.dart';

// Re-export for callers that import clinician_shell only.
export 'shell_nav_model.dart' show ClinicianTab;

class ClinicianShell extends StatelessWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;

  /// When set, tab changes (sidebar/bottom nav) call this instead of pushing a new route.
  /// Keeps the same route mounted and avoids Firestore stream cancel/relisten issues.
  final ValueChanged<ClinicianTab>? onTabChanged;

  const ClinicianShell({
    super.key,
    required this.selected,
    required this.child,
    this.title,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    // If clinic context isn't ready, just show the child (no shell).
    if (!clinicCtx.hasClinic) {
      return Scaffold(body: child);
    }

    // ✅ KEY FIX:
    // Once a clinic is selected, we wait for session/perms to load before
    // building NavigationRail/NavigationBar. This prevents "null perms" causing
    // tabs like Invoices to flash then disappear.
    if (!clinicCtx.hasSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading clinic…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 1100;

        return PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (_, __) {
            if (selected != ClinicianTab.calendar) {
              _navigateTo(context, ClinicianTab.calendar, onTabChanged);
            }
          },
          child: isWide
              ? _WideScaffold(
                  selected: selected,
                  title: title,
                  child: child,
                  onTabChanged: onTabChanged,
                )
              : _NarrowScaffold(
                  selected: selected,
                  title: title,
                  child: child,
                  onTabChanged: onTabChanged,
                ),
        );
      },
    );
  }
}

class _WideScaffold extends StatefulWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;
  final ValueChanged<ClinicianTab>? onTabChanged;

  const _WideScaffold({
    required this.selected,
    required this.child,
    this.title,
    this.onTabChanged,
  });

  @override
  State<_WideScaffold> createState() => _WideScaffoldState();
}

class _WideScaffoldState extends State<_WideScaffold>
    with SingleTickerProviderStateMixin {
  static const _sidebarExpandedWidth = 232.0;
  static const _sidebarCollapsedWidth = 72.0;
  static const _collapseKey = 'shell.sidebarCollapsed';

  late bool _isCollapsed;

  /// When on calendar tab, shell open/closed. Width animates via _shellAnimController.
  bool _isShellOverlayOpen = true;

  /// Drives calendar-tab shell width (0 = collapsed 72px, 1 = expanded 280px) so only layout animates, no full rebuild.
  late AnimationController _shellAnimController;
  late Animation<double> _shellCurved;

  @override
  void initState() {
    super.initState();
    _isCollapsed = true;
    _shellAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _shellCurved = CurvedAnimation(
      parent: _shellAnimController,
      curve: Curves.easeOutCubic,
    );
    _shellAnimController.addStatusListener(_onShellAnimStatus);
    _loadCollapsedPreference();
    _loadCalendarShellPreference();
  }

  void _onShellAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
      final open = _shellAnimController.value > 0.5;
      if (mounted && _isShellOverlayOpen != open) {
        setState(() => _isShellOverlayOpen = open);
        SharedPreferences.getInstance().then((prefs) =>
            prefs.setBool('shell.calendarOpen', open));
      }
    }
  }

  Future<void> _loadCalendarShellPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final open = prefs.getBool('shell.calendarOpen') ?? true;
    if (mounted) {
      setState(() => _isShellOverlayOpen = open);
      _shellAnimController.value = open ? 1.0 : 0.0;
    }
  }

  Future<void> _loadCollapsedPreference() async {
    // When on Settings tab, start collapsed to give more space to settings content.
    if (widget.selected == ClinicianTab.settings) {
      if (mounted) setState(() => _isCollapsed = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final width = MediaQuery.sizeOf(context).width;
    final defaultCollapsed = width < 1100;
    if (mounted) {
      setState(() {
        _isCollapsed = prefs.getBool(_collapseKey) ?? defaultCollapsed;
      });
    }
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _isCollapsed = !_isCollapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_collapseKey, _isCollapsed);
  }

  @override
  void dispose() {
    _shellAnimController.removeStatusListener(_onShellAnimStatus);
    _shellAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCalendarTab = widget.selected == ClinicianTab.calendar;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth >= 900 ? 280.0 : (screenWidth * 0.85).clamp(260.0, 360.0);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyB, meta: true): _ToggleSidebarIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, control: true): _ToggleSidebarIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
            onInvoke: (_) {
              if (isCalendarTab) {
                if (_shellAnimController.value > 0.5) {
                  _shellAnimController.reverse();
                } else {
                  _shellAnimController.forward();
                }
              } else {
                _toggleCollapsed();
              }
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: AppSurfaces.pageBg,
          body: isCalendarTab
              ? AnimatedBuilder(
                  animation: _shellCurved,
                  builder: (context, _) {
                    final t = _shellCurved.value;
                    final w =
                        _sidebarCollapsedWidth +
                        (drawerWidth - _sidebarCollapsedWidth) * t;
                    final isOpen = t > 0.5;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Row(
                              children: [
                                // Sidebar width + strip width so child content starts after the strip
                                SizedBox(width: w + _ShellCollapseStrip.stripWidth),
                                Expanded(
                                  child: RepaintBoundary(
                                    child: Container(
                                      color: AppSurfaces.workspaceBg,
                                      child: ShellOverlayScope(
                                        closeShell: () =>
                                            _shellAnimController.reverse(),
                                        shellRightEdge: 0,
                                        child: widget.child,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: w,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppSurfaces.shellBg,
                                  border: Border(
                                    right: BorderSide(color: AppSurfaces.divider),
                                  ),
                                ),
                                child: _Sidebar(
                                    selected: widget.selected,
                                    isCollapsed: !isOpen,
                                    onToggleCollapsed: () =>
                                        _shellAnimController.reverse(),
                                    onTabChanged: widget.onTabChanged,
                                  ),
                                ),
                              ),
                            Positioned(
                              left: w,
                              top: 0,
                              bottom: 0,
                              child: _ShellCollapseStrip(
                                isExpanded: t > 0.5,
                                onTap: () {
                                  if (_shellAnimController.value > 0.5) {
                                    _shellAnimController.reverse();
                                  } else {
                                    _shellAnimController.forward();
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                )
              : Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          width: _isCollapsed ? _sidebarCollapsedWidth : _sidebarExpandedWidth,
                          decoration: BoxDecoration(
                            color: AppSurfaces.shellBg,
                            border: Border(
                              right: BorderSide(color: AppSurfaces.divider),
                            ),
                          ),
                          child: _Sidebar(
                            selected: widget.selected,
                            isCollapsed: _isCollapsed,
                            onToggleCollapsed: _toggleCollapsed,
                            onTabChanged: widget.onTabChanged,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: _CollapseTab(
                            isCollapsed: _isCollapsed,
                            onToggle: _toggleCollapsed,
                          ),
                        ),
                      ],
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// Full-height narrow vertical strip (calendar overlay layout): light purple, <> chevrons.
class _ShellCollapseStrip extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  /// Width of the strip; shell reserves this so it does not overlap calendar tool rail.
  static const double stripWidth = 20;
  static const double _stripWidth = stripWidth;
  static const Color _stripBg = Color(0xFFEDE7F6);
  static const Color _chevronColor = Color(0xFF6A4C93);

  const _ShellCollapseStrip({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isExpanded ? 'Close menu' : 'Open menu',
      child: Material(
        color: _stripBg,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: _stripWidth,
            child: Center(
              child: Icon(
                isExpanded ? Icons.chevron_left : Icons.chevron_right,
                size: 18,
                color: _chevronColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-length narrow vertical strip to collapse/expand the shell.
/// Light purple background with darker purple chevrons.
class _CollapseTab extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;

  static const double _stripWidth = 20;
  static const Color _stripBg = Color(0xFFEDE7F6);
  static const Color _chevronColor = Color(0xFF6A4C93);

  const _CollapseTab({
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _stripBg,
      child: InkWell(
        onTap: onToggle,
        child: SizedBox(
          width: _stripWidth,
          child: Center(
            child: Icon(
              isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 18,
              color: _chevronColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final ClinicianTab selected;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<ClinicianTab>? onTabChanged;

  const _Sidebar({
    required this.selected,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      right: false,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SidebarHeader(
            isCollapsed: isCollapsed,
            onToggleCollapsed: onToggleCollapsed,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _SidebarNav(
                isCollapsed: isCollapsed,
                selected: selected,
                onTabChanged: onTabChanged,
              ),
            ),
          ),
          _SidebarFooter(isCollapsed: isCollapsed),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  final bool isCollapsed;

  const _SidebarFooter({required this.isCollapsed});

  static const _logoHeight = 28.0;
  static const _padding = 12.0;

  @override
  Widget build(BuildContext context) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.all(_padding),
        child: Center(
          child: Image.asset(
            'assets/icons/app_icon.png',
            height: 24,
            width: 24,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.calendar_today, size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, _padding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Powered by',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          Image.asset(
            'assets/kineticdx_logo2.png',
            height: _logoHeight,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.calendar_today, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  const _SidebarHeader({
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  static String _clinicInitial(String name) {
    if (name.isEmpty) return '?';
    final t = name.trim();
    if (t.length >= 2) return t.substring(0, 2).toUpperCase();
    return t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const height = 64.0;
    final theme = Theme.of(context);
    final clinicCtx = context.watch<ClinicContext>();
    final user = FirebaseAuth.instance.currentUser;

    if (!clinicCtx.hasClinic || user == null) {
      return SizedBox(
        height: height,
        child: Center(
          child: IconButton(
            icon: Icon(isCollapsed ? Icons.chevron_right : Icons.chevron_left),
            onPressed: onToggleCollapsed,
          ),
        ),
      );
    }

    final clinicId = clinicCtx.clinicId;
    final permissions = clinicCtx.hasSession ? clinicCtx.session.permissions : null;
    final userName = user.displayName ?? user.email ?? (user.uid.length <= 10 ? user.uid : '${user.uid.substring(0, 10)}…');
    final clinicRepo = ClinicRepository();
    final clinicStream = clinicRepo.watchClinic(clinicId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: clinicStream,
      builder: (context, snap) {
        final clinicData = snap.data?.data() ?? const <String, dynamic>{};
        final profile = clinicData['profile'] is Map ? clinicData['profile'] as Map : null;
        final clinicName = (profile != null && profile['name'] != null)
            ? (profile['name'] as String).trim()
            : (clinicData['name'] != null
                ? (clinicData['name'] as String).trim()
                : (clinicId.length <= 12 ? clinicId : '${clinicId.substring(0, 12)}…'));
        final logoUrl = (profile != null && profile['logoUrl'] != null)
            ? (profile['logoUrl'] as String).trim()
            : null;
        final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

        if (isCollapsed) {
          return SizedBox(
            height: height,
            child: Center(
              child: hasLogo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        logoUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _avatarPlaceholder(theme, _clinicInitial(clinicName)),
                      ),
                    )
                  : _avatarPlaceholder(theme, _clinicInitial(clinicName)),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppSurfaces.shellBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppSurfaces.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasLogo)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          logoUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _avatarPlaceholder(theme, _clinicInitial(clinicName)),
                        ),
                      )
                    else
                      _avatarPlaceholder(theme, _clinicInitial(clinicName)),
                    const SizedBox(height: 6),
                    Text(
                      clinicName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    PopupMenuButton<String>(
                      offset: const Offset(0, 40),
                      padding: EdgeInsets.zero,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              _getUserInitials(userName),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              userName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.onSurface),
                        ],
                      ),
                      onSelected: (value) => _handleProfileMenuAction(context, value, clinicId, permissions),
                      itemBuilder: (context) => _buildProfileMenuItems(context, userName: userName, clinicName: clinicName, permissions: permissions),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarPlaceholder(ThemeData theme, String initial) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  final bool isCollapsed;
  final ClinicianTab selected;

  final ValueChanged<ClinicianTab>? onTabChanged;

  const _SidebarNav({
    required this.isCollapsed,
    required this.selected,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final visibleTabs = _visibleTabs(context);
    final allowed = visibleTabs.toSet();
    final items = shellNavItems.where((e) => allowed.contains(e.tab)).toList();
    final grouped = groupNavItems(items);

    final children = <Widget>[];
    for (final entry in grouped.entries) {
      if (!isCollapsed) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              entry.key.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      } else {
        children.add(const SizedBox(height: 12));
      }
      for (final item in entry.value) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: _SidebarNavTile(
              label: item.label,
              icon: item.icon,
              isActive: selected == item.tab,
              isCollapsed: isCollapsed,
              onTap: () => _navigateTo(context, item.tab, onTabChanged),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _SidebarNavTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _hover = false;

  static const _height = 44.0;
  static const _radius = 12.0;
  static const _accentWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = widget.isActive;
    final isCollapsed = widget.isCollapsed;
    final onTap = widget.onTap;
    final label = widget.label;
    final icon = widget.icon;

    final bgColor = isActive
        ? AppAccent.primarySoft
        : _hover
            ? AppAccent.primaryHover
            : Colors.transparent;
    final iconColor = isActive ? AppAccent.primary : scheme.onSurfaceVariant;
    final labelColor = isActive ? AppAccent.primary : scheme.onSurface;

    Widget content;
    if (isCollapsed) {
      content = Center(
        child: Icon(icon, size: 22, color: iconColor),
      );
    } else {
      content = Row(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: labelColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: isCollapsed ? label : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
            child: InkWell(
              onTap: onTap,
              child: Row(
                children: [
                  if (isActive)
                    Container(
                      width: _accentWidth,
                      height: _height,
                      decoration: BoxDecoration(
                        color: AppAccent.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(_radius),
                          bottomLeft: Radius.circular(_radius),
                        ),
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // When width is too small for icon+gap+text, show only icon to avoid overflow.
                        final useNarrowContent =
                            isCollapsed || constraints.maxWidth < 40;
                        return Container(
                          height: _height,
                          padding: EdgeInsets.only(
                            left: useNarrowContent ? 0 : 12,
                            right: 12,
                            top: 0,
                            bottom: 0,
                          ),
                          child: useNarrowContent
                              ? Center(
                                  child: Icon(icon, size: 22, color: iconColor),
                                )
                              : content,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NarrowScaffold extends StatelessWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;
  final ValueChanged<ClinicianTab>? onTabChanged;

  const _NarrowScaffold({
    required this.selected,
    required this.child,
    this.title,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs(context);
    final selectedIndex = _selectedIndex(tabs, selected);

    return Scaffold(
      backgroundColor: AppSurfaces.pageBg,
      appBar: AppBar(
        backgroundColor: AppSurfaces.shellBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title ?? _labelFor(selected)),
        actions: _appBarActions(context),
        flexibleSpace: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 1,
            color: AppSurfaces.divider,
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppSurfaces.shellBg,
          border: Border(top: BorderSide(color: AppSurfaces.divider)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) {
            final next = tabs[i];
            if (next != selected) _navigateTo(context, next, onTabChanged);
          },
          destinations: tabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(_iconFor(t)),
                  label: _labelFor(t),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

List<ClinicianTab> _visibleTabs(BuildContext context) {
  final session = context.watch<ClinicSession?>();
  final perms = session?.permissions;

  bool has(String key) => perms?.has(key) == true;
  bool hasAny(List<String> keys) => keys.any(has);

  final tabs = <ClinicianTab>[];

  // Note: with the session gate in ClinicianShell, perms should not be null here
  // during normal operation. But leaving the checks defensive is fine.
  if (perms == null || has('schedule.read')) tabs.add(ClinicianTab.calendar);
  // Only show Patients tab when we have session and user has patients.read (avoids permission-denied on load).
  if (perms != null && has('patients.read')) tabs.add(ClinicianTab.patients);
  if (perms == null || has('clinical.read') || has('notes.read')) {
    tabs.add(ClinicianTab.preassess);
  }

  tabs.add(ClinicianTab.exercises);
  if (perms != null && hasAny(PermissionKeys.billingReadAny)) {
    tabs.add(ClinicianTab.invoices);
  }
  tabs.add(ClinicianTab.paymentQr);
  if (perms == null || has('settings.read')) tabs.add(ClinicianTab.settings);

  // ✅ Always last
  tabs.add(ClinicianTab.publicPortal);

  return tabs;
}

int _selectedIndex(List<ClinicianTab> tabs, ClinicianTab selected) {
  final i = tabs.indexOf(selected);
  return i >= 0 ? i : 0;
}

List<Widget> _appBarActions(BuildContext context) {
  return [
    const _ProfileBar(),
  ];
}

String _labelFor(ClinicianTab t) {
  switch (t) {
    case ClinicianTab.calendar:
      return 'Booking Calendar';
    case ClinicianTab.patients:
      return 'Patients';
    case ClinicianTab.preassess:
      return 'Pre-Assessments';
    case ClinicianTab.exercises:
      return 'Exercises';
    case ClinicianTab.invoices:
      return 'Accounts';
    case ClinicianTab.paymentQr:
      return 'Payment QR';
    case ClinicianTab.settings:
      return 'Clinic Settings';
    case ClinicianTab.publicPortal:
      return 'Public Portal';
  }
}

IconData _iconFor(ClinicianTab t) {
  switch (t) {
    case ClinicianTab.calendar:
      return Icons.calendar_today;
    case ClinicianTab.patients:
      return Icons.people;
    case ClinicianTab.preassess:
      return Icons.assignment;
    case ClinicianTab.exercises:
      return Icons.fitness_center;
    case ClinicianTab.invoices:
      return Icons.request_quote;
    case ClinicianTab.paymentQr:
      return Icons.qr_code_2;
    case ClinicianTab.settings:
      return Icons.settings;
    case ClinicianTab.publicPortal:
      return Icons.public;
  }
}

/// Use [onTabChanged] when set (keeps route mounted, no Firestore stream dispose).
/// Otherwise [ _go] for Public Portal or push new ClinicHomeShell.
void _navigateTo(
  BuildContext context,
  ClinicianTab t,
  ValueChanged<ClinicianTab>? onTabChanged,
) {
  if (t == ClinicianTab.publicPortal) {
    _go(context, t);
    return;
  }
  if (onTabChanged != null) {
    onTabChanged(t);
    return;
  }
  _go(context, t);
}

void _go(BuildContext context, ClinicianTab t) {
  if (t == ClinicianTab.publicPortal) {
    final clinicCtx = context.read<ClinicContext>();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(
          name: PublicHomeScreen.routeName,
          arguments: {'clinicId': clinicCtx.clinicId},
        ),
        builder: (_) => const PublicHomeScreen(),
      ),
    );
    return;
  }
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => ClinicHomeShell(initialTab: t),
    ),
  );
}

String _getUserInitials(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name[0].toUpperCase();
}

List<PopupMenuEntry<String>> _buildProfileMenuItems(
  BuildContext context, {
  required String userName,
  required String clinicName,
  required dynamic permissions,
}) {
  final items = <PopupMenuEntry<String>>[];
  items.add(
    PopupMenuItem<String>(
      enabled: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(userName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(clinicName, style: Theme.of(context).textTheme.bodySmall),
          if (permissions != null && !permissions.has('schedule.write'))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Read-only access', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    ),
  );
  items.add(const PopupMenuDivider());
  items.add(PopupMenuItem<String>(value: 'my_profile', child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline, size: 20), title: Text('My profile'), dense: true)));
  items.add(PopupMenuItem<String>(value: 'switch_clinic', child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.swap_horiz_outlined, size: 20), title: Text('Switch clinic'), dense: true)));
  items.add(const PopupMenuDivider());
  if (permissions != null && permissions.has('settings.write')) {
    items.add(PopupMenuItem<String>(value: 'clinic_settings', child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.settings_outlined, size: 20), title: Text('Clinic settings'), dense: true)));
    items.add(PopupMenuItem<String>(value: 'opening_hours', child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.schedule_outlined, size: 20), title: Text('Opening hours & closures'), dense: true)));
  }
  items.add(const PopupMenuDivider());
  items.add(PopupMenuItem<String>(value: 'help', child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.help_outline, size: 20), title: Text('Help / Feedback'), dense: true)));
  items.add(const PopupMenuDivider());
  items.add(PopupMenuItem<String>(value: 'sign_out', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout, size: 20, color: Theme.of(context).colorScheme.error), title: Text('Sign out', style: TextStyle(color: Theme.of(context).colorScheme.error)), dense: true)));
  return items;
}

void _handleProfileMenuAction(BuildContext context, String value, String clinicId, dynamic permissions) {
  switch (value) {
    case 'my_profile':
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffMemberScreen(memberUid: user.uid)));
      else _showPlaceholderDialog(context, 'My profile', 'Not implemented yet');
      break;
    case 'switch_clinic':
      _showPlaceholderDialog(context, 'Switch clinic', 'Switch clinic not wired yet');
      break;
    case 'clinic_settings':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClinicProfileScreen()));
      break;
    case 'opening_hours':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClinicOpeningHoursScreen(clinicId: clinicId)));
      break;
    case 'help':
      _showHelpDialog(context);
      break;
    case 'sign_out':
      context.read<ClinicContext>().clear();
      FirebaseAuth.instance.signOut();
      break;
  }
}

void _showPlaceholderDialog(BuildContext context, String title, String message) {
  showDialog(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
}

void _showHelpDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Help / Feedback'), content: const Text('Email support / documentation not wired yet.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
}

/// Profile bar widget showing avatar, clinician name, and clinic name.
/// Opens a menu when clicked.
class _ProfileBar extends StatelessWidget {
  const _ProfileBar();

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final user = FirebaseAuth.instance.currentUser;

    if (!clinicCtx.hasClinic || user == null) {
      return const SizedBox.shrink();
    }

    final clinicId = clinicCtx.clinicId;
    final permissions = clinicCtx.hasSession ? clinicCtx.session.permissions : null;
    final userName = user.displayName ?? user.email ?? (user.uid.length <= 10 ? user.uid : '${user.uid.substring(0, 10)}…');

    // Get clinic name from stream
    final clinicRepo = ClinicRepository();
    final clinicStream = clinicRepo.watchClinic(clinicId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: clinicStream,
      builder: (context, clinicSnap) {
        final clinicData = clinicSnap.data?.data() ?? const <String, dynamic>{};
        final clinicName = (clinicData['profile'] is Map &&
                (clinicData['profile'] as Map)['name'] != null)
            ? ((clinicData['profile'] as Map)['name'] as String).trim()
            : (clinicData['name'] != null
                ? (clinicData['name'] as String).trim()
                : (clinicId.length <= 12 ? clinicId : '${clinicId.substring(0, 12)}…'));

        return PopupMenuButton<String>(
          offset: const Offset(0, 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _getUserInitials(userName),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      userName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    Text(
                      clinicName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ],
            ),
          ),
          onSelected: (value) => _handleProfileMenuAction(context, value, clinicId, permissions),
          itemBuilder: (context) => _buildProfileMenuItems(context, userName: userName, clinicName: clinicName, permissions: permissions),
        );
      },
    );
  }
}

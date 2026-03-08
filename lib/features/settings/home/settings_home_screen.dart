// lib/features/settings/home/settings_home_screen.dart
//
// Settings shell (patient-profile style): header bar + category rail + content
// with sub-tabs per category. Gated by PermGate(settings.read); no role inference.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/app_routes.dart';
import '../../../../data/repositories/appointment_types_repository.dart';
import '../../../../data/repositories/calendar_display_settings_repository.dart';
import '../../../../data/repositories/communication_settings_repository.dart';
import '../../../../data/repositories/locations_repository.dart';
import '../../../../data/repositories/public_booking_settings_repository.dart';
import '../../../../data/repositories/staff_repository.dart';
import '../../../../app/clinic_context.dart';
import '../../../../shared/ui/perm_gate.dart';
import '../screens/appointment_types_list_screen.dart';
import '../screens/clinic_general_settings_screen.dart';
import '../screens/public_booking_settings_screen.dart';
import '../screens/online_booking_enablement_screen.dart';
import '../screens/communication_settings_screen.dart';
import '../screens/location_display_order_screen.dart';
import '../screens/location_form_screen.dart';
import '../screens/location_resources_screen.dart';
import '../screens/locations_list_screen.dart';
import '../screens/settings_placeholder_screen.dart';

import '../../../features/clinic/settings/ui/clinic_opening_hours_screen.dart';
import '../../../features/clinic_settings/clinic_closures_screen.dart';
import '../../../features/clinic_settings/clinic_policies_screen.dart';
import '../screens/calendar_display_settings_screen.dart' as settings_calendar;

import '../../../models/clinic_location.dart';
import '../../../staff/invite_staff_form.dart';
import '../../../staff/staff_settings_screen.dart';

/// Section id for settings category rail. Must match route/section slugs.
enum SettingsSection {
  clinic,
  locations,
  team,
  scheduling,
  communication,
  billing,
  data,
}

extension _SettingsSectionX on SettingsSection {
  String get slug {
    switch (this) {
      case SettingsSection.clinic:
        return AppRoutes.settingsClinic;
      case SettingsSection.locations:
        return AppRoutes.settingsLocations;
      case SettingsSection.team:
        return AppRoutes.settingsTeam;
      case SettingsSection.scheduling:
        return AppRoutes.settingsScheduling;
      case SettingsSection.communication:
        return AppRoutes.settingsCommunication;
      case SettingsSection.billing:
        return AppRoutes.settingsBilling;
      case SettingsSection.data:
        return AppRoutes.settingsData;
    }
  }

  String get label {
    switch (this) {
      case SettingsSection.clinic:
        return 'Clinic';
      case SettingsSection.locations:
        return 'Locations';
      case SettingsSection.team:
        return 'Team';
      case SettingsSection.scheduling:
        return 'Scheduling';
      case SettingsSection.communication:
        return 'Communication';
      case SettingsSection.billing:
        return 'Billing';
      case SettingsSection.data:
        return 'Data';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsSection.clinic:
        return Icons.business_outlined;
      case SettingsSection.locations:
        return Icons.location_on_outlined;
      case SettingsSection.team:
        return Icons.people_outline;
      case SettingsSection.scheduling:
        return Icons.schedule_outlined;
      case SettingsSection.communication:
        return Icons.mail_outline;
      case SettingsSection.billing:
        return Icons.receipt_long_outlined;
      case SettingsSection.data:
        return Icons.storage_outlined;
    }
  }

  bool get enabled {
    switch (this) {
      case SettingsSection.billing:
      case SettingsSection.data:
        return false;
      default:
        return true;
    }
  }

  /// Sub-tabs for this category (like patient profile tabs).
  List<String> get subTabs {
    switch (this) {
      case SettingsSection.clinic:
        return ['General', 'Opening hours', 'Closures', 'Policies'];
      case SettingsSection.locations:
        return ['List', 'Add location', 'Display order', 'Resources'];
      case SettingsSection.team:
        return ['Members', 'Invite'];
      case SettingsSection.scheduling:
        return ['Calendar display', 'Appointment types', 'Public booking', 'Online booking', 'Practitioners'];
      case SettingsSection.communication:
        return ['Defaults', 'Templates'];
      case SettingsSection.billing:
      case SettingsSection.data:
        return [];
    }
  }
}

SettingsSection? _sectionFromSlug(String? slug) {
  if (slug == null || slug.isEmpty) return SettingsSection.clinic;
  for (final s in SettingsSection.values) {
    if (s.slug == slug) return s;
  }
  return SettingsSection.clinic;
}

/// Optional icon for a sub-tab (Clinic, Locations, etc.) for quicker scan.
IconData? _subTabIcon(SettingsSection section, String subTabLabel) {
  switch (section) {
    case SettingsSection.clinic:
      switch (subTabLabel) {
        case 'General': return Icons.business_outlined;
        case 'Opening hours': return Icons.schedule_outlined;
        case 'Closures': return Icons.event_busy_outlined;
        case 'Policies': return Icons.policy_outlined;
        default: return null;
      }
    case SettingsSection.locations:
      switch (subTabLabel) {
        case 'List': return Icons.list_outlined;
        case 'Add location': return Icons.add_location_alt_outlined;
        case 'Display order': return Icons.sort_outlined;
        case 'Resources': return Icons.meeting_room_outlined;
        default: return null;
      }
    default:
      return null;
  }
}

/// Settings header bar (patient-profile style) with optional breadcrumb.
class _SettingsHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const _SettingsHeaderBar({
    this.onOpenDrawer,
    this.categoryLabel,
    this.subTabLabel,
  });

  final VoidCallback? onOpenDrawer;
  final String? categoryLabel;
  final String? subTabLabel;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showBreadcrumb = categoryLabel != null && subTabLabel != null && subTabLabel!.isNotEmpty;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (onOpenDrawer != null)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: onOpenDrawer,
              tooltip: 'Categories',
            ),
          Icon(Icons.settings_outlined, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          if (showBreadcrumb)
            Text(
              '$categoryLabel \u203a $subTabLabel',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              'Settings',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// Category rail item (one category in the left rail).
class _CategoryItem {
  const _CategoryItem({required this.section});
  final SettingsSection section;
}

/// Settings home: header + category rail + content with sub-tabs (patient-profile style).
/// When [clinicId] is set, General screen uses it (reliable when opened from shell).
class SettingsHomeScreen extends StatefulWidget {
  const SettingsHomeScreen({
    super.key,
    this.initialSection,
    this.clinicId,
  });

  final String? initialSection;
  final String? clinicId;

  @override
  State<SettingsHomeScreen> createState() => _SettingsHomeScreenState();
}

class _SettingsHomeScreenState extends State<SettingsHomeScreen> {
  late SettingsSection _category;
  late int _subIndex;
  /// When non-null, locations form is shown for editing this location.
  ClinicLocation? _editingLocation;

  static const _categories = [
    _CategoryItem(section: SettingsSection.clinic),
    _CategoryItem(section: SettingsSection.locations),
    _CategoryItem(section: SettingsSection.team),
    _CategoryItem(section: SettingsSection.scheduling),
    _CategoryItem(section: SettingsSection.communication),
    _CategoryItem(section: SettingsSection.billing),
    _CategoryItem(section: SettingsSection.data),
  ];

  @override
  void initState() {
    super.initState();
    _category = _sectionFromSlug(widget.initialSection) ?? SettingsSection.clinic;
    _subIndex = 0;
    if (_category.subTabs.isEmpty) _subIndex = 0;
  }

  @override
  void didUpdateWidget(covariant SettingsHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      final next = _sectionFromSlug(widget.initialSection);
      if (next != null) {
        _category = next;
        _subIndex = 0;
      }
    }
  }

  Widget _buildContent(BuildContext context) {
    if (!_category.enabled) {
      return SettingsPlaceholderScreen(
        title: _category.label,
        subtitle: 'This section is not available yet.',
        disabled: true,
      );
    }
    final tabs = _category.subTabs;
    if (tabs.isEmpty) {
      return SettingsPlaceholderScreen(title: _category.label);
    }
    final clinicId = widget.clinicId ?? context.read<ClinicContext>().clinicId;

    // Scheduling requires a clinic; avoid building any sub-screen (e.g. Calendar StreamBuilder) with empty clinicId.
    if (_category == SettingsSection.scheduling && clinicId.trim().isEmpty) {
      return const Center(child: Text('No clinic selected.'));
    }

    // Clinic → General: read-only clinic profile (Commit 03).
    if (_category == SettingsSection.clinic &&
        _subIndex == 0 &&
        tabs[_subIndex] == 'General') {
      return ClinicGeneralSettingsScreen(clinicId: clinicId);
    }

    // Locations → List (Commit 20–22). View with settings.read; callable enforces settings.write on save.
    if (_category == SettingsSection.locations &&
        _subIndex == 0 &&
        tabs[_subIndex] == 'List') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: LocationsListScreen(
          clinicId: clinicId,
          onAdd: () => setState(() {
            _subIndex = 1;
            _editingLocation = null;
          }),
          onEditLocation: (loc) => setState(() {
            _subIndex = 1;
            _editingLocation = loc;
          }),
        ),
      );
    }

    // Team → Members: reuse full staff management (invite, profile, suspend). Embedded = no AppBar.
    if (_category == SettingsSection.team &&
        _subIndex == 0 &&
        tabs[_subIndex] == 'Members') {
      return PermGate(
        requiredPerm: 'members.read',
        message: 'You need "members.read" to view the team list.',
        child: const StaffSettingsScreen(embedded: true),
      );
    }

    // Team → Invite (Commit 09): invite form wired to inviteMemberFn.
    if (_category == SettingsSection.team &&
        tabs.length > 1 &&
        _subIndex == 1 &&
        tabs[_subIndex] == 'Invite') {
      return PermGate(
        requiredPerm: 'members.manage',
        message: 'You need "members.manage" to invite team members.',
        child: clinicId.trim().isEmpty
            ? const Center(child: Text('No clinic selected.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Invite team member',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Send an invite by email. The recipient will get a link to join this clinic.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: InviteStaffForm(
                        clinicId: clinicId,
                        clearFormOnSuccess: true,
                        onSuccess: (sent, inviteLink) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                sent
                                    ? 'Invite email sent.'
                                    : 'Invite created but email not sent. Share the invite link with the recipient.',
                              ),
                            ),
                          );
                          if (!sent && (inviteLink ?? '').isNotEmpty) {
                            debugPrint('Invite link: $inviteLink');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
      );
    }

    // Locations → Add/Edit form (Commit 21–22). View with settings.read; callable enforces settings.write.
    if (_category == SettingsSection.locations &&
        _subIndex == 1 &&
        tabs.length > 1 &&
        tabs[1] == 'Add location') {
      void goBackToList() => setState(() {
            _subIndex = 0;
            _editingLocation = null;
          });
      return PermGate(
        requiredPerm: 'settings.read',
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (!didPop) goBackToList();
          },
          child: LocationFormScreen(
            clinicId: clinicId,
            location: _editingLocation,
            onSaved: goBackToList,
            onCancel: goBackToList,
          ),
        ),
      );
    }

    // Locations → Display order
    if (_category == SettingsSection.locations &&
        tabs.length > 2 &&
        _subIndex == 2 &&
        tabs[_subIndex] == 'Display order') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: LocationDisplayOrderScreen(clinicId: clinicId),
      );
    }

    // Locations → Resources (phase 1: settings UI only)
    if (_category == SettingsSection.locations &&
        tabs.length > 3 &&
        _subIndex == 3 &&
        tabs[_subIndex] == 'Resources') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: LocationResourcesScreen(clinicId: clinicId),
      );
    }

    // Scheduling → Calendar display (Commit 26: contract fields, callable-only write).
    if (_category == SettingsSection.scheduling &&
        tabs.isNotEmpty &&
        _subIndex == 0 &&
        tabs[0] == 'Calendar display') {
      return PermGate(
        requiredPerm: 'settings.write',
        child: settings_calendar.CalendarDisplaySettingsScreen(clinicId: clinicId),
      );
    }

    // Scheduling → Appointment types (Commit 11/12).
    if (_category == SettingsSection.scheduling &&
        tabs.length > 1 &&
        _subIndex == 1 &&
        tabs[_subIndex] == 'Appointment types') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: AppointmentTypesListScreen(clinicId: clinicId),
      );
    }

    // Scheduling → Public booking (Commit 15: callable-only writes).
    if (_category == SettingsSection.scheduling &&
        tabs.length > 2 &&
        _subIndex == 2 &&
        tabs[_subIndex] == 'Public booking') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: PublicBookingSettingsScreen(clinicId: clinicId),
      );
    }

    // Scheduling → Online booking (CP-P2: visibility toggles for locations/practitioners/types).
    if (_category == SettingsSection.scheduling &&
        tabs.length > 3 &&
        _subIndex == 3 &&
        tabs[_subIndex] == 'Online booking') {
      return OnlineBookingEnablementScreen(clinicId: clinicId);
    }

    // Scheduling → Practitioners: same staff list as Team → Members (view + Edit availability).
    if (_category == SettingsSection.scheduling &&
        tabs.length > 4 &&
        _subIndex == 4 &&
        tabs[_subIndex] == 'Practitioners') {
      return PermGate(
        requiredPerm: 'members.read',
        message: 'You need "members.read" to view practitioners.',
        child: const StaffSettingsScreen(embedded: true),
      );
    }

    // Communication → Defaults (Commit 18: callable-only writes).
    if (_category == SettingsSection.communication &&
        tabs.isNotEmpty &&
        _subIndex == 0 &&
        tabs[0] == 'Defaults') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: CommunicationSettingsScreen(clinicId: clinicId),
      );
    }

    // Communication → Templates (SETTINGS_SYSTEM §4.9: clinics/{clinicId}/templates).
    if (_category == SettingsSection.communication &&
        tabs.length > 1 &&
        _subIndex == 1 &&
        tabs[1] == 'Templates') {
      return PermGate(
        requiredPerm: 'settings.write',
        message: 'You need "settings.write" (manageClinic) to manage communication templates.',
        child: SettingsPlaceholderScreen(
          title: 'Communication templates',
          subtitle:
              'Confirmation, reminder email and reminder SMS templates. '
              'Coming soon; see SETTINGS_SYSTEM §4.9 for the data contract.',
        ),
      );
    }

    // Clinic → Opening hours: same source as public booking (settings/publicBooking.weeklyHours).
    if (_category == SettingsSection.clinic &&
        tabs.length > 1 &&
        _subIndex == 1 &&
        tabs[_subIndex] == 'Opening hours') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: clinicId.trim().isEmpty
            ? const Center(child: Text('No clinic selected.'))
            : ClinicOpeningHoursScreen(clinicId: clinicId),
      );
    }

    // Clinic → Closures: manage closed hours / holidays.
    if (_category == SettingsSection.clinic &&
        tabs.length > 2 &&
        _subIndex == 2 &&
        tabs[_subIndex] == 'Closures') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: clinicId.trim().isEmpty
            ? const Center(child: Text('No clinic selected.'))
            : const ClinicClosuresScreen(),
      );
    }

    // Clinic → Policies: cancellation, late/no-show, consent (practice policies).
    if (_category == SettingsSection.clinic &&
        tabs.length > 3 &&
        _subIndex == 3 &&
        tabs[_subIndex] == 'Policies') {
      return PermGate(
        requiredPerm: 'settings.read',
        child: clinicId.trim().isEmpty
            ? const Center(child: Text('No clinic selected.'))
            : ClinicPoliciesScreen(clinicId: clinicId),
      );
    }

    final subLabel = _subIndex < tabs.length ? tabs[_subIndex] : tabs.first;
    return SettingsPlaceholderScreen(
      title: subLabel,
      subtitle: '${_category.label} → $subLabel',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermGate(
      requiredPerm: 'settings.read',
      child: _buildGatedContent(context),
    );
  }

  /// Single content area: sub-tab bar + expanded content. Used in both narrow and wide layouts.
  Widget _buildMainColumn(BuildContext context, ThemeData theme, bool isNarrow) {
    final clinicId = widget.clinicId ?? context.read<ClinicContext>().clinicId;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSubTabBar(theme, isNarrow: isNarrow),
            Expanded(child: _buildContent(context)),
          ],
        ),
        if (clinicId.trim().isNotEmpty)
          _SettingsStreamPrewarmer(clinicId: clinicId),
      ],
    );
  }

  Widget _buildGatedContent(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 800;
    final tabs = _category.subTabs;
    final subTabLabel = tabs.isNotEmpty && _subIndex < tabs.length ? tabs[_subIndex] : null;

    if (isNarrow) {
      return Scaffold(
        appBar: _SettingsHeaderBar(
          onOpenDrawer: () => Scaffold.of(context).openDrawer(),
          categoryLabel: _category.label,
          subTabLabel: subTabLabel,
        ),
        body: _buildMainColumn(context, theme, true),
        drawer: _buildCategoryDrawer(theme),
      );
    }

    return Scaffold(
      appBar: _SettingsHeaderBar(
        categoryLabel: _category.label,
        subTabLabel: subTabLabel,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCategoryRail(theme),
          Expanded(
            child: _buildMainColumn(context, theme, false),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRail(ThemeData theme) {
    return SizedBox(
      width: 260,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final item in _categories) ...[
              if (!item.section.enabled)
                _buildCategoryTile(theme, item.section, disabled: true)
              else
                _buildCategoryTile(theme, item.section, disabled: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(ThemeData theme, SettingsSection section, {required bool disabled}) {
    final selected = _category == section;
    return InkWell(
      onTap: disabled ? null : () => setState(() { _category = section; _subIndex = 0; }),
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        ),
        child: Row(
          children: [
            Icon(
              section.icon,
              size: 22,
              color: disabled
                  ? theme.colorScheme.outline
                  : (selected ? theme.colorScheme.primary : theme.colorScheme.onSurface),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: disabled ? theme.colorScheme.outline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabBar(ThemeData theme, {required bool isNarrow}) {
    if (!_category.enabled || _category.subTabs.isEmpty) {
      return const SizedBox.shrink();
    }
    final tabs = _category.subTabs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _SubTabChip(
                label: tabs[i],
                icon: _subTabIcon(_category, tabs[i]),
                selected: _subIndex == i,
                onTap: () => setState(() {
                  _subIndex = i;
                  if (i == 1 && _category == SettingsSection.locations) {
                    _editingLocation = null;
                  }
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Categories',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final item in _categories)
              ListTile(
                leading: Icon(item.section.icon, size: 22),
                title: Text(item.section.label),
                enabled: item.section.enabled,
                selected: _category == item.section,
                onTap: item.section.enabled
                    ? () {
                        setState(() { _category = item.section; _subIndex = 0; });
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Subscribes to settings data streams when Settings loads so all sections
/// (Communication, Team, Locations, Appointment types, Public booking, Calendar display)
/// get replayed data immediately instead of waiting 2–3s for the first fetch.
class _SettingsStreamPrewarmer extends StatefulWidget {
  const _SettingsStreamPrewarmer({required this.clinicId});
  final String clinicId;

  @override
  State<_SettingsStreamPrewarmer> createState() => _SettingsStreamPrewarmerState();
}

class _SettingsStreamPrewarmerState extends State<_SettingsStreamPrewarmer> {
  final List<StreamSubscription?> _subs = [];
  String? _lastPrewarmClinicId;

  void _safeCancel(StreamSubscription? sub) {
    sub?.cancel().catchError((_) {});
  }

  void _cancelAll() {
    for (final sub in _subs) _safeCancel(sub);
    _subs.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.clinicId.trim();
    if (c.isEmpty) {
      _cancelAll();
      _lastPrewarmClinicId = null;
      return;
    }
    if (c == _lastPrewarmClinicId) return;
    _lastPrewarmClinicId = c;
    _cancelAll();
    // Subscribe only to repos that are available; never throw so Settings doesn't crash.
    _tryPrewarm(c, () {
      final repo = context.read<CommunicationSettingsRepository>();
      return repo.streamSettings(c).listen((_) {});
    });
    _tryPrewarm(c, () {
      final repo = context.read<StaffRepository>();
      return repo.watchMembershipsWithFallback(c).listen((_) {});
    });
    _tryPrewarm(c, () {
      final repo = context.read<LocationsRepository>();
      return repo.watchLocationsViaCallable(c).listen((_) {});
    });
    _tryPrewarm(c, () {
      final repo = context.read<AppointmentTypesRepository>();
      return repo.watchAppointmentTypesViaCallable(c).listen((_) {});
    });
    _tryPrewarm(c, () {
      final repo = context.read<PublicBookingSettingsRepository>();
      return repo.streamSettings(c).listen((_) {});
    });
    _tryPrewarm(c, () {
      final repo = context.read<CalendarDisplaySettingsRepository>();
      return repo.streamSettings(c).listen((_) {});
    });
  }

  void _tryPrewarm(String clinicId, StreamSubscription<dynamic>? Function() subscribe) {
    try {
      final sub = subscribe();
      if (sub != null) _subs.add(sub);
    } catch (_) {
      // Skip this repo so one missing provider or stream error doesn't break Settings.
    }
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _SubTabChip extends StatelessWidget {
  const _SubTabChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

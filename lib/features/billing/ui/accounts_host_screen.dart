// lib/features/billing/ui/accounts_host_screen.dart
//
// Accounts workspace: subsection nav (Overview, Invoices, Payments, Pricing Rules, Configuration)
// with invoice-first content. Matches shell aesthetic; permission-gated.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../app/clinic_session.dart';
import '../../../config/permission_keys.dart';
import '../../settings/home/settings_home_screen.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';
import 'billing_dashboard_screen.dart';
import 'billing_settings_screen.dart';
import 'invoice_editor_screen.dart';
import 'invoices_list_screen.dart';
import 'patient_statements_screen.dart';

enum AccountsSection {
  overview,
  invoices,
  payments,
  pricingRules,
  expenses,
  configuration,
}

extension _AccountsSectionX on AccountsSection {
  String get label {
    switch (this) {
      case AccountsSection.overview:
        return 'Overview';
      case AccountsSection.invoices:
        return 'Invoices';
      case AccountsSection.payments:
        return 'Payments';
      case AccountsSection.pricingRules:
        return 'Pricing Rules';
      case AccountsSection.expenses:
        return 'Expenses';
      case AccountsSection.configuration:
        return 'Configuration';
    }
  }

  IconData get icon {
    switch (this) {
      case AccountsSection.overview:
        return Icons.dashboard_outlined;
      case AccountsSection.invoices:
        return Icons.request_quote_outlined;
      case AccountsSection.payments:
        return Icons.payment_outlined;
      case AccountsSection.pricingRules:
        return Icons.attach_money;
      case AccountsSection.expenses:
        return Icons.receipt_long_outlined;
      case AccountsSection.configuration:
        return Icons.settings_outlined;
    }
  }
}

class AccountsHostScreen extends StatefulWidget {
  const AccountsHostScreen({
    super.key,
    this.initialSection,
  });

  final AccountsSection? initialSection;

  @override
  State<AccountsHostScreen> createState() => _AccountsHostScreenState();
}

class _AccountsHostScreenState extends State<AccountsHostScreen> {
  late AccountsSection _section;

  static const _sections = [
    AccountsSection.overview,
    AccountsSection.invoices,
    AccountsSection.payments,
    AccountsSection.pricingRules,
    AccountsSection.expenses,
    AccountsSection.configuration,
  ];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? AccountsSection.overview;
  }

  @override
  void didUpdateWidget(covariant AccountsHostScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection &&
        widget.initialSection != null) {
      _section = widget.initialSection!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId.trim();
    if (clinicId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected.')),
      );
    }

    final session = context.watch<ClinicSession?>();
    final canReadBilling = session != null &&
        PermissionKeys.billingReadAny.any((k) => session.permissions.has(k));
    if (!canReadBilling) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have billing access for this clinic.'),
        ),
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 800;

    if (isNarrow) {
      return Scaffold(
        backgroundColor: AppSurfaces.workspaceBg,
        appBar: AppBar(
          title: Text(_section.label),
          actions: [_sectionActions(context, clinicId)],
        ),
        body: _buildContent(context, clinicId),
        drawer: _buildRail(context, clinicId, asDrawer: true),
      );
    }

    return Scaffold(
      backgroundColor: AppSurfaces.workspaceBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(context, clinicId, asDrawer: false),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    12,
                    AppSpacing.screenPadding,
                    8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _section.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _sectionActions(context, clinicId),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _buildContent(context, clinicId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail(
    BuildContext context,
    String clinicId, {
    required bool asDrawer,
  }) {
    final theme = Theme.of(context);
    final rail = SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            right: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                'Accounts',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final s in _sections)
              _RailTile(
                section: s,
                selected: _section == s,
                onTap: () {
                  setState(() => _section = s);
                  if (asDrawer) Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );

    if (asDrawer) {
      return Drawer(
        child: SafeArea(child: rail),
      );
    }
    return rail;
  }

  Widget _sectionActions(BuildContext context, String clinicId) {
    if (_section == AccountsSection.invoices) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Billing dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BillingDashboardScreen(clinicId: clinicId),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Statements',
            icon: const Icon(Icons.request_page_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientStatementsScreen(clinicId: clinicId),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvoiceEditorScreen(clinicId: clinicId),
              ),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New invoice'),
          ),
        ],
      );
    }
    if (_section == AccountsSection.configuration) {
      return OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsHomeScreenForAccounts(
              clinicId: clinicId,
            ),
          ),
        ),
        icon: const Icon(Icons.settings_outlined, size: 20),
        label: const Text('Open in Settings'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildContent(BuildContext context, String clinicId) {
    switch (_section) {
      case AccountsSection.overview:
        return _AccountsOverviewContent(clinicId: clinicId);
      case AccountsSection.invoices:
        return const _InvoicesEmbeddedList();
      case AccountsSection.payments:
        return const _PaymentsPlaceholder();
      case AccountsSection.pricingRules:
        return const _PricingRulesPlaceholder();
      case AccountsSection.expenses:
        return const _ExpensesPlaceholder();
      case AccountsSection.configuration:
        return const BillingSettingsScreen(initialTabIndex: 0);
    }
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AccountsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : null,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline invoices list (no FAB; actions are in the app bar / host).
class _InvoicesEmbeddedList extends StatelessWidget {
  const _InvoicesEmbeddedList();

  @override
  Widget build(BuildContext context) {
    return const InvoicesListScreen(embedded: true);
  }
}

class _PaymentsPlaceholder extends StatelessWidget {
  const _PaymentsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payment_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Payments',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Track payments and link them to invoices here. Coming soon.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingRulesPlaceholder extends StatelessWidget {
  const _PricingRulesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.attach_money,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Pricing Rules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Hourly, per appointment type, and client overrides. Coming soon.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Expenses placeholder (first-pass IA; real subsystem later).
class _ExpensesPlaceholder extends StatelessWidget {
  const _ExpensesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Expenses',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Track and categorize clinic expenses. Coming soon.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Overview: summary bar, KPI cards, quick actions, recent activity. Single getSummary (no extra listeners).
class _AccountsOverviewContent extends StatelessWidget {
  const _AccountsOverviewContent({required this.clinicId});

  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Accounts',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Track invoices, payments, pricing, and expenses across your clinic.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          FutureBuilder<BillingSummary>(
            future: context.read<BillingRepository>().getSummary(clinicId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Could not load summary',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${snap.error}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(height: AppSpacing.sm),
                          Text('Loading summary…', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final s = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FinancialSummaryBar(summary: s),
                  const SizedBox(height: AppSpacing.elementGap),
                  Wrap(
                    spacing: AppSpacing.elementGap,
                    runSpacing: AppSpacing.elementGap,
                    children: [
                      _KpiCard(label: 'Revenue (this month)', value: s.revenueMonth.toStringAsFixed(2), subtitle: null),
                      _KpiCard(label: 'Outstanding', value: s.outstandingInvoices.toStringAsFixed(2), subtitle: null),
                      _KpiCard(label: 'Revenue (today)', value: s.revenueToday.toStringAsFixed(2), subtitle: null),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  _QuickActionsRow(clinicId: clinicId),
                  const SizedBox(height: AppSpacing.sectionGap),
                  _RecentActivityPanel(activities: s.recentActivity),
                  const SizedBox(height: AppSpacing.xl),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compact summary row above KPI cards (Phase 7A.1). Uses existing overview data only.
class _FinancialSummaryBar extends StatelessWidget {
  const _FinancialSummaryBar({required this.summary});

  final BillingSummary summary;

  @override
  Widget build(BuildContext context) {
    return Text(
      'This month: ${summary.revenueMonth.toStringAsFixed(2)} collected  •  ${summary.outstandingInvoices.toStringAsFixed(2)} outstanding',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Recent activity panel (Phase 7A.5). Uses summary.recentActivity from same getSummary; no extra listeners.
class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.activities});

  final List<RecentActivityItem> activities;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (activities.isEmpty)
              Text(
                'No recent activity',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else
              ...activities.take(5).map((a) {
                final label = _activityLabel(a);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: Theme.of(context).textTheme.bodySmall),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  static String _activityLabel(RecentActivityItem a) {
    final numStr = a.displayNumber.isNotEmpty ? a.displayNumber : a.invoiceId;
    switch (a.status) {
      case 'issued':
        return 'Invoice $numStr issued';
      case 'paid':
        return 'Invoice $numStr paid';
      case 'void':
        return 'Invoice $numStr voided';
      default:
        return 'Invoice $numStr updated';
    }
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.25,
                    ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.clinicId});

  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.elementGap),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InvoiceEditorScreen(clinicId: clinicId),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New invoice'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BillingDashboardScreen(clinicId: clinicId),
                    ),
                  ),
                  icon: const Icon(Icons.dashboard_outlined, size: 18),
                  label: const Text('Dashboard'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientStatementsScreen(clinicId: clinicId),
                    ),
                  ),
                  icon: const Icon(Icons.request_page_outlined, size: 18),
                  label: const Text('Statements'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal wrapper to open Settings with Accounts (billing) section selected.
/// Used from Accounts host "Configuration" quick action.
class SettingsHomeScreenForAccounts extends StatelessWidget {
  const SettingsHomeScreenForAccounts({
    super.key,
    required this.clinicId,
  });

  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return SettingsHomeScreen(
      clinicId: clinicId,
      initialSection: 'billing',
    );
  }
}

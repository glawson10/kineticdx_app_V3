import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../app/clinic_session.dart';
import '../../../config/permission_keys.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';
import 'billing_dashboard_screen.dart';
import 'invoice_editor_screen.dart';
import 'patient_statements_screen.dart';

class InvoicesListScreen extends StatefulWidget {
  const InvoicesListScreen({super.key, this.embedded = false});

  /// When true, used inside Accounts host; FAB and duplicate header actions are hidden.
  final bool embedded;

  @override
  State<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends State<InvoicesListScreen> {
  String _statusFilter = 'all';
  Stream<List<BillingInvoice>>? _invoicesStream;
  String? _cachedClinicId;

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId.trim();
    if (clinicId.isEmpty) return const Center(child: Text('No clinic selected.'));
    final session = context.watch<ClinicSession?>();
    final canReadBilling = session != null &&
        PermissionKeys.billingReadAny.any((k) => session.permissions.has(k));
    if (!canReadBilling) {
      return const Center(
        child: Text('You do not have billing access for this clinic.'),
      );
    }
    if (clinicId != _cachedClinicId) {
      _cachedClinicId = clinicId;
      _invoicesStream = context.read<BillingRepository>().watchInvoices(clinicId);
    }
    if (_invoicesStream == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
        backgroundColor: AppSurfaces.workspaceBg,
        floatingActionButton: widget.embedded
            ? null
            : FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => InvoiceEditorScreen(clinicId: clinicId)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New invoice'),
              ),
        body: StreamBuilder<List<BillingInvoice>>(
          stream: _invoicesStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return _InvoicesErrorState(
                message: '${snap.error}',
                onRetry: () => setState(() {
                  _invoicesStream = context.read<BillingRepository>().watchInvoices(clinicId);
                }),
              );
            }
            if (!snap.hasData) {
              return const _InvoicesLoadingState();
            }
            final invoices = snap.data!;
            final filtered = _statusFilter == 'all'
                ? invoices
                : invoices.where((i) => i.status == _statusFilter).toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.embedded) _Header(clinicId: clinicId),
                  if (!widget.embedded) const SizedBox(height: AppSpacing.sectionGap),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      ('all', 'All'),
                      ('draft', 'Draft'),
                      ('issued', 'Issued'),
                      ('paid', 'Paid'),
                      ('void', 'Void'),
                    ].map((entry) {
                      final isSelected = _statusFilter == entry.$1;
                      return FilterChip(
                        label: Text(entry.$2),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _statusFilter = entry.$1),
                        selectedColor: _statusChipColor(context, entry.$1, selected: true),
                        checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  if (filtered.isEmpty)
                    _InvoicesEmptyState(clinicId: clinicId, filter: _statusFilter)
                  else
                    ...filtered.map(
                      (inv) => _InvoiceListCard(
                        clinicId: clinicId,
                        invoice: inv,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
  }
}

Color? _statusChipColor(BuildContext context, String status, {required bool selected}) {
  if (!selected) return null;
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case 'draft':
      return scheme.surfaceContainerHighest;
    case 'issued':
      return AppColors.info.withValues(alpha: 0.2);
    case 'paid':
      return AppColors.success.withValues(alpha: 0.2);
    case 'void':
      return scheme.outlineVariant;
    default:
      return scheme.primaryContainer;
  }
}

class _InvoicesLoadingState extends StatelessWidget {
  const _InvoicesLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Loading invoices…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesErrorState extends StatelessWidget {
  const _InvoicesErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Could not load invoices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoicesEmptyState extends StatelessWidget {
  const _InvoicesEmptyState({required this.clinicId, required this.filter});

  final String clinicId;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final isFiltered = filter != 'all';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isFiltered ? 'No invoices match this filter' : 'No invoices yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isFiltered
                  ? 'Try another status or create a new invoice.'
                  : 'Create your first invoice to get started.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InvoiceEditorScreen(clinicId: clinicId),
                ),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Create invoice'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceListCard extends StatelessWidget {
  const _InvoiceListCard({required this.clinicId, required this.invoice});

  final String clinicId;
  final BillingInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final displayLabel = invoice.effectiveDisplayNumber ?? invoice.id.substring(0, 8);
    final currency = invoice.effectiveCurrency ?? invoice.currency;
    final currencySuffix = (currency != null && currency.isNotEmpty) ? ' $currency' : '';
    final total = invoice.effectiveTotal;
    final dueStr = invoice.dueDate != null
        ? 'Due ${invoice.dueDate!.day}/${invoice.dueDate!.month}/${invoice.dueDate!.year}'
        : null;
    final isPaid = invoice.status == 'paid' || invoice.balanceDue <= 0;
    final paymentLine = isPaid
        ? 'Paid in full'
        : 'Balance due ${invoice.balanceDue.toStringAsFixed(2)}$currencySuffix';
    final now = DateTime.now();
    final isOverdue = invoice.dueDate != null &&
        now.isAfter(invoice.dueDate!) &&
        invoice.status != 'paid' &&
        invoice.status != 'void';
    int overdueDays = 0;
    if (isOverdue && invoice.dueDate != null) {
      overdueDays = now.difference(invoice.dueDate!).inDays;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.elementGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceEditorScreen(clinicId: clinicId, invoice: invoice),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusBadge(status: invoice.status),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            displayLabel,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Patient: ${invoice.patientId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (dueStr != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        dueStr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    if (isOverdue && overdueDays > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Overdue by $overdueDays ${overdueDays == 1 ? 'day' : 'days'}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${total.toStringAsFixed(2)}$currencySuffix',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    paymentLine,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isPaid ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: isPaid ? FontWeight.w500 : null,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusStyle(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.element),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

(Color, String) _statusStyle(BuildContext context, String status) {
  switch (status) {
    case 'draft':
      return (Theme.of(context).colorScheme.onSurfaceVariant, 'Draft');
    case 'issued':
      return (AppColors.info, 'Issued');
    case 'paid':
      return (AppColors.success, 'Paid');
    case 'void':
      return (Theme.of(context).colorScheme.outline, 'Void');
    default:
      return (Theme.of(context).colorScheme.primary, status);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invoices',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Drafts, issued invoices, payment status, and balances.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          tooltip: 'Billing dashboard',
          icon: const Icon(Icons.dashboard_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => BillingDashboardScreen(clinicId: clinicId)),
          ),
        ),
        IconButton(
          tooltip: 'Statements',
          icon: const Icon(Icons.request_page_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PatientStatementsScreen(clinicId: clinicId)),
          ),
        ),
      ],
    );
  }
}

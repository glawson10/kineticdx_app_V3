import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';

class InvoiceEditorScreen extends StatefulWidget {
  const InvoiceEditorScreen({
    super.key,
    required this.clinicId,
    this.invoice,
  });

  final String clinicId;
  final BillingInvoice? invoice;

  @override
  State<InvoiceEditorScreen> createState() => _InvoiceEditorScreenState();
}

class _InvoiceEditorScreenState extends State<InvoiceEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _patientCtrl;
  late final TextEditingController _appointmentCtrl;
  late final TextEditingController _discountCtrl;
  final List<InvoiceLine> _items = [];
  bool _saving = false;
  bool _issuing = false;

  @override
  void initState() {
    super.initState();
    _patientCtrl = TextEditingController(text: widget.invoice?.patientId ?? '');
    _appointmentCtrl = TextEditingController(text: widget.invoice?.appointmentId ?? '');
    _discountCtrl = TextEditingController(text: '0');
    _items.addAll(widget.invoice?.effectiveLineItems ?? widget.invoice?.lineItems ?? const []);
    if (_items.isEmpty) {
      _items.add(
        const InvoiceLine(
          type: 'service',
          itemId: 'manual',
          description: 'Consultation',
          quantity: 1,
          unitPrice: 0,
          taxRate: 0,
          total: 0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _patientCtrl.dispose();
    _appointmentCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = context.read<BillingRepository>();
    try {
      final discount = double.tryParse(_discountCtrl.text.trim()) ?? 0;
      if (widget.invoice == null) {
        await repo.createInvoice(
          clinicId: widget.clinicId,
          patientId: _patientCtrl.text.trim(),
          appointmentId: _appointmentCtrl.text.trim().isEmpty ? null : _appointmentCtrl.text.trim(),
          lineItems: _items,
          invoiceDiscount: discount,
        );
      } else {
        await repo.updateInvoice(
          clinicId: widget.clinicId,
          invoiceId: widget.invoice!.id,
          patch: {
            'lineItems': _items.map((e) => e.toJson()).toList(),
            'invoiceDiscount': discount,
          },
        );
      }
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice saved')),
        );
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _issue() async {
    if (widget.invoice == null || widget.invoice!.status != 'draft') return;
    setState(() => _issuing = true);
    final repo = context.read<BillingRepository>();
    try {
      await repo.updateInvoice(
        clinicId: widget.clinicId,
        invoiceId: widget.invoice!.id,
        patch: {'status': 'issued'},
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice issued successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.length > 200 ? '${message.substring(0, 200)}…' : message),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final isDraft = inv?.status == 'draft';
    final isIssuedOrPaid = inv != null && (inv.status == 'issued' || inv.status == 'paid');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          inv == null
              ? 'Create invoice'
              : isIssuedOrPaid
                  ? 'Issued invoice'
                  : 'Edit invoice',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.generalSettingsMaxWidth),
            child: isIssuedOrPaid
                ? _IssuedInvoiceReadView(clinicId: widget.clinicId, invoice: inv)
                : _DraftInvoiceForm(
                    formKey: _formKey,
                    patientCtrl: _patientCtrl,
                    appointmentCtrl: _appointmentCtrl,
                    discountCtrl: _discountCtrl,
                    items: _items,
                    invoice: inv,
                    onItemsChanged: () => setState(() {}),
                  ),
          ),
        ),
      ),
      bottomNavigationBar: isIssuedOrPaid
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.sm, AppSpacing.screenPadding, AppSpacing.md),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: (_saving || _issuing) ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    if (inv != null && isDraft)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: FilledButton.tonalIcon(
                          onPressed: _issuing || _saving ? null : _issue,
                          icon: _issuing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_issuing ? 'Issuing…' : 'Issue invoice'),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _saving || _issuing ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save invoice'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

String _monthName(int month) {
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[(month - 1).clamp(0, 11)];
}

/// Export PDF trigger (Phase 9). Backend uses issuedSnapshot only; fails safely if missing.
class _ExportPdfButton extends StatefulWidget {
  const _ExportPdfButton({required this.clinicId, required this.invoiceId});

  final String clinicId;
  final String invoiceId;

  @override
  State<_ExportPdfButton> createState() => _ExportPdfButtonState();
}

class _ExportPdfButtonState extends State<_ExportPdfButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _requestPdf,
      icon: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.picture_as_pdf_outlined, size: 20),
      label: Text(_loading ? 'Requesting…' : 'Export PDF'),
    );
  }

  Future<void> _requestPdf() async {
    setState(() => _loading = true);
    try {
      await context.read<BillingRepository>().generateInvoicePdf(
            clinicId: widget.clinicId,
            invoiceId: widget.invoiceId,
          );
      if (!mounted) return;
      final url = await context.read<BillingRepository>().getInvoicePdfDownloadUrl(
            clinicId: widget.clinicId,
            invoiceId: widget.invoiceId,
          );
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF generated; download opened.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF generated.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF generated.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.length > 120 ? '${msg.substring(0, 120)}…' : msg)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

/// Read-only view for issued/paid invoices: snapshot-backed values only.
class _IssuedInvoiceReadView extends StatelessWidget {
  const _IssuedInvoiceReadView({required this.clinicId, required this.invoice});

  final String clinicId;
  final BillingInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = invoice.effectiveCurrency ?? invoice.currency;
    final currencySuffix = (currency != null && currency.isNotEmpty) ? ' $currency' : '';
    final isPaid = invoice.status == 'paid' || invoice.balanceDue <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phase 7A.2 — Issued invoice confidence panel
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'This invoice is locked.',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (invoice.issuedAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Issued on ${invoice.issuedAt!.day} ${_monthName(invoice.issuedAt!.month)} ${invoice.issuedAt!.year}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Invoice number: ${invoice.effectiveDisplayNumber ?? invoice.id}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Values reflect the snapshot taken when the invoice was issued. Changes to settings or pricing rules do not modify issued invoices.',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
                if (invoice.dueDate != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Due: ${invoice.dueDate!.day}/${invoice.dueDate!.month}/${invoice.dueDate!.year}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                _ExportPdfButton(clinicId: clinicId, invoiceId: invoice.id),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment status', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: theme.textTheme.bodyMedium),
                    Text(
                      '${invoice.effectiveTotal.toStringAsFixed(2)}$currencySuffix',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Paid', style: theme.textTheme.bodyMedium),
                    Text(
                      '${invoice.amountPaid.toStringAsFixed(2)}$currencySuffix',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Balance due', style: theme.textTheme.bodyMedium),
                    Text(
                      '${invoice.balanceDue.toStringAsFixed(2)}$currencySuffix',
                      style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isPaid ? AppColors.success : theme.colorScheme.onSurface,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isPaid ? 'Paid in full' : 'Balance due ${invoice.balanceDue.toStringAsFixed(2)}$currencySuffix',
                  style: theme.textTheme.titleSmall?.copyWith(
                        color: isPaid ? AppColors.success : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Details', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                _ReadOnlyRow(label: 'Patient', value: invoice.patientId),
                if (invoice.appointmentId != null && invoice.appointmentId!.isNotEmpty)
                  _ReadOnlyRow(label: 'Appointment', value: invoice.appointmentId!),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Line items', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                ...invoice.effectiveLineItems.map((line) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            line.description,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${line.total.toStringAsFixed(2)}$currencySuffix',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Editable form for new or draft invoices.
class _DraftInvoiceForm extends StatefulWidget {
  const _DraftInvoiceForm({
    required this.formKey,
    required this.patientCtrl,
    required this.appointmentCtrl,
    required this.discountCtrl,
    required this.items,
    required this.onItemsChanged,
    this.invoice,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController patientCtrl;
  final TextEditingController appointmentCtrl;
  final TextEditingController discountCtrl;
  final List<InvoiceLine> items;
  final VoidCallback onItemsChanged;
  final BillingInvoice? invoice;

  @override
  State<_DraftInvoiceForm> createState() => _DraftInvoiceFormState();
}

class _DraftInvoiceFormState extends State<_DraftInvoiceForm> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Local accountant review recommended before production use in a new jurisdiction.',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          if (widget.invoice != null) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Draft', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: AppSpacing.sm),
                        if (widget.invoice!.effectiveDisplayNumber != null)
                          Text(
                            'Number: ${widget.invoice!.effectiveDisplayNumber}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    if (widget.invoice!.dueDate != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Due: ${widget.invoice!.dueDate!.day}/${widget.invoice!.dueDate!.month}/${widget.invoice!.dueDate!.year}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
          ],
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invoice details', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.elementGap),
                  TextFormField(
                    controller: widget.patientCtrl,
                    decoration: const InputDecoration(labelText: 'Patient ID'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.elementGap),
                  TextFormField(
                    controller: widget.appointmentCtrl,
                    decoration: const InputDecoration(labelText: 'Appointment ID (optional)'),
                  ),
                  const SizedBox(height: AppSpacing.elementGap),
                  TextFormField(
                    controller: widget.discountCtrl,
                    decoration: const InputDecoration(labelText: 'Invoice discount'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Line items', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          widget.items.add(const InvoiceLine(
                            type: 'service',
                            itemId: 'manual',
                            description: 'New line',
                            quantity: 1,
                            unitPrice: 0,
                            taxRate: 0,
                            total: 0,
                          ));
                          widget.onItemsChanged();
                        }),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...widget.items.asMap().entries.map(
                    (entry) => _InvoiceLineEditor(
                      key: ValueKey('line-${entry.key}'),
                      line: entry.value,
                      onChanged: (next) {
                        widget.items[entry.key] = next;
                        widget.onItemsChanged();
                      },
                      onDelete: widget.items.length <= 1
                          ? null
                          : () => setState(() {
                                widget.items.removeAt(entry.key);
                                widget.onItemsChanged();
                              }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Totals are computed server-side.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceLineEditor extends StatefulWidget {
  const _InvoiceLineEditor({
    super.key,
    required this.line,
    required this.onChanged,
    this.onDelete,
  });
  final InvoiceLine line;
  final ValueChanged<InvoiceLine> onChanged;
  final VoidCallback? onDelete;

  @override
  State<_InvoiceLineEditor> createState() => _InvoiceLineEditorState();
}

class _InvoiceLineEditorState extends State<_InvoiceLineEditor> {
  late final TextEditingController _desc;
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _tax;
  late final TextEditingController _discount;

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.line.description);
    _qty = TextEditingController(text: widget.line.quantity.toString());
    _price = TextEditingController(text: widget.line.unitPrice.toString());
    _tax = TextEditingController(text: widget.line.taxRate.toString());
    _discount = TextEditingController(text: widget.line.discount.toString());
  }

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _price.dispose();
    _tax.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(InvoiceLine(
      type: widget.line.type,
      itemId: widget.line.itemId,
      description: _desc.text.trim().isEmpty ? 'Line item' : _desc.text.trim(),
      quantity: double.tryParse(_qty.text) ?? 1,
      unitPrice: double.tryParse(_price.text) ?? 0,
      taxRate: double.tryParse(_tax.text) ?? 0,
      discount: double.tryParse(_discount.text) ?? 0,
      total: 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _desc,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Remove line',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Unit price'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tax,
                    decoration: const InputDecoration(labelText: 'Tax %'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _discount,
                    decoration: const InputDecoration(labelText: 'Discount'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emit(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

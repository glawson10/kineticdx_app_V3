import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../config/permission_keys.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';
import 'accounts_config_panes.dart';

/// Section indices: 0–6 config panes, 7–10 catalog.
const List<String> _accountsConfigSectionLabels = [
  'Business Identity',
  'Tax & Jurisdiction',
  'Invoice Numbering',
  'Invoice Defaults',
  'Invoice Template',
  'Payment Terms',
  'Compliance & Retention',
  'Taxes',
  'Payment types',
  'Billable items',
  'Products',
];

class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key, this.initialTabIndex = 0});

  /// 0–6: config panes; 7–10: catalog. When embedded from Settings, matches sub-tab index.
  final int initialTabIndex;

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTabIndex.clamp(0, _accountsConfigSectionLabels.length - 1);
  }

  @override
  void didUpdateWidget(covariant BillingSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      _tab = widget.initialTabIndex.clamp(0, _accountsConfigSectionLabels.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId.trim();
    if (clinicId.isEmpty) return const Scaffold(body: Center(child: Text('No clinic selected.')));
    final ctx = context.watch<ClinicContext>();
    final canBillingWrite = ctx.sessionOrNull != null &&
        PermissionKeys.billingWriteAny.any((k) => ctx.sessionOrNull!.permissions.has(k));
    final repo = context.read<BillingRepository>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts settings')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionRail(
            labels: _accountsConfigSectionLabels,
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
            theme: theme,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: _tab >= 0 && _tab <= 6
                  ? _AccountsConfigStream(
                      clinicId: clinicId,
                      builder: (settings) => _buildConfigPane(
                        context,
                        clinicId: clinicId,
                        canEdit: canBillingWrite,
                        sectionIndex: _tab,
                        settings: settings,
                        repo: repo,
                      ),
                    )
                  : switch (_tab) {
                      7 => _TaxesPane(clinicId: clinicId),
                      8 => _PaymentTypesPane(clinicId: clinicId),
                      9 => _CatalogPane(clinicId: clinicId, products: false),
                      _ => _CatalogPane(clinicId: clinicId, products: true),
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPane(
    BuildContext context, {
    required String clinicId,
    required bool canEdit,
    required int sectionIndex,
    required BillingGeneralSettings? settings,
    required BillingRepository repo,
  }) {
    switch (sectionIndex) {
      case 0:
        return businessIdentityPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 1:
        return taxAndJurisdictionPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 2:
        return invoiceNumberingPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 3:
        return invoiceDefaultsPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 4:
        return invoiceTemplatePane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 5:
        return paymentTermsPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      case 6:
        return complianceRetentionPane(clinicId: clinicId, canEdit: canEdit, initial: settings, repo: repo);
      default:
        return const Center(child: Text('Unknown section'));
    }
  }

}

/// Vertical section list (like Settings category rail) so Accounts has one clear navigation.
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.theme,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (int i = 0; i < labels.length; i++) ...[
              InkWell(
                onTap: () => onSelected(i),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.element)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedIndex == i
                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.element)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _iconForSection(i),
                        size: 20,
                        color: selectedIndex == i
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          labels[i],
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: selectedIndex == i ? FontWeight.w600 : null,
                            color: selectedIndex == i
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconForSection(int i) {
    switch (i) {
      case 0:
        return Icons.business_outlined;
      case 1:
        return Icons.percent_outlined;
      case 2:
        return Icons.numbers_outlined;
      case 3:
        return Icons.tune_outlined;
      case 4:
        return Icons.description_outlined;
      case 5:
        return Icons.schedule_outlined;
      case 6:
        return Icons.verified_outlined;
      case 7:
        return Icons.receipt_outlined;
      case 8:
        return Icons.payment_outlined;
      case 9:
        return Icons.inventory_2_outlined;
      case 10:
        return Icons.shopping_bag_outlined;
      default:
        return Icons.settings_outlined;
    }
  }
}

/// Config panes (0–6): show form immediately, load settings in background. Never block on a full-screen loader.
class _AccountsConfigStream extends StatefulWidget {
  const _AccountsConfigStream({
    required this.clinicId,
    required this.builder,
  });
  final String clinicId;
  final Widget Function(BillingGeneralSettings? settings) builder;

  @override
  State<_AccountsConfigStream> createState() => _AccountsConfigStreamState();
}

class _AccountsConfigStreamState extends State<_AccountsConfigStream> {
  BillingGeneralSettings? _settings;
  Object? _loadError;
  bool _loading = true;

  static bool _isPermissionDenied(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('insufficient permissions') ||
        s.contains('missing-permission');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AccountsConfigStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repo = context.read<BillingRepository>();
    try {
      final result = await repo.getBillingGeneralSettingsOnce(widget.clinicId);
      if (!mounted) return;
      setState(() {
        _settings = result;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Loading saved settings…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        if (_loadError != null) ...[
          Material(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.element),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isPermissionDenied(_loadError!)
                          ? 'Couldn\'t load saved settings. You need billing read permission (e.g. manage Billing or billing.read) to view them—ask an admin to grant it. You can still edit and Save below if you have billing write.'
                          : _loadError.toString().contains('timed out')
                              ? 'Couldn\'t load saved settings (timed out). You can still edit and Save below.'
                              : 'Couldn\'t load saved settings. You can still edit and Save below.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: widget.builder(_settings),
        ),
      ],
    );
  }
}

class _TaxesPane extends StatefulWidget {
  const _TaxesPane({required this.clinicId});
  final String clinicId;

  @override
  State<_TaxesPane> createState() => _TaxesPaneState();
}

class _TaxesPaneState extends State<_TaxesPane> {
  Stream<List<BillingTax>>? _stream;
  String? _cachedClinicId;

  void _ensureStream() {
    if (widget.clinicId == _cachedClinicId && _stream != null) return;
    _cachedClinicId = widget.clinicId;
    _stream = context.read<BillingRepository>().watchTaxes(widget.clinicId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStream();
  }

  @override
  void didUpdateWidget(covariant _TaxesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) _ensureStream();
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    if (_stream == null) return const Center(child: CircularProgressIndicator());
    final repo = context.read<BillingRepository>();
    return StreamBuilder<List<BillingTax>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load taxes: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        return ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add tax'),
                onTap: () => _showTaxDialog(context, repo, widget.clinicId),
              ),
            ),
            ...items.map((t) => Card(
                  child: ListTile(
                    title: Text(t.name),
                    subtitle: Text('Rate ${t.rate.toStringAsFixed(2)}%'),
                    trailing: Chip(label: Text(t.active ? 'Active' : 'Inactive')),
                    onTap: () => _showTaxDialog(context, repo, widget.clinicId, tax: t),
                  ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _showTaxDialog(BuildContext context, BillingRepository repo, String clinicId, {BillingTax? tax}) async {
    final name = TextEditingController(text: tax?.name ?? '');
    final rate = TextEditingController(text: tax?.rate.toString() ?? '0');
    bool active = tax?.active ?? true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tax == null ? 'Add tax' : 'Edit tax'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: rate, decoration: const InputDecoration(labelText: 'Rate (%)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await repo.upsertTax(clinicId, taxId: tax?.id, patch: {
                  'name': name.text.trim(),
                  'rate': double.tryParse(rate.text.trim()) ?? 0,
                  'active': active,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTypesPane extends StatefulWidget {
  const _PaymentTypesPane({required this.clinicId});
  final String clinicId;

  @override
  State<_PaymentTypesPane> createState() => _PaymentTypesPaneState();
}

class _PaymentTypesPaneState extends State<_PaymentTypesPane> {
  Stream<List<BillingPaymentType>>? _stream;
  String? _cachedClinicId;

  void _ensureStream() {
    if (widget.clinicId == _cachedClinicId && _stream != null) return;
    _cachedClinicId = widget.clinicId;
    _stream = context.read<BillingRepository>().watchPaymentTypes(widget.clinicId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStream();
  }

  @override
  void didUpdateWidget(covariant _PaymentTypesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) _ensureStream();
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    if (_stream == null) return const Center(child: CircularProgressIndicator());
    final repo = context.read<BillingRepository>();
    return StreamBuilder<List<BillingPaymentType>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load payment types: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        return ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add payment type'),
                onTap: () => _showPaymentTypeDialog(context, repo, widget.clinicId),
              ),
            ),
            ...items.map((p) => Card(
                  child: ListTile(
                    title: Text(p.name),
                    trailing: Chip(label: Text(p.active ? 'Active' : 'Inactive')),
                    onTap: () => _showPaymentTypeDialog(context, repo, widget.clinicId, item: p),
                  ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _showPaymentTypeDialog(BuildContext context, BillingRepository repo, String clinicId, {BillingPaymentType? item}) async {
    final name = TextEditingController(text: item?.name ?? '');
    bool active = item?.active ?? true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(item == null ? 'Add payment type' : 'Edit payment type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await repo.upsertPaymentType(clinicId, paymentTypeId: item?.id, patch: {
                  'name': name.text.trim(),
                  'active': active,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogPane extends StatefulWidget {
  const _CatalogPane({required this.clinicId, required this.products});
  final String clinicId;
  final bool products;

  @override
  State<_CatalogPane> createState() => _CatalogPaneState();
}

class _CatalogPaneState extends State<_CatalogPane> {
  Stream<List<BillingCatalogItem>>? _stream;
  String? _cachedClinicId;
  bool? _cachedProducts;

  void _ensureStream() {
    if (widget.clinicId == _cachedClinicId && widget.products == _cachedProducts && _stream != null) return;
    _cachedClinicId = widget.clinicId;
    _cachedProducts = widget.products;
    final repo = context.read<BillingRepository>();
    _stream = widget.products ? repo.watchProducts(widget.clinicId) : repo.watchBillableItems(widget.clinicId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStream();
  }

  @override
  void didUpdateWidget(covariant _CatalogPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId || oldWidget.products != widget.products) _ensureStream();
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    if (_stream == null) return const Center(child: CircularProgressIndicator());
    final repo = context.read<BillingRepository>();
    return StreamBuilder<List<BillingCatalogItem>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load catalog: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        final products = widget.products;
        return ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.add),
                title: Text(products ? 'Add product' : 'Add billable item'),
                onTap: () => _showCatalogDialog(context, repo, widget.clinicId, products: products),
              ),
            ),
            ...items.map((item) => Card(
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text(
                      'Price ${item.price.toStringAsFixed(2)}'
                      '${products && item.stock != null ? ' • Stock ${item.stock}' : ''}',
                    ),
                    trailing: Chip(label: Text(item.active ? 'Active' : 'Inactive')),
                    onTap: () => _showCatalogDialog(
                      context,
                      repo,
                      widget.clinicId,
                      products: products,
                      item: item,
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _showCatalogDialog(
    BuildContext context,
    BillingRepository repo,
    String clinicId, {
    required bool products,
    BillingCatalogItem? item,
  }) async {
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(text: item?.price.toString() ?? '0');
    final stock = TextEditingController(text: item?.stock?.toString() ?? '0');
    bool active = item?.active ?? true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(item == null
              ? (products ? 'Add product' : 'Add billable item')
              : (products ? 'Edit product' : 'Edit billable item')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: price, decoration: const InputDecoration(labelText: 'Price')),
                if (products) TextField(controller: stock, decoration: const InputDecoration(labelText: 'Stock')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final patch = <String, dynamic>{
                  'name': name.text.trim(),
                  'price': double.tryParse(price.text.trim()) ?? 0,
                  'active': active,
                };
                if (products) patch['stock'] = int.tryParse(stock.text.trim()) ?? 0;
                if (products) {
                  await repo.upsertProduct(clinicId, productId: item?.id, patch: patch);
                } else {
                  await repo.upsertBillableItem(clinicId, itemId: item?.id, patch: patch);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// Dedicated Accounts configuration panes (Business Identity, Tax & Jurisdiction, etc.).
// Each pane saves a partial patch via the same backend; issued invoices use issuedSnapshot, not live settings.

import 'package:flutter/material.dart';

import '../../../data/repositories/billing_repository.dart';
import '../models/billing_models.dart';

Widget _permissionMessage(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'To edit these settings you need billing write permission (e.g. manage Billing or billing.write).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'To view saved settings you need billing read (e.g. billing.read or manage Billing). A clinic admin can grant these via Team → Members → edit member → Permissions.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _savePatch(
  BuildContext context, {
  required String clinicId,
  required BillingRepository repo,
  required Map<String, dynamic> patch,
  required void Function(bool) setSaving,
}) async {
  setSaving(true);
  try {
    await repo.updateBillingGeneralSettings(clinicId, patch);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accounts settings saved.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  } finally {
    if (context.mounted) setSaving(false);
  }
}

/// Business Identity — display name, legal name, address, country, registration, tax ID, contact.
class _BusinessIdentityPane extends StatefulWidget {
  const _BusinessIdentityPane({
    required this.clinicId,
    required this.canEdit,
    required this.initial,
    required this.repo,
  });
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  State<_BusinessIdentityPane> createState() => _BusinessIdentityPaneState();
}

class _BusinessIdentityPaneState extends State<_BusinessIdentityPane> {
  late final TextEditingController _displayName;
  late final TextEditingController _legalName;
  late final TextEditingController _address;
  late final TextEditingController _country;
  late final TextEditingController _registrationNumber;
  late final TextEditingController _taxId;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _website;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _displayName = TextEditingController(text: s?.businessDisplayName ?? '');
    _legalName = TextEditingController(text: s?.businessLegalName ?? '');
    _address = TextEditingController(text: s?.businessAddress ?? '');
    _country = TextEditingController(text: s?.businessCountry ?? '');
    _registrationNumber = TextEditingController(text: s?.registrationNumber ?? '');
    _taxId = TextEditingController(text: s?.taxId ?? '');
    _phone = TextEditingController(text: s?.businessPhone ?? '');
    _email = TextEditingController(text: s?.businessEmail ?? '');
    _website = TextEditingController(text: s?.businessWebsite ?? '');
  }

  @override
  void didUpdateWidget(covariant _BusinessIdentityPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial && widget.initial != null) {
      final s = widget.initial!;
      _displayName.text = s.businessDisplayName ?? '';
      _legalName.text = s.businessLegalName ?? '';
      _address.text = s.businessAddress ?? '';
      _country.text = s.businessCountry ?? '';
      _registrationNumber.text = s.registrationNumber ?? '';
      _taxId.text = s.taxId ?? '';
      _phone.text = s.businessPhone ?? '';
      _email.text = s.businessEmail ?? '';
      _website.text = s.businessWebsite ?? '';
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _legalName.dispose();
    _address.dispose();
    _country.dispose();
    _registrationNumber.dispose();
    _taxId.dispose();
    _phone.dispose();
    _email.dispose();
    _website.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!widget.canEdit) _permissionMessage(context),
        // Preview: how this will appear on issued invoices (snapshot at issue time).
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Preview (as on issued invoices)', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  _displayName.text.trim().isEmpty ? '—' : _displayName.text.trim(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_address.text.trim().isNotEmpty) Text(_address.text.trim(), style: Theme.of(context).textTheme.bodySmall),
                if (_country.text.trim().isNotEmpty) Text(_country.text.trim(), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Business Identity', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Changes affect future invoices only. Issued invoices use the frozen snapshot from issue time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(controller: _displayName, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Display name', hintText: 'Clinic or business name on invoices')),
                const SizedBox(height: 8),
                TextField(controller: _legalName, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Legal business name')),
                const SizedBox(height: 8),
                TextField(controller: _address, readOnly: !widget.canEdit, maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 8),
                TextField(controller: _country, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Country (e.g. GB, CZ)')),
                const SizedBox(height: 8),
                TextField(controller: _registrationNumber, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Registration number')),
                const SizedBox(height: 8),
                TextField(controller: _taxId, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'VAT / GST / ABN / Business number')),
                const SizedBox(height: 8),
                TextField(controller: _phone, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                TextField(controller: _email, readOnly: !widget.canEdit, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 8),
                TextField(controller: _website, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Website')),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : () => _savePatch(context, clinicId: widget.clinicId, repo: widget.repo, setSaving: (v) => setState(() => _saving = v), patch: {
                      'businessDisplayName': _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
                      'businessLegalName': _legalName.text.trim().isEmpty ? null : _legalName.text.trim(),
                      'businessAddress': _address.text.trim().isEmpty ? null : _address.text.trim(),
                      'businessCountry': _country.text.trim().isEmpty ? null : _country.text.trim(),
                      'registrationNumber': _registrationNumber.text.trim().isEmpty ? null : _registrationNumber.text.trim(),
                      'taxId': _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
                      'businessPhone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                      'businessEmail': _email.text.trim().isEmpty ? null : _email.text.trim(),
                      'businessWebsite': _website.text.trim().isEmpty ? null : _website.text.trim(),
                    }),
                    child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tax & Jurisdiction — tax-inclusive pricing (country-driven; backend uses jurisdiction for issue-time validation).
class _TaxAndJurisdictionPane extends StatefulWidget {
  const _TaxAndJurisdictionPane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  State<_TaxAndJurisdictionPane> createState() => _TaxAndJurisdictionPaneState();
}

class _TaxAndJurisdictionPaneState extends State<_TaxAndJurisdictionPane> {
  bool _taxInclusive = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _taxInclusive = widget.initial?.taxInclusivePricing ?? false;
  }

  @override
  void didUpdateWidget(covariant _TaxAndJurisdictionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null) _taxInclusive = widget.initial!.taxInclusivePricing ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!widget.canEdit) _permissionMessage(context),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tax & Jurisdiction', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Set how tax is applied to new invoices. Issued invoices use the snapshot at issue time.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tax-inclusive pricing'),
                  subtitle: const Text('When on, line unit prices are treated as including tax (e.g. VAT-inclusive).'),
                  value: _taxInclusive,
                  onChanged: widget.canEdit ? (v) => setState(() => _taxInclusive = v) : null,
                ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : () => _savePatch(context, clinicId: widget.clinicId, repo: widget.repo, setSaving: (v) => setState(() => _saving = v), patch: {'taxInclusivePricing': _taxInclusive}),
                    child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Invoice Numbering — prefix, next number. Preview: "Next number will be {prefix}{next}".
class _InvoiceNumberingPane extends StatefulWidget {
  const _InvoiceNumberingPane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  State<_InvoiceNumberingPane> createState() => _InvoiceNumberingPaneState();
}

class _InvoiceNumberingPaneState extends State<_InvoiceNumberingPane> {
  late final TextEditingController _prefix;
  late final TextEditingController _nextNumber;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefix = TextEditingController(text: widget.initial?.invoicePrefix ?? '');
    _nextNumber = TextEditingController(text: widget.initial?.nextInvoiceNumber?.toString() ?? '1');
  }

  @override
  void didUpdateWidget(covariant _InvoiceNumberingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null) {
      _prefix.text = widget.initial!.invoicePrefix;
      _nextNumber.text = widget.initial!.nextInvoiceNumber?.toString() ?? '1';
    }
  }

  @override
  void dispose() {
    _prefix.dispose();
    _nextNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = int.tryParse(_nextNumber.text.trim()) ?? 1;
    final preview = '${_prefix.text.trim()}$next';
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!widget.canEdit) _permissionMessage(context),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Preview', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text('Next invoice number will be: $preview', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Invoice Numbering', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: _prefix, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Invoice number prefix', hintText: 'e.g. INV-')),
                const SizedBox(height: 8),
                TextField(controller: _nextNumber, readOnly: !widget.canEdit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Next invoice number')),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : () => _savePatch(context, clinicId: widget.clinicId, repo: widget.repo, setSaving: (v) => setState(() => _saving = v), patch: {
                      'invoicePrefix': _prefix.text.trim(),
                      'nextInvoiceNumber': next,
                    }),
                    child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Invoice Defaults — due days, currency, default notes, locale.
class _InvoiceDefaultsPane extends StatefulWidget {
  const _InvoiceDefaultsPane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  State<_InvoiceDefaultsPane> createState() => _InvoiceDefaultsPaneState();
}

class _InvoiceDefaultsPaneState extends State<_InvoiceDefaultsPane> {
  late final TextEditingController _defaultDueDays;
  late final TextEditingController _currency;
  late final TextEditingController _defaultInvoiceNotes;
  late final TextEditingController _defaultLocale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _defaultDueDays = TextEditingController(text: widget.initial?.defaultDueDays?.toString() ?? '30');
    _currency = TextEditingController(text: widget.initial?.currency ?? '');
    _defaultInvoiceNotes = TextEditingController(text: widget.initial?.defaultInvoiceNotes ?? '');
    _defaultLocale = TextEditingController(text: widget.initial?.defaultLocale ?? '');
  }

  @override
  void didUpdateWidget(covariant _InvoiceDefaultsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null) {
      _defaultDueDays.text = widget.initial!.defaultDueDays?.toString() ?? '30';
      _currency.text = widget.initial!.currency ?? '';
      _defaultInvoiceNotes.text = widget.initial!.defaultInvoiceNotes ?? '';
      _defaultLocale.text = widget.initial!.defaultLocale ?? '';
    }
  }

  @override
  void dispose() {
    _defaultDueDays.dispose();
    _currency.dispose();
    _defaultInvoiceNotes.dispose();
    _defaultLocale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!widget.canEdit) _permissionMessage(context),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Invoice Defaults', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: _defaultDueDays, readOnly: !widget.canEdit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default due days', hintText: '30')),
                const SizedBox(height: 8),
                TextField(controller: _currency, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Currency (e.g. USD, EUR)')),
                const SizedBox(height: 8),
                TextField(controller: _defaultInvoiceNotes, readOnly: !widget.canEdit, maxLines: 2, decoration: const InputDecoration(labelText: 'Default invoice notes')),
                const SizedBox(height: 8),
                TextField(controller: _defaultLocale, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Default locale', hintText: 'e.g. en_GB')),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : () => _savePatch(context, clinicId: widget.clinicId, repo: widget.repo, setSaving: (v) => setState(() => _saving = v), patch: {
                      'defaultDueDays': int.tryParse(_defaultDueDays.text.trim()) ?? 30,
                      'currency': _currency.text.trim().isEmpty ? null : _currency.text.trim(),
                      'defaultInvoiceNotes': _defaultInvoiceNotes.text.trim().isEmpty ? null : _defaultInvoiceNotes.text.trim(),
                      'defaultLocale': _defaultLocale.text.trim().isEmpty ? null : _defaultLocale.text.trim(),
                    }),
                    child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Invoice Template — footer, title, show logo / practitioner / contact, group tax lines. Preview summary.
class _InvoiceTemplatePane extends StatefulWidget {
  const _InvoiceTemplatePane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  State<_InvoiceTemplatePane> createState() => _InvoiceTemplatePaneState();
}

class _InvoiceTemplatePaneState extends State<_InvoiceTemplatePane> {
  late final TextEditingController _footerText;
  late final TextEditingController _invoiceTitle;
  bool _showLogo = true;
  bool _showPractitioner = true;
  bool _showBusinessContact = true;
  bool _groupTaxLines = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _footerText = TextEditingController(text: widget.initial?.defaultFooterText ?? '');
    _invoiceTitle = TextEditingController(text: widget.initial?.invoiceTitle ?? '');
    _showLogo = widget.initial?.showLogoOnInvoice ?? true;
    _showPractitioner = widget.initial?.showPractitionerOnInvoice ?? true;
    _showBusinessContact = widget.initial?.showBusinessContactOnInvoice ?? true;
    _groupTaxLines = widget.initial?.groupTaxLinesOnInvoice ?? false;
  }

  @override
  void didUpdateWidget(covariant _InvoiceTemplatePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null) {
      _footerText.text = widget.initial!.defaultFooterText ?? '';
      _invoiceTitle.text = widget.initial!.invoiceTitle ?? '';
      _showLogo = widget.initial!.showLogoOnInvoice ?? true;
      _showPractitioner = widget.initial!.showPractitionerOnInvoice ?? true;
      _showBusinessContact = widget.initial!.showBusinessContactOnInvoice ?? true;
      _groupTaxLines = widget.initial!.groupTaxLinesOnInvoice ?? false;
    }
  }

  @override
  void dispose() {
    _footerText.dispose();
    _invoiceTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!widget.canEdit) _permissionMessage(context),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Preview summary', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text('Logo: ${_showLogo ? "Yes" : "No"} · Practitioner: ${_showPractitioner ? "Yes" : "No"} · Business contact: ${_showBusinessContact ? "Yes" : "No"} · Group tax lines: ${_groupTaxLines ? "Yes" : "No"}', style: Theme.of(context).textTheme.bodySmall),
                if (_invoiceTitle.text.trim().isNotEmpty) Text('Title: ${_invoiceTitle.text.trim()}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Invoice Template', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: _footerText, readOnly: !widget.canEdit, maxLines: 2, decoration: const InputDecoration(labelText: 'Default footer text')),
                const SizedBox(height: 8),
                TextField(controller: _invoiceTitle, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Invoice title', hintText: 'e.g. Invoice, Tax Invoice')),
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show logo on invoice'), value: _showLogo, onChanged: widget.canEdit ? (v) => setState(() => _showLogo = v) : null),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show practitioner details'), value: _showPractitioner, onChanged: widget.canEdit ? (v) => setState(() => _showPractitioner = v) : null),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show business contact'), value: _showBusinessContact, onChanged: widget.canEdit ? (v) => setState(() => _showBusinessContact = v) : null),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Group tax lines'), value: _groupTaxLines, onChanged: widget.canEdit ? (v) => setState(() => _groupTaxLines = v) : null),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : () => _savePatch(context, clinicId: widget.clinicId, repo: widget.repo, setSaving: (v) => setState(() => _saving = v), patch: {
                      'defaultFooterText': _footerText.text.trim().isEmpty ? null : _footerText.text.trim(),
                      'invoiceTitle': _invoiceTitle.text.trim().isEmpty ? null : _invoiceTitle.text.trim(),
                      'showLogoOnInvoice': _showLogo,
                      'showPractitionerOnInvoice': _showPractitioner,
                      'showBusinessContactOnInvoice': _showBusinessContact,
                      'groupTaxLinesOnInvoice': _groupTaxLines,
                    }),
                    child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Payment Terms — placeholder / minimal (e.g. default payment terms text if we add it to settings later).
class _PaymentTermsPane extends StatelessWidget {
  const _PaymentTermsPane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Payment Terms', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Default payment terms can be set in Invoice Defaults (default notes) or in footer text in Invoice Template. A dedicated payment-terms field can be added to the settings contract when needed.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Compliance & Retention — guidance; retention is jurisdiction-driven (backend registry).
class _ComplianceRetentionPane extends StatelessWidget {
  const _ComplianceRetentionPane({required this.clinicId, required this.canEdit, required this.initial, required this.repo});
  final String clinicId;
  final bool canEdit;
  final BillingGeneralSettings? initial;
  final BillingRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Compliance & Retention', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Jurisdiction and retention rules are driven by your clinic country (Business Identity). This system is compliance-supportive, not legal advice.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '• Local accountant review is recommended before production use in a new jurisdiction.\n'
                  '• Issued invoices are immutable; values come from the snapshot at issue time. Changing settings does not modify issued invoices.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Public exports for use from BillingSettingsScreen.
Widget businessIdentityPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _BusinessIdentityPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget taxAndJurisdictionPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _TaxAndJurisdictionPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget invoiceNumberingPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _InvoiceNumberingPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget invoiceDefaultsPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _InvoiceDefaultsPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget invoiceTemplatePane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _InvoiceTemplatePane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget paymentTermsPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _PaymentTermsPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}
Widget complianceRetentionPane({required String clinicId, required bool canEdit, required BillingGeneralSettings? initial, required BillingRepository repo}) {
  return _ComplianceRetentionPane(clinicId: clinicId, canEdit: canEdit, initial: initial, repo: repo);
}

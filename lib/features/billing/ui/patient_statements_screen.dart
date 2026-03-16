import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';

class PatientStatementsScreen extends StatefulWidget {
  const PatientStatementsScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  State<PatientStatementsScreen> createState() => _PatientStatementsScreenState();
}

class _PatientStatementsScreenState extends State<PatientStatementsScreen> {
  Stream<List<BillingInvoice>>? _stream;
  String? _cachedClinicId;

  void _ensureStream() {
    if (widget.clinicId == _cachedClinicId && _stream != null) return;
    _cachedClinicId = widget.clinicId;
    _stream = context.read<BillingRepository>().watchInvoices(widget.clinicId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStream();
  }

  @override
  void didUpdateWidget(covariant PatientStatementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) _ensureStream();
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    if (_stream == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Patient statements')),
      body: StreamBuilder<List<BillingInvoice>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load statements: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final byPatient = <String, List<BillingInvoice>>{};
          for (final inv in snap.data!) {
            byPatient.putIfAbsent(inv.patientId, () => []).add(inv);
          }
          final patients = byPatient.keys.toList()..sort();
          if (patients.isEmpty) {
            return const Center(child: Text('No statement data yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: patients.length,
            itemBuilder: (context, i) {
              final patientId = patients[i];
              final invoices = byPatient[patientId]!;
              final total = invoices.fold<double>(0, (a, b) => a + b.total);
              final paid = invoices.fold<double>(0, (a, b) => a + b.amountPaid);
              final balance = invoices.fold<double>(0, (a, b) => a + b.balanceDue);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(patientId),
                  subtitle: Text(
                    'Invoices: ${invoices.length} • '
                    'Total: ${total.toStringAsFixed(2)} • '
                    'Paid: ${paid.toStringAsFixed(2)}',
                  ),
                  trailing: Text('Balance ${balance.toStringAsFixed(2)}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

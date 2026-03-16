import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/billing_repository.dart';
import '../../../ui/design_tokens.dart';
import '../models/billing_models.dart';

class BillingDashboardScreen extends StatefulWidget {
  const BillingDashboardScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  State<BillingDashboardScreen> createState() => _BillingDashboardScreenState();
}

class _BillingDashboardScreenState extends State<BillingDashboardScreen> {
  Future<(BillingSummary, AgedReceivables)>? _future;
  String? _cachedClinicId;

  void _ensureFuture(BuildContext context) {
    if (widget.clinicId == _cachedClinicId && _future != null) return;
    _cachedClinicId = widget.clinicId;
    final repo = context.read<BillingRepository>();
    _future = Future(() async {
      final summary = await repo.getSummary(widget.clinicId);
      final aged = await repo.getAgedReceivables(widget.clinicId);
      return (summary, aged);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureFuture(context);
  }

  @override
  void didUpdateWidget(covariant BillingDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) _ensureFuture(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Billing dashboard')),
      body: FutureBuilder<(BillingSummary, AgedReceivables)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load dashboard: ${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final summary = snap.data!.$1;
          final aged = snap.data!.$2;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              children: [
                _MetricCard(title: 'Revenue today', value: summary.revenueToday),
                _MetricCard(title: 'Revenue this month', value: summary.revenueMonth),
                _MetricCard(title: 'Outstanding invoices', value: summary.outstandingInvoices),
                _MetricCard(title: 'Current receivables', value: aged.current),
                _MetricCard(title: '30 days', value: aged.days30),
                _MetricCard(title: '60 days', value: aged.days60),
                _MetricCard(title: '90+ days', value: aged.days90plus),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});
  final String title;
  final double value;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value.toStringAsFixed(2),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../general_visit_v1_summary.dart';

class GeneralVisitClinicianSummaryCard extends StatelessWidget {
  final GeneralVisitSummaryV1 summary;

  const GeneralVisitClinicianSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    Widget chips(List<String> items) {
      if (items.isEmpty) return const Text('—');
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((t) => Chip(label: Text(t))).toList(),
      );
    }

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(summary.disclaimer, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(height: 22),

            // Visit context
            Text('Visit context', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            row('Reason', summary.reasonForVisit),
            row('Clarity', summary.concernClarityLabel),

            const SizedBox(height: 6),
            const Text('Areas mentioned', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            chips(summary.bodyAreaLabels),
            const Divider(height: 26),

            // Impact
            Text('Impact', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            row('Primary', summary.primaryImpactLabel),
            const SizedBox(height: 6),
            const Text('Activities affected', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            chips(summary.limitedActivityLabels),
            const Divider(height: 26),

            // Timeframe + goals
            Text('Timeframe & goals', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            row('Duration', summary.durationLabel),
            const SizedBox(height: 6),
            const Text('Visit intent', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            chips(summary.visitIntentLabels),
            const Divider(height: 26),

            // Safety
            Text('Safety', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            row('Not emergency', summary.ackNotEmergency),
            row('No diagnosis', summary.ackNoDiagnosis),
          ],
        ),
      ),
    );
  }
}

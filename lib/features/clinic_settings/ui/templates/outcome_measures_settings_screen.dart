import 'package:flutter/material.dart';

import '../../../../data/repositories/clinic_registry_repository.dart';
import '../../../../models/outcome_measure.dart';
import 'edit_outcome_measure_screen.dart';

class OutcomeMeasuresSettingsScreen extends StatefulWidget {
  final String clinicId;
  const OutcomeMeasuresSettingsScreen({super.key, required this.clinicId});

  @override
  State<OutcomeMeasuresSettingsScreen> createState() => _OutcomeMeasuresSettingsScreenState();
}

class _OutcomeMeasuresSettingsScreenState extends State<OutcomeMeasuresSettingsScreen> {
  final _repo = ClinicRegistryRepository();
  final _search = TextEditingController();
  bool _activeOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filters(context),
        Expanded(
          child: StreamBuilder<List<OutcomeMeasure>>(
            stream: _repo.streamOutcomeMeasures(
              clinicId: widget.clinicId,
              activeOnly: _activeOnly,
            ),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final query = _search.text.trim().toLowerCase();
              final items = snap.data!
                  .where((m) {
                    if (query.isEmpty) return true;
                    final hay = [
                      m.name,
                      m.fullName ?? '',
                      m.scoreFormatHint ?? '',
                      ...m.tags,
                    ].join(' ').toLowerCase();
                    return hay.contains(query);
                  })
                  .toList();

              if (items.isEmpty) {
                return const Center(child: Text('No outcome measures found.'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = items[i];
                  return ListTile(
                    title: Text(m.name),
                    subtitle: Text(_subtitle(m)),
                    trailing: Switch(
                      value: m.active,
                      onChanged: (v) async {
                        try {
                          await _repo.setRegistryActive(
                            clinicId: widget.clinicId,
                            collection: 'outcomeMeasures',
                            id: m.id,
                            active: v,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')),
                            );
                          }
                        }
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditOutcomeMeasureScreen(
                          clinicId: widget.clinicId,
                          existing: m,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search outcome measures',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _search.clear()),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('Active only'),
                selected: _activeOnly,
                onSelected: (v) => setState(() => _activeOnly = v),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditOutcomeMeasureScreen(
                      clinicId: widget.clinicId,
                      existing: null,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add measure'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(OutcomeMeasure m) {
    final tags = m.tags.isEmpty ? '' : ' • tags: ${m.tags.join(", ")}';
    final hint = (m.scoreFormatHint?.isNotEmpty == true) ? ' • ${m.scoreFormatHint}' : '';
    final full = (m.fullName?.isNotEmpty == true) ? ' • ${m.fullName}' : '';
    return '${m.name}$full$hint$tags';
  }
}

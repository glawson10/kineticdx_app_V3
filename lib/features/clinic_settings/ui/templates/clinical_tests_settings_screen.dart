import 'package:flutter/material.dart';

import '../../../../data/repositories/clinic_registry_repository.dart';
import '../../../../models/clinical_test_registry_item.dart';
import 'edit_clinical_test_screen.dart';

class ClinicalTestsSettingsScreen extends StatefulWidget {
  final String clinicId;
  const ClinicalTestsSettingsScreen({super.key, required this.clinicId});

  @override
  State<ClinicalTestsSettingsScreen> createState() => _ClinicalTestsSettingsScreenState();
}

class _ClinicalTestsSettingsScreenState extends State<ClinicalTestsSettingsScreen> {
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
          child: StreamBuilder<List<ClinicalTestRegistryItem>>(
            stream: _repo.streamClinicalTests(
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
                  .where((t) {
                    if (query.isEmpty) return true;
                    final hay = [
                      t.name,
                      t.shortName ?? '',
                      t.category,
                      ...t.tags,
                      ...t.bodyRegions,
                    ].join(' ').toLowerCase();
                    return hay.contains(query);
                  })
                  .toList();

              if (items.isEmpty) {
                return const Center(child: Text('No tests found.'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = items[i];
                  return ListTile(
                    title: Text(t.name),
                    subtitle: Text(_subtitle(t)),
                    trailing: Switch(
                      value: t.active,
                      onChanged: (v) async {
                        try {
                          await _repo.setRegistryActive(
                            clinicId: widget.clinicId,
                            collection: 'clinicalTestRegistry',
                            id: t.id,
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
                        builder: (_) => EditClinicalTestScreen(
                          clinicId: widget.clinicId,
                          existing: t,
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
              labelText: 'Search tests',
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
                    builder: (_) => EditClinicalTestScreen(
                      clinicId: widget.clinicId,
                      existing: null,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add test'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(ClinicalTestRegistryItem t) {
    final regions = t.bodyRegions.isEmpty ? '' : ' • ${t.bodyRegions.join(", ")}';
    final tags = t.tags.isEmpty ? '' : ' • tags: ${t.tags.join(", ")}';
    final short = (t.shortName?.isNotEmpty == true) ? ' (${t.shortName})' : '';
    return '${t.category}$short$regions$tags';
  }
}

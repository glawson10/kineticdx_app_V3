import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../models/clinic_permissions.dart';
import '../../../models/clinical_test_registry_item.dart';
import '../../../models/clinical_tests.dart';
import '../../../data/repositories/clinic_registry_repository.dart';
import '../../notes/data/notes_permissions.dart';
import 'clinical_test_editor_screen.dart';

class ClinicalTestRegistryScreen extends StatefulWidget {
  final String clinicId;

  const ClinicalTestRegistryScreen({
    super.key,
    required this.clinicId,
  });

  @override
  State<ClinicalTestRegistryScreen> createState() =>
      _ClinicalTestRegistryScreenState();
}

class _ClinicalTestRegistryScreenState
    extends State<ClinicalTestRegistryScreen> {
  final ClinicRegistryRepository _repo = ClinicRegistryRepository();
  final TextEditingController _search = TextEditingController();

  bool _activeOnly = true;
  BodyRegion? _regionFilter;
  bool _seeding = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final perms = clinicCtx.session.permissions;
    final canRead = canViewClinicalNotes(perms);
    final canManage = canManageNotesSettings(perms);

    if (!canRead) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No access to clinical test registry.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Test Registry'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Import recommended tests',
              icon: _seeding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              onPressed: _seeding ? null : _confirmAndSeed,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(context, canManage),
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

                final items = _applyFilters(snap.data!);
                if (items.isEmpty) {
                  return const Center(child: Text('No tests found.'));
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final t = items[index];
                    return ListTile(
                      title: Text(t.name),
                      subtitle: Text(_subtitle(t)),
                      trailing: Switch(
                        value: t.active,
                        onChanged: !canManage
                            ? null
                            : (v) async {
                                try {
                                  await _repo.setRegistryActive(
                                    clinicId: widget.clinicId,
                                    collection: 'clinicalTestRegistry',
                                    id: t.id,
                                    active: v,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed: $e'),
                                    ),
                                  );
                                }
                              },
                      ),
                      onTap: !canManage
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ClinicalTestEditorScreen(
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
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClinicalTestEditorScreen(
                    clinicId: widget.clinicId,
                    existing: null,
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildFilters(BuildContext context, bool canManage) {
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
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All regions'),
                        selected: _regionFilter == null,
                        onSelected: (_) =>
                            setState(() => _regionFilter = null),
                      ),
                      const SizedBox(width: 4),
                      for (final region in BodyRegion.values) ...[
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: Text(_regionLabel(region)),
                          selected: _regionFilter == region,
                          onSelected: (_) =>
                              setState(() => _regionFilter = region),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (canManage) const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  List<ClinicalTestRegistryItem> _applyFilters(
    List<ClinicalTestRegistryItem> source,
  ) {
    final query = _search.text.trim().toLowerCase();
    final region = _regionFilter;

    return source.where((t) {
      if (region != null &&
          !t.bodyRegions
              .map((e) => e.toLowerCase())
              .contains(region.name.toLowerCase())) {
        return false;
      }

      if (query.isEmpty) return true;
      final hay = [
        t.name,
        t.shortName ?? '',
        t.category,
        ...t.tags,
        ...t.bodyRegions,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
  }

  String _subtitle(ClinicalTestRegistryItem t) {
    final regions =
        t.bodyRegions.isEmpty ? '' : ' • ${t.bodyRegions.join(", ")}';
    final tags = t.tags.isEmpty ? '' : ' • tags: ${t.tags.join(", ")}';
    final short =
        (t.shortName?.isNotEmpty == true) ? ' (${t.shortName})' : '';
    return '${t.category}$short$regions$tags';
  }

  String _regionLabel(BodyRegion region) {
    switch (region) {
      case BodyRegion.cervical:
        return 'Cervical';
      case BodyRegion.thoracic:
        return 'Thoracic';
      case BodyRegion.lumbar:
        return 'Lumbar';
      case BodyRegion.shoulder:
        return 'Shoulder';
      case BodyRegion.elbow:
        return 'Elbow';
      case BodyRegion.wristHand:
        return 'Wrist/Hand';
      case BodyRegion.hip:
        return 'Hip';
      case BodyRegion.knee:
        return 'Knee';
      case BodyRegion.ankleFoot:
        return 'Ankle/Foot';
      case BodyRegion.other:
        return 'Other';
    }
  }

  Future<void> _confirmAndSeed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import recommended tests'),
        content: const Text(
          'This will upsert a curated set of research-grade clinical tests '
          'into this clinic\'s registry. Existing tests with the same id will '
          'be updated. You can safely run this more than once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _seeding = true);
    try {
      final tests = ClinicalTestRegistry.allTests;
      for (final def in tests) {
        await _repo.upsertClinicalTest(
          clinicId: widget.clinicId,
          testId: def.id,
          name: def.name,
          shortName: def.synonyms.isNotEmpty ? def.synonyms.first : null,
          bodyRegions: [def.region.name],
          tags: [
            ...def.synonyms,
            ...def.primaryStructures,
            def.category.name,
            def.evidenceLevel.name,
            if (def.isCommon) 'common',
          ],
          category: 'special_test',
          instructions: def.purpose.isEmpty ? null : def.purpose,
          positiveCriteria: null,
          contraindications: null,
          interpretation: def.keyReference,
          resultType: 'ternary',
          allowedResults: const ['pos', 'neg', 'nt'],
          active: true,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported clinical tests.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }
}


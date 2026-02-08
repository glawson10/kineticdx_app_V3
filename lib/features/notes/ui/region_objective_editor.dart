// Region-specific objective editor with normative ROM ranges per movement.
// Used in the Objective tab when one or more body regions are selected.

import 'package:flutter/material.dart';

import '../../../models/clinical_tests.dart';
import '../../../models/region_objective_templates.dart';
import '../../../models/soap_note.dart';
import 'widgets/spine_rom_diagram.dart';

class RegionObjectiveEditor extends StatelessWidget {
  final RegionObjective regionObjective;
  final RegionObjectiveTemplate template;
  final bool readOnly;
  final ValueChanged<RegionObjective> onChanged;

  const RegionObjectiveEditor({
    super.key,
    required this.regionObjective,
    required this.template,
    required this.readOnly,
    required this.onChanged,
  });

  static RomFinding _findRom(List<RomFinding> list, String movement,
      {RomValueUnit? defaultUnit}) {
    return list.cast<RomFinding?>().firstWhere(
          (r) => r?.movement == movement,
          orElse: () => RomFinding(
              movement: movement,
              valueUnit: defaultUnit ?? RomValueUnit.deg),
        )!;
  }

  static StrengthFinding _findStrength(List<StrengthFinding> list, String key) {
    return list.cast<StrengthFinding?>().firstWhere(
          (s) => s?.movementOrMyotome == key,
          orElse: () => StrengthFinding(movementOrMyotome: key),
        )!;
  }

  static NeuroFinding _findNeuro(List<NeuroFinding> list, String structure) {
    return list.cast<NeuroFinding?>().firstWhere(
          (n) => n?.structure == structure,
          orElse: () => NeuroFinding(structure: structure, status: 'normal'),
        )!;
  }

  static JointMobilityFinding _findJointMob(
      List<JointMobilityFinding> list, String level) {
    return list.cast<JointMobilityFinding?>().firstWhere(
          (j) => j?.level == level,
          orElse: () => JointMobilityFinding(level: level, mobility: 'normal'),
        )!;
  }

  static PalpationFinding _findPalpation(
      List<PalpationFinding> list, String location) {
    return list.cast<PalpationFinding?>().firstWhere(
          (p) => p?.location == location,
          orElse: () => PalpationFinding(location: location),
        )!;
  }

  static bool _isSpineRegion(BodyRegion region) =>
      region == BodyRegion.cervical ||
      region == BodyRegion.thoracic ||
      region == BodyRegion.lumbar;

  /// On desktop/tablet (wide screen), Strength/Neuro/Joint mobility/Palpation in one row.
  static Widget _buildObjectiveSectionsRow({
    required BuildContext context,
    required RegionObjectiveTemplate template,
    required RegionObjective regionObjective,
    required bool readOnly,
    required ValueChanged<RegionObjective> onChanged,
  }) {
    final sections = <Widget>[];
    if (template.strengthItems.isNotEmpty)
      sections.add(
        _StrengthSection(
          items: template.strengthItems,
          findings: regionObjective.strength,
          readOnly: readOnly,
          onUpdate: (updated) =>
              onChanged(regionObjective.copyWith(strength: updated)),
        ),
      );
    if (template.neuroItems.isNotEmpty)
      sections.add(
        _NeuroSection(
          items: template.neuroItems,
          findings: regionObjective.neuro,
          readOnly: readOnly,
          onUpdate: (updated) =>
              onChanged(regionObjective.copyWith(neuro: updated)),
        ),
      );
    if (template.jointMobilityLevels.isNotEmpty)
      sections.add(
        _JointMobilitySection(
          levels: template.jointMobilityLevels,
          findings: regionObjective.jointMobility,
          readOnly: readOnly,
          onUpdate: (updated) => onChanged(
            regionObjective.copyWith(jointMobility: updated),
          ),
        ),
      );
    if (template.palpationAreas.isNotEmpty)
      sections.add(
        _PalpationSection(
          areas: template.palpationAreas,
          findings: regionObjective.palpation,
          readOnly: readOnly,
          onUpdate: (updated) =>
              onChanged(regionObjective.copyWith(palpation: updated)),
        ),
      );
    if (sections.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final useRow = width > 800 && sections.length > 1;
    if (useRow)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.map((s) => Expanded(child: s)).toList(),
      );
    return Column(children: sections);
  }

  @override
  Widget build(BuildContext context) {
    final region = regionObjective.region;
    final regionLabel = region.name.replaceFirst(region.name[0], region.name[0].toUpperCase());
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              regionLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (template.aromMovements.isNotEmpty)
            _isSpineRegion(region)
                ? _SpineAromSection(
                    region: region,
                    defs: template.aromMovements,
                    findings: regionObjective.activeRom,
                    readOnly: readOnly,
                    onUpdate: (updated) => onChanged(
                      regionObjective.copyWith(activeRom: updated),
                    ),
                  )
                : _RomSection(
                    title: 'AROM',
                    defs: template.aromMovements,
                    findings: regionObjective.activeRom,
                    readOnly: readOnly,
                    onUpdate: (updated) => onChanged(
                      regionObjective.copyWith(activeRom: updated),
                    ),
                  ),
          if (template.promMovements.isNotEmpty && !_isSpineRegion(region))
            _RomSection(
              title: 'PROM',
              defs: template.promMovements,
              findings: regionObjective.passiveRom,
              readOnly: readOnly,
              onUpdate: (updated) => onChanged(
                regionObjective.copyWith(passiveRom: updated),
              ),
            ),
          _buildObjectiveSectionsRow(
            context: context,
            template: template,
            regionObjective: regionObjective,
            readOnly: readOnly,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Spine AROM: toggle between list view and radial diagram (cervical/thoracic/lumbar).
class _SpineAromSection extends StatefulWidget {
  final BodyRegion region;
  final List<RomMovementDef> defs;
  final List<RomFinding> findings;
  final bool readOnly;
  final ValueChanged<List<RomFinding>> onUpdate;

  const _SpineAromSection({
    required this.region,
    required this.defs,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  @override
  State<_SpineAromSection> createState() => _SpineAromSectionState();
}

class _SpineAromSectionState extends State<_SpineAromSection> {
  bool _useDiagram = false;

  static RomValueUnit _defaultUnitForRegion(BodyRegion region) {
    return (region == BodyRegion.lumbar || region == BodyRegion.thoracic)
        ? RomValueUnit.pct
        : RomValueUnit.deg;
  }

  @override
  Widget build(BuildContext context) {
    final defaultUnit = _defaultUnitForRegion(widget.region);
    return ExpansionTile(
      title: const Text('AROM'),
      initiallyExpanded: true,
      children: [
        if (!widget.readOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('View: ', style: TextStyle(fontSize: 13)),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('List')),
                    ButtonSegment(value: true, label: Text('Diagram')),
                  ],
                  selected: {_useDiagram},
                  onSelectionChanged: (s) => setState(() => _useDiagram = s.first),
                ),
                const SizedBox(width: 24),
                const Text('Unit: ', style: TextStyle(fontSize: 13)),
                SegmentedButton<RomValueUnit>(
                  segments: const [
                    ButtonSegment(value: RomValueUnit.deg, label: Text('°')),
                    ButtonSegment(value: RomValueUnit.pct, label: Text('%')),
                  ],
                  selected: {
                    widget.findings.isNotEmpty
                        ? RegionObjectiveEditor._findRom(widget.findings, widget.defs.first.movement).valueUnit
                        : defaultUnit
                  },
                  onSelectionChanged: (s) {
                    final u = s.first;
                    final byMovement = {for (final f in widget.findings) f.movement: f};
                    widget.onUpdate(widget.defs
                        .map((d) =>
                            (byMovement[d.movement] ?? RomFinding(movement: d.movement, valueUnit: defaultUnit))
                                .copyWith(valueUnit: u))
                        .toList());
                  },
                ),
              ],
            ),
          ),
        if (_useDiagram)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SpineRomDiagram(
                defs: widget.defs,
                findings: widget.findings,
                readOnly: widget.readOnly,
                onUpdate: widget.onUpdate,
              ),
            ),
          )
        else
          _RomSection(
            title: 'AROM',
            defs: widget.defs,
            findings: widget.findings,
            readOnly: widget.readOnly,
            onUpdate: widget.onUpdate,
            embedContentOnly: true,
            showUnitInHeader: false,
            defaultUnit: defaultUnit,
          ),
      ],
    );
  }
}

class _RomSection extends StatefulWidget {
  final String title;
  final List<RomMovementDef> defs;
  final List<RomFinding> findings;
  final bool readOnly;
  final ValueChanged<List<RomFinding>> onUpdate;
  final bool embedContentOnly;
  final bool showUnitInHeader;
  final RomValueUnit? defaultUnit;

  const _RomSection({
    required this.title,
    required this.defs,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
    this.embedContentOnly = false,
    this.showUnitInHeader = true,
    this.defaultUnit,
  });

  @override
  State<_RomSection> createState() => _RomSectionState();
}

class _RomSectionState extends State<_RomSection> {
  List<RomFinding> get _findings => widget.findings;

  List<RomFinding> _mergeUpdate(int index, RomFinding updated) {
    final byMovement = {
      for (final r in _findings) r.movement: r,
    };
    byMovement[updated.movement] = updated;
    final defUnit = widget.defaultUnit ?? RomValueUnit.deg;
    return widget.defs
        .map((d) => byMovement[d.movement] ?? RomFinding(movement: d.movement, valueUnit: defUnit))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.defs.isEmpty) {
      if (widget.embedContentOnly) return const SizedBox.shrink();
      return ExpansionTile(
        title: Text(widget.title),
        initiallyExpanded: false,
        children: const [SizedBox(height: 8)],
      );
    }
    final sectionUnit = _findings.isNotEmpty
        ? RegionObjectiveEditor._findRom(_findings, widget.defs.first.movement).valueUnit
        : (widget.defaultUnit ?? RomValueUnit.deg);
    final isPercentage = sectionUnit == RomValueUnit.pct;

    final headerRow = widget.readOnly
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showUnitInHeader)
                  Row(
                    children: [
                      const Text('Unit: ', style: TextStyle(fontSize: 12)),
                      SegmentedButton<RomValueUnit>(
                        segments: const [
                          ButtonSegment(value: RomValueUnit.deg, label: Text('°')),
                          ButtonSegment(value: RomValueUnit.pct, label: Text('%')),
                        ],
                        selected: {sectionUnit},
                        onSelectionChanged: (s) {
                          final u = s.first;
                          final byMovement = {for (final f in _findings) f.movement: f};
                          final defUnit = widget.defaultUnit ?? RomValueUnit.deg;
                          widget.onUpdate(widget.defs
                              .map((d) =>
                                  (byMovement[d.movement] ?? RomFinding(movement: d.movement, valueUnit: defUnit))
                                      .copyWith(valueUnit: u))
                              .toList());
                        },
                      ),
                    ],
                  ),
                if (widget.showUnitInHeader) const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 160),
                    const SizedBox(width: 100),
                    const SizedBox(width: 12),
                    const SizedBox(width: 56, child: Text('Pain', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                    const SizedBox(width: 8),
                    const SizedBox(width: 100, child: Text('Reproduces symptoms', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
                  ],
                ),
              ],
            ),
          );

    final listContent = widget.defs.asMap().entries.map((entry) {
        final i = entry.key;
        final def = entry.value;
        final finding = RegionObjectiveEditor._findRom(
            _findings, def.movement,
            defaultUnit: widget.defaultUnit);
        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: Text(
                    def.movement,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: TextFormField(
                          key: ValueKey('rom_${def.movement}_${finding.valueUnit.name}'),
                          initialValue: finding.value != null
                              ? finding.value!.toStringAsFixed(0)
                              : '',
                          readOnly: widget.readOnly,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: isPercentage ? '%' : '°',
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onChanged: widget.readOnly
                              ? null
                              : (v) {
                                  final numVal = double.tryParse(v.trim());
                                  widget.onUpdate(_mergeUpdate(
                                      i,
                                      finding.copyWith(
                                          value: numVal,
                                          valueUnit: finding.valueUnit,
                                          painful: finding.painful,
                                          reproducesMainSymptoms:
                                              finding.reproducesMainSymptoms,
                                          notes: finding.notes)));
                                },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          isPercentage ? '%' : '°',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!widget.readOnly) ...[
                  SizedBox(
                    width: 56,
                    child: Checkbox(
                      value: finding.painful,
                      onChanged: (v) => widget.onUpdate(_mergeUpdate(
                          i, finding.copyWith(painful: v ?? false))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Checkbox(
                      value: finding.reproducesMainSymptoms,
                      onChanged: (v) => widget.onUpdate(_mergeUpdate(
                          i,
                          finding.copyWith(
                              reproducesMainSymptoms: v ?? false))),
                    ),
                  ),
                ] else ...[
                  Text(finding.painful ? '✓' : '—', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(
                    finding.reproducesMainSymptoms ? '✓' : '—',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList();

    final children = [
      if (headerRow != null) headerRow,
      ...listContent,
    ];
    if (widget.embedContentOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    return ExpansionTile(
      title: Text(widget.title),
      initiallyExpanded: true,
      children: children,
    );
  }
}

class _StrengthSection extends StatelessWidget {
  final List<String> items;
  final List<StrengthFinding> findings;
  final bool readOnly;
  final ValueChanged<List<StrengthFinding>> onUpdate;

  const _StrengthSection({
    required this.items,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  List<StrengthFinding> _merge(String key, StrengthFinding updated) {
    final byKey = {
      for (final s in findings) s.movementOrMyotome: s,
    };
    byKey[key] = updated;
    return items
        .map((k) =>
            byKey[k] ?? StrengthFinding(movementOrMyotome: k))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Strength'),
      initiallyExpanded: false,
      children: items.isEmpty
          ? [const SizedBox(height: 8)]
          : items.map((key) {
              final s = RegionObjectiveEditor._findStrength(findings, key);
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 160, child: Text(key, style: const TextStyle(fontSize: 13))),
                      if (!readOnly)
                        SizedBox(
                          width: 72,
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: s.grade.clamp(0, 5),
                            items: [0, 1, 2, 3, 4, 5]
                                .map((g) => DropdownMenuItem(value: g, child: Text('$g')))
                                .toList(),
                            onChanged: (g) =>
                                onUpdate(_merge(key, s.copyWith(grade: g ?? 5))),
                          ),
                        ),
                      if (readOnly) Text('Grade ${s.grade}', style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: CheckboxListTile(
                          title: const Text('Pain', style: TextStyle(fontSize: 12)),
                          value: s.painful,
                          onChanged: readOnly
                              ? null
                              : (v) => onUpdate(_merge(key, s.copyWith(painful: v ?? false))),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
    );
  }
}

class _NeuroSection extends StatelessWidget {
  final List<String> items;
  final List<NeuroFinding> findings;
  final bool readOnly;
  final ValueChanged<List<NeuroFinding>> onUpdate;

  const _NeuroSection({
    required this.items,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  List<NeuroFinding> _merge(String structure, NeuroFinding updated) {
    final byStruct = {for (final n in findings) n.structure: n};
    byStruct[structure] = updated;
    return items
        .map((s) =>
            byStruct[s] ?? NeuroFinding(structure: s, status: 'normal'))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Neuro'),
      initiallyExpanded: false,
      children: items.isEmpty
          ? [const SizedBox(height: 8)]
          : items.map((structure) {
              final n = RegionObjectiveEditor._findNeuro(findings, structure);
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 180,
                          child: Text(structure, style: const TextStyle(fontSize: 13))),
                      if (!readOnly)
                        SizedBox(
                          width: 100,
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: n.status,
                            items: ['normal', 'reduced', 'absent', 'positive']
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                onUpdate(_merge(structure, n.copyWith(status: v ?? 'normal'))),
                          ),
                        ),
                      if (readOnly) Text(n.status, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
    );
  }
}

class _JointMobilitySection extends StatelessWidget {
  final List<String> levels;
  final List<JointMobilityFinding> findings;
  final bool readOnly;
  final ValueChanged<List<JointMobilityFinding>> onUpdate;

  const _JointMobilitySection({
    required this.levels,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  List<JointMobilityFinding> _merge(String level, JointMobilityFinding updated) {
    final byLevel = {for (final j in findings) j.level: j};
    byLevel[level] = updated;
    return levels
        .map((l) =>
            byLevel[l] ?? JointMobilityFinding(level: l, mobility: 'normal'))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Joint mobility'),
      initiallyExpanded: false,
      children: levels.isEmpty
          ? [const SizedBox(height: 8)]
          : levels.map((level) {
              final j = RegionObjectiveEditor._findJointMob(findings, level);
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 120, child: Text(level, style: const TextStyle(fontSize: 13))),
                      if (!readOnly)
                        SizedBox(
                          width: 100,
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: j.mobility,
                            items: ['hypo', 'normal', 'hyper']
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                onUpdate(_merge(level, j.copyWith(mobility: v ?? 'normal'))),
                          ),
                        ),
                      if (readOnly) Text(j.mobility, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
    );
  }
}

class _PalpationSection extends StatelessWidget {
  final List<String> areas;
  final List<PalpationFinding> findings;
  final bool readOnly;
  final ValueChanged<List<PalpationFinding>> onUpdate;

  const _PalpationSection({
    required this.areas,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  List<PalpationFinding> _merge(String location, PalpationFinding updated) {
    final byLoc = {for (final p in findings) p.location: p};
    byLoc[location] = updated;
    return areas
        .map((a) => byLoc[a] ?? PalpationFinding(location: a))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Palpation'),
      initiallyExpanded: false,
      children: areas.isEmpty
          ? [const SizedBox(height: 8)]
          : areas.map((location) {
              final p = RegionObjectiveEditor._findPalpation(findings, location);
              return Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 160,
                          child: Text(location, style: const TextStyle(fontSize: 13))),
                      if (!readOnly)
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            key: ValueKey('palp_${p.location}_${p.quality}'),
                            initialValue: p.quality ?? '',
                            readOnly: false,
                            decoration: const InputDecoration(
                              hintText: 'e.g. tender',
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                onUpdate(_merge(location, p.copyWith(quality: v.isEmpty ? null : v))),
                          ),
                        ),
                      if (readOnly && p.quality != null) Text(p.quality!, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
    );
  }
}

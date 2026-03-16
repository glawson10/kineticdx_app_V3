import '../../../data/repositories/questionnaire_templates_repository.dart';
import '../../../models/questionnaire_flow.dart';

class QuestionnaireTemplateCatalogService {
  QuestionnaireTemplateCatalogService(this._repository);

  final QuestionnaireTemplatesRepository _repository;

  /// Built-in templates (General questionnaire, Specific issue questionnaire). Use for fallback when stream has no data.
  List<QuestionnaireTemplateSummary> get builtInPatientFacingTemplates =>
      _repository
          .builtInPatientFacingTemplates()
          .where((t) => t.active && t.patientFacing)
          .toList(growable: false);

  /// Emits built-in templates immediately so they always appear as options even before
  /// custom templates load or if the clinic collection is empty/inaccessible. Then
  /// merges in clinic-created templates when available.
  Stream<List<QuestionnaireTemplateSummary>> watchPatientFacingTemplates(
    String clinicId,
  ) {
    final builtIns = _repository
        .builtInPatientFacingTemplates()
        .where((t) => t.active && t.patientFacing)
        .toList(growable: false);
    return Stream.value(builtIns).asyncExpand((initial) {
      return _repository.watchClinicCreatedTemplates(clinicId).map((custom) {
        final customFiltered = custom
            .where((t) => t.active && t.patientFacing)
            .where((t) => !initial.any((b) => b.templateId == t.templateId))
            .toList(growable: false);
        final merged = <QuestionnaireTemplateSummary>[...initial, ...customFiltered];
        merged.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        return merged;
      });
    });
  }

  List<QuestionnaireTemplateSummary> sortByConfig(
    List<QuestionnaireTemplateSummary> templates,
    QuestionnaireFlowConfig config,
  ) {
    final selectedIds = config.templates.map((t) => t.templateId).toList(growable: false);
    final rank = <String, int>{
      for (var i = 0; i < selectedIds.length; i++) selectedIds[i]: i,
    };
    final out = List<QuestionnaireTemplateSummary>.from(templates);
    out.sort((a, b) {
      final aRank = rank[a.templateId];
      final bRank = rank[b.templateId];
      if (aRank != null && bRank != null) return aRank.compareTo(bRank);
      if (aRank != null) return -1;
      if (bRank != null) return 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out;
  }

  QuestionnaireFlowConfig configFromSelectedTemplates(
    QuestionnaireFlowConfig current,
    Iterable<QuestionnaireTemplateSummary> templates,
  ) {
    final refs = templates
        .map(
          (t) => QuestionnaireFlowTemplateRef(
            templateId: t.templateId,
            source: t.source,
          ),
        )
        .toList(growable: false);
    return QuestionnaireFlowConfig(enabled: current.enabled, templates: refs);
  }

  QuestionnaireFlowConfig reorderSelectedTemplates(
    QuestionnaireFlowConfig current,
    int oldIndex,
    int newIndex,
  ) {
    final refs = List<QuestionnaireFlowTemplateRef>.from(current.templates);
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= refs.length ||
        newIndex >= refs.length) {
      return current;
    }
    final item = refs.removeAt(oldIndex);
    refs.insert(newIndex, item);
    return QuestionnaireFlowConfig(enabled: current.enabled, templates: refs);
  }

  QuestionnaireFlowConfig toggleTemplate(
    QuestionnaireFlowConfig current,
    QuestionnaireTemplateSummary template,
    bool enabled,
  ) {
    final refs = List<QuestionnaireFlowTemplateRef>.from(current.templates);
    final existingIndex = refs.indexWhere((ref) => ref.templateId == template.templateId);
    if (enabled) {
      if (existingIndex == -1) {
        refs.add(
          QuestionnaireFlowTemplateRef(
            templateId: template.templateId,
            source: template.source,
          ),
        );
      }
    } else if (existingIndex != -1) {
      refs.removeAt(existingIndex);
    }
    return QuestionnaireFlowConfig(enabled: current.enabled, templates: refs);
  }

  /// Returns a new config with the given template's locationIds updated.
  QuestionnaireFlowConfig updateTemplateLocationIds(
    QuestionnaireFlowConfig current,
    String templateId,
    List<String>? locationIds,
  ) {
    final refs = current.templates.map((ref) {
      if (ref.templateId != templateId) return ref;
      return QuestionnaireFlowTemplateRef(
        templateId: ref.templateId,
        source: ref.source,
        locationIds: locationIds,
      );
    }).toList(growable: false);
    return QuestionnaireFlowConfig(enabled: current.enabled, templates: refs);
  }

  bool isSelected(
    QuestionnaireFlowConfig config,
    QuestionnaireTemplateSummary template,
  ) {
    return config.templates.any((ref) => ref.templateId == template.templateId);
  }

  List<QuestionnaireTemplateSummary> selectedTemplates(
    List<QuestionnaireTemplateSummary> allTemplates,
    QuestionnaireFlowConfig config,
  ) {
    final byId = {for (final template in allTemplates) template.templateId: template};
    return config.templates
        .map((ref) => byId[ref.templateId])
        .whereType<QuestionnaireTemplateSummary>()
        .toList(growable: false);
  }
}


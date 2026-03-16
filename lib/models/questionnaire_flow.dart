class QuestionnaireTemplateSource {
  static const String builtIn = 'builtIn';
  static const String custom = 'custom';
}

class QuestionnaireLaunchKind {
  static const String bookingPreassessment = 'bookingPreassessment';
  static const String intakeLink = 'intakeLink';
  static const String route = 'route';
}

class QuestionnaireFlowTemplateRef {
  const QuestionnaireFlowTemplateRef({
    required this.templateId,
    this.source = QuestionnaireTemplateSource.builtIn,
    this.locationIds,
  });

  final String templateId;
  final String source;
  /// When non-null and non-empty, this template is only offered at these location IDs. Empty or null = all locations.
  final List<String>? locationIds;

  factory QuestionnaireFlowTemplateRef.fromJson(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final templateId = (map['templateId'] ?? map['id'] ?? '').toString().trim();
    final source = (map['source'] ?? '').toString().trim();
    final locationIdsRaw = map['locationIds'];
    List<String>? locationIds;
    if (locationIdsRaw is List) {
      final list = locationIdsRaw
          .map((e) => (e?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      locationIds = list.isEmpty ? null : list;
    }
    return QuestionnaireFlowTemplateRef(
      templateId: templateId,
      source: source.isEmpty ? QuestionnaireTemplateSource.builtIn : source,
      locationIds: locationIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'templateId': templateId,
      'source': source,
      if (locationIds != null && locationIds!.isNotEmpty) 'locationIds': locationIds,
    };
  }
}

class QuestionnaireFlowConfig {
  const QuestionnaireFlowConfig({
    this.enabled = false,
    this.templates = const <QuestionnaireFlowTemplateRef>[],
  });

  final bool enabled;
  final List<QuestionnaireFlowTemplateRef> templates;

  factory QuestionnaireFlowConfig.fromJson(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final templatesRaw = map['templates'];
    final templates = templatesRaw is List
        ? templatesRaw
            .map(QuestionnaireFlowTemplateRef.fromJson)
            .where((t) => t.templateId.isNotEmpty)
            .toList(growable: false)
        : const <QuestionnaireFlowTemplateRef>[];
    return QuestionnaireFlowConfig(
      enabled: map['enabled'] == true,
      templates: templates,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'templates': templates.map((t) => t.toJson()).toList(growable: false),
    };
  }
}

class QuestionnaireTemplateSummary {
  const QuestionnaireTemplateSummary({
    required this.templateId,
    required this.source,
    required this.label,
    required this.launchKind,
    this.description,
    this.launchRoute,
    this.active = true,
    this.patientFacing = true,
    this.locationIds,
    this.flowId,
    this.flowVersion,
    this.flowCategory,
    this.flowDefinitionId,
    this.clinicalProfileId,
    this.version,
    this.category,
  });

  final String templateId;
  final String source;
  final String label;
  final String? description;
  final bool active;
  final bool patientFacing;
  final String launchKind;
  final String? launchRoute;
  /// When non-null and non-empty, show this template only when booking at one of these location IDs. Empty or null = all locations.
  final List<String>? locationIds;
  final String? flowId;
  final int? flowVersion;
  final String? flowCategory;
  /// PA-P3: registry id for flow definition. Required for custom templates; built-ins may have default.
  final String? flowDefinitionId;
  /// PA-P3: registry id for clinical profile (summary/decision support). Required for custom templates; built-ins may have default.
  final String? clinicalProfileId;
  /// Optional template version (distinct from flowVersion).
  final int? version;
  /// Optional category for grouping.
  final String? category;

  bool get isBuiltIn => source == QuestionnaireTemplateSource.builtIn;

  factory QuestionnaireTemplateSummary.fromJson(dynamic raw, {String? fallbackTemplateId}) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final templateId =
        (map['templateId'] ?? map['id'] ?? fallbackTemplateId ?? '').toString().trim();
    final source = (map['source'] ?? '').toString().trim();
    final label = (map['label'] ?? map['name'] ?? map['title'] ?? templateId).toString().trim();
    final descriptionRaw = (map['description'] ?? '').toString().trim();
    final launchKind =
        (map['launchKind'] ?? QuestionnaireLaunchKind.intakeLink).toString().trim();
    final launchRouteRaw = (map['launchRoute'] ?? '').toString().trim();
    final locationIdsRaw = map['locationIds'];
    List<String>? locationIds;
    if (locationIdsRaw is List) {
      final list = locationIdsRaw
          .map((e) => (e?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      locationIds = list.isEmpty ? null : list;
    }
    final flowIdRaw = (map['flowId'] ?? '').toString().trim();
    final flowVersionRaw = map['flowVersion'];
    final flowCategoryRaw = (map['flowCategory'] ?? '').toString().trim();
    final flowDefinitionIdRaw = (map['flowDefinitionId'] ?? '').toString().trim();
    final clinicalProfileIdRaw = (map['clinicalProfileId'] ?? '').toString().trim();
    return QuestionnaireTemplateSummary(
      templateId: templateId,
      source: source.isEmpty ? QuestionnaireTemplateSource.custom : source,
      label: label.isEmpty ? templateId : label,
      description: descriptionRaw.isEmpty ? null : descriptionRaw,
      active: map['active'] != false,
      patientFacing: map['patientFacing'] != false,
      launchKind: launchKind.isEmpty ? QuestionnaireLaunchKind.intakeLink : launchKind,
      launchRoute: launchRouteRaw.isEmpty ? null : launchRouteRaw,
      locationIds: locationIds,
      flowId: flowIdRaw.isEmpty ? null : flowIdRaw,
      flowVersion: flowVersionRaw is int ? flowVersionRaw : null,
      flowCategory: flowCategoryRaw.isEmpty ? null : flowCategoryRaw,
      flowDefinitionId: flowDefinitionIdRaw.isEmpty ? null : flowDefinitionIdRaw,
      clinicalProfileId: clinicalProfileIdRaw.isEmpty ? null : clinicalProfileIdRaw,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'templateId': templateId,
      'source': source,
      'label': label,
      if (description != null) 'description': description,
      'active': active,
      'patientFacing': patientFacing,
      'launchKind': launchKind,
      if (launchRoute != null) 'launchRoute': launchRoute,
      if (flowId != null) 'flowId': flowId,
      if (flowVersion != null) 'flowVersion': flowVersion,
      if (flowCategory != null) 'flowCategory': flowCategory,
      if (flowDefinitionId != null) 'flowDefinitionId': flowDefinitionId,
      if (clinicalProfileId != null) 'clinicalProfileId': clinicalProfileId,
      if (version != null) 'version': version,
      if (category != null) 'category': category,
    };
  }
}

class QuestionnaireFlowPublicConfig {
  const QuestionnaireFlowPublicConfig({
    this.enabled = false,
    this.templates = const <QuestionnaireTemplateSummary>[],
  });

  final bool enabled;
  final List<QuestionnaireTemplateSummary> templates;

  factory QuestionnaireFlowPublicConfig.fromJson(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final templatesRaw = map['templates'];
    final templates = templatesRaw is List
        ? templatesRaw
            .map(QuestionnaireTemplateSummary.fromJson)
            .where((t) => t.templateId.isNotEmpty)
            .toList(growable: false)
        : const <QuestionnaireTemplateSummary>[];
    return QuestionnaireFlowPublicConfig(
      enabled: map['enabled'] == true,
      templates: templates,
    );
  }
}


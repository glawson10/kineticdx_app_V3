import 'package:cloud_firestore/cloud_firestore.dart';

class NotesTemplate {
  final String id;
  final String name;
  final String type;
  final bool isDefault;

  const NotesTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.isDefault,
  });

  factory NotesTemplate.fromMap(Map<String, dynamic>? data) {
    final m = data ?? const <String, dynamic>{};
    return NotesTemplate(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      isDefault: m['isDefault'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'isDefault': isDefault,
    };
  }
}

class NotesSettings {
  final int schemaVersion;
  final List<NotesTemplate> templates;
  final DateTime? updatedAt;
  final String? updatedByUid;
  /// Default note kind when creating a new initial note from the patient tab.
  /// 'basicSoap' | 'initialAssessment'
  final String defaultInitialNoteKind;

  const NotesSettings({
    required this.schemaVersion,
    required this.templates,
    required this.updatedAt,
    required this.updatedByUid,
    required this.defaultInitialNoteKind,
  });

  static const NotesTemplate defaultTemplate = NotesTemplate(
    id: 'basicSoap',
    name: 'Basic SOAP',
    type: 'soap',
    isDefault: true,
  );

  static List<NotesTemplate> defaultTemplates() {
    return const [defaultTemplate];
  }

  factory NotesSettings.fallback() {
    return NotesSettings(
      schemaVersion: 1,
      templates: defaultTemplates(),
      updatedAt: null,
      updatedByUid: null,
      defaultInitialNoteKind: 'basicSoap',
    );
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  factory NotesSettings.fromMap(Map<String, dynamic>? data) {
    final m = data ?? const <String, dynamic>{};
    final templatesRaw = m['templates'];
    final templates = <NotesTemplate>[];
    if (templatesRaw is List) {
      for (final t in templatesRaw) {
        if (t is Map) {
          templates.add(NotesTemplate.fromMap(Map<String, dynamic>.from(t)));
        }
      }
    }

    return NotesSettings(
      schemaVersion: (m['schemaVersion'] as num?)?.toInt() ?? 1,
      templates: templates.isEmpty ? defaultTemplates() : templates,
      updatedAt: _toDate(m['updatedAt']),
      updatedByUid: (m['updatedByUid'] ?? '').toString().trim().isEmpty
          ? null
          : m['updatedByUid'].toString(),
      defaultInitialNoteKind:
          (m['defaultInitialNoteKind'] ?? 'basicSoap').toString(),
    );
  }

  NotesTemplate pickDefaultTemplate() {
    for (final t in templates) {
      if (t.isDefault) return t;
    }
    return templates.isNotEmpty ? templates.first : defaultTemplate;
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'templates': templates.map((t) => t.toMap()).toList(),
      'updatedAt': updatedAt,
      'updatedByUid': updatedByUid,
      'defaultInitialNoteKind': defaultInitialNoteKind,
    };
  }
}

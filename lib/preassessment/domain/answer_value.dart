// lib/preassessment/domain/answer_value.dart
//
// Canonical typed answer value for Phase 3 (Preassessment).
// Stored as a discriminated union: { t: <type>, v: <value> }
//
// This file MUST stay in sync with backend expectations.
// Do not change meanings or types without bumping flowVersion.

import 'package:flutter/foundation.dart';

@immutable
class AnswerValue {
  final String t; // type discriminator
  final dynamic v; // value (validated by factory constructors)

  const AnswerValue._(this.t, this.v);

  // ---------------------------------------------------------------------------
  // Factory constructors (canonical)
  // ---------------------------------------------------------------------------

  factory AnswerValue.bool(bool value) => AnswerValue._('bool', value);

  factory AnswerValue.int(int value) => AnswerValue._('int', value);

  factory AnswerValue.num(double value) => AnswerValue._('num', value);

  factory AnswerValue.text(String value) => AnswerValue._('text', value.trim());

  /// Single choice optionId (stable string, not label)
  factory AnswerValue.single(String optionId) =>
      AnswerValue._('single', optionId);

  /// Multiple choice optionIds (stable strings)
  ///
  /// IMPORTANT:
  /// We defensively coerce any incoming list-ish values to strings to prevent
  /// runtime type errors in Flutter Web (JSArray of dynamic) and during JSON
  /// round-trips where List<dynamic> can appear.
  factory AnswerValue.multi(List<String> optionIds) {
    // Ensure stable type + immutability.
    final coerced = optionIds.map((e) => e.toString()).toList(growable: false);
    return AnswerValue._('multi', List<String>.unmodifiable(coerced));
  }

  /// Date stored as yyyy-mm-dd (metadata only; not for queries)
  factory AnswerValue.date(String isoDate) => AnswerValue._('date', isoDate);

  /// Escape hatch — use sparingly and document usage
  factory AnswerValue.map(Map<String, dynamic> value) =>
      AnswerValue._('map', Map<String, dynamic>.unmodifiable(value));

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() => {'t': t, 'v': v};

  static AnswerValue fromMap(Map<String, dynamic> map) {
    final type = map['t'];
    final value = map['v'];

    if (type is! String) {
      throw StateError('AnswerValue.t must be a string');
    }

    switch (type) {
      case 'bool':
        if (value is bool) return AnswerValue.bool(value);
        break;

      case 'int':
        if (value is int) return AnswerValue.int(value);
        // tolerate num coming back as double for older/looser writers
        if (value is num) return AnswerValue.int(value.toInt());
        break;

      case 'num':
        if (value is num) return AnswerValue.num(value.toDouble());
        break;

      case 'text':
        if (value is String) return AnswerValue.text(value);
        break;

      case 'single':
        if (value is String) return AnswerValue.single(value);
        break;

      case 'multi':
        if (value is List) {
          // Keep only strings; coerce non-strings to strings to avoid crashes.
          final list = value.map((e) => e.toString()).toList(growable: false);
          return AnswerValue._('multi', List<String>.unmodifiable(list));
        }
        break;

      case 'date':
        if (value is String) return AnswerValue.date(value);
        break;

      case 'map':
        if (value is Map) {
          // Firestore/JSON may return Map of dynamic,dynamic
          final casted = Map<String, dynamic>.from(value);
          return AnswerValue.map(casted);
        }
        break;
    }

    throw StateError('Invalid AnswerValue payload: $map');
  }

  // ---------------------------------------------------------------------------
  // Typed accessors (safe reads)
  // ---------------------------------------------------------------------------

  bool? get asBool => t == 'bool' && v is bool ? v as bool : null;

  int? get asInt {
    if (t != 'int') return null;
    if (v is int) return v as int;
    if (v is num) return (v as num).toInt();
    return null;
  }

  double? get asNum {
    if (t != 'num') return null;
    if (v is double) return v as double;
    if (v is num) return (v as num).toDouble();
    return null;
  }

  String? get asText => t == 'text' && v is String ? v as String : null;

  String? get asSingle => t == 'single' && v is String ? v as String : null;

  /// This is the critical fix for your red-screen crash:
  /// Flutter Web can surface multi values as JSArray of dynamic (List of dynamic).
  /// We safely coerce to List<String> instead of doing `v as List<String>`.
  List<String>? get asMulti {
    if (t != 'multi') return null;

    final raw = v;

    if (raw is List<String>) return raw;

    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }

    return null;
  }

  String? get asDate => t == 'date' && v is String ? v as String : null;

  Map<String, dynamic>? get asMap {
    if (t != 'map') return null;
    final raw = v;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Debug helpers
  // ---------------------------------------------------------------------------

  @override
  String toString() => 'AnswerValue(t: $t, v: $v)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnswerValue &&
          runtimeType == other.runtimeType &&
          t == other.t &&
          v == other.v;

  @override
  int get hashCode => Object.hash(t, v);
}

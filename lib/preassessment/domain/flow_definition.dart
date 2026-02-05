// lib/features/domain/flow_definition.dart
//
// Canonical Phase 3 (Preassessment) flow definition contract.
// Client-side equivalent of backend "assessmentPack".
//
// RULES (DO NOT BREAK):
// - questionId meaning NEVER changes once released
// - breaking changes require bumping flowVersion
// - option IDs are stable identifiers (labels are UI-only)
// - NO diagnoses, NO clinical reasoning here

import 'package:flutter/foundation.dart';

import 'answer_value.dart';

/// ---------------------------------------------------------------------------
/// Question value typing
/// ---------------------------------------------------------------------------

enum QuestionValueType {
  boolType,
  intType,
  numType,
  textType,
  singleChoice,
  multiChoice,
  dateType,
  mapType;

  /// Maps to AnswerValue.t
  String toAnswerTag() {
    switch (this) {
      case QuestionValueType.boolType:
        return 'bool';
      case QuestionValueType.intType:
        return 'int';
      case QuestionValueType.numType:
        return 'num';
      case QuestionValueType.textType:
        return 'text';
      case QuestionValueType.singleChoice:
        return 'single';
      case QuestionValueType.multiChoice:
        return 'multi';
      case QuestionValueType.dateType:
        return 'date';
      case QuestionValueType.mapType:
        return 'map';
    }
  }
}

/// ---------------------------------------------------------------------------
/// Option definitions
/// ---------------------------------------------------------------------------

@immutable
class OptionDef {
  /// Stable stored identifier (e.g. "onset.sudden")
  final String id;

  /// Localisation key only (never stored)
  final String labelKey;

  const OptionDef({
    required this.id,
    required this.labelKey,
  });
}

/// ---------------------------------------------------------------------------
/// Constraints
/// ---------------------------------------------------------------------------

@immutable
class NumericConstraints {
  final double? min;
  final double? max;
  final double? step;

  const NumericConstraints({
    this.min,
    this.max,
    this.step,
  });
}

@immutable
class TextConstraints {
  final int? minLength;
  final int? maxLength;

  const TextConstraints({
    this.minLength,
    this.maxLength,
  });
}

/// ---------------------------------------------------------------------------
/// Question definition
/// ---------------------------------------------------------------------------

@immutable
class QuestionDef {
  /// Canonical identifier (e.g. "ankle.pain.now")
  final String questionId;

  /// Expected answer type
  final QuestionValueType valueType;

  /// Localisation key for prompt text
  final String promptKey;

  /// Required for submission
  final bool required;

  /// Choice options (single / multi)
  final List<OptionDef> options;

  /// Numeric constraints (int / num)
  final NumericConstraints? numeric;

  /// Text constraints
  final TextConstraints? text;

  /// Indicates triage relevance (metadata only)
  final bool contributesToTriage;

  /// Optional grouping for clinician display
  final String? domain;

  const QuestionDef({
    required this.questionId,
    required this.valueType,
    required this.promptKey,
    this.required = false,
    this.options = const <OptionDef>[],
    this.numeric,
    this.text,
    this.contributesToTriage = false,
    this.domain,
  });

  /// Validate an answer against this definition.
  /// Returns null if valid, otherwise an error code.
  String? validate(AnswerValue? answer) {
    if (answer == null) {
      return required ? 'required' : null;
    }

    if (answer.t != valueType.toAnswerTag()) {
      return 'type_mismatch';
    }

    switch (valueType) {
      case QuestionValueType.boolType:
        return answer.asBool == null ? 'invalid_bool' : null;

      case QuestionValueType.intType:
        final v = answer.asInt;
        if (v == null) return 'invalid_int';
        if (numeric?.min != null && v < numeric!.min!) return 'below_min';
        if (numeric?.max != null && v > numeric!.max!) return 'above_max';
        return null;

      case QuestionValueType.numType:
        final v = answer.asNum;
        if (v == null) return 'invalid_num';
        if (numeric?.min != null && v < numeric!.min!) return 'below_min';
        if (numeric?.max != null && v > numeric!.max!) return 'above_max';
        return null;

      case QuestionValueType.textType:
        final v = answer.asText;
        if (v == null) return 'invalid_text';
        if (text?.minLength != null && v.length < text!.minLength!) return 'too_short';
        if (text?.maxLength != null && v.length > text!.maxLength!) return 'too_long';
        return null;

      case QuestionValueType.singleChoice:
        final v = answer.asSingle;
        if (v == null) return 'invalid_single';
        if (options.isNotEmpty && !options.any((o) => o.id == v)) {
          return 'invalid_option';
        }
        return null;

      case QuestionValueType.multiChoice:
        final v = answer.asMulti;
        if (v == null) return 'invalid_multi';
        if (options.isNotEmpty) {
          final allowed = options.map((o) => o.id).toSet();
          if (v.any((e) => !allowed.contains(e))) return 'invalid_option';
        }
        return null;

      case QuestionValueType.dateType:
        final v = answer.asDate;
        if (v == null) return 'invalid_date';
        final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        return re.hasMatch(v) ? null : 'invalid_date_format';

      case QuestionValueType.mapType:
        return answer.asMap == null ? 'invalid_map' : null;
    }
  }
}

/// ---------------------------------------------------------------------------
/// Flow definition (assessmentPack)
/// ---------------------------------------------------------------------------

@immutable
class FlowDefinition {
  /// Region identifier (ankle, knee, lumbar, etc.)
  final String flowId;

  /// Version of this flow (bump for breaking changes)
  final int flowVersion;

  /// Localisation key for title
  final String titleKey;

  /// Optional description localisation key
  final String? descriptionKey;

  /// All questions in canonical order
  final List<QuestionDef> questions;

  /// Whitelist for clinician summaries
  final List<String> keyAnswerIds;

  const FlowDefinition({
    required this.flowId,
    required this.flowVersion,
    required this.titleKey,
    this.descriptionKey,
    required this.questions,
    this.keyAnswerIds = const <String>[],
  });

  /// Map for fast lookup
  Map<String, QuestionDef> get byId =>
      {for (final q in questions) q.questionId: q};

  /// Validate all answers for submission
  List<FlowValidationError> validateAnswers(
    Map<String, AnswerValue> answers,
  ) {
    final errors = <FlowValidationError>[];
    for (final q in questions) {
      final err = q.validate(answers[q.questionId]);
      if (err != null) {
        errors.add(
          FlowValidationError(
            questionId: q.questionId,
            errorCode: err,
          ),
        );
      }
    }
    return errors;
  }

  /// Extract clinician summary answers
  Map<String, AnswerValue> extractKeyAnswers(
    Map<String, AnswerValue> answers,
  ) {
    final out = <String, AnswerValue>{};
    for (final id in keyAnswerIds) {
      final v = answers[id];
      if (v != null) out[id] = v;
    }
    return out;
  }

  /// Debug guard — run when registering flows
  void assertKeyAnswersValid() {
    assert(() {
      final ids = byId.keys.toSet();
      for (final id in keyAnswerIds) {
        if (!ids.contains(id)) {
          throw StateError(
            'FlowDefinition($flowId v$flowVersion) keyAnswerId not found: $id',
          );
        }
      }
      return true;
    }());
  }
}

/// ---------------------------------------------------------------------------
/// Validation error
/// ---------------------------------------------------------------------------

@immutable
class FlowValidationError {
  final String questionId;
  final String errorCode;

  const FlowValidationError({
    required this.questionId,
    required this.errorCode,
  });

  @override
  String toString() =>
      'FlowValidationError(questionId: $questionId, errorCode: $errorCode)';
}

// lib/features/notes/data/soap_note_pdf_generator.dart
//
// PDF generator for SOAP notes that mirrors the structured UI hierarchy.
// Professional clinical layout with clear visual hierarchy for Assessment and Plan.

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets' as pw;
import '../../../models/soap_note.dart';

class SoapNotePdfGenerator {
  /// Generate a professional PDF from a SOAP note
  static Future<Uint8List> generate(SoapNote note, {String? patientName, String? clinicianName}) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildHeader(note, patientName, clinicianName),
          pw.SizedBox(height: 20),
          _buildSubjectiveSection(note.subjective),
          pw.SizedBox(height: 16),
          _buildObjectiveSection(note.objective, note.clinicalTests),
          pw.SizedBox(height: 16),
          _buildAssessmentSection(note.analysis),
          pw.SizedBox(height: 16),
          _buildPlanSection(note.plan, note.subjective.patientGoals),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(SoapNote note, String? patientName, String? clinicianName) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'SOAP Note',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                _formatDate(note.createdAt),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          if (patientName != null) ...[
            pw.Text('Patient: $patientName', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 2),
          ],
          if (clinicianName != null) ...[
            pw.Text('Clinician: $clinicianName', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 2),
          ],
          pw.Text('Region: ${_formatRegion(note.bodyRegion)}', style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static pw.Widget _buildSubjectiveSection(SubjectiveSection subj) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('SUBJECTIVE'),
        pw.SizedBox(height: 8),
        if (subj.presentingComplaint.isNotEmpty) ...[
          _buildSubsectionTitle('Presenting Complaint'),
          _buildBodyText(subj.presentingComplaint),
          pw.SizedBox(height: 8),
        ],
        if (subj.mechanismOfInjury?.isNotEmpty == true) ...[
          _buildSubsectionTitle('Onset & Mechanism'),
          _buildBodyText(subj.mechanismOfInjury!),
          pw.SizedBox(height: 8),
        ],
        // Pain levels
        pw.Row(
          children: [
            _buildLabelValue('Pain Now', '${subj.painCurrent ?? 0}/10'),
            pw.SizedBox(width: 20),
            _buildLabelValue('Best', '${subj.painBest ?? 0}/10'),
            pw.SizedBox(width: 20),
            _buildLabelValue('Worst', '${subj.painWorst ?? 0}/10'),
            pw.SizedBox(width: 20),
            _buildLabelValue('Irritability', _formatIrritability(subj.irritability)),
          ],
        ),
        pw.SizedBox(height: 8),
        if (subj.aggravatingFactors.isNotEmpty) ...[
          _buildSubsectionTitle('Aggravating Factors'),
          ...subj.aggravatingFactors.map((f) => _buildBullet(f.label)),
          pw.SizedBox(height: 8),
        ],
        if (subj.easingFactors.isNotEmpty) ...[
          _buildSubsectionTitle('Easing Factors'),
          ...subj.easingFactors.map((f) => _buildBullet(f.label)),
          pw.SizedBox(height: 8),
        ],
        if (subj.pattern24h?.isNotEmpty == true) ...[
          _buildSubsectionTitle('24-Hour Pattern'),
          _buildBodyText(subj.pattern24h!),
          pw.SizedBox(height: 8),
        ],
        if (subj.pastHistory?.isNotEmpty == true) ...[
          _buildSubsectionTitle('Past History'),
          _buildBodyText(subj.pastHistory!),
          pw.SizedBox(height: 8),
        ],
        if (subj.medications?.isNotEmpty == true) ...[
          _buildSubsectionTitle('Medications'),
          _buildBodyText(subj.medications!),
          pw.SizedBox(height: 8),
        ],
        if (subj.socialHistory?.isNotEmpty == true) ...[
          _buildSubsectionTitle('Social / Work / Sport'),
          _buildBodyText(subj.socialHistory!),
        ],
      ],
    );
  }

  static pw.Widget _buildObjectiveSection(ObjectiveSection obj, List<ClinicalTestEntry> tests) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('OBJECTIVE'),
        pw.SizedBox(height: 8),
        if (obj.globalNotes?.isNotEmpty == true) ...[
          _buildSubsectionTitle('Global Findings'),
          _buildBodyText(obj.globalNotes!),
          pw.SizedBox(height: 8),
        ],
        if (obj.regions.isNotEmpty) ...[
          _buildSubsectionTitle('Regional Examination'),
          ...obj.regions.map((r) => _buildRegionFindings(r)),
        ],
        if (tests.isNotEmpty) ...[
          _buildSubsectionTitle('Clinical Tests'),
          ...tests.map((t) => _buildClinicalTestEntry(t)),
        ],
      ],
    );
  }

  static pw.Widget _buildAssessmentSection(AnalysisSection analysis) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('ASSESSMENT'),
        pw.SizedBox(height: 8),
        
        // Clinical Impression card
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue200),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Text('🧠', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    'Clinical Impression',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              if (analysis.primaryDiagnosis.isNotEmpty) ...[
                pw.Text(
                  'Primary Diagnosis',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  analysis.primaryDiagnosis,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
              ],
              if (analysis.reasoningSummary?.isNotEmpty == true) ...[
                pw.Text(
                  'Assessment Summary',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 2),
                _buildBodyText(analysis.reasoningSummary!),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // Contributing Factors
        if (analysis.contributingFactorsText?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('🔍', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Contributing Factors',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: analysis.contributingFactorsText!
                      .split('\n')
                      .where((s) => s.trim().isNotEmpty)
                      .map((factor) => pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.blue50,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                              border: pw.Border.all(color: PdfColors.blue200),
                            ),
                            child: pw.Text(
                              factor.trim(),
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Key Impairments
        if (analysis.keyImpairments.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('⚠️', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Key Impairments',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                ...analysis.keyImpairments.map((imp) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
                          pw.Expanded(
                            child: pw.Text(imp, style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Differential Diagnoses (if any)
        if (analysis.secondaryDiagnoses.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('📋', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Differential Diagnoses',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                ...analysis.secondaryDiagnoses.map((diag) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('• $diag', style: const pw.TextStyle(fontSize: 10)),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildPlanSection(PlanSection plan, List<GoalItem> goals) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('PLAN'),
        pw.SizedBox(height: 8),

        // Shared Goals
        if (goals.isNotEmpty) ...[
          _buildSubsectionTitle('Shared Goals'),
          pw.SizedBox(height: 6),
          ...goals.asMap().entries.map((entry) {
            final idx = entry.key;
            final goal = entry.value;
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 24,
                    height: 24,
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue500,
                      shape: pw.BoxShape.circle,
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        '${idx + 1}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(goal.description, style: const pw.TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 12),
        ],

        // Treatment Today
        if (plan.treatmentToday?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('🩺', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Treatment Today',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                _buildBodyText(plan.treatmentToday!),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Home Programme
        if (plan.homeExercise?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('🏠', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Home Programme',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                _buildBodyText(plan.homeExercise!),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Education & Advice
        if (plan.educationAdvice?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('🎓', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Education & Advice',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                _buildBodyText(plan.educationAdvice!),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Time-based Planning
        _buildSubsectionTitle('Time-based Plan'),
        pw.SizedBox(height: 6),
        
        if (plan.planShortTermSummary?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Text(
                    '1–2 weeks',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Short-term',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                _buildBodyText(plan.planShortTermSummary!),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
        ],

        if (plan.planMediumTermSummary?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.purple100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Text(
                    '4–8 weeks',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Medium-term',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                _buildBodyText(plan.planMediumTermSummary!),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
        ],

        // Follow-up Plan
        if (plan.followUpPlan?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('📅', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Follow-up Plan',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                _buildBodyText(plan.followUpPlan!),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Contingency Plan
        if (plan.contingencyPlan?.isNotEmpty == true) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('🔀', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Contingency Plan',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                _buildBodyText(plan.contingencyPlan!),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Helper widgets
  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey800,
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _buildSubsectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey800,
      ),
    );
  }

  static pw.Widget _buildBodyText(String text) {
    return pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10),
    );
  }

  static pw.Widget _buildBullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );
  }

  static pw.Widget _buildLabelValue(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  static pw.Widget _buildRegionFindings(RegionObjective region) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${_formatRegion(region.region)} ${region.side != BodySide.central ? "(${region.side.name})" : ""}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          if (region.summary?.isNotEmpty == true) ...[
            pw.SizedBox(height: 4),
            _buildBodyText(region.summary!),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildClinicalTestEntry(ClinicalTestEntry test) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(
              '${test.displayName}: ${_formatTestResult(test.result)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  // Formatters
  static String _formatDate(DateTime? date) {
    if (date == null) return '--';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _formatRegion(BodyRegion region) {
    final name = region.name;
    return name[0].toUpperCase() + name.substring(1);
  }

  static String _formatIrritability(TernaryLevel level) {
    return level.name[0].toUpperCase() + level.name.substring(1);
  }

  static String _formatTestResult(ClinicalTestResult result) {
    switch (result) {
      case ClinicalTestResult.positive:
        return 'Positive';
      case ClinicalTestResult.negative:
        return 'Negative';
      case ClinicalTestResult.notTested:
        return 'Not tested';
    }
  }
}

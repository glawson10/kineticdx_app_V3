# SOAP Note PDF Structure

This document describes the professional PDF layout that mirrors the structured Assessment and Plan UI hierarchy.

## Overview

The PDF generator (`SoapNotePdfGenerator`) produces clinically professional, medico-legally clear documentation that matches the new UI structure.

---

## PDF Layout Structure

### **Header Section**
- Document title: "SOAP Note"
- Creation date
- Patient name (when available)
- Clinician name
- Body region
- Blue header background for visual prominence

---

### **SUBJECTIVE Section**

**Standard Fields:**
- Presenting Complaint
- Onset & Mechanism
- Pain levels (Now/Best/Worst) + Irritability
- Aggravating Factors (bulleted)
- Easing Factors (bulleted)
- 24-Hour Pattern
- Past History
- Medications
- Social / Work / Sport

---

### **OBJECTIVE Section**

**Structure:**
- Global Findings (general observations)
- Regional Examination (organized by body region)
- Clinical Tests (structured list with results)

---

### **ASSESSMENT Section** ✨ (New Professional Structure)

#### 🧠 Clinical Impression (Blue-bordered card)
- **Primary Diagnosis** (bold, prominent)
- **Assessment Summary** (clinical reasoning narrative)

#### 🔍 Contributing Factors (Card with chips)
- Each factor displayed as a rounded chip/tag
- Visual: blue background chips with borders
- Quick scanning for biopsychosocial factors

#### ⚠️ Key Impairments (Card with bullets)
- Bullet-point list format
- Professional readability
- Medico-legal clarity

#### 📋 Differential Diagnoses (Optional card)
- Only shown if documented
- Lists alternative diagnoses considered
- IFOMT-level detail when needed

**Visual Design:**
- Section cards with subtle borders
- Icon-based headers for quick identification
- Hierarchical text styling

---

### **PLAN Section** ✨ (New Action-Map Structure)

#### Shared Goals (Numbered cards)
- Each goal in a separate card
- Numbered circles (1, 2, 3) in blue
- Clear visual hierarchy
- Goal timeframes included when specified

#### 🩺 Treatment Today (Highlighted section)
- Blue-tinted background (medico-legally important)
- Darker border for emphasis
- Documents what was actually done
- Response to treatment included

#### 🏠 Home Programme
- Structured exercise prescription
- Format: Exercise → Dosage → Cues
- Future-proofed for exercise app integration

#### 🎓 Education & Advice
- Safety netting and red flag discussion
- Patient expectations
- Load management advice

#### Time-based Plan

**Short-term (1–2 weeks)**
- Badge: "1–2 weeks" with blue background
- Focus: Settle symptoms, establish tolerance

**Medium-term (4–8 weeks)**
- Badge: "4–8 weeks" with purple background
- Focus: Strengthen, return to function/sport

#### 📅 Follow-up Plan
- Review schedule
- Discharge planning

#### 🔀 Contingency Plan
- "If progress is not as expected..."
- Alternative approaches
- Referral considerations

---

## Visual Design Principles

### Color Scheme
- **Primary sections**: Grey800 headers with white text
- **Clinical Impression**: Blue borders (PdfColors.blue200)
- **Treatment Today**: Blue-tinted background (highlighted importance)
- **Time badges**: Blue (short-term), Purple (medium-term)
- **Contributing factors**: Blue50 chip backgrounds

### Typography
- **Section headers**: 14pt, bold, white on grey800
- **Subsection titles**: 11pt, bold, grey800
- **Body text**: 10pt, regular
- **Labels**: 8-9pt, bold

### Layout
- A4 page format
- 40pt margins
- Cards with rounded corners (4pt radius)
- Consistent 8-12pt spacing between elements
- Bullet points with proper indentation

### Hierarchy
1. Section headers (SUBJECTIVE, OBJECTIVE, etc.)
2. Subsection cards with borders
3. Icon + title rows
4. Content within cards
5. Detailed text and bullets

---

## Professional Features

### Medico-Legal Clarity
✓ Treatment Today section is visually highlighted  
✓ Key impairments clearly bulleted  
✓ Differential diagnoses documented  
✓ Contingency planning shown  
✓ Professional card-based layout  

### Scanability
✓ Clear section headers  
✓ Icon-based subsection identification  
✓ Visual cards group related information  
✓ Contributing factors as chips (not dense text)  
✓ Numbered goals with visual prominence  

### Clinical Reasoning
✓ Assessment flows from impression → factors → impairments → differentials  
✓ Plan flows from goals → treatment today → home programme → time-based → contingency  
✓ Mirrors clinical thinking process  
✓ IFOMT-appropriate structure  

---

## Usage

### From UI
1. Open SOAP note editor
2. Click print icon in app bar
3. PDF preview appears with print/share options
4. Native platform printing/sharing

### Programmatic
```dart
import 'package:printing/printing.dart';
import '../data/soap_note_pdf_generator.dart';

final pdfBytes = await SoapNotePdfGenerator.generate(
  soapNote,
  patientName: 'Patient Name',
  clinicianName: 'Clinician Name',
);

await Printing.layoutPdf(
  onLayout: (_) => Future.value(pdfBytes),
);
```

---

## Technical Details

### Dependencies
- `pdf: ^3.11.1` - PDF document generation
- `printing: ^5.13.2` - Print preview and sharing

### File Location
- Generator: `/lib/features/notes/data/soap_note_pdf_generator.dart`
- Integration: `/lib/features/notes/ui/soap_note_edit_screen.dart`

### Data Source
- Uses `SoapNote` model from `/lib/models/soap_note.dart`
- All section data (AnalysisSection, PlanSection, etc.)
- Clinical test entries
- Patient goals

---

## Future Enhancements

Potential improvements:
- [ ] Patient name integration from patient document
- [ ] Clinic branding/logo in header
- [ ] QR code for digital verification
- [ ] Exercise images in home programme
- [ ] Outcome measure charts
- [ ] Body chart diagram integration
- [ ] Digital signature field
- [ ] Export to specific formats (PDF/A for archival)

---

## Validation

The PDF structure has been designed to:
1. ✅ Mirror the new UI hierarchy exactly
2. ✅ Maintain professional clinical appearance
3. ✅ Ensure medico-legal clarity
4. ✅ Optimize for printing and scanning
5. ✅ Support IFOMT-level documentation
6. ✅ Read clearly in both digital and printed formats

// lib/models/clinical_test_registry.dart
//
// Backwards-compat shim.
// The *real* registry + model live in `clinical_tests.dart`.
// This file simply re-exports them so any existing imports of
// `clinical_test_registry.dart` keep working.

export 'clinical_tests.dart'
    show
        BodyRegion,
        TestCategory,
        EvidenceLevel,
        ClinicalTestDefinition,
        ClinicalTestRegistry;

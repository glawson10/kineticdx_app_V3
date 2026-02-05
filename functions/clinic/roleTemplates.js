"use strict";
// functions/src/clinic/roleTemplates.ts
// Single source of truth for role permission templates.
// Align these keys with Firestore rules + Cloud Functions authz checks.
Object.defineProperty(exports, "__esModule", { value: true });
exports.ownerRolePermissions = ownerRolePermissions;
exports.managerRolePermissions = managerRolePermissions;
exports.clinicianRolePermissions = clinicianRolePermissions;
exports.adminStaffRolePermissions = adminStaffRolePermissions;
exports.viewerRolePermissions = viewerRolePermissions;
function normalize(p) {
    const out = {};
    for (const k of Object.keys(p))
        out[k] = p[k] === true;
    return out;
}
/**
 * Notes on key contracts:
 * - Scheduling writes require: "schedule.write"
 * - Scheduling reads require: "schedule.read"
 * - Patient reads require: "patients.read"
 * - Patient writes require: "patients.write" BUT:
 *   - patients are function-authoritative (no client writes to /patients via rules)
 *   - this flag gates Cloud Functions that create/update patient records
 *
 * - Templates/packs editing (questionnaire templates, note templates, packs):
 *   "templates.manage" (function-authoritative writes recommended)
 */
// Owner: full access inside clinic boundary
function ownerRolePermissions() {
    return normalize({
        "settings.read": true,
        "settings.write": true,
        "members.read": true,
        "members.manage": true,
        "roles.manage": true,
        "schedule.read": true,
        "schedule.write": true,
        "patients.read": true,
        "patients.write": true,
        "clinical.read": true,
        "clinical.write": true,
        "notes.read": true,
        "notes.write.own": true,
        "notes.write.any": true,
        "services.manage": true,
        "resources.manage": true,
        // registries (tests/outcome measures/region presets/packs)
        "registries.manage": true,
        // templates / packs / questionnaires (if you enforce it in helpers/authz)
        "templates.manage": true,
        "audit.read": true,
    });
}
// Manager: can manage staff + override notes
function managerRolePermissions() {
    return normalize({
        "settings.read": true,
        "settings.write": true,
        "members.read": true,
        "members.manage": true,
        "roles.manage": false,
        "schedule.read": true,
        "schedule.write": true,
        "patients.read": true,
        "patients.write": true,
        "clinical.read": true,
        "clinical.write": true,
        "notes.read": true,
        "notes.write.own": true,
        "notes.write.any": true,
        "services.manage": true,
        "resources.manage": true,
        "registries.manage": true,
        // templates / packs / questionnaires
        "templates.manage": true,
        "audit.read": true,
    });
}
// Clinician: can write clinical + amend own notes only
function clinicianRolePermissions() {
    return normalize({
        "settings.read": true,
        "members.read": false,
        "members.manage": false,
        "roles.manage": false,
        "schedule.read": true,
        "schedule.write": true,
        "patients.read": true,
        "patients.write": true,
        "clinical.read": true,
        "clinical.write": true,
        "notes.read": true,
        "notes.write.own": true,
        "notes.write.any": false,
        "services.manage": false,
        "resources.manage": false,
        "registries.manage": true,
        // clinicians should not edit templates by default
        "templates.manage": false,
        "audit.read": false,
    });
}
// Admin/Reception: no clinical content
function adminStaffRolePermissions() {
    return normalize({
        "settings.read": true,
        "members.read": true,
        "members.manage": false,
        "schedule.read": true,
        "schedule.write": true,
        "patients.read": true,
        "patients.write": true,
        "clinical.read": false,
        "clinical.write": false,
        "notes.read": false,
        "notes.write.own": false,
        "notes.write.any": false,
        "services.manage": false,
        "resources.manage": false,
        "registries.manage": true,
        // admin staff should not edit templates by default
        "templates.manage": false,
        "audit.read": false,
    });
}
// Viewer: read-only (no scheduling writes, no patient writes, no clinical writes)
function viewerRolePermissions() {
    return normalize({
        "settings.read": true,
        "settings.write": false,
        "members.read": false,
        "members.manage": false,
        "roles.manage": false,
        "schedule.read": true,
        "schedule.write": false,
        "patients.read": true,
        "patients.write": false,
        "clinical.read": true,
        "clinical.write": false,
        "notes.read": true,
        "notes.write.own": false,
        "notes.write.any": false,
        "services.manage": false,
        "resources.manage": false,
        "registries.manage": false,
        "templates.manage": false,
        "audit.read": false,
    });
}
//# sourceMappingURL=roleTemplates.js.map
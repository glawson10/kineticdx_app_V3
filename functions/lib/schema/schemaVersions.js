"use strict";
/**
 * Canonical schema version index.
 * Breaking changes must bump versions here and document migration.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SCHEMA_VERSIONS = void 0;
exports.schemaVersion = schemaVersion;
exports.SCHEMA_VERSIONS = {
    clinic: 1,
    member: 1,
    role: 1,
    invite: 1,
    appointment: 1,
    patient: 1,
    episode: 1,
    note: 1,
    noteAmendment: 1,
    assessmentPack: 1,
    assessment: 1,
    closure: 1,
    intakeSession: 1,
    auditEvent: 1,
    registries: 1,
};
/**
 * Helper to safely fetch schema versions.
 * Throws early if an invalid key is used.
 */
function schemaVersion(key) {
    return exports.SCHEMA_VERSIONS[key];
}
//# sourceMappingURL=schemaVersions.js.map
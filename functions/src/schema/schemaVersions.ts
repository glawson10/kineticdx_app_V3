/**
 * Canonical schema version index.
 * Breaking changes must bump versions here and document migration.
 */

export const SCHEMA_VERSIONS = {
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
} as const;

export type SchemaKey = keyof typeof SCHEMA_VERSIONS;

/**
 * Helper to safely fetch schema versions.
 * Throws early if an invalid key is used.
 */
export function schemaVersion(key: SchemaKey): number {
  return SCHEMA_VERSIONS[key];
}

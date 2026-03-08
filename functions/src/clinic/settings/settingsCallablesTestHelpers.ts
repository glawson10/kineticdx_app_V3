/**
 * Shared test helpers for settings callable tests.
 */

export function expectAuditChangedKeysOnly(
  changes: Record<string, unknown>,
  expectedKeys: string[],
  opts: { isUpdate?: boolean } = {}
): void {
  if (!changes || typeof changes !== "object") {
    throw new Error("Expected changes to be an object.");
  }
  const actualKeys = Object.keys(changes);
  for (const key of expectedKeys) {
    if (!actualKeys.includes(key)) {
      throw new Error(`Expected audit changes to include key "${key}".`);
    }
  }
  for (const key of actualKeys) {
    if (!expectedKeys.includes(key)) {
      throw new Error(
        `Unexpected key "${key}" in audit changes. Expected only: ${expectedKeys.join(", ")}`
      );
    }
  }
  if (opts.isUpdate) {
    for (const key of expectedKeys) {
      const val = changes[key];
      if (val && typeof val === "object" && "before" in val && "after" in val) {
        continue;
      }
    }
  }
}

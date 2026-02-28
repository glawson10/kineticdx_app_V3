/**
 * Canonical JSON and SHA-256 hash for projection payloads.
 * Used for caching and no-op write detection.
 */

import * as crypto from "crypto";

/**
 * Recursively sort object keys so that JSON.stringify produces a stable string.
 * Arrays are left in order; only object keys are sorted.
 */
export function canonicalize(obj: unknown): unknown {
  if (obj === null || typeof obj !== "object") {
    return obj;
  }
  if (Array.isArray(obj)) {
    return obj.map(canonicalize);
  }
  const sorted: Record<string, unknown> = {};
  const keys = Object.keys(obj as Record<string, unknown>).sort();
  for (const k of keys) {
    sorted[k] = canonicalize((obj as Record<string, unknown>)[k]);
  }
  return sorted;
}

/**
 * Returns a stable JSON string (sorted keys) for the given object.
 */
export function canonicalJson(obj: unknown): string {
  return JSON.stringify(canonicalize(obj));
}

/**
 * SHA-256 hex digest of the canonical JSON of the given object.
 */
export function sha256Hex(obj: unknown): string {
  const str = canonicalJson(obj);
  return crypto.createHash("sha256").update(str, "utf8").digest("hex");
}

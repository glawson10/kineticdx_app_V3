/**
 * One-time migration:
 * clinics/{clinicId}/public/availability/blocks/{blockId}
 *
 * Backfill:
 * - practitionerId <- clinicianId (if practitionerId missing)
 * - (optional) clinicianId <- practitionerId (if clinicianId missing)
 *
 * Usage examples:
 *   ts-node functions/scripts/migrate_public_blocks.ts --clinicId=WXyILCpdFfdtNhjzeXqD --dryRun=true
 *   ts-node functions/scripts/migrate_public_blocks.ts --clinicId=WXyILCpdFfdtNhjzeXqD --dryRun=false
 */

import * as admin from "firebase-admin";

type Args = {
  clinicId: string;
  dryRun: boolean;
  limit?: number;
};

function parseArgs(): Args {
  const argv = process.argv.slice(2);
  const get = (k: string) => {
    const found = argv.find((a) => a.startsWith(`--${k}=`));
    if (!found) return "";
    return found.split("=").slice(1).join("=");
  };

  const clinicId = (get("clinicId") || "").trim();
  const dryRunStr = (get("dryRun") || "true").trim().toLowerCase();
  const limitStr = (get("limit") || "").trim();

  if (!clinicId) {
    throw new Error("Missing --clinicId=...");
  }

  const dryRun = !(dryRunStr === "false" || dryRunStr === "0" || dryRunStr === "no");

  const limit = limitStr ? Number(limitStr) : undefined;
  if (limitStr && (!Number.isFinite(limit) || (limit ?? 0) <= 0)) {
    throw new Error("Invalid --limit (must be positive number).");
  }

  return { clinicId, dryRun, limit };
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

async function main() {
  const { clinicId, dryRun, limit } = parseArgs();

  // Use ADC (recommended):
  // firebase login
  // gcloud auth application-default login
  // OR set GOOGLE_APPLICATION_CREDENTIALS for a service account json
  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const db = admin.firestore();

  const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);

  console.log(`\n== Migrate public blocks for clinicId=${clinicId} ==`);
  console.log(`dryRun=${dryRun}  limit=${limit ?? "none"}\n`);

  let migrated = 0;
  let skipped = 0;
  let scanned = 0;

  // Batch in pages to avoid memory spikes
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

  while (true) {
    let q: FirebaseFirestore.Query = col.orderBy(admin.firestore.FieldPath.documentId()).limit(400);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    scanned += snap.size;

    const batch = db.batch();
    let batchWrites = 0;

    for (const doc of snap.docs) {
      if (limit && migrated >= limit) break;

      const d = doc.data() as any;

      const practitionerId = safeStr(d?.practitionerId);
      const clinicianId = safeStr(d?.clinicianId);

      // Only migrate records that have at least one of these ids
      if (!practitionerId && !clinicianId) {
        skipped++;
        continue;
      }

      const update: Record<string, any> = {};

      // Backfill canonical field from legacy field
      if (!practitionerId && clinicianId) {
        update.practitionerId = clinicianId;
      }

      // Optional: backfill legacy from canonical (helps older clients)
      if (!clinicianId && practitionerId) {
        update.clinicianId = practitionerId;
      }

      if (Object.keys(update).length === 0) {
        skipped++;
        continue;
      }

      update.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      update.migratedBy = "migrate_public_blocks_v1";

      if (!dryRun) {
        batch.set(doc.ref, update, { merge: true });
        batchWrites++;
      }

      migrated++;
    }

    if (!dryRun && batchWrites > 0) {
      await batch.commit();
    }

    lastDoc = snap.docs[snap.docs.length - 1];

    if (limit && migrated >= limit) break;
  }

  console.log("\n== Done ==");
  console.log(`Scanned:   ${scanned}`);
  console.log(`Migrated:  ${migrated}`);
  console.log(`Skipped:   ${skipped}`);
  console.log(`dryRun:    ${dryRun}\n`);
}

main().catch((e) => {
  console.error("Migration failed:", e);
  process.exit(1);
});

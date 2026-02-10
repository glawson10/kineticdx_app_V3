const admin = require("firebase-admin");

/**
 * One-off backfill script to add flowCategory + flowId
 * to existing intakeSessions without touching clinical payload.
 *
 * Collections:
 *   clinics/{clinicId}/intakeSessions/{intakeSessionId}
 *
 * Logic:
 *   - Skip docs that already have flowId or flowCategory
 *   - If regionSelection.bodyArea is present:
 *       flowCategory = "region"
 *       flowId       = normalized bodyArea (strip leading "region.")
 *   - Else:
 *       flowCategory = "general"
 *       flowId       = "generalVisit"
 *
 * IMPORTANT:
 *   - This script uses GOOGLE_APPLICATION_CREDENTIALS to find a service account key.
 *   - Before running, set:
 *       setx GOOGLE_APPLICATION_CREDENTIALS "C:\path\to\service-account.json"   (cmd)
 *       $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json" (PowerShell)
 *   - Run against the correct project:
 *       kineticdx-app-v3 (prod) or kineticdx-v3-dev (dev)
 */

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "kineticdx-app-v3",
});

const db = admin.firestore();

async function backfillClinic(clinicId) {
  console.log(`Backfilling clinic ${clinicId}...`);

  const col = db
    .collection("clinics")
    .doc(clinicId)
    .collection("intakeSessions");

  const pageSize = 200;
  let last = undefined;

  // Simple paging loop over intakeSessions
  // using documentId as the cursor.
  // This is safe for a one-off backfill.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = col.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (last) {
      q = q.startAfter(last);
    }

    const snap = await q.get();
    if (snap.empty) {
      break;
    }

    const batch = db.batch();

    for (const doc of snap.docs) {
      const data = doc.data() || {};

      // Already migrated or written with new schema
      if (data.flowId || data.flowCategory) {
        continue;
      }

      const regionBodyArea =
        data.regionSelection && typeof data.regionSelection.bodyArea === "string"
          ? data.regionSelection.bodyArea
          : undefined;

      let flowCategory;
      let flowId;

      if (regionBodyArea && regionBodyArea.trim() !== "") {
        flowCategory = "region";
        const body = regionBodyArea.startsWith("region.")
          ? regionBodyArea.replace("region.", "")
          : regionBodyArea;
        flowId = body;
      } else {
        flowCategory = "general";
        flowId = "generalVisit";
      }

      batch.update(doc.ref, {
        flowCategory,
        flowId,
      });
    }

    await batch.commit();
    last = snap.docs[snap.docs.length - 1];
  }
}

async function main() {
  const clinicsSnap = await db.collection("clinics").get();
  for (const clinicDoc of clinicsSnap.docs) {
    await backfillClinic(clinicDoc.id);
  }
  console.log("Backfill complete.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});


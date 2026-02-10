import * as admin from "firebase-admin";

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
 * IMPORTANT: Run this against the correct project.
 *  - For prod: projectId = "kineticdx-app-v3"
 *  - For dev:  projectId = "kineticdx-v3-dev"
 */

admin.initializeApp({
  projectId: "kineticdx-app-v3",
});

const db = admin.firestore();

async function backfillClinic(clinicId: string): Promise<void> {
  console.log(`Backfilling clinic ${clinicId}...`);

  const col = db
    .collection("clinics")
    .doc(clinicId)
    .collection("intakeSessions");

  const pageSize = 200;
  let last:
    | FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>
    | undefined;

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
      const data = doc.data() as Record<string, any>;

      // Already migrated or written with new schema
      if (data.flowId || data.flowCategory) {
        continue;
      }

      const regionBodyArea: string | undefined =
        data.regionSelection?.bodyArea ?? undefined;

      let flowCategory: string;
      let flowId: string;

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

async function main(): Promise<void> {
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


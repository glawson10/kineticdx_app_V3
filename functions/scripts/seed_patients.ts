/* functions/scripts/seed_patients.ts
 *
 * Usage:
 *   cd functions
 *   npm run seed:patients -- --project kineticdx-v3-dev --clinicId <CLINIC_ID> --count 10
 *
 * Auth options:
 *   A) GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   B) gcloud auth application-default login
 */

import * as admin from "firebase-admin";

type Args = {
  project?: string;
  clinicId?: string;
  count?: number;
  dryRun?: boolean;
};

function parseArgs(): Args {
  const argv = process.argv.slice(2);
  const out: Args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    if (a === "--project" && next) out.project = next;
    if (a === "--clinicId" && next) out.clinicId = next;
    if (a === "--count" && next) out.count = Number(next);
    if (a === "--dryRun") out.dryRun = true;
  }
  return out;
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function randomDobYYYYMMDD(): string {
  // 1970-01-01 .. 2006-12-31 (adult-ish range)
  const year = randInt(1970, 2006);
  const month = randInt(1, 12);
  const day = randInt(1, 28); // keep safe
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

function parseDobToDayTimestamp(dob: string): admin.firestore.Timestamp {
  const raw = safeStr(dob);
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) throw new Error(`Invalid dob: ${dob}`);
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return admin.firestore.Timestamp.fromDate(day);
}

function makeEmail(first: string, last: string, i: number): string {
  const f = first.toLowerCase().replace(/[^a-z0-9]/g, "");
  const l = last.toLowerCase().replace(/[^a-z0-9]/g, "");
  return `${f}.${l}.${i}@example.com`;
}

function makePhone(i: number): string {
  // fake but consistent
  return `+420 700 10${pad2(i)} ${pad2(randInt(10, 99))}`;
}

async function main() {
  const args = parseArgs();
  const projectId = safeStr(args.project) || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  const clinicId = safeStr(args.clinicId);
  const count = Number.isFinite(args.count) && (args.count as number) > 0 ? (args.count as number) : 10;

  if (!projectId) {
    throw new Error(
      "Missing projectId. Pass --project kineticdx-v3-dev (recommended)."
    );
  }
  if (!clinicId) {
    throw new Error("Missing --clinicId <CLINIC_ID>.");
  }

  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }

  const db = admin.firestore();
  console.log(`[seed_patients] project=${projectId} clinicId=${clinicId} count=${count} dryRun=${!!args.dryRun}`);

  const firstNames = ["Alex", "Sam", "Jamie", "Taylor", "Jordan", "Morgan", "Casey", "Riley", "Charlie", "Avery"];
  const lastNames = ["Smith", "Brown", "Wilson", "Taylor", "Johnson", "Martin", "Walker", "Thompson", "White", "Clark"];

  // Firestore batch limit: 500 ops per batch (we do 1 set per patient)
  const BATCH_MAX = 450;
  let created = 0;

  for (let start = 0; start < count; start += BATCH_MAX) {
    const end = Math.min(count, start + BATCH_MAX);
    const batch = db.batch();

    for (let i = start; i < end; i++) {
      const firstName = firstNames[i % firstNames.length];
      const lastName = lastNames[(i + 3) % lastNames.length];
      const dobStr = randomDobYYYYMMDD();
      const dobTs = parseDobToDayTimestamp(dobStr);
      const phone = makePhone(i + 1);
      const email = makeEmail(firstName, lastName, i + 1);
      const address = `Test Address ${i + 1}, Prague`;

      const ref = db.collection("clinics").doc(clinicId).collection("patients").doc();
      const now = admin.firestore.FieldValue.serverTimestamp();

      const doc = {
        clinicId,

        // Legacy/simple
        firstName,
        lastName,
        dob: dobTs,
        phone,
        email,
        address,

        // Canonical structured blocks (matching your createPatient)
        identity: {
          firstName,
          lastName,
          preferredName: null,
          dateOfBirth: dobTs,
        },
        contact: {
          phone,
          email,
          preferredMethod: null,
          address: address ? { line1: address } : null,
        },
        emergencyContact: null,
        tags: [],
        alerts: [],
        adminNotes: null,
        status: {
          active: true,
          archived: false,
          archivedAt: null,
        },

        createdByUid: "system.seed",
        createdAt: now,
        updatedByUid: "system.seed",
        updatedAt: now,
        schemaVersion: 1,
      };

      if (!args.dryRun) batch.set(ref, doc);
      created++;
    }

    if (!args.dryRun) {
      await batch.commit();
      console.log(`[seed_patients] committed batch ${start}-${end - 1}`);
    } else {
      console.log(`[seed_patients] dryRun batch ${start}-${end - 1} (no writes)`);
    }
  }

  console.log(`[seed_patients] done. created=${created} patients`);
}

main().catch((e) => {
  console.error("[seed_patients] FAILED:", e);
  process.exitCode = 1;
});

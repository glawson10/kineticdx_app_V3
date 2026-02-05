import * as admin from "firebase-admin";
import { buildPublicBookingProjection } from "./publicProjection";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

function normalizeWeeklyHours(
  weekly: AnyMap | undefined
): Record<string, Array<{ start: string; end: string }>> {
  const out: Record<string, Array<{ start: string; end: string }>> = {
    mon: [],
    tue: [],
    wed: [],
    thu: [],
    fri: [],
    sat: [],
    sun: [],
  };

  if (!weekly || typeof weekly !== "object") return out;

  for (const d of DAY_KEYS) {
    const v = weekly[d];
    if (Array.isArray(v)) {
      out[d] = v
        .map((it) => ({
          start: safeStr(it?.start),
          end: safeStr(it?.end),
        }))
        .filter((it) => it.start && it.end);
    }
  }

  return out;
}

export async function writePublicBookingMirror(
  clinicId: string,
  publicBookingSettingsDoc: any
) {
  const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
  const clinicDoc: AnyMap = (clinicSnap.data() ?? {}) as AnyMap;

  const clinicName =
    safeStr(clinicDoc?.profile?.name) ||
    safeStr(clinicDoc?.name) ||
    safeStr(clinicDoc?.clinicName) ||
    "Clinic";

  const logoUrl =
    safeStr(clinicDoc?.profile?.logoUrl) ||
    safeStr(clinicDoc?.logoUrl) ||
    safeStr(clinicDoc?.branding?.logoUrl) ||
    "";

  const [servicesSnap, practitionersSnap, membershipsSnap] = await Promise.all([
    db.collection(`clinics/${clinicId}/services`).get(),
    db.collection(`clinics/${clinicId}/practitioners`).get(),
    db.collection(`clinics/${clinicId}/memberships`).get(),
  ]);

  const services = servicesSnap.docs.map((d) => ({
    id: d.id,
    data: (d.data() ?? {}) as AnyMap,
  }));

  const practitioners = practitionersSnap.docs.map((d) => ({
    id: d.id,
    data: (d.data() ?? {}) as AnyMap,
  }));

  const memberships = membershipsSnap.docs.map((d) => ({
    id: d.id,
    data: (d.data() ?? {}) as AnyMap,
  }));

  const projection = buildPublicBookingProjection({
    clinicId,
    clinicName,
    logoUrl,
    clinicDoc,
    publicBookingSettingsDoc: (publicBookingSettingsDoc ?? {}) as AnyMap,
    services,
    practitioners,
    memberships,
  }) as AnyMap;

  // 🔐 FORCE canonical weeklyHours (ALL 7 DAYS ALWAYS PRESENT)
  const weeklyHours = normalizeWeeklyHours(projection.weeklyHours);

  const ref = db.doc(
    `clinics/${clinicId}/public/config/publicBooking/publicBooking`
  );

  await ref.set(
    {
      ...projection,
      weeklyHours,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: "writePublicBookingMirror-gen2",
      schemaVersion: projection.schemaVersion ?? 1,
    },
    { merge: false } // AUTHORITATIVE SNAPSHOT
  );

  return {
    ...projection,
    weeklyHours,
  };
}

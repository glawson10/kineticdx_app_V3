// functions/src/clinic/appointments/createAppointmentInternal.ts
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

type AnyMap = Record<string, any>;

function safeString(v: any): string {
  return typeof v === "string" ? v.trim() : "";
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

function uniqStrings(arr: unknown): string[] {
  if (!Array.isArray(arr)) return [];
  const out = arr
    .filter((x) => typeof x === "string")
    .map((x) => (x as string).trim())
    .filter((x) => x.length > 0);
  return Array.from(new Set(out));
}

function getNested(obj: AnyMap, path: string): any {
  const parts = path.split(".");
  let cur: any = obj;
  for (const p of parts) {
    if (!cur || typeof cur !== "object") return undefined;
    cur = cur[p];
  }
  return cur;
}

function buildFullName(first: string, last: string): string {
  return [safeString(first), safeString(last)].filter(Boolean).join(" ").trim();
}

async function assertNoClosureOverlap(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
}) {
  const { db, clinicId, startAt, endAt } = params;

  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", endAt)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() as any;
    const fromAt = data?.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = data?.toAt as admin.firestore.Timestamp | undefined;
    if (!fromAt || !toAt) continue;

    const overlaps =
      startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();

    if (overlaps) {
      throw new HttpsError("failed-precondition", "Appointment overlaps a clinic closure.", {
        closureId: doc.id,
      });
    }
  }
}

export type CreateAppointmentInternalInput = {
  clinicId: string;
  kind: "admin" | "new" | "followup";

  patientId?: string;
  serviceId?: string;
  practitionerId?: string;

  startDt: Date;
  endDt: Date;

  resourceIds?: string[];

  actorUid: string;

  allowClosedOverride?: boolean;
  serviceNameFallback?: string;
};

async function readPractitionerDoc(
  db: admin.firestore.Firestore,
  clinicId: string,
  practitionerId: string
): Promise<{ data: AnyMap | null; active: boolean }> {
  const candidates = [
    `clinics/${clinicId}/memberships/${practitionerId}`, // ✅ canonical first
    `clinics/${clinicId}/members/${practitionerId}`, // legacy fallback
    `clinics/${clinicId}/practitioners/${practitionerId}`,
    `clinics/${clinicId}/staff/${practitionerId}`,
  ];

  for (const path of candidates) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const d = (snap.data() ?? {}) as AnyMap;

    const active =
      d.active === true ||
      d.status === "active" ||
      getNested(d, "status.active") === true;

    return { data: d, active };
  }

  return { data: null, active: false };
}

/**
 * Returns { name, source } where source is useful for debugging.
 */
function resolvePatientName(patientDoc: AnyMap): { name: string; source: string } {
  const fnNested = safeString(getNested(patientDoc, "identity.firstName"));
  const lnNested = safeString(getNested(patientDoc, "identity.lastName"));
  const fullNested = buildFullName(fnNested, lnNested);
  if (fullNested) return { name: fullNested, source: "identity.firstName+identity.lastName" };

  const fn = safeString(patientDoc.firstName);
  const ln = safeString(patientDoc.lastName);
  const fullLegacy = buildFullName(fn, ln);
  if (fullLegacy) return { name: fullLegacy, source: "firstName+lastName" };

  const fullName = safeString(patientDoc.fullName);
  if (fullName) return { name: fullName, source: "fullName" };

  return { name: "", source: "none" };
}

export async function createAppointmentInternal(
  db: admin.firestore.Firestore,
  input: CreateAppointmentInternalInput
) {
  const clinicId = input.clinicId.trim();
  const kind = input.kind;
  const actorUid = input.actorUid;

  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");
  if (!(input.startDt instanceof Date) || Number.isNaN(input.startDt.getTime())) {
    throw new HttpsError("invalid-argument", "Invalid start time.");
  }
  if (!(input.endDt instanceof Date) || Number.isNaN(input.endDt.getTime())) {
    throw new HttpsError("invalid-argument", "Invalid end time.");
  }
  if (input.endDt <= input.startDt) {
    throw new HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
  }

  const startTs = admin.firestore.Timestamp.fromDate(input.startDt);
  const endTs = admin.firestore.Timestamp.fromDate(input.endDt);

  if (input.allowClosedOverride !== true) {
    await assertNoClosureOverlap({ db, clinicId, startAt: startTs, endAt: endTs });
  }

  let patientId = "";
  let serviceId = "";
  let practitionerId = "";

  let patientName = "";
  let patientNameSource = "";
  let serviceName = "";
  let practitionerName = "";

  if (kind !== "admin") {
    if (
      !isNonEmptyString(input.patientId) ||
      !isNonEmptyString(input.serviceId) ||
      !isNonEmptyString(input.practitionerId)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "patientId, serviceId, practitionerId are required for patient bookings."
      );
    }

    patientId = input.patientId.trim();
    serviceId = input.serviceId.trim();
    practitionerId = input.practitionerId.trim();

    // Practitioner must be active
    const pracResult = await readPractitionerDoc(db, clinicId, practitionerId);
    if (!pracResult.data || pracResult.active !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Selected practitioner is not an active clinic member."
      );
    }

    // ✅ Patient must exist (do not silently proceed)
    const patientRef = db
      .collection("clinics")
      .doc(clinicId)
      .collection("patients")
      .doc(patientId);

    const patientSnap = await patientRef.get();

    if (!patientSnap.exists) {
      logger.warn("createAppointmentInternal: patient not found", {
        clinicId,
        patientId,
        actorUid,
      });

      throw new HttpsError(
        "failed-precondition",
        "Selected patient was not found in this clinic."
      );
    }

    const p = (patientSnap.data() ?? {}) as AnyMap;
    const resolved = resolvePatientName(p);
    patientName = resolved.name;
    patientNameSource = resolved.source;

    // ✅ Patient name must be resolvable (prevents UI showing “someone else” via details line)
    if (!patientName.trim()) {
      logger.warn("createAppointmentInternal: patient name missing/unresolvable", {
        clinicId,
        patientId,
        actorUid,
        patientNameSource,
        patientDocKeys: Object.keys(p || {}),
      });

      throw new HttpsError(
        "failed-precondition",
        "Patient record is missing a name (firstName/lastName)."
      );
    }

    // Service
    const serviceRef = db
      .collection("clinics")
      .doc(clinicId)
      .collection("services")
      .doc(serviceId);

    const serviceSnap = await serviceRef.get();
    if (serviceSnap.exists) {
      const s = serviceSnap.data() ?? {};
      serviceName = safeString((s as any).name);
    }
    if (!serviceName) serviceName = safeString(input.serviceNameFallback) || serviceId;

    // Practitioner display name
    const prac = pracResult.data ?? {};
    practitionerName =
      safeString((prac as any).displayName) || safeString((prac as any).name) || practitionerId;

    logger.info("createAppointmentInternal: resolved denorm fields", {
      clinicId,
      kind,
      patientId,
      patientName,
      patientNameSource,
      serviceId,
      serviceName,
      practitionerId,
      practitionerName,
      actorUid,
    });
  }

  const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc();
  const resourceIds = uniqStrings(input.resourceIds);

  await apptRef.set({
    clinicId,
    kind,

    patientId: kind === "admin" ? "" : patientId,
    serviceId: kind === "admin" ? "" : serviceId,
    practitionerId: kind === "admin" ? "" : practitionerId,

    patientName: kind === "admin" ? "" : patientName,
    patientNameSource: kind === "admin" ? "" : patientNameSource, // helpful while debugging
    serviceName: kind === "admin" ? "" : serviceName,
    practitionerName: kind === "admin" ? "" : practitionerName,

    resourceIds,

    startAt: startTs,
    endAt: endTs,

    // legacy mirrors
    start: startTs,
    end: endTs,

    status: "booked",
    createdByUid: actorUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedByUid: actorUid,
  });

  return { success: true, appointmentId: apptRef.id };
}

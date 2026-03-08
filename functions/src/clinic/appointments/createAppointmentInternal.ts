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

/** Safely get milliseconds from a Firestore Timestamp (or legacy { _seconds, _nanoseconds }). */
function toMillisSafe(ts: any): number | null {
  if (ts == null) return null;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  const sec = ts._seconds ?? ts.seconds;
  const nan = ts._nanoseconds ?? ts.nanoseconds ?? 0;
  if (typeof sec === "number" && Number.isFinite(sec)) return sec * 1000 + nan / 1e6;
  return null;
}

async function assertNoClosureOverlap(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
}) {
  const { db, clinicId, startAt, endAt } = params;
  const startMs = startAt.toMillis?.() ?? null;
  const endMs = endAt.toMillis?.() ?? null;
  if (startMs == null || endMs == null) return;

  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", endAt)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() as any;
    const fromAt = data?.fromAt;
    const toAt = data?.toAt;
    const fromMs = toMillisSafe(fromAt);
    const toMs = toMillisSafe(toAt);
    if (fromMs == null || toMs == null) continue;

    const overlaps = startMs < toMs && endMs > fromMs;

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
  /** BOOKING_DATA_CONTRACT: optional location for the appointment. */
  locationId?: string;

  startDt: Date;
  endDt: Date;

  resourceIds?: string[];

  actorUid: string;

  allowClosedOverride?: boolean;
  serviceNameFallback?: string;
};

type PractitionerReadResult = {
  data: AnyMap | null;
  active: boolean;
  bookingMeta: AnyMap | null;
};

async function readPractitionerDoc(
  db: admin.firestore.Firestore,
  clinicId: string,
  practitionerId: string
): Promise<PractitionerReadResult> {
  const candidates = [
    `clinics/${clinicId}/memberships/${practitionerId}`,
    `clinics/${clinicId}/members/${practitionerId}`,
    `clinics/${clinicId}/practitioners/${practitionerId}`,
    `clinics/${clinicId}/staff/${practitionerId}`,
  ];

  let memberData: AnyMap | null = null;
  let active = false;

  for (const path of candidates) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const d = (snap.data() ?? {}) as AnyMap;

    active =
      d.active === true ||
      d.status === "active" ||
      getNested(d, "status.active") === true;

    memberData = d;
    break;
  }

  // Also read the practitioners doc for booking metadata
  let bookingMeta: AnyMap | null = null;
  const pracSnap = await db
    .doc(`clinics/${clinicId}/practitioners/${practitionerId}`)
    .get();
  if (pracSnap.exists) {
    bookingMeta = (pracSnap.data() ?? {}) as AnyMap;
  }

  return { data: memberData, active, bookingMeta };
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

function toDateSafe(v: any): Date | null {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v;
  if (v && typeof v.toDate === "function") return v.toDate();
  if (v != null && typeof v === "object" && "seconds" in v) {
    const s = (v as { seconds: number }).seconds;
    if (typeof s === "number" && Number.isFinite(s)) return new Date(s * 1000);
  }
  if (typeof v === "number" && Number.isFinite(v)) return new Date(v);
  return null;
}

export async function createAppointmentInternal(
  db: admin.firestore.Firestore,
  input: CreateAppointmentInternalInput
) {
  try {
    return await createAppointmentInternalImpl(db, input);
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
    const msg = err?.message ?? String(err);
    logger.error("createAppointmentInternal unexpected error", {
      kind: input.kind,
      err: msg,
      stack: err?.stack,
    });
    throw new HttpsError("internal", msg || "Create appointment failed.", {
      original: msg,
    });
  }
}

async function createAppointmentInternalImpl(
  db: admin.firestore.Firestore,
  input: CreateAppointmentInternalInput
) {
  const clinicId = input.clinicId.trim();
  const kind = input.kind;
  const actorUid = input.actorUid;

  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

  const startDt = toDateSafe(input.startDt);
  const endDt = toDateSafe(input.endDt);
  if (!startDt || !endDt) {
    throw new HttpsError("invalid-argument", "Invalid start or end time.");
  }
  if (endDt <= startDt) {
    throw new HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
  }

  const startTs = admin.firestore.Timestamp.fromDate(startDt);
  const endTs = admin.firestore.Timestamp.fromDate(endDt);

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

    // Booking eligibility checks (from practitioners/{uid} doc)
    const bmeta = pracResult.bookingMeta;
    if (bmeta) {
      if (bmeta.activeForBooking === false) {
        throw new HttpsError(
          "failed-precondition",
          "Selected practitioner is not available for booking."
        );
      }

      const allowedServices: string[] = Array.isArray(bmeta.serviceIdsAllowed)
        ? bmeta.serviceIdsAllowed.filter((x: any) => typeof x === "string" && x.trim())
        : [];
      if (allowedServices.length > 0 && !allowedServices.includes(serviceId)) {
        throw new HttpsError(
          "failed-precondition",
          "Selected practitioner cannot provide this appointment type."
        );
      }

      const allowedLocations: string[] = Array.isArray(bmeta.allowedLocationIds)
        ? bmeta.allowedLocationIds.filter((x: any) => typeof x === "string" && x.trim())
        : [];
      const locId = safeString(input.locationId);
      if (allowedLocations.length > 0 && locId && !allowedLocations.includes(locId)) {
        throw new HttpsError(
          "failed-precondition",
          "Selected practitioner does not work at this location."
        );
      }
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

  const payload: Record<string, unknown> = {
    clinicId,
    kind,

    patientId: kind === "admin" ? "" : patientId,
    serviceId: kind === "admin" ? "" : serviceId,
    practitionerId: kind === "admin" ? "" : practitionerId,
    ...(input.locationId && input.locationId.trim()
      ? { locationId: input.locationId.trim() }
      : {}),

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
  };

  try {
    await apptRef.set(payload);
  } catch (err: any) {
    logger.error("createAppointmentInternal: apptRef.set failed", {
      clinicId,
      kind,
      err: err?.message ?? String(err),
      stack: err?.stack,
    });
    throw new HttpsError(
      "internal",
      err?.message ?? "Failed to write appointment.",
      { original: err?.message }
    );
  }

  return { success: true, appointmentId: apptRef.id };
}

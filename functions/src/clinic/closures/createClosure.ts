import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  fromAt: string; // ISO string (UTC)
  toAt: string;   // ISO string (UTC)
  reason?: string | null;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function parseIso(label: string, v: string): Date {
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) {
    throw new HttpsError("invalid-argument", `Invalid ${label}. Must be ISO8601 string.`);
  }
  return d;
}

// ✅ IMPORTANT: this must be a named export
export async function createClosure(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const fromAtIso = safeStr(req.data?.fromAt);
  const toAtIso = safeStr(req.data?.toAt);
  const reason = safeStr(req.data?.reason);

  if (!clinicId || !fromAtIso || !toAtIso) {
    throw new HttpsError("invalid-argument", "clinicId, fromAt, toAt are required.");
  }

  const fromAt = parseIso("fromAt", fromAtIso);
  const toAt = parseIso("toAt", toAtIso);
  if (toAt <= fromAt) {
    throw new HttpsError("invalid-argument", "toAt must be after fromAt.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ✅ Closures are scheduling operations
  await requireActiveMemberWithPerm(db, clinicId, uid, "schedule.write");

  const now = admin.firestore.FieldValue.serverTimestamp();

  const ref = db.collection("clinics").doc(clinicId).collection("closures").doc();

  await ref.set({
    clinicId,
    active: true,
    fromAt: admin.firestore.Timestamp.fromDate(fromAt),
    toAt: admin.firestore.Timestamp.fromDate(toAt),

    // ✅ TS: strings use .length (not .isEmpty)
    reason: reason.length === 0 ? null : reason,

    createdAt: now,
    createdByUid: uid,
    updatedAt: now,
    updatedByUid: uid,
  });

  await writeAuditEvent(db, clinicId, {
    type: "clinic.closure.created",
    actorUid: uid,
    metadata: { closureId: ref.id },
  });

  return { ok: true, closureId: ref.id };
}

// functions/src/clinic/audit/exportClosureOverrideAuditReport.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "./audit";

type Input = {
  clinicId: string;
  format: "csv" | "pdf";
  limit?: number; // default 2000
};

function csvEscape(v: any): string {
  const s = (v ?? "").toString();
  if (s.includes('"') || s.includes(",") || s.includes("\n") || s.includes("\r")) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function fmtDateTime(d: Date): string {
  return d.toISOString();
}

export async function exportClosureOverrideAuditReport(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const format = (req.data?.format ?? "csv") as "csv" | "pdf";
  const limit = Math.max(1, Math.min(5000, Number(req.data?.limit ?? 2000)));

  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId required.");
  if (format !== "csv" && format !== "pdf") {
    throw new HttpsError("invalid-argument", "format must be csv or pdf.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "audit.read");

  const snap = await db
    .collection("clinics")
    .doc(clinicId)
    .collection("audit")
    .where("type", "==", "appointment.closed_override")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  const rows = snap.docs.map((d) => {
    const data = d.data() || {};
    const meta =
      data["metadata"] && typeof data["metadata"] === "object" ? data["metadata"] : {};
    const createdAt = data["createdAt"]?.toDate?.() ?? null;

    return {
      id: d.id,
      createdAt: createdAt ? fmtDateTime(createdAt) : "",
      actorUid: data["actorUid"] ?? "",
      actorDisplayName: data["actorDisplayName"] ?? "",
      appointmentId: meta["appointmentId"] ?? "",
      startMs: meta["startMs"] ?? "",
      endMs: meta["endMs"] ?? "",
      closureIds: Array.isArray(meta["closureIds"]) ? meta["closureIds"].join("|") : "",
      reason: meta["reason"] ?? "",
    };
  });

  const header = [
    "auditId",
    "createdAt",
    "actorUid",
    "actorDisplayName",
    "appointmentId",
    "startMs",
    "endMs",
    "closureIds",
    "reason",
  ];

  const csv =
    header.join(",") +
    "\n" +
    rows
      .map((r) =>
        [
          r.id,
          r.createdAt,
          r.actorUid,
          r.actorDisplayName,
          r.appointmentId,
          r.startMs,
          r.endMs,
          r.closureIds,
          r.reason,
        ]
          .map(csvEscape)
          .join(",")
      )
      .join("\n");

  // audit the export action (no PHI)
  await writeAuditEvent(db, clinicId, {
    type: "audit.closureOverride.exported",
    actorUid: uid,
    metadata: { format, count: rows.length, limit },
  });

  if (format === "csv") {
    return { ok: true, csv };
  }

  // For now, generate CSV and return signed URL (pdf can come later)
  const bucket = admin.storage().bucket();
  const filePath = `clinics/${clinicId}/reports/closure-overrides/${Date.now()}_${uid}.csv`;
  const file = bucket.file(filePath);

  await file.save(csv, {
    contentType: "text/csv; charset=utf-8",
    resumable: false,
    metadata: { cacheControl: "no-store" },
  });

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 1000 * 60 * 60, // 1 hour
  });

  return { ok: true, url };
}

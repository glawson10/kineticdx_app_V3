// functions/src/clinic/audit/audit.ts
import { Firestore } from "firebase-admin/firestore";
import * as admin from "firebase-admin";

export type AuditEventType =
  | "note.created"
  | "note.signed"
  | "note.amended"
  | "episode.created"
  | "episode.updated"
  | "episode.closed"
  | "patient.created"
  | "patient.updated"
  | "appointment.created"
  | "appointment.updated"
  | "appointment.deleted"
  | "member.invited"
  | "member.accepted"
  | "registry.clinicalTest.upserted"
  | "registry.clinicalTest.deleted"
  | "registry.outcomeMeasure.upserted"
  | "registry.outcomeMeasure.deleted"
  | "closure.created"
  | "closure.deleted"
  | "audit.exported"
  | "audit.closureOverride.exported"
  // ✅ Flutter audit screen expects:
  | "appointment.closed_override";

export type AuditEvent = {
  type: AuditEventType | string;

  actorUid: string;
  actorDisplayName?: string;

  patientId?: string;
  episodeId?: string;
  noteId?: string;
  appointmentId?: string;

  metadata?: Record<string, any>;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

async function resolveActorDisplayName(
  db: Firestore,
  clinicId: string,
  uid: string
): Promise<string> {
  const u = safeStr(uid);
  if (!u) return "";

  try {
    // 1) Clinic membership doc (canonical) — clinic-scoped name/email
    const canon = await db
      .collection("clinics")
      .doc(clinicId)
      .collection("memberships")
      .doc(u)
      .get();

    if (canon.exists) {
      const md = canon.data() || {};
      const dn = safeStr(md["displayName"] ?? md["name"]);
      if (dn) return dn;
      const email = safeStr(md["email"]);
      if (email) return email;
    }

    // 2) Legacy clinic member doc (temporary fallback)
    const legacy = await db
      .collection("clinics")
      .doc(clinicId)
      .collection("members")
      .doc(u)
      .get();

    if (legacy.exists) {
      const md = legacy.data() || {};
      const dn = safeStr(md["displayName"] ?? md["name"]);
      if (dn) return dn;
      const email = safeStr(md["email"]);
      if (email) return email;
    }

    // 3) Global user profile doc
    const userDoc = await db.collection("users").doc(u).get();
    if (userDoc.exists) {
      const ud = userDoc.data() || {};
      const dn = safeStr(ud["displayName"]);
      if (dn) return dn;
      const email = safeStr(ud["email"]);
      if (email) return email;
    }

    // 4) Firebase Auth
    const au = await admin.auth().getUser(u);
    const dn2 = safeStr(au.displayName);
    if (dn2) return dn2;
    const em2 = safeStr(au.email);
    if (em2) return em2;

    return u;
  } catch {
    return u;
  }
}

export async function writeAuditEvent(db: Firestore, clinicId: string, event: AuditEvent) {
  const actorUid = safeStr(event.actorUid);

  const actorDisplayName =
    safeStr(event.actorDisplayName) ||
    (actorUid ? await resolveActorDisplayName(db, clinicId, actorUid) : "");

  await db.collection("clinics").doc(clinicId).collection("audit").add({
    ...event,
    actorUid,
    actorDisplayName: actorDisplayName || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

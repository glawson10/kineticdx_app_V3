// functions/src/clinic/audit/audit.ts
import { Firestore } from "firebase-admin/firestore";
import * as admin from "firebase-admin";

export type AuditEventType =
  | "clinicalNote.created"
  | "clinicalNote.updated"
  | "clinicalNote.finalized"
  | "clinicalNote.unfinalized"
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
  | "appointment.cancelled"
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
  | "appointment.closed_override"
  | "staff.profile.updated"
  | "staff.availability.updated";

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

function removeUndefined(obj: Record<string, any>): Record<string, any> {
  const cleaned: Record<string, any> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) {
      // Recursively clean nested objects
      if (value && typeof value === "object" && !Array.isArray(value) && !(value instanceof admin.firestore.Timestamp)) {
        cleaned[key] = removeUndefined(value);
      } else {
        cleaned[key] = value;
      }
    }
  }
  return cleaned;
}

export async function writeAuditEvent(db: Firestore, clinicId: string, event: AuditEvent) {
  const actorUid = safeStr(event.actorUid);

  const actorDisplayName =
    safeStr(event.actorDisplayName) ||
    (actorUid ? await resolveActorDisplayName(db, clinicId, actorUid) : "");

  // Filter out undefined values - Firestore doesn't accept undefined
  const cleanEvent: Record<string, any> = {
    type: event.type,
    actorUid,
    actorDisplayName: actorDisplayName || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (event.patientId) cleanEvent.patientId = event.patientId;
  if (event.episodeId) cleanEvent.episodeId = event.episodeId;
  if (event.noteId) cleanEvent.noteId = event.noteId;
  if (event.appointmentId) cleanEvent.appointmentId = event.appointmentId;
  if (event.metadata && Object.keys(event.metadata).length > 0) {
    // Remove undefined values from metadata object
    const cleanedMetadata = removeUndefined(event.metadata);
    if (Object.keys(cleanedMetadata).length > 0) {
      cleanEvent.metadata = cleanedMetadata;
    }
  }

  await db.collection("clinics").doc(clinicId).collection("audit").add(cleanEvent);
}

// ─────────────────────────────────────────────────────────────────────────────
// Commit 04: Settings audit payload (do not drift)
// clinics/{clinicId}/audit/{eventId}
// { clinicId, eventType, actorUserId, entityPath, entityId, changes, createdAt }
// Only store changed keys inside changes, not full entity snapshots.
// ─────────────────────────────────────────────────────────────────────────────

export type SettingsAuditEventType =
  | "settings.clinic.updated"
  | "settings.location.created"
  | "settings.location.updated"
  | "settings.location.deactivated"
  | "settings.location.upserted"
  | "settings.location.active_set"
  | "settings.appointmentType.created"
  | "settings.appointmentType.updated"
  | "settings.apptType.upserted"
  | "settings.calendarDisplay.updated"
  | "settings.publicBooking.updated";

export type SettingsAuditPayload = {
  clinicId: string;
  eventType: SettingsAuditEventType | string;
  actorUserId: string;
  entityPath: string;
  entityId: string;
  changes: Record<string, unknown>;
  createdAt: admin.firestore.FieldValue;
};

export async function writeSettingsAuditEvent(
  db: Firestore,
  clinicId: string,
  eventType: SettingsAuditEventType | string,
  actorUserId: string,
  entityPath: string,
  entityId: string,
  changes: Record<string, unknown>
): Promise<void> {
  const ref = db.collection("clinics").doc(clinicId).collection("audit").doc();
  await ref.set({
    clinicId,
    eventType,
    actorUserId: (actorUserId ?? "").toString().trim(),
    entityPath,
    entityId,
    changes: changes ?? {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

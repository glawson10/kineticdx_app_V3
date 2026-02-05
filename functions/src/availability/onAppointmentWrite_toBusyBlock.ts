import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function toTimestamp(v: any): admin.firestore.Timestamp | null {
  if (!v) return null;

  // Firestore Timestamp already
  if (v instanceof admin.firestore.Timestamp) return v;

  // Serialized Timestamp-like
  if (typeof v === "object" && typeof v._seconds === "number") {
    const secs = Number(v._seconds);
    const nanos = Number(v._nanoseconds ?? 0);
    return new admin.firestore.Timestamp(secs, nanos);
  }

  // millis number
  if (typeof v === "number" && Number.isFinite(v)) {
    return admin.firestore.Timestamp.fromMillis(v);
  }

  // ISO string
  if (typeof v === "string") {
    const t = Date.parse(v);
    if (Number.isFinite(t)) return admin.firestore.Timestamp.fromMillis(t);
  }

  return null;
}

export const onAppointmentWrite_toBusyBlock = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/appointments/{appointmentId}",
  },
  async (event) => {
    const { clinicId, appointmentId } = event.params;

    const after = event.data?.after;
    const afterExists = after?.exists ?? false;

    const blockRef = db.doc(
      `clinics/${clinicId}/public/availability/blocks/${appointmentId}`
    );

    // Deleted => remove block
    if (!afterExists) {
      await blockRef.delete().catch(() => {});
      return;
    }

    const a = after!.data() || {};

    // Support multiple possible appointment field names (migration-safe)
    const startRaw =
      a.startAt ?? a.startUtc ?? a.start ?? a.startsAt ?? a.startTime ?? a.startMs;
    const endRaw =
      a.endAt ?? a.endUtc ?? a.end ?? a.endsAt ?? a.endTime ?? a.endMs;

    const startTs = toTimestamp(startRaw);
    const endTs = toTimestamp(endRaw);

    if (!startTs || !endTs) {
      console.warn("Appointment missing start/end; cannot build busy block", {
        clinicId,
        appointmentId,
        keys: Object.keys(a),
      });
      // Don’t leave a stale/invalid block around
      await blockRef.delete().catch(() => {});
      return;
    }

    const status = safeStr(a.status) || "booked";
    if (status === "cancelled") {
      await blockRef.delete().catch(() => {});
      return;
    }

    const kind = safeStr(a.kind);
    const practitionerId = safeStr(a.practitionerId) || safeStr(a.clinicianId);

    // ✅ Scope rules:
    // - admin without practitioner => clinic-wide block
    // - admin with practitioner    => practitioner block
    // - everything else            => practitioner block
    const scope =
      kind === "admin"
        ? practitionerId
          ? "practitioner"
          : "clinic"
        : "practitioner";

    await blockRef.set(
      {
        clinicId,
        appointmentId,

        startUtc: startTs, // Timestamp
        endUtc: endTs, // Timestamp

        scope,

        // standardize on practitionerId
        practitionerId: practitionerId || null,
        // legacy mirror for older readers
        clinicianId: practitionerId || null,

        status,
        kind: kind || null,

        source: "appointments_mirror",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
);

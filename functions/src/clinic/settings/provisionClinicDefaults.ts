import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/**
 * Creates default settings docs for a clinic + ensures owner membership exists.
 * Safe: idempotent (only writes if missing).
 *
 * Trigger: when clinics/{clinicId} is created.
 */
export const onClinicCreatedProvisionDefaults = onDocumentCreated(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}",
  },
  async (event) => {
    const clinicId = (event.params.clinicId ?? "").toString().trim();
    if (!clinicId) return;

    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    const clinic = clinicSnap.data() ?? {};

    const createdByUid = (clinic.createdByUid ?? "").toString().trim();
    const createdByEmail = (clinic.createdByEmail ?? "").toString().trim() || null;

    // ───────────────────────────────────────────────────────────
    // 1) Provision notification settings doc (your existing logic)
    // ───────────────────────────────────────────────────────────
    const notifRef = db.doc(`clinics/${clinicId}/settings/notifications`);
    const notifSnap = await notifRef.get();

    if (!notifSnap.exists) {
      const defaultNotifications = {
        schemaVersion: 1,
        defaultLocale: "en",
        brevo: {
          senderId: null, // set in Brevo + clinic settings later
          replyToEmail: null, // set later
        },
        events: {
          "booking.created.patientConfirmation": {
            enabled: false,
            templateIdByLocale: {},
          },
          "booking.created.clinicianNotification": {
            enabled: false,
            templateIdByLocale: {},
            recipientPolicy: { mode: "practitionerOnAppointment" },
          },
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: "system.provisioner",
      };

      await notifRef.set(defaultNotifications, { merge: false });
      logger.info("Provisioned default notifications settings", { clinicId });
    } else {
      logger.info("notifications settings already exist; skipping", { clinicId });
    }

    // ───────────────────────────────────────────────────────────
    // 2) Ensure the creator is the clinic owner member
    // ───────────────────────────────────────────────────────────
    if (!createdByUid) {
      logger.warn("Clinic missing createdByUid; cannot provision owner membership", { clinicId });
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // clinics/{clinicId}/members/{uid}  (authoritative)
    const memberRef = db.doc(`clinics/${clinicId}/members/${createdByUid}`);
    const memberSnap = await memberRef.get();

    if (!memberSnap.exists) {
      const ownerPermissions: Record<string, boolean> = {
        // Settings / staff
        "settings.read": true,
        "settings.write": true,
        "members.read": true,
        "members.manage": true,
        "roles.manage": true,

        // Schedule
        "schedule.read": true,
        "schedule.write": true,

        // Patients / clinical
        "patients.read": true,
        "patients.write": true,
        "clinical.read": true,
        "clinical.write": true,

        // Notes
        "notes.read": true,
        "notes.write.any": true,
        "notes.write.own": true,

        // Services / registries / resources
        "services.manage": true,
        "registries.manage": true,
        "resources.manage": true,

        // Audit
        "audit.read": true,
      };

      await memberRef.set(
        {
          active: true,
          status: "active",
          roleId: "owner",
          invitedEmail: createdByEmail, // optional (nice for UI)
          permissions: ownerPermissions,

          createdAt: now,
          updatedAt: now,
          createdByUid: createdByUid,
          updatedByUid: createdByUid,
        },
        { merge: false }
      );

      logger.info("Provisioned owner membership", { clinicId, uid: createdByUid });
    } else {
      logger.info("Owner membership already exists; skipping", { clinicId, uid: createdByUid });
    }

    // Optional but recommended: users/{uid}/memberships/{clinicId} (fast clinic picker index)
    // Only create if missing.
    const indexRef = db.doc(`users/${createdByUid}/memberships/${clinicId}`);
    const indexSnap = await indexRef.get();

    if (!indexSnap.exists) {
      await indexRef.set(
        {
          clinicId,
          roleId: "owner",
          active: true,
          invitedEmail: createdByEmail,
          createdAt: now,
          updatedAt: now,
        },
        { merge: false }
      );

      logger.info("Provisioned membership index", { clinicId, uid: createdByUid });
    }
  }
);

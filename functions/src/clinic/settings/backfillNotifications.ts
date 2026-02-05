import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/**
 * Backfill notifications settings for existing clinics.
 *
 * ✅ Idempotent: only creates if missing.
 * ✅ Clinic-scoped: writes under clinics/{clinicId}/settings/notifications
 * ✅ Permissioned: requires caller to be an authenticated platform admin
 *    (custom claim: request.auth.token.admin === true)
 *
 * Callable name: backfillNotificationsSettings
 *
 * Optional input:
 *  - clinicId?: string   // if provided, only backfill that clinic
 *
 * Output:
 *  - processed: number
 *  - created: number
 *  - skipped: number
 */
export const backfillNotificationsSettings = onCall(
  { region: "europe-west3" },
  async (req) => {
    // ── Authz: platform admin only ─────────────────────────────
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const isAdmin = (req.auth.token as any)?.admin === true;
    if (!isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Admin privileges required to run backfill."
      );
    }

    const clinicId = (req.data?.clinicId ?? "").toString().trim();

    // ── Default settings (safe: disabled until configured) ─────
    const makeDefaultDoc = () => ({
      schemaVersion: 1,
      defaultLocale: "en",
      brevo: {
        senderId: null, // set later
        replyToEmail: null, // set later
      },
      events: {
        // ✅ INVITES (new)
        // NOTE: inviteBaseUrl MUST be set per environment (dev/prod)
        // Example:
        //  - dev:  https://kineticdx-v3-dev.web.app/#/accept-invite
        //  - prod: https://<your-prod-site>.web.app/#/accept-invite
        "members.invite": {
          enabled: false,
          templateIdByLocale: {},
          inviteBaseUrl: null,
        },

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
      createdBy: "system.backfillNotificationsSettings",
    });

    // ── Helper: one clinic ─────────────────────────────────────
    const ensureClinic = async (cid: string) => {
      const ref = db.doc(`clinics/${cid}/settings/notifications`);
      const snap = await ref.get();
      if (snap.exists) return { created: false };

      await ref.set(makeDefaultDoc(), { merge: false });
      return { created: true };
    };

    // ── Run backfill ───────────────────────────────────────────
    let processed = 0;
    let created = 0;
    let skipped = 0;

    if (clinicId) {
      processed = 1;
      const r = await ensureClinic(clinicId);
      if (r.created) created++;
      else skipped++;

      logger.info("Backfill notifications done (single clinic)", {
        clinicId,
        processed,
        created,
        skipped,
      });

      return { processed, created, skipped };
    }

    // All clinics: iterate in pages
    const clinicsCol = db.collection("clinics");
    const pageSize = 250;

    let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    while (true) {
      let q: FirebaseFirestore.Query = clinicsCol
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);

      if (last) {
        q = q.startAfter(last);
      }

      const page = await q.get();
      if (page.empty) break;

      for (const doc of page.docs) {
        const cid = doc.id;
        processed++;
        try {
          const r = await ensureClinic(cid);
          if (r.created) created++;
          else skipped++;
        } catch (e: any) {
          // Continue backfill even if one clinic fails
          logger.error("Backfill failed for clinic", {
            clinicId: cid,
            err: (e?.message ?? String(e)).toString().slice(0, 500),
          });
          skipped++;
        }
      }

      last = page.docs[page.docs.length - 1];
      if (page.size < pageSize) break;
    }

    logger.info("Backfill notifications done (all clinics)", {
      processed,
      created,
      skipped,
    });

    return { processed, created, skipped };
  }
);

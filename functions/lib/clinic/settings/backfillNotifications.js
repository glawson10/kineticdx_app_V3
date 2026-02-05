"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.backfillNotificationsSettings = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
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
exports.backfillNotificationsSettings = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b, _c, _d;
    // ── Authz: platform admin only ─────────────────────────────
    if (!req.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const isAdmin = ((_a = req.auth.token) === null || _a === void 0 ? void 0 : _a.admin) === true;
    if (!isAdmin) {
        throw new https_1.HttpsError("permission-denied", "Admin privileges required to run backfill.");
    }
    const clinicId = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.clinicId) !== null && _c !== void 0 ? _c : "").toString().trim();
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
    const ensureClinic = async (cid) => {
        const ref = db.doc(`clinics/${cid}/settings/notifications`);
        const snap = await ref.get();
        if (snap.exists)
            return { created: false };
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
        if (r.created)
            created++;
        else
            skipped++;
        logger_1.logger.info("Backfill notifications done (single clinic)", {
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
    let last = null;
    while (true) {
        let q = clinicsCol
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(pageSize);
        if (last) {
            q = q.startAfter(last);
        }
        const page = await q.get();
        if (page.empty)
            break;
        for (const doc of page.docs) {
            const cid = doc.id;
            processed++;
            try {
                const r = await ensureClinic(cid);
                if (r.created)
                    created++;
                else
                    skipped++;
            }
            catch (e) {
                // Continue backfill even if one clinic fails
                logger_1.logger.error("Backfill failed for clinic", {
                    clinicId: cid,
                    err: ((_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : String(e)).toString().slice(0, 500),
                });
                skipped++;
            }
        }
        last = page.docs[page.docs.length - 1];
        if (page.size < pageSize)
            break;
    }
    logger_1.logger.info("Backfill notifications done (all clinics)", {
        processed,
        created,
        skipped,
    });
    return { processed, created, skipped };
});
//# sourceMappingURL=backfillNotifications.js.map
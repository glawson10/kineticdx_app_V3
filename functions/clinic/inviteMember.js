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
exports.BREVO_API_KEY = void 0;
exports.inviteMember = inviteMember;
// functions/src/clinic/inviteMember.ts
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger_1 = require("firebase-functions/logger");
const admin = __importStar(require("firebase-admin"));
const hash_1 = require("./hash");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
// ✅ Secret (set via: firebase functions:secrets:set BREVO_API_KEY)
exports.BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
function normEmail(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim().toLowerCase();
}
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function nonEmptyOrNull(v) {
    const s = safeStr(v);
    return s ? s : null;
}
function pickFirst(...vals) {
    for (const v of vals) {
        if (v !== undefined && v !== null)
            return v;
    }
    return undefined;
}
function roleLabel(roleId) {
    const r = roleId.trim();
    if (!r)
        return "Staff";
    const spaced = r.replace(/([a-z])([A-Z])/g, "$1 $2");
    return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}
/**
 * Reads invite email config:
 * clinics/{clinicId}/settings/notifications
 *
 * Expected:
 * - brevo.senderId
 * - brevo.replyToEmail
 * - events.members.invite.enabled
 * - events.members.invite.templateIdByLocale.en = 3
 *
 * Recommended:
 * - events.members.invite.inviteBaseUrl
 *   e.g. https://kineticdx-v3-dev.web.app/#/accept-invite
 */
async function loadInviteEmailConfig(clinicId) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const notifRef = db.doc(`clinics/${clinicId}/settings/notifications`);
    const snap = await notifRef.get();
    const settings = (snap.exists ? snap.data() : null);
    const defaultLocale = safeStr(settings === null || settings === void 0 ? void 0 : settings.defaultLocale) || "en";
    const senderId = (_b = (_a = settings === null || settings === void 0 ? void 0 : settings.brevo) === null || _a === void 0 ? void 0 : _a.senderId) !== null && _b !== void 0 ? _b : null;
    const replyToEmail = nonEmptyOrNull((_c = settings === null || settings === void 0 ? void 0 : settings.brevo) === null || _c === void 0 ? void 0 : _c.replyToEmail);
    const eventKey = "members.invite";
    const templateId = (_l = (_g = (_f = (_e = (_d = settings === null || settings === void 0 ? void 0 : settings.events) === null || _d === void 0 ? void 0 : _d[eventKey]) === null || _e === void 0 ? void 0 : _e.templateIdByLocale) === null || _f === void 0 ? void 0 : _f[defaultLocale]) !== null && _g !== void 0 ? _g : (_k = (_j = (_h = settings === null || settings === void 0 ? void 0 : settings.events) === null || _h === void 0 ? void 0 : _h[eventKey]) === null || _j === void 0 ? void 0 : _j.templateIdByLocale) === null || _k === void 0 ? void 0 : _k["en"]) !== null && _l !== void 0 ? _l : null;
    const enabled = ((_o = (_m = settings === null || settings === void 0 ? void 0 : settings.events) === null || _m === void 0 ? void 0 : _m[eventKey]) === null || _o === void 0 ? void 0 : _o.enabled) === true;
    // ✅ store the invite landing route here (not in publicBooking)
    const inviteBaseUrl = nonEmptyOrNull((_q = (_p = settings === null || settings === void 0 ? void 0 : settings.events) === null || _p === void 0 ? void 0 : _p[eventKey]) === null || _q === void 0 ? void 0 : _q.inviteBaseUrl);
    // ✅ DEBUG (safe: no secrets)
    logger_1.logger.info("[inviteMember] loadInviteEmailConfig()", {
        clinicId,
        notifDocExists: snap.exists,
        defaultLocale,
        enabled,
        templateId,
        senderId,
        replyToEmailPresent: !!replyToEmail,
        inviteBaseUrl,
    });
    return {
        enabled,
        templateId,
        defaultLocale,
        senderId,
        replyToEmail,
        inviteBaseUrl,
        // raw is useful sometimes, but can be noisy. Keep it for dev:
        raw: settings,
    };
}
/**
 * Sends invite email via Brevo Transactional Email API.
 * Uses template variables via `params`.
 */
async function sendBrevoInviteEmail(args) {
    const { apiKey, toEmail, templateId, senderId, replyToEmail, params } = args;
    const payload = {
        to: [{ email: toEmail }],
        templateId,
        params,
    };
    // If you created sender in Brevo, you can reference by id.
    if (typeof senderId === "number" && senderId > 0) {
        payload.sender = { id: senderId };
    }
    if (replyToEmail) {
        payload.replyTo = { email: replyToEmail };
    }
    // ✅ DEBUG (do NOT log apiKey)
    logger_1.logger.info("[Brevo] about to send invite email", {
        toEmail,
        templateId,
        senderId,
        replyToEmailPresent: !!replyToEmail,
        paramsKeys: Object.keys(params !== null && params !== void 0 ? params : {}),
        accept_invite_url: params === null || params === void 0 ? void 0 : params.accept_invite_url,
    });
    // Node 18+ has global fetch (Cloud Functions gen2 uses Node 18/20)
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
            "api-key": apiKey,
            "content-type": "application/json",
            accept: "application/json",
        },
        body: JSON.stringify(payload),
    });
    const text = await res.text().catch(() => "");
    if (!res.ok) {
        logger_1.logger.error("[Brevo] sendTransacEmail failed", {
            status: res.status,
            body: text === null || text === void 0 ? void 0 : text.slice(0, 1200),
        });
        throw new https_1.HttpsError("internal", `Brevo send failed (${res.status})`);
    }
    logger_1.logger.info("[Brevo] invite email sent", {
        toEmail,
        templateId,
        // Brevo returns JSON; keep short
        resp: text === null || text === void 0 ? void 0 : text.slice(0, 600),
    });
}
async function inviteMember(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    // ✅ DEBUG: confirm function entry + inputs
    logger_1.logger.info("[inviteMember] called", {
        clinicId: (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId,
        email: (_b = req.data) === null || _b === void 0 ? void 0 : _b.email,
        roleId: (_c = req.data) === null || _c === void 0 ? void 0 : _c.roleId,
        uid: (_d = req.auth) === null || _d === void 0 ? void 0 : _d.uid,
    });
    const clinicId = safeStr((_e = req.data) === null || _e === void 0 ? void 0 : _e.clinicId);
    const email = normEmail((_f = req.data) === null || _f === void 0 ? void 0 : _f.email);
    const roleId = safeStr((_g = req.data) === null || _g === void 0 ? void 0 : _g.roleId);
    if (!clinicId || !email || !roleId) {
        logger_1.logger.warn("[inviteMember] invalid arguments", { clinicId, email, roleId });
        throw new https_1.HttpsError("invalid-argument", "clinicId, email, roleId are required.");
    }
    const uid = req.auth.uid;
    // ─────────────────────────────────────────────────────────────
    // Authorize inviter (canonical memberships first, legacy fallback)
    // ─────────────────────────────────────────────────────────────
    const canonMemberRef = db
  .collection("clinics")
  .doc(clinicId)
  .collection("members")       // ✅ canonical
  .doc(uid);

const legacyMemberRef = db
  .collection("clinics")
  .doc(clinicId)
  .collection("memberships")   // ✅ legacy fallback
  .doc(uid);

    logger_1.logger.info("[inviteMember] authz lookup", {
        clinicId,
        uid,
        canonPath: canonMemberRef.path,
        legacyPath: legacyMemberRef.path,
    });
    const canonSnap = await canonMemberRef.get();
    const legacySnap = canonSnap.exists ? null : await legacyMemberRef.get();
    logger_1.logger.info("[inviteMember] authz snapshots", {
        clinicId,
        uid,
        canonExists: canonSnap.exists,
        legacyExists: (_h = legacySnap === null || legacySnap === void 0 ? void 0 : legacySnap.exists) !== null && _h !== void 0 ? _h : false,
    });
    const memberData = canonSnap.exists
        ? canonSnap.data()
        : legacySnap === null || legacySnap === void 0 ? void 0 : legacySnap.data();
    if (!memberData) {
        logger_1.logger.warn("[inviteMember] inviter is not a clinic member", { clinicId, uid });
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    // Back-compat: treat missing active as active
    const isActive = memberData.active === false ? false : true;
    logger_1.logger.info("[inviteMember] authz memberData", {
        clinicId,
        uid,
        isActive,
        roleId: (_k = (_j = memberData.roleId) !== null && _j !== void 0 ? _j : memberData.role) !== null && _k !== void 0 ? _k : null,
        hasMembersManage: ((_l = memberData.permissions) !== null && _l !== void 0 ? _l : {})["members.manage"] === true,
    });
    if (!isActive)
        throw new https_1.HttpsError("permission-denied", "Membership is inactive.");
    const perms = ((_m = memberData.permissions) !== null && _m !== void 0 ? _m : {});
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
    }
    // ─────────────────────────────────────────────────────────────
    // Validate role exists
    // ─────────────────────────────────────────────────────────────
    const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
    logger_1.logger.info("[inviteMember] role lookup", { roleRef: roleRef.path, roleId });
    const roleSnap = await roleRef.get();
    if (!roleSnap.exists) {
        logger_1.logger.warn("[inviteMember] role missing", { clinicId, roleId, roleRef: roleRef.path });
        throw new https_1.HttpsError("invalid-argument", "Role does not exist.");
    }
    // ─────────────────────────────────────────────────────────────
    // Create invite token (store hash only)
    // ─────────────────────────────────────────────────────────────
    const rawToken = (0, hash_1.generateToken)();
    const tokenHash = (0, hash_1.hashToken)(rawToken);
    const inviteRef = db.collection("clinics").doc(clinicId).collection("invites").doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 60 * 60 * 24 * 7);
    logger_1.logger.info("[inviteMember] creating invite doc", {
        clinicId,
        inviteRef: inviteRef.path,
        inviteEmail: email,
        inviteRoleId: roleId,
        expiresAtMs: expiresAt.toMillis(),
    });
    await inviteRef.set({
        clinicId,
        email,
        roleId,
        tokenHash,
        status: "pending",
        createdByUid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
    });
    logger_1.logger.info("[inviteMember] invite doc written", {
        clinicId,
        inviteId: inviteRef.id,
    });
    // ─────────────────────────────────────────────────────────────
    // Load clinic + config needed for email params
    // ─────────────────────────────────────────────────────────────
    const clinicRef = db.collection("clinics").doc(clinicId);
    logger_1.logger.info("[inviteMember] loading clinic doc", { clinicRef: clinicRef.path });
    const clinicSnap = await clinicRef.get();
    const clinicData = (_o = clinicSnap.data()) !== null && _o !== void 0 ? _o : {};
    logger_1.logger.info("[inviteMember] clinic loaded", {
        clinicId,
        clinicDocExists: clinicSnap.exists,
        hasProfileName: !!((_p = clinicData === null || clinicData === void 0 ? void 0 : clinicData.profile) === null || _p === void 0 ? void 0 : _p.name),
        hasLogoUrl: !!((clinicData === null || clinicData === void 0 ? void 0 : clinicData.logoUrl) || ((_q = clinicData === null || clinicData === void 0 ? void 0 : clinicData.profile) === null || _q === void 0 ? void 0 : _q.logoUrl)),
    });
    const clinicName = safeStr((_r = clinicData === null || clinicData === void 0 ? void 0 : clinicData.profile) === null || _r === void 0 ? void 0 : _r.name) || safeStr(clinicData === null || clinicData === void 0 ? void 0 : clinicData.name) || clinicId;
    const clinicLogoUrl = safeStr(clinicData === null || clinicData === void 0 ? void 0 : clinicData.logoUrl) || safeStr((_s = clinicData === null || clinicData === void 0 ? void 0 : clinicData.profile) === null || _s === void 0 ? void 0 : _s.logoUrl) || "";
    const inviterEmailLocal = safeStr(memberData.invitedEmail)
        ? safeStr(memberData.invitedEmail).split("@")[0]
        : "";
    const inviterName = safeStr(memberData.displayName) ||
        safeStr(memberData.fullName) ||
        inviterEmailLocal ||
        safeStr((_t = req.auth.token) === null || _t === void 0 ? void 0 : _t.name) ||
        safeStr((_u = req.auth.token) === null || _u === void 0 ? void 0 : _u.displayName) ||
        "A team member";
    logger_1.logger.info("[inviteMember] derived email params (pre-config)", {
        clinicId,
        clinicName,
        clinicLogoUrlPresent: !!clinicLogoUrl,
        inviterName,
        roleName: roleLabel(roleId),
    });
    // ─────────────────────────────────────────────────────────────
    // Brevo send
    // ─────────────────────────────────────────────────────────────
    const cfg = await loadInviteEmailConfig(clinicId);
    // ✅ DEBUG: what config did we resolve?
    logger_1.logger.info("[inviteMember] invite email config resolved", {
        clinicId,
        enabled: cfg.enabled,
        templateId: cfg.templateId,
        inviteBaseUrl: cfg.inviteBaseUrl,
        senderId: cfg.senderId,
        replyToEmailPresent: !!cfg.replyToEmail,
    });
    const templateId = pickFirst(cfg.templateId);
    if (!templateId) {
        logger_1.logger.error("[inviteMember] Invite templateId missing", {
            clinicId,
            expectedPath: `clinics/${clinicId}/settings/notifications ` +
                `(events.members.invite.templateIdByLocale.${cfg.defaultLocale})`,
        });
        throw new https_1.HttpsError("failed-precondition", "Invite email templateId not configured.");
    }
    if (!cfg.inviteBaseUrl) {
        logger_1.logger.error("[inviteMember] Invite base URL missing", {
            clinicId,
            expectedPath: `clinics/${clinicId}/settings/notifications ` + `(events.members.invite.inviteBaseUrl)`,
            example: "https://kineticdx-v3-dev.web.app/#/accept-invite",
        });
        throw new https_1.HttpsError("failed-precondition", "Invite base URL not configured.");
    }
    // Build accept URL: use query param token
    const compositeToken = `${clinicId}.${rawToken}`;

const acceptInviteUrl = cfg.inviteBaseUrl.includes("?")
  ? `${cfg.inviteBaseUrl}&token=${encodeURIComponent(compositeToken)}`
  : `${cfg.inviteBaseUrl}?token=${encodeURIComponent(compositeToken)}`;

    logger_1.logger.info("[inviteMember] acceptInviteUrl built", { clinicId, acceptInviteUrl });
    if (cfg.enabled !== true) {
        logger_1.logger.warn("[inviteMember] Invite emailing disabled; invite created but email not sent", {
            clinicId,
            email,
            templateId,
        });
        return { success: true, inviteId: inviteRef.id, sent: false, token: rawToken, expiresAt };
    }
    const params = {
        clinic_name: clinicName,
        clinic_logo_url: clinicLogoUrl || null,
        inviter_name: inviterName,
        role_name: roleLabel(roleId),
        accept_invite_url: acceptInviteUrl,
        expires_in_days: 7,
    };
    logger_1.logger.info("[inviteMember] sending via Brevo", {
        clinicId,
        to: email,
        templateId,
        params,
    });
    await sendBrevoInviteEmail({
        apiKey: exports.BREVO_API_KEY.value(),
        toEmail: email,
        templateId: Number(templateId),
        senderId: cfg.senderId,
        replyToEmail: cfg.replyToEmail,
        params,
    });
    logger_1.logger.info("[inviteMember] completed", {
        clinicId,
        inviteId: inviteRef.id,
        sent: true,
    });
    return { success: true, inviteId: inviteRef.id, sent: true, expiresAt };
}
//# sourceMappingURL=inviteMember.js.map
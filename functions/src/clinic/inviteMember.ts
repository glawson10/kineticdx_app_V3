// functions/src/clinic/inviteMember.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { generateToken, hashToken } from "./hash";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type InviteMemberInput = {
  clinicId: string;
  email: string;
  roleId: string; // role template id (e.g. "clinician", "reception", etc.)
  /** Optional override: if set, stored on invite and used on accept instead of role template. */
  permissions?: Record<string, boolean>;
};

type AnyMap = Record<string, any>;

function normEmail(v: unknown): string {
  return (v ?? "").toString().trim().toLowerCase();
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function nonEmptyOrNull(v: unknown): string | null {
  const s = safeStr(v);
  return s ? s : null;
}

function pickFirst<T>(...vals: Array<T | undefined | null>): T | undefined {
  for (const v of vals) {
    if (v !== undefined && v !== null) return v;
  }
  return undefined;
}

function roleLabel(roleId: string): string {
  const r = safeStr(roleId);
  if (!r) return "Staff";
  const spaced = r.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/[._-]+/g, " ");
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

/**
 * Reads invite email config:
 * clinics/{clinicId}/settings/notifications
 *
 * Expected:
 * - brevo.senderId
 * - brevo.replyToEmail
 * - events["members.invite"].enabled
 * - events["members.invite"].templateIdByLocale.en = <number>
 *
 * Recommended:
 * - events["members.invite"].inviteBaseUrl
 *   e.g. https://kineticdx-v3-dev.web.app/#/invite/accept
 */
async function loadInviteEmailConfig(clinicId: string) {
  const notifRef = db.doc(`clinics/${clinicId}/settings/notifications`);
  const snap = await notifRef.get();
  const settings = (snap.exists ? (snap.data() ?? {}) : null) as AnyMap | null;

  const defaultLocale = safeStr(settings?.defaultLocale) || "en";

  const senderId = (settings?.brevo?.senderId ?? null) as number | null;
  const replyToEmail = nonEmptyOrNull(settings?.brevo?.replyToEmail);

  const eventKey = "members.invite";
  const eventCfg = (settings?.events?.[eventKey] ?? {}) as AnyMap;

  const templateId =
    pickFirst<number>(
      eventCfg?.templateIdByLocale?.[defaultLocale],
      eventCfg?.templateIdByLocale?.["en"]
    ) ?? null;

  const enabled = eventCfg?.enabled === true;

  const inviteBaseUrl = nonEmptyOrNull(eventCfg?.inviteBaseUrl);

  // ✅ DEBUG (safe: no secrets)
  logger.info("[inviteMember] loadInviteEmailConfig()", {
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
    raw: settings,
  };
}

/**
 * Sends invite email via Brevo Transactional Email API.
 * Uses template variables via `params`.
 */
async function sendBrevoInviteEmail(args: {
  apiKey: string;
  toEmail: string;
  templateId: number;
  senderId: number | null;
  replyToEmail: string | null;
  params: Record<string, any>;
}) {
  const { apiKey, toEmail, templateId, senderId, replyToEmail, params } = args;

  const payload: AnyMap = {
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
  logger.info("[Brevo] about to send invite email", {
    toEmail,
    templateId,
    senderId,
    replyToEmailPresent: !!replyToEmail,
    paramsKeys: Object.keys(params ?? {}),
    accept_invite_url: params?.accept_invite_url,
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
    logger.error("[Brevo] sendTransacEmail failed", {
      status: res.status,
      body: text?.slice(0, 1200),
    });
    throw new HttpsError("internal", `Brevo send failed (${res.status})`);
  }

  logger.info("[Brevo] invite email sent", {
    toEmail,
    templateId,
    resp: text?.slice(0, 600),
  });
}

export async function inviteMember(req: CallableRequest<InviteMemberInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  // ✅ DEBUG: confirm function entry + inputs
  logger.info("[inviteMember] called", {
    clinicId: (req.data as any)?.clinicId,
    email: (req.data as any)?.email,
    roleId: (req.data as any)?.roleId,
    uid: req.auth?.uid,
  });

  const clinicId = safeStr(req.data?.clinicId);
  const email = normEmail(req.data?.email);
  const roleId = safeStr(req.data?.roleId);

  if (!clinicId || !email || !roleId) {
    logger.warn("[inviteMember] invalid arguments", { clinicId, email, roleId });
    throw new HttpsError("invalid-argument", "clinicId, email, roleId are required.");
  }

  const uid = req.auth.uid;

  // ─────────────────────────────────────────────────────────────
  // Authorize inviter (canonical members first, legacy fallback)
  // ─────────────────────────────────────────────────────────────
  const canonMemberRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
  const legacyMemberRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("memberships")
    .doc(uid);

  logger.info("[inviteMember] authz lookup", {
    clinicId,
    uid,
    canonPath: canonMemberRef.path,
    legacyPath: legacyMemberRef.path,
  });

  const canonSnap = await canonMemberRef.get();
  const legacySnap = canonSnap.exists ? null : await legacyMemberRef.get();

  logger.info("[inviteMember] authz snapshots", {
    clinicId,
    uid,
    canonExists: canonSnap.exists,
    legacyExists: legacySnap?.exists ?? false,
  });

  const memberData = (canonSnap.exists ? canonSnap.data() : legacySnap?.data()) as AnyMap | undefined;

  if (!memberData) {
    logger.warn("[inviteMember] inviter is not a clinic member", { clinicId, uid });
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  // Back-compat: treat missing active as active
  const isActive = memberData.active === false ? false : true;

  logger.info("[inviteMember] authz memberData", {
    clinicId,
    uid,
    isActive,
    roleId: (memberData.roleId ?? memberData.role ?? null) as any,
    hasMembersManage: ((memberData.permissions ?? {}) as AnyMap)["members.manage"] === true,
  });

  if (!isActive) throw new HttpsError("permission-denied", "Membership is inactive.");

  const perms = (memberData.permissions ?? {}) as AnyMap;
  if (perms["members.manage"] !== true) {
    throw new HttpsError("permission-denied", "Insufficient permissions.");
  }

  // ─────────────────────────────────────────────────────────────
  // Resolve permissions: optional override, else from role
  // ─────────────────────────────────────────────────────────────
  const permissionsOverride = req.data?.permissions as Record<string, boolean> | undefined;
  let invitePermissions: Record<string, boolean> | undefined;

  if (permissionsOverride && typeof permissionsOverride === "object") {
    invitePermissions = {};
    for (const k of Object.keys(permissionsOverride)) {
      if (permissionsOverride[k] === true) invitePermissions[k] = true;
    }
    logger.info("[inviteMember] using permissions override", {
      keys: Object.keys(invitePermissions),
    });
  }

  const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
  logger.info("[inviteMember] role lookup", { roleRef: roleRef.path, roleId });
  const roleSnap = await roleRef.get();
  if (!roleSnap.exists) {
    logger.warn("[inviteMember] role missing", { clinicId, roleId, roleRef: roleRef.path });
    throw new HttpsError("invalid-argument", "Role does not exist.");
  }

  // ─────────────────────────────────────────────────────────────
  // Create invite token (store hash only; raw token never stored)
  // ─────────────────────────────────────────────────────────────
  const rawToken = generateToken();
  const tokenHash = hashToken(rawToken);

  const inviteRef = db.collection("clinics").doc(clinicId).collection("invites").doc();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 60 * 60 * 24 * 7);

  logger.info("[inviteMember] creating invite doc", {
    clinicId,
    inviteRef: inviteRef.path,
    inviteEmail: email,
    inviteRoleId: roleId,
    expiresAtMs: expiresAt.toMillis(),
  });

  const inviteData: AnyMap = {
    clinicId,
    email,
    roleId,
    role: roleId,
    tokenHash,
    status: "active",
    createdByUid: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt,
  };
  if (invitePermissions) inviteData.permissions = invitePermissions;
  await inviteRef.set(inviteData);

  logger.info("[inviteMember] invite doc written", {
    clinicId,
    inviteId: inviteRef.id,
  });

  // ─────────────────────────────────────────────────────────────
  // Load clinic + config needed for email params
  // ─────────────────────────────────────────────────────────────
  const clinicRef = db.collection("clinics").doc(clinicId);
  logger.info("[inviteMember] loading clinic doc", { clinicRef: clinicRef.path });

  const clinicSnap = await clinicRef.get();
  const clinicData = (clinicSnap.data() ?? {}) as AnyMap;

  logger.info("[inviteMember] clinic loaded", {
    clinicId,
    clinicDocExists: clinicSnap.exists,
    hasProfileName: !!clinicData?.profile?.name,
    hasLogoUrl: !!(clinicData?.logoUrl || clinicData?.profile?.logoUrl),
  });

  const clinicName =
    safeStr(clinicData?.profile?.name) || safeStr(clinicData?.name) || clinicId;

  const clinicLogoUrl =
    safeStr(clinicData?.logoUrl) || safeStr(clinicData?.profile?.logoUrl) || "";

  const inviterEmailLocal = safeStr(memberData.invitedEmail)
    ? safeStr(memberData.invitedEmail).split("@")[0]
    : "";

  const inviterName =
    safeStr(memberData.displayName) ||
    safeStr(memberData.fullName) ||
    inviterEmailLocal ||
    safeStr(req.auth.token?.name) ||
    safeStr(req.auth.token?.displayName) ||
    "A team member";

  logger.info("[inviteMember] derived email params (pre-config)", {
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

  logger.info("[inviteMember] invite email config resolved", {
    clinicId,
    enabled: cfg.enabled,
    templateId: cfg.templateId,
    inviteBaseUrl: cfg.inviteBaseUrl,
    senderId: cfg.senderId,
    replyToEmailPresent: !!cfg.replyToEmail,
  });

  const templateId = pickFirst(cfg.templateId);
  if (!templateId) {
    logger.error("[inviteMember] Invite templateId missing", {
      clinicId,
      expectedPath:
        `clinics/${clinicId}/settings/notifications ` +
        `(events["members.invite"].templateIdByLocale.${cfg.defaultLocale})`,
    });
    throw new HttpsError("failed-precondition", "Invite email templateId not configured.");
  }

  if (!cfg.inviteBaseUrl) {
    logger.error("[inviteMember] Invite base URL missing", {
      clinicId,
      expectedPath:
        `clinics/${clinicId}/settings/notifications ` +
        `(events["members.invite"].inviteBaseUrl)`,
      example: "https://kineticdx-v3-dev.web.app/#/invite/accept",
    });
    throw new HttpsError("failed-precondition", "Invite base URL not configured.");
  }

  // ✅ Composite token for acceptInvite: "<clinicId>.<rawToken>"
  const compositeToken = `${clinicId}.${rawToken}`;

  const acceptInviteUrl = cfg.inviteBaseUrl.includes("?")
    ? `${cfg.inviteBaseUrl}&token=${encodeURIComponent(compositeToken)}`
    : `${cfg.inviteBaseUrl}?token=${encodeURIComponent(compositeToken)}`;

  logger.info("[inviteMember] acceptInviteUrl built", { clinicId, acceptInviteUrl });

  const inviteLink = `${clinicId}.${rawToken}`;

  if (cfg.enabled !== true) {
    logger.warn("[inviteMember] Invite emailing disabled; invite created but email not sent", {
      clinicId,
      email,
      templateId,
    });
    return {
      success: true,
      inviteId: inviteRef.id,
      inviteLink,
      sent: false,
      expiresAt,
    };
  }

  const params = {
    clinic_name: clinicName,
    clinic_logo_url: clinicLogoUrl || null,
    inviter_name: inviterName,
    role_name: roleLabel(roleId),
    accept_invite_url: acceptInviteUrl,
    expires_in_days: 7,
  };

  logger.info("[inviteMember] sending via Brevo", {
    clinicId,
    to: email,
    templateId,
    paramsKeys: Object.keys(params),
  });

  await sendBrevoInviteEmail({
    apiKey: process.env.BREVO_API_KEY!,
    toEmail: email,
    templateId: Number(templateId),
    senderId: cfg.senderId,
    replyToEmail: cfg.replyToEmail,
    params,
  });

  logger.info("[inviteMember] completed", {
    clinicId,
    inviteId: inviteRef.id,
    sent: true,
  });

  return {
    success: true,
    inviteId: inviteRef.id,
    inviteLink,
    sent: true,
    expiresAt,
  };
}

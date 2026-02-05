// functions/src/clinic/onClinicCreatedProvisionOwner.ts
import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";
import { ownerRolePermissions } from "./roleTemplates";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function pickOwnerDisplayName(clinic: AnyMap): string {
  const fromClinic =
    safeStr(clinic?.createdByName) ||
    safeStr(clinic?.createdByDisplayName) ||
    safeStr(clinic?.profile?.ownerName);
  if (fromClinic) return fromClinic;

  const email = safeStr(clinic?.createdByEmail);
  if (email && email.includes("@")) return email.split("@")[0];

  return "Owner";
}

export const onClinicCreatedProvisionOwnerMembership = onDocumentCreated(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}",
  },
  async (event) => {
    const clinicId = safeStr(event.params.clinicId);
    if (!clinicId) return;

    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    const clinic = (clinicSnap.data() ?? {}) as AnyMap;

    const ownerUid =
      safeStr(clinic?.ownerUid) || safeStr(clinic?.createdByUid);

    if (!ownerUid) {
      logger.warn("Clinic has no ownerUid/createdByUid; cannot provision owner", {
        clinicId,
      });
      return;
    }

    const displayName = pickOwnerDisplayName(clinic);
    const invitedEmail = safeStr(clinic?.createdByEmail) || null;

    const now = admin.firestore.FieldValue.serverTimestamp();

    const canonRef = db
      .collection("clinics")
      .doc(clinicId)
      .collection("memberships")
      .doc(ownerUid);

    const canonSnap = await canonRef.get();
    if (canonSnap.exists) {
      logger.info("Owner membership already exists; skipping", {
        clinicId,
        ownerUid,
        path: canonRef.path,
      });
      return;
    }

    logger.info("Provisioning missing owner membership", {
      clinicId,
      ownerUid,
    });

    const batch = db.batch();

    batch.set(canonRef, {
      role: "owner",
      roleId: "owner",
      displayName,
      invitedEmail,
      permissions: ownerRolePermissions(),
      status: "active",
      active: true,
      createdAt: now,
      updatedAt: now,
      createdByUid: ownerUid,
      updatedByUid: ownerUid,
    });

    // Optional legacy mirror during migration window
    const legacyRef = db
      .collection("clinics")
      .doc(clinicId)
      .collection("members")
      .doc(ownerUid);

    batch.set(
      legacyRef,
      {
        roleId: "owner",
        displayName,
        invitedEmail,
        permissions: ownerRolePermissions(),
        active: true,
        createdAt: now,
        updatedAt: now,
        createdByUid: ownerUid,
        updatedByUid: ownerUid,
      },
      { merge: true }
    );

    // Ensure user index exists too (clinic picker)
    const clinicName =
      safeStr(clinic?.profile?.name) || safeStr(clinic?.name) || clinicId;

    const userIdxRef = db
      .collection("users")
      .doc(ownerUid)
      .collection("memberships")
      .doc(clinicId);

    batch.set(
      userIdxRef,
      {
        clinicNameCache: clinicName,
        role: "owner",
        roleId: "owner",
        status: "active",
        active: true,
        createdAt: now,
      },
      { merge: true }
    );

    await batch.commit();

    logger.info("Owner membership provisioned", {
      clinicId,
      ownerUid,
    });
  }
);

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

type PublicPractitioner = {
  practitionerId: string;
  displayName: string;
  active: boolean;
  activeForBooking: boolean;
  showInPublicBooking: boolean;
  sortOrder?: number;
  title?: string;
  photoUrl?: string;
  bio?: string;
  serviceIdsAllowed?: string[];
  allowedLocationIds?: string[];
};

async function rebuildPublicPractitionerMirrors(clinicId: string) {
  const db = admin.firestore();

  const dirSnap = await db
    .collection(`clinics/${clinicId}/public/directory/practitioners`)
    .get();

  const list: PublicPractitioner[] = dirSnap.docs.map((d) => {
    const data = d.data() ?? {};
    const entry: PublicPractitioner = {
      practitionerId: String(data.practitionerId ?? d.id),
      displayName: String(data.displayName ?? "").trim(),
      active: Boolean(data.active ?? false),
      activeForBooking: data.activeForBooking !== false,
      showInPublicBooking: data.showInPublicBooking === true,
    };
    if (typeof data.sortOrder === "number") entry.sortOrder = data.sortOrder;
    if (data.title) entry.title = String(data.title).trim();
    if (data.photoUrl) entry.photoUrl = String(data.photoUrl).trim();
    if (data.bio) entry.bio = String(data.bio).trim();
    if (Array.isArray(data.serviceIdsAllowed)) entry.serviceIdsAllowed = data.serviceIdsAllowed;
    if (Array.isArray(data.allowedLocationIds)) entry.allowedLocationIds = data.allowedLocationIds;
    return entry;
  });

  const payload = {
    // UI might expect this exact nesting
    publicBooking: { practitioners: list },

    // Some code might expect a top-level list
    practitioners: list,

    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: "mirrorPractitionerToPublic.rebuildMirrors",
  };

  const refA = db.doc(`clinics/${clinicId}/public/config/publicBooking`);
  const refB = db.doc(`clinics/${clinicId}/public/publicBooking`);

  console.log("rebuild mirrors", {
    clinicId,
    count: list.length,
    refA: refA.path,
    refB: refB.path,
  });

  await Promise.all([
    refA.set(payload, { merge: true }),
    refB.set(payload, { merge: true }),
  ]);
}

export const mirrorPractitionerToPublic = onDocumentWritten(
  {
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
    region: "europe-west3",
  },
  async (event) => {
    const { clinicId, practitionerId } = event.params;

    console.log("mirrorPractitionerToPublic fired", { clinicId, practitionerId });

    try {
      const afterSnap = event.data?.after;

      const publicDirRef = admin
        .firestore()
        .doc(
          `clinics/${clinicId}/public/directory/practitioners/${practitionerId}`
        );

      // Delete
      if (!afterSnap?.exists) {
        console.log("deleted -> removing directory doc", publicDirRef.path);
        await publicDirRef.delete().catch(() => {});
        await rebuildPublicPractitionerMirrors(clinicId);
        return;
      }

      const data = afterSnap.data() ?? {};

      const dirPayload: Record<string, any> = {
        practitionerId,
        displayName: String(data.displayName ?? "").trim(),
        active: Boolean(data.active ?? false),
        activeForBooking: data.activeForBooking !== false,
        showInPublicBooking: data.showInPublicBooking === true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "mirrorPractitionerToPublic",
      };
      if (typeof data.sortOrder === "number") dirPayload.sortOrder = data.sortOrder;
      if (data.title) dirPayload.title = String(data.title).trim();
      if (data.photoUrl) dirPayload.photoUrl = String(data.photoUrl).trim();
      if (data.bio) dirPayload.bio = String(data.bio).trim();
      if (Array.isArray(data.serviceIdsAllowed)) dirPayload.serviceIdsAllowed = data.serviceIdsAllowed;
      if (Array.isArray(data.allowedLocationIds)) dirPayload.allowedLocationIds = data.allowedLocationIds;

      console.log("writing directory doc", { path: publicDirRef.path, dirPayload });
      await publicDirRef.set(dirPayload, { merge: true });

      await rebuildPublicPractitionerMirrors(clinicId);

      console.log("mirrorPractitionerToPublic complete");
    } catch (err: any) {
      console.error("mirrorPractitionerToPublic FAILED", err?.message ?? err, err);
      throw err;
    }
  }
);

// functions/src/clinic/notes/_helpers.ts
import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { Firestore } from "firebase-admin/firestore";

export type PermissionMap = Record<string, boolean>;

export type MemberRecord = {
  active: boolean;
  roleId?: string | null;
  permissions?: PermissionMap;
};

export async function requireAuthAndClinicId(req: CallableRequest<any>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const clinicId = (req.data?.clinicId ?? "").trim();
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId required.");
  return { uid: req.auth.uid, clinicId };
}

export async function requireActiveMember(
  db: Firestore,
  clinicId: string,
  uid: string
): Promise<MemberRecord> {
  const memberRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .doc(uid);

  const snap = await memberRef.get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Not a clinic member.");

  const data = snap.data() as any;
  if (data.active !== true) throw new HttpsError("permission-denied", "Membership inactive.");

  return data as MemberRecord;
}

export async function requirePerm(
  db: Firestore,
  clinicId: string,
  uid: string,
  perm: string
) {
  const member = await requireActiveMember(db, clinicId, uid);
  const perms: PermissionMap = member.permissions ?? {};
  if (perms[perm] !== true) {
    throw new HttpsError("permission-denied", `Missing permission: ${perm}`);
  }
  return member;
}

export async function hasPerm(
  db: Firestore,
  clinicId: string,
  uid: string,
  perm: string
): Promise<boolean> {
  try {
    await requirePerm(db, clinicId, uid, perm);
    return true;
  } catch {
    return false;
  }
}

/**
 * Notes write context:
 * - everyone who writes notes must have notes.write.own
 * - manager override is notes.write.any
 */
export async function requireNotesWriteContext(req: CallableRequest<any>) {
  const { uid, clinicId } = await requireAuthAndClinicId(req);
  const db = admin.firestore();

  // baseline write permission
  const member = await requirePerm(db, clinicId, uid, "notes.write.own");
  const perms: PermissionMap = member.permissions ?? {};

  // override permission
  const canWriteAny = perms["notes.write.any"] === true;

  return { db, clinicId, uid, member, perms, canWriteAny };
}

/**
 * Episode existence + reference
 */
export async function requireEpisodeExists(params: {
  db: Firestore;
  clinicId: string;
  patientId: string;
  episodeId: string;
}) {
  const { db, clinicId, patientId, episodeId } = params;

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("patients")
    .doc(patientId)
    .collection("episodes")
    .doc(episodeId);

  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Episode not found.");

  return { episodeRef: ref, episode: snap.data() as any };
}

/**
 * Note existence + reference (Phase 5.3 canonical path: episodes/{episodeId}/notes/{noteId})
 */
export async function requireNoteExists(params: {
  db: Firestore;
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteId: string;
}) {
  const { db, clinicId, patientId, episodeId, noteId } = params;

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("patients")
    .doc(patientId)
    .collection("episodes")
    .doc(episodeId)
    .collection("notes")
    .doc(noteId);

  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Note not found.");

  return { noteRef: ref, note: snap.data() as any };
}

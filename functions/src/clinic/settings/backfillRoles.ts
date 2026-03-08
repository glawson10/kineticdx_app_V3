import { HttpsError } from "firebase-functions/v2/https";

export async function backfillRoles(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "backfillRoles not implemented");
}

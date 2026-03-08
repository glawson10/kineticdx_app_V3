import { HttpsError } from "firebase-functions/v2/https";

export async function backfillMemberPermissions(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "backfillMemberPermissions not implemented");
}

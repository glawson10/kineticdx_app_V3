import { HttpsError } from "firebase-functions/v2/https";

export async function issueCreditNote(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "issueCreditNote not implemented");
}

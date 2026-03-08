import { HttpsError } from "firebase-functions/v2/https";

export async function updateBillingSettings(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "updateBillingSettings not implemented");
}

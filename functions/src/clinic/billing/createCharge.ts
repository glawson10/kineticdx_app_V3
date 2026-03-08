import { HttpsError } from "firebase-functions/v2/https";

export async function createCharge(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "createCharge not implemented");
}

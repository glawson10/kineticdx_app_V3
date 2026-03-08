import { HttpsError } from "firebase-functions/v2/https";

export async function getMembership(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getMembership not implemented");
}

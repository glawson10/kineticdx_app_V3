import { HttpsError } from "firebase-functions/v2/https";

export async function setLocationActive(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "setLocationActive not implemented");
}

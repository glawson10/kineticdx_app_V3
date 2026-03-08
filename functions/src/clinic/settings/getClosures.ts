import { HttpsError } from "firebase-functions/v2/https";

export async function getClosures(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getClosures not implemented");
}

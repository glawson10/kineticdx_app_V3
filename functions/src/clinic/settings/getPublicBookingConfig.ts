import { HttpsError } from "firebase-functions/v2/https";

export async function getPublicBookingConfig(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getPublicBookingConfig not implemented");
}

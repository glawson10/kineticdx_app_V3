import { HttpsError } from "firebase-functions/v2/https";

export async function updateOnlineBookingEnablement(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "updateOnlineBookingEnablement not implemented");
}

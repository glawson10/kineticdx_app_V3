import { HttpsError } from "firebase-functions/v2/https";

export async function getCalendarDisplayConfig(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getCalendarDisplayConfig not implemented");
}

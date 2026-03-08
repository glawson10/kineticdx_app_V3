import { HttpsError } from "firebase-functions/v2/https";

export async function getClinicProfile(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getClinicProfile not implemented");
}

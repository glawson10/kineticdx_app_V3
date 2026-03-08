import { HttpsError } from "firebase-functions/v2/https";

export async function updateAppointmentOccurrence(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "updateAppointmentOccurrence not implemented");
}

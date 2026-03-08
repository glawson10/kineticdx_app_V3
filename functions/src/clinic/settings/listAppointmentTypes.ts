import { HttpsError } from "firebase-functions/v2/https";

export async function listAppointmentTypes(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "listAppointmentTypes not implemented");
}

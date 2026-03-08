import { HttpsError } from "firebase-functions/v2/https";

export async function createAppointmentSeries(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "createAppointmentSeries not implemented");
}

import { HttpsError } from "firebase-functions/v2/https";

export async function updateAppointmentSeries(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "updateAppointmentSeries not implemented");
}

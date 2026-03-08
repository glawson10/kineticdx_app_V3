import { HttpsError } from "firebase-functions/v2/https";

export async function splitAppointmentSeries(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "splitAppointmentSeries not implemented");
}

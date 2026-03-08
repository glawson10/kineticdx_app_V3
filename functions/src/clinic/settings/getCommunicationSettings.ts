import { HttpsError } from "firebase-functions/v2/https";

export async function getCommunicationSettings(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getCommunicationSettings not implemented");
}

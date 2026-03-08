import { HttpsError } from "firebase-functions/v2/https";

export async function listLocations(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "listLocations not implemented");
}

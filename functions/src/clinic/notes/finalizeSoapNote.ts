import { HttpsError } from "firebase-functions/v2/https";

export async function finalizeSoapNote(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "finalizeSoapNote not implemented");
}

export async function unfinalizeSoapNote(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "unfinalizeSoapNote not implemented");
}

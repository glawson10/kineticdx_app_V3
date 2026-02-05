import { HttpsError } from "firebase-functions/v2/https";

export function requireAuth(auth: any) {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign-in required");
  }
  return auth.uid;
}

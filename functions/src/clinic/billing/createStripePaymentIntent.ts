import { HttpsError } from "firebase-functions/v2/https";

export async function createStripePaymentIntent(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "createStripePaymentIntent not implemented");
}

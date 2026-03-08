import { HttpsError } from "firebase-functions/v2/https";

export async function createInvoiceDraft(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "createInvoiceDraft not implemented");
}

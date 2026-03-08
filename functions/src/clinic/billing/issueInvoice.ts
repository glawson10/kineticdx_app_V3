import { HttpsError } from "firebase-functions/v2/https";

export async function issueInvoice(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "issueInvoice not implemented");
}

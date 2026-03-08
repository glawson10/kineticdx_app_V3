import { HttpsError } from "firebase-functions/v2/https";

export async function generateInvoicePdf(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "generateInvoicePdf not implemented");
}

export async function getInvoicePdfDownloadUrl(_request: { auth?: { uid?: string }; data?: unknown }) {
  throw new HttpsError("unimplemented", "getInvoicePdfDownloadUrl not implemented");
}

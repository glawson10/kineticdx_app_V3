import { asObject } from "./common";
import { createInvoice } from "./createInvoice";

export async function createInvoiceDraft(request: { auth?: { uid?: string }; data?: unknown }) {
  const data = asObject(request.data);
  return createInvoice({
    auth: request.auth,
    data: { ...data, status: "draft" },
  });
}

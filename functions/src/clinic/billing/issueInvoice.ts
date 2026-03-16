import { asObject } from "./common";
import { updateInvoice } from "./updateInvoice";

export async function issueInvoice(request: { auth?: { uid?: string }; data?: unknown }) {
  const data = asObject(request.data);
  return updateInvoice({
    auth: request.auth,
    data: {
      clinicId: data.clinicId,
      invoiceId: data.invoiceId,
      patch: { status: "issued" },
    },
  });
}

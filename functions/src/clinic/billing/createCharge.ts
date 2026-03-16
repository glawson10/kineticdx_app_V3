import { HttpsError } from "firebase-functions/v2/https";
import { asObject } from "./common";
import { createInvoice } from "./createInvoice";

export async function createCharge(request: { auth?: { uid?: string }; data?: unknown }) {
  const data = asObject(request.data);
  const lineItem = data.lineItem;
  if (!lineItem || typeof lineItem !== "object") {
    throw new HttpsError("invalid-argument", "lineItem is required.");
  }
  return createInvoice({
    auth: request.auth,
    data: {
      clinicId: data.clinicId,
      patientId: data.patientId,
      appointmentId: data.appointmentId,
      lineItems: [lineItem],
      status: "draft",
    },
  });
}

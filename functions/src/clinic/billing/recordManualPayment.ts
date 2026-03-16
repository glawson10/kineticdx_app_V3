import { recordPayment } from "./recordPayment";

export async function recordManualPayment(request: { auth?: { uid?: string }; data?: unknown }) {
  return recordPayment(request);
}

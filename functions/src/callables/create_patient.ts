// functions/src/callables/create_patient.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

// ✅ Reuse the canonical clinic-scoped implementation
import { createPatient as createPatientClinic } from "../clinic/patients/createPatient";

type Input = {
  clinicId: string;
  firstName: string;
  lastName: string;
  dob: string; // YYYY-MM-DD recommended (or ISO)
  phone: string;
  email: string;
  address?: string;
};

export async function createPatient(req: CallableRequest<Input>) {
  // Keep the callable name/entry-point the same, but ensure one source of truth.
  try {
    return await createPatientClinic(req);
  } catch (err: any) {
    // If clinic version already throws HttpsError, preserve it.
    if (err instanceof HttpsError) throw err;

    throw new HttpsError("internal", "createPatient crashed. Check function logs.", {
      original: err?.message ?? String(err),
    });
  }
}

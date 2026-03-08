import { onDocumentWritten } from "firebase-functions/v2/firestore";

/** Stub: Public booking config mirror trigger. Replace with real implementation. */
export const onPublicBookingConfigMirror = onDocumentWritten(
  {
    document: "clinics/{clinicId}/public/config/publicBooking/config",
    region: "europe-west3",
  },
  async () => {}
);

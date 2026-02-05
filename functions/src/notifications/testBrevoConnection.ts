import { onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const BREVO_API_KEY = defineSecret("BREVO_API_KEY");

export const testBrevoConnection = onCall(
  {
    region: "europe-west3",
    secrets: [BREVO_API_KEY],
  },
  async () => {
    const res = await fetch("https://api.brevo.com/v3/account", {
      headers: {
        accept: "application/json",
        "api-key": BREVO_API_KEY.value(),
      },
    });

    if (!res.ok) {
      return {
        ok: false,
        status: res.status,
      };
    }

    return { ok: true };
  }
);

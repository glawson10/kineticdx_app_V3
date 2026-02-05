import { onCall } from "firebase-functions/v2/https";

export const testCallable = onCall(
  { region: "europe-west3" },
  async () => {
    return { ok: true, message: "Callable works" };
  }
);

export async function handleStripeWebhook(
  _req: import("firebase-functions/v2/https").Request,
  res: { status: (code: number) => { send: (body: string) => void } }
): Promise<void> {
  res.status(501).send("Stripe webhook not implemented");
}

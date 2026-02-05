import { defineSecret } from "firebase-functions/params";

export const BREVO_API_KEY = defineSecret("BREVO_API_KEY");

export type BrevoSendEmailInput = {
  senderId?: number;
  replyToEmail?: string;
  to: { email: string; name?: string }[];
  templateId: number;
  params?: Record<string, unknown>;
};

export type BrevoSendEmailResult = {
  messageId?: string;
};

export async function brevoSendTemplateEmail(
  input: BrevoSendEmailInput
): Promise<BrevoSendEmailResult> {
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      "api-key": BREVO_API_KEY.value(),
    },
    body: JSON.stringify({
      sender: input.senderId ? { id: input.senderId } : undefined,
      replyTo: input.replyToEmail ? { email: input.replyToEmail } : undefined,
      to: input.to,
      templateId: input.templateId,
      params: input.params ?? {},
    }),
  });

  const text = await res.text();
  if (!res.ok) {
    // Don't leak secrets; include status + truncated body
    throw new Error(`Brevo send failed: ${res.status} ${text.slice(0, 400)}`);
  }

  // Brevo returns JSON with messageId on success
  const data = JSON.parse(text) as { messageId?: string };
  return { messageId: data.messageId };
}

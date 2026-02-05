import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Add new event keys here as you introduce more transactional emails.
 */
export type NotificationEventKey =
  | "booking.created.patientConfirmation"
  | "booking.created.clinicianNotification"
  | "members.invite";

type RecipientPolicyMode = "practitionerOnAppointment" | "clinicInbox" | "both";

type EventSettings = {
  enabled?: boolean;

  /**
   * Brevo template id per locale, e.g.
   * templateIdByLocale: { en: 3, cs: 9 }
   */
  templateIdByLocale?: Record<string, number>;

  /**
   * Used by clinician notification event.
   * Ignored for events that don't need it.
   */
  recipientPolicy?: { mode: RecipientPolicyMode };

  /**
   * Used by members.invite.
   * This is the base URL to your accept invite route.
   * Example (dev):
   *   https://kineticdx-v3-dev.web.app/#/accept-invite
   */
  inviteBaseUrl?: string;
};

export type NotificationSettings = {
  schemaVersion?: number;
  defaultLocale?: string;

  brevo?: {
    senderId?: number;
    replyToEmail?: string;
  };

  events?: Record<string, EventSettings>;
};

export async function getClinicNotificationSettings(
  clinicId: string
): Promise<NotificationSettings> {
  const snap = await db.doc(`clinics/${clinicId}/settings/notifications`).get();
  return (snap.exists ? (snap.data() as NotificationSettings) : {}) ?? {};
}

export function resolveTemplateId(
  settings: NotificationSettings,
  eventId: NotificationEventKey,
  locale?: string
): number | null {
  const ev = settings.events?.[eventId];
  if (!ev?.enabled) return null;

  const loc = (locale || settings.defaultLocale || "en").toLowerCase();
  const byLoc = ev.templateIdByLocale ?? {};
  return byLoc[loc] ?? byLoc["en"] ?? null;
}

/**
 * Invite emails need a base URL to build:
 *   <inviteBaseUrl>?token=...
 *
 * We keep this clinic-scoped and event-scoped so you can change it per clinic.
 */
export function resolveInviteBaseUrl(settings: NotificationSettings): string | null {
  const ev = settings.events?.["members.invite"];
  if (!ev?.enabled) return null;

  const raw = (ev.inviteBaseUrl ?? "").toString().trim();
  if (!raw) return null;

  return raw;
}

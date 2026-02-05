import * as admin from "firebase-admin";
import { brevoSendTemplateEmail } from "./brevo";
import {
  getClinicNotificationSettings,
  resolveTemplateId,
  NotificationEventKey,
} from "./notificationSettings";

const db = admin.firestore();

function redactEmail(email: string): string {
  const at = email.indexOf("@");
  if (at <= 1) return "***";
  return `${email[0]}***${email.slice(at - 1)}`;
}

async function writeLog(params: {
  clinicId: string;
  eventId: NotificationEventKey;
  appointmentPath: string;
  toEmail: string;
  status: "accepted" | "skipped" | "error";
  messageId?: string;
  errorMessage?: string;
}) {
  await db.collection(`clinics/${params.clinicId}/notificationLogs`).add({
    eventId: params.eventId,
    appointmentPath: params.appointmentPath,
    to: redactEmail(params.toEmail),
    provider: "brevo",
    messageId: params.messageId ?? null,
    status: params.status,
    errorMessage: params.errorMessage ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export type BookingNotificationContext = {
  clinicId: string;
  appointmentPath: string; // e.g. clinics/{clinicId}/appointments/{id}
  locale?: string;

  patient: { email: string; name?: string };
  clinician?: { email?: string; name?: string };
  clinicInboxEmail?: string;

  templateParams: Record<string, unknown>; // passed into Brevo template
};

export async function sendBookingNotifications(ctx: BookingNotificationContext) {
  const settings = await getClinicNotificationSettings(ctx.clinicId);
  const senderId = settings.brevo?.senderId;
  const replyToEmail = settings.brevo?.replyToEmail;

  // 1) Patient confirmation
  await sendOne({
    clinicId: ctx.clinicId,
    appointmentPath: ctx.appointmentPath,
    settings,
    eventId: "booking.created.patientConfirmation",
    locale: ctx.locale,
    to: [{ email: ctx.patient.email, name: ctx.patient.name }],
    senderId,
    replyToEmail,
    params: ctx.templateParams,
  });

  // 2) Clinician notification (optional)
  const mode =
    settings.events?.["booking.created.clinicianNotification"]?.recipientPolicy
      ?.mode ?? "practitionerOnAppointment";

  const clinicianEmail = ctx.clinician?.email;
  const inboxEmail = ctx.clinicInboxEmail;

  const recipients: { email: string; name?: string }[] = [];
  if (mode === "practitionerOnAppointment" || mode === "both") {
    if (clinicianEmail) recipients.push({ email: clinicianEmail, name: ctx.clinician?.name });
  }
  if (mode === "clinicInbox" || mode === "both") {
    if (inboxEmail) recipients.push({ email: inboxEmail });
  }

  if (recipients.length > 0) {
    await sendOne({
      clinicId: ctx.clinicId,
      appointmentPath: ctx.appointmentPath,
      settings,
      eventId: "booking.created.clinicianNotification",
      locale: ctx.locale,
      to: recipients,
      senderId,
      replyToEmail,
      params: ctx.templateParams,
    });
  }
}

async function sendOne(args: {
  clinicId: string;
  appointmentPath: string;
  settings: any;
  eventId: NotificationEventKey;
  locale?: string;
  to: { email: string; name?: string }[];
  senderId?: number;
  replyToEmail?: string;
  params: Record<string, unknown>;
}) {
  const templateId = resolveTemplateId(args.settings, args.eventId, args.locale);
  if (!templateId) {
    // Disabled or not configured
    await writeLog({
      clinicId: args.clinicId,
      eventId: args.eventId,
      appointmentPath: args.appointmentPath,
      toEmail: args.to[0]?.email ?? "unknown",
      status: "skipped",
    });
    return;
  }

  try {
    const result = await brevoSendTemplateEmail({
      senderId: args.senderId,
      replyToEmail: args.replyToEmail,
      to: args.to,
      templateId,
      params: args.params,
    });

    await writeLog({
      clinicId: args.clinicId,
      eventId: args.eventId,
      appointmentPath: args.appointmentPath,
      toEmail: args.to[0]?.email ?? "unknown",
      status: "accepted",
      messageId: result.messageId,
    });
  } catch (e: any) {
    await writeLog({
      clinicId: args.clinicId,
      eventId: args.eventId,
      appointmentPath: args.appointmentPath,
      toEmail: args.to[0]?.email ?? "unknown",
      status: "error",
      errorMessage: (e?.message ?? "Unknown error").toString().slice(0, 500),
    });
    throw e; // optional: rethrow or swallow depending on booking flow
  }
}

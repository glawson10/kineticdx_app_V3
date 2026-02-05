import * as admin from "firebase-admin";

function fmtGoogleUtc(ts: admin.firestore.Timestamp): string {
  // Google expects UTC format: YYYYMMDDTHHmmssZ
  return ts
    .toDate()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

export function buildGoogleCalendarUrl(params: {
  title: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
  details?: string;
  location?: string;
}): string {
  const qs = new URLSearchParams({
    action: "TEMPLATE",
    text: params.title,
    dates: `${fmtGoogleUtc(params.startAt)}/${fmtGoogleUtc(params.endAt)}`,
    details: params.details ?? "",
    location: params.location ?? "",
  });

  return `https://www.google.com/calendar/render?${qs.toString()}`;
}

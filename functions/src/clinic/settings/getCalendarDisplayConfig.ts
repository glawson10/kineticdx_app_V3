/**
 * settings.getCalendarDisplayConfig
 * Read-only. Returns normalized calendar display config from Firestore.
 * Read path: clinics/{clinicId}/settings/calendarDisplay
 * If doc is missing, returns default config (does not create the doc).
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { requireNonEmptyString } from "./validators";

const db = admin.firestore();

/** Default config when doc is missing. Aligned with Dart CalendarDisplaySettings.defaults. */
function getDefaultCalendarDisplayConfig(): Record<string, unknown> {
  return {
    displayStartHour: 7,
    displayEndHour: 20,
    slotMinutes: 15,
    slotHeightPx: 48,
    timePickerIncrement: 5,
    showCurrentTimeIndicator: true,
    hidePatientNames: false,
    confirmMove: true,
    showFinancialIndicators: false,
    showWaitlistMatches: true,
    smartOneDayView: false,
    defaultView: "week",
    weekStartsOn: "monday",
    showWeekends: true,
    showClosedDayLabel: true,
    condensedHeader: false,
    clientNameSeparateLine: false,
  };
}

/** Normalize stored doc to canonical response: legacy field names and slotMinutes from minutesPerBlock. */
function normalizeCalendarDisplayConfig(raw: Record<string, unknown> | undefined): Record<string, unknown> {
  const d = raw ?? {};
  const slotMinutes =
    (typeof d.slotMinutes === "number" && Number.isInteger(d.slotMinutes) ? d.slotMinutes : null) ??
    (typeof d.minutesPerBlock === "number" && Number.isInteger(d.minutesPerBlock) ? d.minutesPerBlock : null) ??
    15;
  const confirmMove =
    typeof d.confirmMove === "boolean"
      ? d.confirmMove
      : typeof d.confirmAppointmentMoves === "boolean"
        ? d.confirmAppointmentMoves
        : true;

  return {
    displayStartHour: typeof d.displayStartHour === "number" && Number.isInteger(d.displayStartHour) ? d.displayStartHour : 7,
    displayEndHour: typeof d.displayEndHour === "number" && Number.isInteger(d.displayEndHour) ? d.displayEndHour : 20,
    slotMinutes,
    slotHeightPx: typeof d.slotHeightPx === "number" ? d.slotHeightPx : 48,
    timePickerIncrement: typeof d.timePickerIncrement === "number" && Number.isInteger(d.timePickerIncrement) ? d.timePickerIncrement : 5,
    showCurrentTimeIndicator: typeof d.showCurrentTimeIndicator === "boolean" ? d.showCurrentTimeIndicator : true,
    hidePatientNames: typeof d.hidePatientNames === "boolean" ? d.hidePatientNames : false,
    confirmMove,
    showFinancialIndicators: typeof d.showFinancialIndicators === "boolean" ? d.showFinancialIndicators : false,
    showWaitlistMatches: typeof d.showWaitlistMatches === "boolean" ? d.showWaitlistMatches : true,
    smartOneDayView: typeof d.smartOneDayView === "boolean" ? d.smartOneDayView : false,
    defaultView: typeof d.defaultView === "string" && d.defaultView.trim() ? d.defaultView.trim() : "week",
    weekStartsOn: typeof d.weekStartsOn === "string" && d.weekStartsOn.trim() ? d.weekStartsOn.trim() : "monday",
    showWeekends: typeof d.showWeekends === "boolean" ? d.showWeekends : true,
    showClosedDayLabel: typeof d.showClosedDayLabel === "boolean" ? d.showClosedDayLabel : true,
    condensedHeader: typeof d.condensedHeader === "boolean" ? d.condensedHeader : false,
    clientNameSeparateLine: typeof d.clientNameSeparateLine === "boolean" ? d.clientNameSeparateLine : false,
  };
}

export async function getCalendarDisplayConfig(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const uid = request.auth.uid;

  // Require settings.read or settings.write (active membership implied by requireClinicPermission)
  try {
    await requireClinicPermission(db, clinicId, uid, "settings.read");
  } catch (e) {
    if (e instanceof HttpsError && e.code === "permission-denied") {
      await requireClinicPermission(db, clinicId, uid, "settings.write");
    } else {
      throw e;
    }
  }

  const ref = db.doc(`clinics/${clinicId}/settings/calendarDisplay`);
  const snap = await ref.get();

  if (!snap.exists) {
    return getDefaultCalendarDisplayConfig();
  }

  const stored = snap.data() as Record<string, unknown> | undefined;
  return normalizeCalendarDisplayConfig(stored);
}
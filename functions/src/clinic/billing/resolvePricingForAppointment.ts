/**
 * Returns resolved price and suggested line item for an appointment (for UI preview before creating invoice).
 * Does not create an invoice; used so the client can show "Price: X (from Practitioner hourly)" before calling createInvoiceFromAppointment.
 */

import { asObject, db, requireAuthUid, requireBillingRead, requireString } from "./common";
import { resolvePrice } from "./pricingResolution";

function getAppointmentFields(data: Record<string, unknown>) {
  const practitionerId = String(data.practitionerId ?? data.practitioner ?? "").trim();
  const serviceId = String(data.serviceId ?? data.appointmentTypeId ?? "").trim();
  return {
    practitionerId,
    serviceId,
    startAt: data.startAt ?? data.start,
    endAt: data.endAt ?? data.end,
  };
}

function durationMinutesFromAppointment(data: Record<string, unknown>): number | null {
  const start = data.startAt ?? data.start;
  const end = data.endAt ?? data.end;
  const toMs = (v: unknown): number | null => {
    if (v == null) return null;
    if (typeof v === "object" && v !== null && "toMillis" in v && typeof (v as { toMillis: () => number }).toMillis === "function") {
      return (v as { toMillis: () => number }).toMillis();
    }
    if (v instanceof Date) return v.getTime();
    if (typeof v === "number" && Number.isFinite(v)) return v;
    if (typeof v === "string") {
      const d = new Date(v);
      return Number.isFinite(d.getTime()) ? d.getTime() : null;
    }
    return null;
  };
  const startMs = toMs(start);
  const endMs = toMs(end);
  if (startMs == null || endMs == null || endMs <= startMs) return null;
  return (endMs - startMs) / 60_000;
}

export async function resolvePricingForAppointment(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const appointmentId = requireString(data.appointmentId, "appointmentId", 1, 120);
  const patientId = requireString(data.patientId, "patientId", 1, 120);
  await requireBillingRead(clinicId, uid);

  const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) {
    return { ok: true, found: false, appointmentId } as const;
  }
  const apptData = (apptSnap.data() || {}) as Record<string, unknown>;
  const { practitionerId, serviceId } = getAppointmentFields(apptData);
  const durationMinutes = durationMinutesFromAppointment(apptData);

  let scheduledDurationMinutes: number | null = null;
  let serviceName = "Appointment";
  if (serviceId) {
    const typeSnap = await db.collection("clinics").doc(clinicId).collection("appointmentTypes").doc(serviceId).get();
    if (typeSnap.exists) {
      const typeData = (typeSnap.data() || {}) as Record<string, unknown>;
      const name = typeData.name ?? typeData.label;
      if (name != null) serviceName = String(name).trim() || serviceName;
      const dur = typeData.durationMinutes ?? typeData.duration;
      if (typeof dur === "number" && Number.isFinite(dur)) scheduledDurationMinutes = dur;
    }
  }

  const pricing = await resolvePrice(db, {
    clinicId,
    patientId,
    practitionerId: practitionerId || undefined,
    appointmentTypeId: serviceId || undefined,
    durationMinutes: durationMinutes ?? undefined,
    scheduledDurationMinutes: scheduledDurationMinutes ?? undefined,
  });

  if (!pricing) {
    return {
      ok: true,
      found: true,
      appointmentId,
      resolved: false,
      suggestedDescription: serviceName,
    } as const;
  }

  return {
    ok: true,
    found: true,
    appointmentId,
    resolved: true,
    amount: pricing.amount,
    source: pricing.source,
    sourceSnapshot: pricing.sourceSnapshot,
    suggestedLineItem: {
      description: serviceName,
      quantity: 1,
      unitPrice: pricing.amount,
      taxRate: 0,
      pricingSource: pricing.source,
      pricingSourceSnapshot: pricing.sourceSnapshot,
    },
  } as const;
}

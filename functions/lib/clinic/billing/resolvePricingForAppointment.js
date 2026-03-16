"use strict";
/**
 * Returns resolved price and suggested line item for an appointment (for UI preview before creating invoice).
 * Does not create an invoice; used so the client can show "Price: X (from Practitioner hourly)" before calling createInvoiceFromAppointment.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolvePricingForAppointment = resolvePricingForAppointment;
const common_1 = require("./common");
const pricingResolution_1 = require("./pricingResolution");
function getAppointmentFields(data) {
    var _a, _b, _c, _d, _e, _f;
    const practitionerId = String((_b = (_a = data.practitionerId) !== null && _a !== void 0 ? _a : data.practitioner) !== null && _b !== void 0 ? _b : "").trim();
    const serviceId = String((_d = (_c = data.serviceId) !== null && _c !== void 0 ? _c : data.appointmentTypeId) !== null && _d !== void 0 ? _d : "").trim();
    return {
        practitionerId,
        serviceId,
        startAt: (_e = data.startAt) !== null && _e !== void 0 ? _e : data.start,
        endAt: (_f = data.endAt) !== null && _f !== void 0 ? _f : data.end,
    };
}
function durationMinutesFromAppointment(data) {
    var _a, _b;
    const start = (_a = data.startAt) !== null && _a !== void 0 ? _a : data.start;
    const end = (_b = data.endAt) !== null && _b !== void 0 ? _b : data.end;
    const toMs = (v) => {
        if (v == null)
            return null;
        if (typeof v === "object" && v !== null && "toMillis" in v && typeof v.toMillis === "function") {
            return v.toMillis();
        }
        if (v instanceof Date)
            return v.getTime();
        if (typeof v === "number" && Number.isFinite(v))
            return v;
        if (typeof v === "string") {
            const d = new Date(v);
            return Number.isFinite(d.getTime()) ? d.getTime() : null;
        }
        return null;
    };
    const startMs = toMs(start);
    const endMs = toMs(end);
    if (startMs == null || endMs == null || endMs <= startMs)
        return null;
    return (endMs - startMs) / 60000;
}
async function resolvePricingForAppointment(request) {
    var _a, _b;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const appointmentId = (0, common_1.requireString)(data.appointmentId, "appointmentId", 1, 120);
    const patientId = (0, common_1.requireString)(data.patientId, "patientId", 1, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const apptRef = common_1.db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists) {
        return { ok: true, found: false, appointmentId };
    }
    const apptData = (apptSnap.data() || {});
    const { practitionerId, serviceId } = getAppointmentFields(apptData);
    const durationMinutes = durationMinutesFromAppointment(apptData);
    let scheduledDurationMinutes = null;
    let serviceName = "Appointment";
    if (serviceId) {
        const typeSnap = await common_1.db.collection("clinics").doc(clinicId).collection("appointmentTypes").doc(serviceId).get();
        if (typeSnap.exists) {
            const typeData = (typeSnap.data() || {});
            const name = (_a = typeData.name) !== null && _a !== void 0 ? _a : typeData.label;
            if (name != null)
                serviceName = String(name).trim() || serviceName;
            const dur = (_b = typeData.durationMinutes) !== null && _b !== void 0 ? _b : typeData.duration;
            if (typeof dur === "number" && Number.isFinite(dur))
                scheduledDurationMinutes = dur;
        }
    }
    const pricing = await (0, pricingResolution_1.resolvePrice)(common_1.db, {
        clinicId,
        patientId,
        practitionerId: practitionerId || undefined,
        appointmentTypeId: serviceId || undefined,
        durationMinutes: durationMinutes !== null && durationMinutes !== void 0 ? durationMinutes : undefined,
        scheduledDurationMinutes: scheduledDurationMinutes !== null && scheduledDurationMinutes !== void 0 ? scheduledDurationMinutes : undefined,
    });
    if (!pricing) {
        return {
            ok: true,
            found: true,
            appointmentId,
            resolved: false,
            suggestedDescription: serviceName,
        };
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
    };
}
//# sourceMappingURL=resolvePricingForAppointment.js.map
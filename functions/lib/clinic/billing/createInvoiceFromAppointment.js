"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInvoiceFromAppointment = createInvoiceFromAppointment;
const https_1 = require("firebase-functions/v2/https");
const common_1 = require("./common");
const createInvoice_1 = require("./createInvoice");
const pricingResolution_1 = require("./pricingResolution");
/** Appointment doc shape (subset we need for pricing). */
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
async function createInvoiceFromAppointment(request) {
    var _a, _b, _c, _d;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const appointmentId = (0, common_1.requireString)(data.appointmentId, "appointmentId", 1, 120);
    const patientId = (0, common_1.requireString)(data.patientId, "patientId", 1, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const lineItemsFromClient = Array.isArray(data.lineItems) ? data.lineItems : [];
    if (lineItemsFromClient.length > 0) {
        return (0, createInvoice_1.createInvoice)({
            auth: request.auth,
            data: {
                clinicId,
                appointmentId,
                patientId,
                lineItems: lineItemsFromClient,
                invoiceDiscount: (_a = data.invoiceDiscount) !== null && _a !== void 0 ? _a : 0,
                status: "draft",
            },
        });
    }
    const apptRef = common_1.db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists) {
        throw new https_1.HttpsError("not-found", "Appointment not found.");
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
            const name = (_b = typeData.name) !== null && _b !== void 0 ? _b : typeData.label;
            if (name != null)
                serviceName = String(name).trim() || serviceName;
            const dur = (_c = typeData.durationMinutes) !== null && _c !== void 0 ? _c : typeData.duration;
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
    const taxRate = 0;
    const unitPrice = pricing ? pricing.amount : 0;
    const lineItem = {
        type: "service",
        itemId: serviceId || "appointment",
        description: serviceName,
        quantity: 1,
        unitPrice,
        taxRate,
        ...(pricing
            ? {
                pricingSource: pricing.source,
                pricingSourceSnapshot: pricing.sourceSnapshot,
            }
            : {}),
    };
    return (0, createInvoice_1.createInvoice)({
        auth: request.auth,
        data: {
            clinicId,
            appointmentId,
            patientId,
            lineItems: [lineItem],
            invoiceDiscount: (_d = data.invoiceDiscount) !== null && _d !== void 0 ? _d : 0,
            status: "draft",
        },
    });
}
//# sourceMappingURL=createInvoiceFromAppointment.js.map
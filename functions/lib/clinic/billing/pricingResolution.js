"use strict";
/**
 * Phase 6A: Pricing Rules Foundation.
 * Deterministic resolution order: client override → appointment-type practitioner → appointment-type default → practitioner hourly → clinic fallback.
 * Changing a pricing rule must never rewrite issued or historic invoices; invoice lines store a frozen snapshot at issue time.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.roundDuration = void 0;
exports.resolvePrice = resolvePrice;
const common_1 = require("./common");
const common_2 = require("./common");
const durationRounding_1 = require("./durationRounding");
/** Re-export for callers that need duration rounding without loading Firestore. */
var durationRounding_2 = require("./durationRounding");
Object.defineProperty(exports, "roundDuration", { enumerable: true, get: function () { return durationRounding_2.roundDuration; } });
function roundDurationWithOptions(durationMinutes, policy, options) {
    return (0, durationRounding_1.roundDuration)(durationMinutes, policy, options);
}
/**
 * Loads clinic pricing settings (default rates + duration policy).
 */
async function loadPricingSettings(db, clinicId) {
    var _a;
    const ref = (0, common_2.billingPricingSettingsRef)(clinicId);
    const snap = await ref.get();
    if (!snap.exists)
        return null;
    const d = snap.data();
    if (!d)
        return null;
    return {
        defaultHourlyRate: typeof d.defaultHourlyRate === "number" ? d.defaultHourlyRate : undefined,
        defaultFixedRate: typeof d.defaultFixedRate === "number" ? d.defaultFixedRate : undefined,
        durationRoundingPolicy: (_a = d.durationRoundingPolicy) !== null && _a !== void 0 ? _a : "actual",
        durationRoundingMinutes: typeof d.durationRoundingMinutes === "number" ? d.durationRoundingMinutes : 15,
        minimumBillableMinutes: typeof d.minimumBillableMinutes === "number" ? d.minimumBillableMinutes : 15,
    };
}
/**
 * Resolves price for the given context using the mandatory resolution order.
 * Used when building draft invoice lines; result must be snapshot into the line so issued invoices are never rewritten.
 */
async function resolvePrice(db, ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r;
    const durationMinutes = Number((_a = ctx.durationMinutes) !== null && _a !== void 0 ? _a : 0) || 0;
    const scheduledDurationMinutes = Number((_b = ctx.scheduledDurationMinutes) !== null && _b !== void 0 ? _b : 0) || 0;
    const settings = await loadPricingSettings(db, ctx.clinicId);
    const policy = ((_c = settings === null || settings === void 0 ? void 0 : settings.durationRoundingPolicy) !== null && _c !== void 0 ? _c : "actual");
    const roundUpTo = (_d = settings === null || settings === void 0 ? void 0 : settings.durationRoundingMinutes) !== null && _d !== void 0 ? _d : 15;
    const minBillable = (_e = settings === null || settings === void 0 ? void 0 : settings.minimumBillableMinutes) !== null && _e !== void 0 ? _e : 15;
    const roundedMinutes = roundDurationWithOptions(durationMinutes, policy, {
        roundUpToMinutes: roundUpTo,
        minimumBillableMinutes: minBillable,
        scheduledDurationMinutes,
    });
    // 1. Client-specific override
    if ((_f = ctx.patientId) === null || _f === void 0 ? void 0 : _f.trim()) {
        const overrideRef = (0, common_2.billingClientPricingOverridesCol)(ctx.clinicId).doc(ctx.patientId.trim());
        const overrideSnap = await overrideRef.get();
        if (overrideSnap.exists) {
            const data = overrideSnap.data();
            const type = String((_g = data === null || data === void 0 ? void 0 : data.type) !== null && _g !== void 0 ? _g : "fixed").trim();
            const value = Number((_j = (_h = data === null || data === void 0 ? void 0 : data.value) !== null && _h !== void 0 ? _h : data === null || data === void 0 ? void 0 : data.amount) !== null && _j !== void 0 ? _j : 0);
            if (Number.isFinite(value) && value >= 0) {
                const amount = type === "hourly"
                    ? (0, common_1.roundMoney)((value / 60) * roundedMinutes)
                    : (0, common_1.roundMoney)(value);
                return {
                    amount,
                    source: "clientOverride",
                    sourceSnapshot: {
                        source: "clientOverride",
                        durationMinutes: type === "hourly" ? roundedMinutes : undefined,
                        rateOrFixed: value,
                        description: "Client override",
                    },
                };
            }
        }
    }
    // 2. Appointment-type practitioner override
    if (((_k = ctx.appointmentTypeId) === null || _k === void 0 ? void 0 : _k.trim()) && ((_l = ctx.practitionerId) === null || _l === void 0 ? void 0 : _l.trim())) {
        const atRef = (0, common_2.billingAppointmentTypePractitionerPricesCol)(ctx.clinicId).doc(ctx.appointmentTypeId.trim());
        const atSnap = await atRef.get();
        if (atSnap.exists) {
            const data = atSnap.data();
            const overrides = ((_m = data === null || data === void 0 ? void 0 : data.practitionerOverrides) !== null && _m !== void 0 ? _m : data);
            const price = overrides === null || overrides === void 0 ? void 0 : overrides[ctx.practitionerId.trim()];
            if (typeof price === "number" && Number.isFinite(price) && price >= 0) {
                return {
                    amount: (0, common_1.roundMoney)(price),
                    source: "appointmentTypePractitioner",
                    sourceSnapshot: {
                        source: "appointmentTypePractitioner",
                        rateOrFixed: price,
                        description: "Appointment type (practitioner override)",
                    },
                };
            }
        }
    }
    // 3. Appointment-type default
    if ((_o = ctx.appointmentTypeId) === null || _o === void 0 ? void 0 : _o.trim()) {
        const atRef = db
            .collection("clinics")
            .doc(ctx.clinicId)
            .collection("appointmentTypes")
            .doc(ctx.appointmentTypeId.trim());
        const atSnap = await atRef.get();
        if (atSnap.exists) {
            const data = atSnap.data();
            const defaultPrice = data === null || data === void 0 ? void 0 : data.defaultPrice;
            if (typeof defaultPrice === "number" && Number.isFinite(defaultPrice) && defaultPrice >= 0) {
                return {
                    amount: (0, common_1.roundMoney)(defaultPrice),
                    source: "appointmentTypeDefault",
                    sourceSnapshot: {
                        source: "appointmentTypeDefault",
                        rateOrFixed: defaultPrice,
                        description: "Appointment type default",
                    },
                };
            }
        }
    }
    // 4. Practitioner hourly default
    if ((_p = ctx.practitionerId) === null || _p === void 0 ? void 0 : _p.trim()) {
        const pracRef = (0, common_2.billingPractitionerRatesCol)(ctx.clinicId).doc(ctx.practitionerId.trim());
        const pracSnap = await pracRef.get();
        if (pracSnap.exists) {
            const data = pracSnap.data();
            const hourlyRate = Number((_r = (_q = data === null || data === void 0 ? void 0 : data.hourlyRate) !== null && _q !== void 0 ? _q : data === null || data === void 0 ? void 0 : data.rate) !== null && _r !== void 0 ? _r : 0);
            if (Number.isFinite(hourlyRate) && hourlyRate >= 0) {
                const amount = (0, common_1.roundMoney)((hourlyRate / 60) * roundedMinutes);
                return {
                    amount,
                    source: "practitionerHourly",
                    sourceSnapshot: {
                        source: "practitionerHourly",
                        durationMinutes: roundedMinutes,
                        rateOrFixed: hourlyRate,
                        description: "Practitioner hourly",
                    },
                };
            }
        }
    }
    // 5. Clinic default fallback
    if (settings) {
        if (typeof settings.defaultFixedRate === "number" &&
            Number.isFinite(settings.defaultFixedRate) &&
            settings.defaultFixedRate >= 0) {
            return {
                amount: (0, common_1.roundMoney)(settings.defaultFixedRate),
                source: "clinicFallback",
                sourceSnapshot: {
                    source: "clinicFallback",
                    rateOrFixed: settings.defaultFixedRate,
                    description: "Clinic default (fixed)",
                },
            };
        }
        if (typeof settings.defaultHourlyRate === "number" &&
            Number.isFinite(settings.defaultHourlyRate) &&
            settings.defaultHourlyRate >= 0) {
            const amount = (0, common_1.roundMoney)((settings.defaultHourlyRate / 60) * roundedMinutes);
            return {
                amount,
                source: "clinicFallback",
                sourceSnapshot: {
                    source: "clinicFallback",
                    durationMinutes: roundedMinutes,
                    rateOrFixed: settings.defaultHourlyRate,
                    description: "Clinic default (hourly)",
                },
            };
        }
    }
    return null;
}
//# sourceMappingURL=pricingResolution.js.map
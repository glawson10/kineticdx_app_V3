"use strict";
/**
 * Transitional: mirror practitioners/{id}/availability → staffProfiles/{id}/availability/default
 * so listPublicSlotsFn (which still reads only the legacy path) sees edits from the new Availability UI.
 * See docs/AVAILABILITY_SOURCES.md.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.mirrorPractitionerAvailabilityToLegacy = mirrorPractitionerAvailabilityToLegacy;
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const db = admin.firestore();
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
/** dayOfWeek 1 = Monday → mon, 7 = Sunday → sun */
const DOW_TO_DAY = {
    1: "mon",
    2: "tue",
    3: "wed",
    4: "thu",
    5: "fri",
    6: "sat",
    7: "sun",
};
function hmToMinutes(hhmm) {
    const s = String(hhmm !== null && hhmm !== void 0 ? hhmm : "").trim();
    const m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(s);
    if (!m)
        return null;
    return Number(m[1]) * 60 + Number(m[2]);
}
function minutesToHHmm(m) {
    const hh = Math.floor(m / 60);
    const mm = m % 60;
    return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}
function mergeIntervals(list) {
    if (list.length === 0)
        return [];
    const sorted = [...list].sort((x, y) => x.a - y.a);
    const out = [];
    let cur = sorted[0];
    for (let i = 1; i < sorted.length; i++) {
        const it = sorted[i];
        if (it.a <= cur.b) {
            cur = { a: cur.a, b: Math.max(cur.b, it.b) };
        }
        else {
            out.push(cur);
            cur = it;
        }
    }
    out.push(cur);
    return out;
}
/**
 * Load all active practitioner availability docs, merge blocks into a single weekly map
 * (union across locations), and write to staffProfiles/{practitionerId}/availability/default.
 * Timezone is left unset so listPublicSlots uses clinic/settings timezone.
 */
async function mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId) {
    const availCol = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(practitionerId)
        .collection("availability");
    const snap = await availCol.get();
    const perDay = Object.fromEntries(DAY_KEYS.map((k) => [k, []]));
    for (const doc of snap.docs) {
        const data = doc.data();
        if ((data === null || data === void 0 ? void 0 : data.active) === false)
            continue;
        const blocks = Array.isArray(data === null || data === void 0 ? void 0 : data.blocks) ? data.blocks : [];
        for (const b of blocks) {
            if (!b || typeof b !== "object")
                continue;
            const bookableOnline = b.bookableOnline !== false;
            if (!bookableOnline)
                continue;
            const dayOfWeek = Number(b.dayOfWeek);
            const dayKey = DOW_TO_DAY[dayOfWeek];
            if (!dayKey)
                continue;
            const startM = hmToMinutes(b.startTime);
            const endM = hmToMinutes(b.endTime);
            if (startM == null || endM == null || endM <= startM)
                continue;
            perDay[dayKey].push({ a: startM, b: endM });
        }
    }
    const weekly = Object.fromEntries(DAY_KEYS.map((k) => [
        k,
        mergeIntervals(perDay[k]).map(({ a, b }) => ({
            start: minutesToHHmm(a),
            end: minutesToHHmm(b),
        })),
    ]));
    const hasAny = Object.values(weekly).some((arr) => arr.length > 0);
    const legacyRef = db.doc(`clinics/${clinicId}/staffProfiles/${practitionerId}/availability/default`);
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (hasAny) {
        await legacyRef.set({
            weekly,
            updatedAt: now,
            updatedByMirror: "mirrorPractitionerAvailabilityToLegacy",
        }, { merge: true });
        logger_1.logger.info("mirrorPractitionerAvailabilityToLegacy: updated", {
            clinicId,
            practitionerId,
        });
    }
    else {
        // Do not delete: leave legacy doc unchanged so legacy-only data (setStaffAvailabilityDefault) is preserved.
        logger_1.logger.info("mirrorPractitionerAvailabilityToLegacy: no active availability (legacy doc unchanged)", {
            clinicId,
            practitionerId,
        });
    }
}
//# sourceMappingURL=mirrorPractitionerAvailabilityToLegacy.js.map
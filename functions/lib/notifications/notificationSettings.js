"use strict";
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
exports.getClinicNotificationSettings = getClinicNotificationSettings;
exports.resolveTemplateId = resolveTemplateId;
exports.resolveInviteBaseUrl = resolveInviteBaseUrl;
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
async function getClinicNotificationSettings(clinicId) {
    var _a;
    const snap = await db.doc(`clinics/${clinicId}/settings/notifications`).get();
    return (_a = (snap.exists ? snap.data() : {})) !== null && _a !== void 0 ? _a : {};
}
function resolveTemplateId(settings, eventId, locale) {
    var _a, _b, _c, _d;
    const ev = (_a = settings.events) === null || _a === void 0 ? void 0 : _a[eventId];
    if (!(ev === null || ev === void 0 ? void 0 : ev.enabled))
        return null;
    const loc = (locale || settings.defaultLocale || "en").toLowerCase();
    const byLoc = (_b = ev.templateIdByLocale) !== null && _b !== void 0 ? _b : {};
    return (_d = (_c = byLoc[loc]) !== null && _c !== void 0 ? _c : byLoc["en"]) !== null && _d !== void 0 ? _d : null;
}
/**
 * Invite emails need a base URL to build:
 *   <inviteBaseUrl>?token=...
 *
 * We keep this clinic-scoped and event-scoped so you can change it per clinic.
 */
function resolveInviteBaseUrl(settings) {
    var _a, _b;
    const ev = (_a = settings.events) === null || _a === void 0 ? void 0 : _a["members.invite"];
    if (!(ev === null || ev === void 0 ? void 0 : ev.enabled))
        return null;
    const raw = ((_b = ev.inviteBaseUrl) !== null && _b !== void 0 ? _b : "").toString().trim();
    if (!raw)
        return null;
    return raw;
}
//# sourceMappingURL=notificationSettings.js.map
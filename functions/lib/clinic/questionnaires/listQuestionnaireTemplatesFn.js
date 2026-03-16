"use strict";
/**
 * OBS-P2: List and update questionnaire templates for a clinic.
 * Clinic-scoped: custom templates at clinics/{clinicId}/questionnaireTemplates/{templateId}.
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
exports.updateQuestionnaireTemplateFn = exports.listQuestionnaireTemplatesFn = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const questionnaireTemplates_1 = require("./questionnaireTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
exports.listQuestionnaireTemplatesFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    const clinicId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId.");
    }
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.read");
    const templates = await (0, questionnaireTemplates_1.listQuestionnaireTemplates)(db, clinicId);
    return { templates };
});
/** OBS-P2: Update metadata for a custom template only. Editable: label, description, active, patientFacing, category. */
exports.updateQuestionnaireTemplateFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    const clinicId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    const templateId = safeStr((_c = request.data) === null || _c === void 0 ? void 0 : _c.templateId);
    if (!clinicId || !templateId) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId or templateId.");
    }
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const template = await (0, questionnaireTemplates_1.loadQuestionnaireTemplateById)(db, clinicId, templateId);
    if (!template) {
        throw new https_1.HttpsError("not-found", "Template not found.");
    }
    if (template.source === questionnaireTemplates_1.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN) {
        throw new https_1.HttpsError("invalid-argument", "Cannot update built-in template.");
    }
    const active = (_d = request.data) === null || _d === void 0 ? void 0 : _d.active;
    const patientFacing = (_e = request.data) === null || _e === void 0 ? void 0 : _e.patientFacing;
    const labelRaw = (_g = (_f = request.data) === null || _f === void 0 ? void 0 : _f.label) !== null && _g !== void 0 ? _g : (_h = request.data) === null || _h === void 0 ? void 0 : _h.name;
    const descriptionRaw = (_j = request.data) === null || _j === void 0 ? void 0 : _j.description;
    const categoryRaw = (_k = request.data) === null || _k === void 0 ? void 0 : _k.category;
    const updates = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (typeof active === "boolean")
        updates.active = active;
    if (typeof patientFacing === "boolean")
        updates.patientFacing = patientFacing;
    if (typeof labelRaw === "string") {
        const label = labelRaw.trim();
        if (!label) {
            throw new https_1.HttpsError("invalid-argument", "Label (name) is required and cannot be empty.");
        }
        updates.label = label;
    }
    if (descriptionRaw !== undefined) {
        updates.description = typeof descriptionRaw === "string" ? descriptionRaw.trim() || null : null;
    }
    if (categoryRaw !== undefined) {
        updates.category = typeof categoryRaw === "string" ? categoryRaw.trim() || null : null;
    }
    // Ensure final label is non-empty: use existing if no label in patch
    const finalLabel = (_l = updates.label) !== null && _l !== void 0 ? _l : template.label;
    if (!finalLabel || !finalLabel.trim()) {
        throw new https_1.HttpsError("invalid-argument", "Template label (name) is required and cannot be empty.");
    }
    if (Object.keys(updates).length <= 1) {
        return { ok: true };
    }
    await db
        .collection("clinics")
        .doc(clinicId)
        .collection("questionnaireTemplates")
        .doc(templateId)
        .set(updates, { merge: true });
    return { ok: true };
});
//# sourceMappingURL=listQuestionnaireTemplatesFn.js.map
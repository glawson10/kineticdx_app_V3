/**
 * OBS-P2: List and update questionnaire templates for a clinic.
 * Clinic-scoped: custom templates at clinics/{clinicId}/questionnaireTemplates/{templateId}.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import {
  listQuestionnaireTemplates,
  loadQuestionnaireTemplateById,
  QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
} from "./questionnaireTemplates";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

export const listQuestionnaireTemplatesFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const clinicId = safeStr(request.data?.clinicId);
    if (!clinicId) {
      throw new HttpsError("invalid-argument", "Missing clinicId.");
    }
    await requireClinicPermission(db, clinicId, uid, "settings.read");
    const templates = await listQuestionnaireTemplates(db, clinicId);
    return { templates };
  }
);

/** OBS-P2: Update metadata for a custom template only. Editable: label, description, active, patientFacing, category. */
export const updateQuestionnaireTemplateFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const clinicId = safeStr(request.data?.clinicId);
    const templateId = safeStr(request.data?.templateId);
    if (!clinicId || !templateId) {
      throw new HttpsError("invalid-argument", "Missing clinicId or templateId.");
    }
    await requireClinicPermission(db, clinicId, uid, "settings.write");
    const template = await loadQuestionnaireTemplateById(db, clinicId, templateId);
    if (!template) {
      throw new HttpsError("not-found", "Template not found.");
    }
    if (template.source === QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN) {
      throw new HttpsError("invalid-argument", "Cannot update built-in template.");
    }
    const active = request.data?.active;
    const patientFacing = request.data?.patientFacing;
    const labelRaw = request.data?.label ?? request.data?.name;
    const descriptionRaw = request.data?.description;
    const categoryRaw = request.data?.category;
    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (typeof active === "boolean") updates.active = active;
    if (typeof patientFacing === "boolean") updates.patientFacing = patientFacing;
    if (typeof labelRaw === "string") {
      const label = labelRaw.trim();
      if (!label) {
        throw new HttpsError("invalid-argument", "Label (name) is required and cannot be empty.");
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
    const finalLabel = (updates.label as string | undefined) ?? template.label;
    if (!finalLabel || !finalLabel.trim()) {
      throw new HttpsError("invalid-argument", "Template label (name) is required and cannot be empty.");
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
  }
);

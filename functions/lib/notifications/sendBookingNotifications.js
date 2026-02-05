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
exports.sendBookingNotifications = sendBookingNotifications;
const admin = __importStar(require("firebase-admin"));
const brevo_1 = require("./brevo");
const notificationSettings_1 = require("./notificationSettings");
const db = admin.firestore();
function redactEmail(email) {
    const at = email.indexOf("@");
    if (at <= 1)
        return "***";
    return `${email[0]}***${email.slice(at - 1)}`;
}
async function writeLog(params) {
    var _a, _b;
    await db.collection(`clinics/${params.clinicId}/notificationLogs`).add({
        eventId: params.eventId,
        appointmentPath: params.appointmentPath,
        to: redactEmail(params.toEmail),
        provider: "brevo",
        messageId: (_a = params.messageId) !== null && _a !== void 0 ? _a : null,
        status: params.status,
        errorMessage: (_b = params.errorMessage) !== null && _b !== void 0 ? _b : null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
async function sendBookingNotifications(ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const settings = await (0, notificationSettings_1.getClinicNotificationSettings)(ctx.clinicId);
    const senderId = (_a = settings.brevo) === null || _a === void 0 ? void 0 : _a.senderId;
    const replyToEmail = (_b = settings.brevo) === null || _b === void 0 ? void 0 : _b.replyToEmail;
    // 1) Patient confirmation
    await sendOne({
        clinicId: ctx.clinicId,
        appointmentPath: ctx.appointmentPath,
        settings,
        eventId: "booking.created.patientConfirmation",
        locale: ctx.locale,
        to: [{ email: ctx.patient.email, name: ctx.patient.name }],
        senderId,
        replyToEmail,
        params: ctx.templateParams,
    });
    // 2) Clinician notification (optional)
    const mode = (_f = (_e = (_d = (_c = settings.events) === null || _c === void 0 ? void 0 : _c["booking.created.clinicianNotification"]) === null || _d === void 0 ? void 0 : _d.recipientPolicy) === null || _e === void 0 ? void 0 : _e.mode) !== null && _f !== void 0 ? _f : "practitionerOnAppointment";
    const clinicianEmail = (_g = ctx.clinician) === null || _g === void 0 ? void 0 : _g.email;
    const inboxEmail = ctx.clinicInboxEmail;
    const recipients = [];
    if (mode === "practitionerOnAppointment" || mode === "both") {
        if (clinicianEmail)
            recipients.push({ email: clinicianEmail, name: (_h = ctx.clinician) === null || _h === void 0 ? void 0 : _h.name });
    }
    if (mode === "clinicInbox" || mode === "both") {
        if (inboxEmail)
            recipients.push({ email: inboxEmail });
    }
    if (recipients.length > 0) {
        await sendOne({
            clinicId: ctx.clinicId,
            appointmentPath: ctx.appointmentPath,
            settings,
            eventId: "booking.created.clinicianNotification",
            locale: ctx.locale,
            to: recipients,
            senderId,
            replyToEmail,
            params: ctx.templateParams,
        });
    }
}
async function sendOne(args) {
    var _a, _b, _c, _d, _e, _f, _g;
    const templateId = (0, notificationSettings_1.resolveTemplateId)(args.settings, args.eventId, args.locale);
    if (!templateId) {
        // Disabled or not configured
        await writeLog({
            clinicId: args.clinicId,
            eventId: args.eventId,
            appointmentPath: args.appointmentPath,
            toEmail: (_b = (_a = args.to[0]) === null || _a === void 0 ? void 0 : _a.email) !== null && _b !== void 0 ? _b : "unknown",
            status: "skipped",
        });
        return;
    }
    try {
        const result = await (0, brevo_1.brevoSendTemplateEmail)({
            senderId: args.senderId,
            replyToEmail: args.replyToEmail,
            to: args.to,
            templateId,
            params: args.params,
        });
        await writeLog({
            clinicId: args.clinicId,
            eventId: args.eventId,
            appointmentPath: args.appointmentPath,
            toEmail: (_d = (_c = args.to[0]) === null || _c === void 0 ? void 0 : _c.email) !== null && _d !== void 0 ? _d : "unknown",
            status: "accepted",
            messageId: result.messageId,
        });
    }
    catch (e) {
        await writeLog({
            clinicId: args.clinicId,
            eventId: args.eventId,
            appointmentPath: args.appointmentPath,
            toEmail: (_f = (_e = args.to[0]) === null || _e === void 0 ? void 0 : _e.email) !== null && _f !== void 0 ? _f : "unknown",
            status: "error",
            errorMessage: ((_g = e === null || e === void 0 ? void 0 : e.message) !== null && _g !== void 0 ? _g : "Unknown error").toString().slice(0, 500),
        });
        throw e; // optional: rethrow or swallow depending on booking flow
    }
}
//# sourceMappingURL=sendBookingNotifications.js.map
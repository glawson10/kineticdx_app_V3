"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BREVO_API_KEY = void 0;
exports.brevoSendTemplateEmail = brevoSendTemplateEmail;
const params_1 = require("firebase-functions/params");
exports.BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
async function brevoSendTemplateEmail(input) {
    var _a;
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
            accept: "application/json",
            "content-type": "application/json",
            "api-key": exports.BREVO_API_KEY.value(),
        },
        body: JSON.stringify({
            sender: input.senderId ? { id: input.senderId } : undefined,
            replyTo: input.replyToEmail ? { email: input.replyToEmail } : undefined,
            to: input.to,
            templateId: input.templateId,
            params: (_a = input.params) !== null && _a !== void 0 ? _a : {},
        }),
    });
    const text = await res.text();
    if (!res.ok) {
        // Don't leak secrets; include status + truncated body
        throw new Error(`Brevo send failed: ${res.status} ${text.slice(0, 400)}`);
    }
    // Brevo returns JSON with messageId on success
    const data = JSON.parse(text);
    return { messageId: data.messageId };
}
//# sourceMappingURL=brevo.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.testBrevoConnection = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
exports.testBrevoConnection = (0, https_1.onCall)({
    region: "europe-west3",
    secrets: [BREVO_API_KEY],
}, async () => {
    const res = await fetch("https://api.brevo.com/v3/account", {
        headers: {
            accept: "application/json",
            "api-key": BREVO_API_KEY.value(),
        },
    });
    if (!res.ok) {
        return {
            ok: false,
            status: res.status,
        };
    }
    return { ok: true };
});
//# sourceMappingURL=testBrevoConnection.js.map
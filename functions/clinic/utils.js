"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
const https_1 = require("firebase-functions/v2/https");
function requireAuth(auth) {
    if (!auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign-in required");
    }
    return auth.uid;
}
//# sourceMappingURL=utils.js.map
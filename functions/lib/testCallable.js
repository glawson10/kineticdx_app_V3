"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.testCallable = void 0;
const https_1 = require("firebase-functions/v2/https");
exports.testCallable = (0, https_1.onCall)({ region: "europe-west3" }, async () => {
    return { ok: true, message: "Callable works" };
});
//# sourceMappingURL=testCallable.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createPatient = createPatient;
// functions/src/callables/create_patient.ts
const https_1 = require("firebase-functions/v2/https");
// ✅ Reuse the canonical clinic-scoped implementation
const createPatient_1 = require("../clinic/patients/createPatient");
async function createPatient(req) {
    var _a;
    // Keep the callable name/entry-point the same, but ensure one source of truth.
    try {
        return await (0, createPatient_1.createPatient)(req);
    }
    catch (err) {
        // If clinic version already throws HttpsError, preserve it.
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "createPatient crashed. Check function logs.", {
            original: (_a = err === null || err === void 0 ? void 0 : err.message) !== null && _a !== void 0 ? _a : String(err),
        });
    }
}
//# sourceMappingURL=create_patient.js.map
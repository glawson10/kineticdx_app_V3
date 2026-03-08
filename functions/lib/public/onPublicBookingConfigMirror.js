"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onPublicBookingConfigMirror = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
/** Stub: Public booking config mirror trigger. Replace with real implementation. */
exports.onPublicBookingConfigMirror = (0, firestore_1.onDocumentWritten)({
    document: "clinics/{clinicId}/public/config/publicBooking/config",
    region: "europe-west3",
}, async () => { });
//# sourceMappingURL=onPublicBookingConfigMirror.js.map
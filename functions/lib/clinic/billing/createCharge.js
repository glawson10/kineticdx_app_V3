"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createCharge = createCharge;
const https_1 = require("firebase-functions/v2/https");
const common_1 = require("./common");
const createInvoice_1 = require("./createInvoice");
async function createCharge(request) {
    const data = (0, common_1.asObject)(request.data);
    const lineItem = data.lineItem;
    if (!lineItem || typeof lineItem !== "object") {
        throw new https_1.HttpsError("invalid-argument", "lineItem is required.");
    }
    return (0, createInvoice_1.createInvoice)({
        auth: request.auth,
        data: {
            clinicId: data.clinicId,
            patientId: data.patientId,
            appointmentId: data.appointmentId,
            lineItems: [lineItem],
            status: "draft",
        },
    });
}
//# sourceMappingURL=createCharge.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.recordManualPayment = recordManualPayment;
const recordPayment_1 = require("./recordPayment");
async function recordManualPayment(request) {
    return (0, recordPayment_1.recordPayment)(request);
}
//# sourceMappingURL=recordManualPayment.js.map
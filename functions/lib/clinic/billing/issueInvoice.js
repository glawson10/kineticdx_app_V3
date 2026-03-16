"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.issueInvoice = issueInvoice;
const common_1 = require("./common");
const updateInvoice_1 = require("./updateInvoice");
async function issueInvoice(request) {
    const data = (0, common_1.asObject)(request.data);
    return (0, updateInvoice_1.updateInvoice)({
        auth: request.auth,
        data: {
            clinicId: data.clinicId,
            invoiceId: data.invoiceId,
            patch: { status: "issued" },
        },
    });
}
//# sourceMappingURL=issueInvoice.js.map
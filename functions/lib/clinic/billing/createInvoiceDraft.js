"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInvoiceDraft = createInvoiceDraft;
const common_1 = require("./common");
const createInvoice_1 = require("./createInvoice");
async function createInvoiceDraft(request) {
    const data = (0, common_1.asObject)(request.data);
    return (0, createInvoice_1.createInvoice)({
        auth: request.auth,
        data: { ...data, status: "draft" },
    });
}
//# sourceMappingURL=createInvoiceDraft.js.map
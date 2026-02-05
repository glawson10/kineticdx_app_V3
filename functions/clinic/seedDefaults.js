"use strict";
// functions/src/clinic/seedDefaults.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.seedDefaultRoles = seedDefaultRoles;
exports.seedDefaultLocation = seedDefaultLocation;
exports.seedStarterServices = seedStarterServices;
const roleTemplates_1 = require("./roleTemplates");
/**
 * Default role templates for a new clinic
 * Roles are templates only. Membership.permissions is authoritative.
 */
function seedDefaultRoles() {
    const billingPerms = {
        "settings.read": true,
        "members.read": true,
        "schedule.read": true,
        "patients.read": true,
        // Future billing keys (only meaningful once you add features/rules)
        "billing.read": true,
        "billing.write": true,
        "invoices.issue": true,
    };
    const readOnlyPerms = {
        "settings.read": true,
        "schedule.read": true,
        "patients.read": true,
        "clinical.read": false,
        "notes.read": false,
    };
    return [
        {
            id: "owner",
            data: {
                name: "Owner",
                permissions: (0, roleTemplates_1.ownerRolePermissions)(),
            },
        },
        {
            id: "manager",
            data: {
                name: "Manager",
                permissions: (0, roleTemplates_1.managerRolePermissions)(),
            },
        },
        {
            id: "clinician",
            data: {
                name: "Clinician",
                permissions: (0, roleTemplates_1.clinicianRolePermissions)(),
            },
        },
        {
            id: "adminStaff",
            data: {
                name: "Admin / Reception",
                permissions: (0, roleTemplates_1.adminStaffRolePermissions)(),
            },
        },
        {
            id: "billing",
            data: {
                name: "Billing",
                permissions: billingPerms,
            },
        },
        {
            id: "readOnly",
            data: {
                name: "Read only",
                permissions: readOnlyPerms,
            },
        },
    ];
}
/**
 * Default physical / logical location
 */
function seedDefaultLocation() {
    return {
        id: "main",
        data: {
            name: "Main location",
            address: "",
            phone: "",
            active: true,
            createdAt: "SERVER_TIMESTAMP",
        },
    };
}
/**
 * Starter services for booking
 */
function seedStarterServices() {
    return [
        {
            id: "np",
            data: {
                name: "New patient assessment",
                defaultMinutes: 60,
                defaultFee: null,
                onlineBookable: true,
                description: "",
                active: true,
            },
        },
        {
            id: "fu",
            data: {
                name: "Follow-up",
                defaultMinutes: 30,
                defaultFee: null,
                onlineBookable: true,
                description: "",
                active: true,
            },
        },
    ];
}
//# sourceMappingURL=seedDefaults.js.map
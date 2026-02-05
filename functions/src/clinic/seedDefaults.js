"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.seedDefaultRoles = seedDefaultRoles;
exports.seedDefaultLocation = seedDefaultLocation;
exports.seedStarterServices = seedStarterServices;
var permissions_1 = require("./permissions");
function seedDefaultRoles() {
    var owner = {
        id: "owner",
        data: { name: "Owner", permissions: (0, permissions_1.ownerPermissions)() },
    };
    var manager = {
        id: "manager",
        data: {
            name: "Manager",
            permissions: {
                "settings.read": true,
                "settings.write": true,
                "members.read": true,
                "members.manage": true,
                "roles.manage": true,
                "audit.read": true,
                "schedule.read": true,
                "schedule.write": true,
                "patients.read": true,
                "patients.write": true,
                "notes.read": true,
                "notes.write": true,
            },
        },
    };
    var clinician = {
        id: "clinician",
        data: {
            name: "Clinician",
            permissions: {
                "schedule.read": true,
                "schedule.write": true,
                "patients.read": true,
                "patients.write": true,
                "notes.read": true,
                "notes.write": true,
            },
        },
    };
    var reception = {
        id: "reception",
        data: {
            name: "Reception",
            permissions: {
                "schedule.read": true,
                "schedule.write": true,
                "patients.read": true,
            },
        },
    };
    var billing = {
        id: "billing",
        data: {
            name: "Billing",
            permissions: {
                "billing.read": true,
                "billing.write": true,
                "invoices.issue": true,
            },
        },
    };
    var readOnly = {
        id: "readOnly",
        data: {
            name: "Read only",
            permissions: {
                "schedule.read": true,
                "patients.read": true,
            },
        },
    };
    return [owner, manager, clinician, reception, billing, readOnly];
}
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

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ownerPermissions = ownerPermissions;
exports.flattenPermissions = flattenPermissions;
function ownerPermissions() {
    return {
        "settings.read": true,
        "settings.write": true,
        "members.read": true,
        "members.manage": true,
        "roles.manage": true,
        "schedule.read": true,
        "schedule.write": true,
        "schedule.override": true,
        "patients.read": true,
        "patients.write": true,
        "notes.read": true,
        "notes.write": true,
        "billing.read": true,
        "billing.write": true,
        "invoices.issue": true,
        "services.manage": true,
        "resources.manage": true,
        "closures.manage": true,
        "audit.read": true
    };
}
function flattenPermissions(rolePermissions) {
    var flattened = {};
    for (var _i = 0, _a = Object.keys(rolePermissions); _i < _a.length; _i++) {
        var k = _a[_i];
        flattened[k] = rolePermissions[k] === true;
    }
    return flattened;
}

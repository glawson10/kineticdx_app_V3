// functions/src/clinic/seedDefaults.ts

import {
  ownerRolePermissions,
  managerRolePermissions,
  clinicianRolePermissions,
  adminStaffRolePermissions,
  PermissionMap,
} from "./roleTemplates";

/**
 * Default role templates for a new clinic
 * Roles are templates only. Membership.permissions is authoritative.
 */
export function seedDefaultRoles() {
  const billingPerms: PermissionMap = {
    "settings.read": true,
    "members.read": true,
    "schedule.read": true,
    "patients.read": true,
    // Future billing keys (only meaningful once you add features/rules)
    "billing.read": true,
    "billing.write": true,
    "invoices.issue": true,
  };

  const readOnlyPerms: PermissionMap = {
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
        permissions: ownerRolePermissions(),
      },
    },
    {
      id: "manager",
      data: {
        name: "Manager",
        permissions: managerRolePermissions(),
      },
    },
    {
      id: "clinician",
      data: {
        name: "Clinician",
        permissions: clinicianRolePermissions(),
      },
    },
    {
      id: "adminStaff",
      data: {
        name: "Admin / Reception",
        permissions: adminStaffRolePermissions(),
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
export function seedDefaultLocation() {
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
export function seedStarterServices() {
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

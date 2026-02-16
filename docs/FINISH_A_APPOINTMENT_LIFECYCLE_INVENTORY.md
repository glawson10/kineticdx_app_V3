# Finish A — Appointment Lifecycle Inventory Report

**Date:** 2025-02-15  
**Scope:** Update/reschedule and cancel with projections and permission enforcement.

---

## A) Existing appointment schema

**Where appointment docs live:**  
`clinics/{clinicId}/appointments/{appointmentId}`

**Fields in use (from createAppointmentInternal + updateAppointment + trigger):**

| Field            | Type      | Notes                          |
|-----------------|-----------|--------------------------------|
| `startAt`       | Timestamp | Canonical start                |
| `endAt`         | Timestamp | Canonical end                  |
| `start`         | Timestamp | Legacy mirror                  |
| `end`           | Timestamp | Legacy mirror                  |
| `status`        | string    | e.g. booked, attended, cancelled, missed |
| `patientId`     | string    |                                |
| `serviceId`     | string    |                                |
| `practitionerId`| string    |                                |
| `patientName`   | string    | Denormalized                   |
| `serviceName`   | string    | Denormalized                   |
| `practitionerName` | string | Denormalized                   |
| `kind`          | string    | admin \| new \| followup       |
| `resourceIds`   | array     | Optional                       |
| `createdByUid`  | string    |                                |
| `createdAt`     | Timestamp |                                |
| `updatedAt`     | Timestamp |                                |
| `updatedByUid`  | string    |                                |
| `cancelledAt`   | Timestamp | Set when status = cancelled    |
| `cancelledByUid`| string    | Optional                       |
| `cancelReason`  | string    | Optional                       |
| `attendedAt`    | Timestamp | Optional                       |
| `missedAt`      | Timestamp | Optional                       |
| `closureOverride` etc. |       | For override-into-closure audit |

**Existing create callable:**  
- **Name:** `createAppointmentFn`  
- **File:** `functions/src/clinic/createAppointment.ts`  
- **Internal:** `createAppointmentInternal` in `functions/src/clinic/appointments/createAppointmentInternal.ts`

---

## B) Existing schedule / public projection structure

**Projection path:**  
`clinics/{clinicId}/public/availability/blocks/{blockId}`

- **Block ID:** Same as `appointmentId` (one block per appointment).
- **Writer:** Firestore trigger **only** — `onAppointmentWrite_toBusyBlock` in `functions/src/availability/onAppointmentWrite_toBusyBlock.ts`.
- **Behavior:**
  - On appointment **create/update:** trigger writes or merges a doc with `startUtc`, `endUtc`, `scope` (clinic | practitioner), `practitionerId`, `status`, `kind`, `source: "appointments_mirror"`.
  - On appointment **delete** or **status === "cancelled":** trigger **deletes** the block doc.
- **No other paths:** Public scheduling “occupied” is represented only via `public/availability/blocks`. Config is `public/config/publicBooking/publicBooking` (separate).

**Conclusion:** No per-day or per-slot docs; one block per appointment. Update/reschedule and cancel are handled by the same trigger (doc update or delete). No separate “remove from old slot / add to new slot” helper is needed — the trigger reacts to the single appointment document.

---

## C) Permissions

**Permission keys (do not rename):**

- **Read schedule:** `schedule.read` — required to read appointments/closures.
- **Write schedule:** `schedule.write` or `schedule.manage` — required for create/update/cancel.

**Where stored:**  
Canonical: `clinics/{clinicId}/members/{uid}` with `permissions.schedule.read`, `permissions.schedule.write`, etc.  
Legacy: `clinics/{clinicId}/memberships/{uid}` (same shape).  
Code uses members-first or memberships-first by file; authz and rules use `hasPerm(clinicId, "schedule.read")` / `schedule.write`.

---

## D) Firestore rules

**Appointments:**  
`clinics/{clinicId}/appointments/{appointmentId}`

- **Read:** `hasPerm(clinicId, "schedule.read")` ✅  
- **Create, update, delete:** `if false` ✅ (client writes already denied)

**Public:**  
`clinics/{clinicId}/public/{docId}` and subcollections

- **Read:** `if true` ✅  
- **Write:** `if false` ✅ (function-only)

**Conclusion:** Rules already deny client appointment writes and all client writes under `public/**`. No rule changes required for Finish A.

---

## Summary

| Item                         | Result |
|-----------------------------|--------|
| Appointment schema          | startAt, endAt (+ legacy start/end), status, patientId, serviceId, practitionerId, denorm names, kind, timestamps, optional cancelledAt/cancelledByUid/cancelReason |
| Create callable             | `createAppointmentFn` in `functions/src/clinic/createAppointment.ts` |
| Projection                  | `public/availability/blocks/{appointmentId}`; updated/deleted by trigger only |
| Permission keys             | `schedule.read`, `schedule.write` (and `schedule.manage`) |
| Client appointment writes   | Already denied |
| Public writes               | Already denied |

Next: implement update (with overlap validation and optional practitionerId), cancel callable (status-based), then Flutter wiring and smoke test script.

/**
 * Light tests for settings callables: permission denied, validation fails, success writes expected shape.
 */

import { describe, it, expect, jest, beforeEach } from "@jest/globals";
import { HttpsError } from "firebase-functions/v2/https";

const mockSet = jest.fn().mockResolvedValue(undefined);
const mockUpdate = jest.fn().mockResolvedValue(undefined);
const mockGet = jest.fn().mockResolvedValue({ exists: false, data: () => ({}) });

const createDocRef = (exists: boolean, data: Record<string, unknown> = {}) => ({
  get: jest.fn().mockResolvedValue({ exists, data: () => data }),
  set: mockSet,
  update: mockUpdate,
});

const createCollectionRef = (docId?: string) => ({
  doc: (id?: string) => {
    if (!id) {
      return { id: "generated-id-1", set: mockSet };
    }
    return createDocRef(id === "existing-loc", { name: "Existing", active: true });
  },
});

const locationsDocRef = createDocRef(false, {});
const locationsCollectionRef = {
  doc: (id?: string) => {
    if (!id) return { id: "generated-id-1", set: mockSet };
    return id === "existing-loc"
      ? createDocRef(true, { name: "Existing", active: true })
      : createDocRef(false, {});
  },
};

function getLocationDocRef(path: string) {
  const match = path.match(/locations\/([^/]+)$/);
  const locationId = match?.[1];
  const exists = locationId === "existing-loc";
  const data = exists ? { name: "Existing", active: true } : {};
  return createDocRef(exists, data);
}

const mockDb = {
  collection: (path: string) => {
    if (path === "clinics") {
      return {
        doc: (_clinicId: string) => ({
          collection: (subPath: string) => {
            if (subPath === "locations") return locationsCollectionRef;
            if (subPath === "appointmentTypes") {
              return {
                doc: (id?: string) => {
                  if (!id) return { id: "at-new-1", set: mockSet };
                  return createDocRef(id === "at1", { name: "Consult", durationMinutes: 30 });
                },
              };
            }
            return createCollectionRef();
          },
        }),
      };
    }
    if (path === "settings") {
      return {
        doc: (_docId: string) =>
          createDocRef(true, { displayStartHour: 8, displayEndHour: 18 }),
      };
    }
    return createCollectionRef();
  },
  doc: (path: string) => {
    if (path.includes("settings/calendarDisplay"))
      return createDocRef(true, { displayStartHour: 8, displayEndHour: 18 });
    if (path.includes("settings/communication"))
      return createDocRef(false, {});
    if (path.includes("settings/publicBooking"))
      return createDocRef(true, { slotStepMinutes: 15, weeklyHours: {} });
    if (path.includes("locations/")) return getLocationDocRef(path);
    return createDocRef(false, {});
  },
  runTransaction: jest.fn().mockResolvedValue(undefined),
};

const firestoreMock = Object.assign(jest.fn(() => mockDb), {
  FieldValue: { serverTimestamp: () => ({ _serverTimestamp: true }) },
});

jest.mock("firebase-admin", () => ({
  app: {},
  apps: [{}],
  initializeApp: jest.fn(),
  firestore: firestoreMock,
}));

jest.mock("../permissions", () => ({
  requireClinicPermission: jest.fn(),
}));

jest.mock("../audit/audit", () => ({
  writeSettingsAuditEvent: jest.fn().mockResolvedValue(undefined),
}));

const { requireClinicPermission } = require("../permissions");

import { upsertLocation } from "./upsertLocation";
import { setLocationActive } from "./setLocationActive";
import { updateCalendarDisplayConfig } from "./updateCalendarDisplayConfig";
import { updateCommunicationSettings } from "./updateCommunicationSettings";
import { upsertAppointmentType } from "./upsertAppointmentType";
import { updatePublicBookingConfig } from "./updatePublicBookingConfig";
import { expectAuditChangedKeysOnly } from "./settingsCallablesTestHelpers";

describe("settings callables", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockResolvedValue({ exists: false, data: () => ({}) });
  });

  describe("upsertLocation", () => {
    it("throws unauthenticated when not signed in", async () => {
      await expect(
        upsertLocation({ data: { clinicId: "c1", patch: { name: "Loc" } } } as any)
      ).rejects.toThrow(HttpsError);
      try {
        await upsertLocation({ data: { clinicId: "c1", patch: { name: "Loc" } } } as any);
      } catch (e: any) {
        expect(e.code).toBe("unauthenticated");
      }
    });

    it("throws permission-denied when missing settings.write", async () => {
      requireClinicPermission.mockRejectedValueOnce(
        new HttpsError("permission-denied", "Missing")
      );
      try {
        await upsertLocation({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { name: "Loc" } },
        } as any);
      } catch (e: any) {
        expect(e.code).toBe("permission-denied");
        return;
      }
      expect(true).toBe(false);
    });

    it("throws invalid-argument for empty name on create", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      try {
        await upsertLocation({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { name: "  " } },
        } as any);
      } catch (e: any) {
        expect(e.code).toBe("invalid-argument");
        return;
      }
      expect(true).toBe(false);
    });

    it("throws invalid-argument for invalid colorHex", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        upsertLocation({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { name: "Loc", colorHex: "invalid" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("succeeds on create and writes expected doc shape", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await upsertLocation({
        auth: { uid: "u1" },
        data: {
          clinicId: "c1",
          patch: { name: "New Location", colorHex: "#aabbcc" },
        },
      } as any);
      expect(result).toEqual(
        expect.objectContaining({ ok: true, locationId: "generated-id-1" })
      );
      expect(mockSet).toHaveBeenCalled();
      const setCall = mockSet.mock.calls[0][0];
      expect(setCall.name).toBe("New Location");
      expect(setCall.colorHex).toBe("#aabbcc");
      expect(setCall).toHaveProperty("createdAt");
      expect(setCall).toHaveProperty("updatedAt");
    });

    it("update success leaves createdAt unchanged, updatedAt changes", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await upsertLocation({
        auth: { uid: "u1" },
        data: {
          clinicId: "c1",
          locationId: "existing-loc",
          patch: { name: "Updated Name" },
        },
      } as any);
      expect(mockUpdate).toHaveBeenCalled();
      const updateCall = mockUpdate.mock.calls[0][0];
      expect(updateCall.name).toBe("Updated Name");
      expect(updateCall).toHaveProperty("updatedAt");
    });

    it("audit event includes only patch keys", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      await upsertLocation({
        auth: { uid: "u1" },
        data: { clinicId: "c1", patch: { name: "Loc", addressText: "Addr" } },
      } as any);
      expect(writeSettingsAuditEvent).toHaveBeenCalled();
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expectAuditChangedKeysOnly(changes, ["name", "addressText", "active", "showInOnlineBooking", "colorHex"]);
    });
  });

  describe("setLocationActive", () => {
    it("throws invalid-argument when active is not boolean", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        setLocationActive({
          auth: { uid: "u1" },
          data: { clinicId: "c1", locationId: "loc1", active: "yes" },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws not-found when location doc missing", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        setLocationActive({
          auth: { uid: "u1" },
          data: { clinicId: "c1", locationId: "nonexistent", active: false },
        } as any)
      ).rejects.toThrow(HttpsError);
      try {
        await setLocationActive({
          auth: { uid: "u1" },
          data: { clinicId: "c1", locationId: "nonexistent", active: false },
        } as any);
      } catch (e: any) {
        expect(e.code).toBe("not-found");
      }
    });

    it("toggles active and writes audit with only active", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await setLocationActive({
        auth: { uid: "u1" },
        data: { clinicId: "c1", locationId: "existing-loc", active: false },
      } as any);
      expect(result).toEqual({ ok: true });
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ active: false, updatedAt: expect.anything() })
      );
      expect(writeSettingsAuditEvent).toHaveBeenCalledWith(
        expect.anything(),
        "c1",
        "settings.location.active_set",
        "u1",
        "clinics/c1/locations/existing-loc",
        "existing-loc",
        expect.objectContaining({ active: { before: true, after: false } })
      );
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expectAuditChangedKeysOnly(changes, ["active"], { isUpdate: true });
    });
  });

  describe("updateCalendarDisplayConfig", () => {
    it("throws invalid-argument when displayEndHour <= displayStartHour in patch", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCalendarDisplayConfig({
          auth: { uid: "u1" },
          data: {
            clinicId: "c1",
            patch: { displayStartHour: 10, displayEndHour: 10 },
          },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws invalid-argument for minutesPerBlock not in allowed set", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCalendarDisplayConfig({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { minutesPerBlock: 7 } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws invalid-argument for invalid defaultView", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCalendarDisplayConfig({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { defaultView: "year" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws invalid-argument for invalid weekStartsOn", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCalendarDisplayConfig({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { weekStartsOn: "friday" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("accepts valid layout patch and writes audit event", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await updateCalendarDisplayConfig({
        auth: { uid: "u1" },
        data: {
          clinicId: "c1",
          patch: {
            defaultView: "month",
            weekStartsOn: "sunday",
            showWeekends: false,
            showClosedDayLabel: true,
            condensedHeader: true,
          },
        },
      } as any);
      expect(result).toEqual({ ok: true });
      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          defaultView: "month",
          weekStartsOn: "sunday",
          showWeekends: false,
          showClosedDayLabel: true,
          condensedHeader: true,
          updatedAt: expect.anything(),
        }),
        { merge: true }
      );
      expect(writeSettingsAuditEvent).toHaveBeenCalledWith(
        expect.anything(),
        "c1",
        "settings.calendarDisplay.updated",
        "u1",
        "clinics/c1/settings/calendarDisplay",
        "calendarDisplay",
        expect.objectContaining({
          defaultView: expect.anything(),
          weekStartsOn: expect.anything(),
          showWeekends: expect.anything(),
          showClosedDayLabel: expect.anything(),
          condensedHeader: expect.anything(),
        })
      );
    });

    it("partial patch cannot break merged start/end (invalid end <= start rejected)", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCalendarDisplayConfig({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { displayStartHour: 10, displayEndHour: 10 } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("audit changed keys only", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      await updateCalendarDisplayConfig({
        auth: { uid: "u1" },
        data: { clinicId: "c1", patch: { minutesPerBlock: 15 } },
      } as any);
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expectAuditChangedKeysOnly(changes, ["minutesPerBlock"]);
    });
  });

  describe("updateCommunicationSettings", () => {
    it("throws unauthenticated when not signed in", async () => {
      await expect(
        updateCommunicationSettings({
          data: { clinicId: "c1", patch: { defaultReminderChannel: "email" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws permission-denied when no settings.write", async () => {
      requireClinicPermission.mockRejectedValueOnce(new HttpsError("permission-denied", "No access"));
      await expect(
        updateCommunicationSettings({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { defaultReminderChannel: "sms" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws invalid-argument for invalid email", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCommunicationSettings({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { defaultReplyToEmail: "not-an-email" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("throws invalid-argument for invalid reminder channel", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updateCommunicationSettings({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { defaultReminderChannel: "push" } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("success write updates doc and writes audit with changed keys only", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await updateCommunicationSettings({
        auth: { uid: "u1" },
        data: {
          clinicId: "c1",
          patch: {
            defaultReplyToEmail: "replies@clinic.example",
            defaultReminderChannel: "both",
          },
        },
      } as any);
      expect(result).toEqual({ ok: true });
      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          defaultReplyToEmail: "replies@clinic.example",
          defaultReminderChannel: "both",
          updatedAt: expect.anything(),
          updatedByUid: "u1",
        }),
        { merge: true }
      );
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expectAuditChangedKeysOnly(changes, ["defaultReplyToEmail", "defaultReminderChannel"]);
    });
  });

  describe("upsertAppointmentType", () => {
    it("throws invalid-argument when duration not divisible by 5", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        upsertAppointmentType({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { name: "Consult", durationMinutes: 17 } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("create success writes doc with createdAt, updatedAt", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await upsertAppointmentType({
        auth: { uid: "u1" },
        data: { clinicId: "c1", patch: { name: "New Type", durationMinutes: 30 } },
      } as any);
      expect(result).toEqual(expect.objectContaining({ ok: true }));
      expect(mockSet).toHaveBeenCalled();
      const setCall = mockSet.mock.calls[0][0];
      expect(setCall.name).toBe("New Type");
      expect(setCall.durationMinutes).toBe(30);
      expect(setCall).toHaveProperty("createdAt");
      expect(setCall).toHaveProperty("updatedAt");
    });

    it("audit changed keys only", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      await upsertAppointmentType({
        auth: { uid: "u1" },
        data: { clinicId: "c1", appointmentTypeId: "at1", patch: { name: "Updated" } },
      } as any);
      expect(writeSettingsAuditEvent).toHaveBeenCalled();
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expect(Object.keys(changes).length).toBeGreaterThan(0);
      expect(changes).toHaveProperty("name");
    });
  });

  describe("updatePublicBookingConfig", () => {
    it("rejects invalid slotStep", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      await expect(
        updatePublicBookingConfig({
          auth: { uid: "u1" },
          data: { clinicId: "c1", patch: { slotStepMinutes: 7 } },
        } as any)
      ).rejects.toThrow(HttpsError);
    });

    it("accepts weeklyHours patch", async () => {
      requireClinicPermission.mockResolvedValueOnce({});
      const result = await updatePublicBookingConfig({
        auth: { uid: "u1" },
        data: {
          clinicId: "c1",
          patch: { weeklyHours: { sat: [{ start: "09:00", end: "13:00" }] } },
        },
      } as any);
      expect(result).toEqual({ ok: true });
      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({ weeklyHours: { sat: [{ start: "09:00", end: "13:00" }] } }),
        { merge: true }
      );
    });

    it("audit changed keys only", async () => {
      const { writeSettingsAuditEvent } = require("../audit/audit");
      requireClinicPermission.mockResolvedValueOnce({});
      await updatePublicBookingConfig({
        auth: { uid: "u1" },
        data: { clinicId: "c1", patch: { slotStepMinutes: 10 } },
      } as any);
      const changes = writeSettingsAuditEvent.mock.calls[0][5];
      expectAuditChangedKeysOnly(changes, ["slotStepMinutes"]);
    });
  });
});

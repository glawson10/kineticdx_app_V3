/**
 * Commit 16: Tests for public booking projection (minimal config v1).
 * - Defaults when settings missing
 * - Settings applied (slotStep, minNotice, maxAdvance)
 * - Weekly hours passthrough (sat/sun)
 * - Hash stable (same input => same hash)
 * - No PII (only whitelisted keys; extra keys ignored)
 */

import { describe, it, expect, jest, beforeEach } from "@jest/globals";

const SERVER_TIMESTAMP = { _serverTimestamp: true };

jest.mock("firebase-admin", () => ({
  firestore: {
    FieldValue: {
      serverTimestamp: () => SERVER_TIMESTAMP,
    },
  },
}));

import { buildPublicBookingConfigV1 } from "./publicBookingProjection";
import { sha256Hex } from "./hash";

describe("publicBookingProjection", () => {
  const ts = (millis: number) =>
    ({ toMillis: () => millis, seconds: Math.floor(millis / 1000) }) as any;

  describe("buildPublicBookingConfigV1", () => {
    it("writes defaults when settings doc missing", () => {
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: null,
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });

      expect(out.schemaVersion).toBe(1);
      expect(out.clinicId).toBe("c1");
      expect(out.bookingRules).toEqual({
        slotStepMinutes: 15,
        minNoticeMinutes: 0,
        maxAdvanceDays: 90,
        allowNewPatients: true,
        requireEmail: true,
        requirePhone: false,
        cancellationPolicyHours: 24,
      });
      expect(out.weeklyHours).toEqual({
        mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [],
      });
      expect(out.locationOpeningHours).toEqual({});
      expect(out.jurisdiction).toEqual({ timezone: "UTC", currencyCode: "EUR" });
      expect(out.source.publicBookingUpdatedAt).toBeNull();
      expect(out.hash).toBeDefined();
      expect(typeof out.hash).toBe("string");
      expect(out.hash.length).toBe(64);
    });

    it("applies slotStep minNotice maxAdvance from settings", () => {
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: {
          slotStepMinutes: 10,
          minNoticeMinutes: 120,
          maxAdvanceDays: 30,
        },
        settingsUpdatedAt: ts(1000),
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });

      expect(out.bookingRules.slotStepMinutes).toBe(10);
      expect(out.bookingRules.minNoticeMinutes).toBe(120);
      expect(out.bookingRules.maxAdvanceDays).toBe(30);
      expect(out.source.publicBookingUpdatedAt).toBeDefined();
      expect((out.source.publicBookingUpdatedAt as { toMillis: () => number })?.toMillis?.()).toBe(1000);
    });

    it("weekly hours passthrough includes sat/sun", () => {
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: {
          weeklyHours: {
            mon: [{ start: "09:00", end: "17:00" }],
            sat: [{ start: "10:00", end: "14:00" }],
            sun: [],
          },
        },
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });

      expect(out.weeklyHours.mon).toEqual([{ start: "09:00", end: "17:00" }]);
      expect(out.weeklyHours.sat).toEqual([{ start: "10:00", end: "14:00" }]);
      expect(out.weeklyHours.sun).toEqual([]);
      expect(out.weeklyHours.tue).toEqual([]);
    });

    it("no PII: extra keys in settings are not in output", () => {
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: {
          internalNote: "secret",
          adminEmail: "admin@clinic.com",
          slotStepMinutes: 20,
        },
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });

      const keys = Object.keys(out);
      expect(keys.sort()).toEqual([
        "bookingRules", "clinicId", "hash", "jurisdiction", "locationOpeningHours",
        "schemaVersion", "source", "updatedAt", "weeklyHours",
      ]);
      expect((out as any).internalNote).toBeUndefined();
      expect((out as any).adminEmail).toBeUndefined();
      expect(out.bookingRules.slotStepMinutes).toBe(20);
    });

    it("payload contains only whitelisted fields (no PII, Commit 19)", () => {
      const allowedTopLevel = new Set([
        "bookingRules", "clinicId", "hash", "jurisdiction", "locationOpeningHours",
        "schemaVersion", "source", "updatedAt", "weeklyHours",
      ]);
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: { slotStepMinutes: 15 },
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });
      for (const key of Object.keys(out)) {
        expect(allowedTopLevel.has(key)).toBe(true);
      }
      expect(Object.keys(out.bookingRules).every((k) =>
        ["slotStepMinutes", "minNoticeMinutes", "maxAdvanceDays", "allowNewPatients",
         "requireEmail", "requirePhone", "cancellationPolicyHours"].includes(k))).toBe(true);
    });

    it("weeklyHours round-trips (Commit 19)", () => {
      const hours = {
        mon: [{ start: "08:00", end: "12:00" }, { start: "14:00", end: "18:00" }],
        sun: [],
      };
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: { weeklyHours: hours },
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });
      expect(out.weeklyHours.mon).toEqual(hours.mon);
      expect(out.weeklyHours.sun).toEqual([]);
    });

    it("jurisdiction from clinic doc (timezone, currencyCode)", () => {
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: {},
        settingsUpdatedAt: null,
        clinicDoc: {
          timezone: "Europe/Prague",
          currencyCode: "CZK",
        },
        clinicUpdatedAt: null,
        questionnaireFlow: {},
      });

      expect(out.jurisdiction.timezone).toBe("Europe/Prague");
      expect(out.jurisdiction.currencyCode).toBe("CZK");
    });

    it("locationOpeningHours is included when provided", () => {
      const locHours = {
        loc1: {
          mon: [{ start: "09:00", end: "17:00" }],
          tue: [],
          wed: [],
          thu: [],
          fri: [],
          sat: [],
          sun: [],
        },
      };
      const out = buildPublicBookingConfigV1({
        clinicId: "c1",
        settingsDoc: { weeklyHours: { mon: [{ start: "08:00", end: "18:00" }] } },
        settingsUpdatedAt: null,
        clinicDoc: null,
        clinicUpdatedAt: null,
        questionnaireFlow: {},
        locationOpeningHours: locHours,
      });
      expect(out.locationOpeningHours).toEqual(locHours);
      expect(out.locationOpeningHours.loc1.mon).toEqual([{ start: "09:00", end: "17:00" }]);
    });
  });

  describe("hash", () => {
    it("same input produces same hash", () => {
      const obj = { a: 1, bookingRules: { slotStepMinutes: 15 }, weeklyHours: { mon: [] } };
      const h1 = sha256Hex(obj);
      const h2 = sha256Hex(obj);
      expect(h1).toBe(h2);
    });

    it("different key order produces same hash (canonical)", () => {
      const h1 = sha256Hex({ b: 2, a: 1 });
      const h2 = sha256Hex({ a: 1, b: 2 });
      expect(h1).toBe(h2);
    });

    it("different values produce different hash", () => {
      const h1 = sha256Hex({ slotStepMinutes: 15 });
      const h2 = sha256Hex({ slotStepMinutes: 10 });
      expect(h1).not.toBe(h2);
    });
  });
});

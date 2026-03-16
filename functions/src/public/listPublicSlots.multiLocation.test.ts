/**
 * Multi-location slot resolution tests.
 * - Clinic open, location closed → no slots
 * - Clinic open, location open, practitioner available → slots
 * - "Any location" (no location filter) → effective hours = clinic ∩ practitioner only
 */

import { describe, it, expect } from "@jest/globals";
import {
  intersectWeeklyHours,
  computeEffectiveWeeklyHours,
} from "./listPublicSlots";

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

function emptyWeekly(): Record<string, Array<{ start: string; end: string }>> {
  const out: Record<string, Array<{ start: string; end: string }>> = {};
  for (const k of DAY_KEYS) {
    out[k] = [];
  }
  return out;
}

function hasAnyHours(weekly: Record<string, Array<{ start: string; end: string }>>): boolean {
  return Object.values(weekly).some((arr) => Array.isArray(arr) && arr.length > 0);
}

describe("listPublicSlots multi-location slot resolution", () => {
  describe("intersectWeeklyHours", () => {
    it("clinic open Monday 08-18, location closed Monday → intersection has no Monday hours", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly();
      location.mon = []; // location closed Monday

      const result = intersectWeeklyHours(clinic, location);
      expect(result.mon).toEqual([]);
      expect(hasAnyHours(result)).toBe(false);
    });

    it("clinic open Monday 08-18, location open Monday 09-17 → intersection 09-17", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly();
      location.mon = [{ start: "09:00", end: "17:00" }];

      const result = intersectWeeklyHours(clinic, location);
      expect(result.mon).toEqual([{ start: "09:00", end: "17:00" }]);
      expect(hasAnyHours(result)).toBe(true);
    });
  });

  describe("computeEffectiveWeeklyHours", () => {
    it("clinic open, location closed on that day → no slots (effective has no hours)", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];
      clinic.tue = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly();
      location.mon = []; // location closed Monday
      location.tue = [{ start: "09:00", end: "17:00" }]; // location open Tuesday (so location filter is applied)

      const practitioner = emptyWeekly();
      practitioner.mon = [{ start: "09:00", end: "17:00" }];
      practitioner.tue = [{ start: "09:00", end: "17:00" }];

      const effective = computeEffectiveWeeklyHours(clinic, location, practitioner);
      expect(effective.mon).toEqual([]); // clinic open but location closed Monday → no Monday slots
      expect(effective.tue).toEqual([{ start: "09:00", end: "17:00" }]);
      expect(hasAnyHours(effective)).toBe(true);
    });

    it("clinic open, location open, practitioner available → slots shown", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly();
      location.mon = [{ start: "09:00", end: "17:00" }];

      const practitioner = emptyWeekly();
      practitioner.mon = [{ start: "10:00", end: "16:00" }];

      const effective = computeEffectiveWeeklyHours(clinic, location, practitioner);
      expect(effective.mon).toEqual([{ start: "10:00", end: "16:00" }]);
      expect(hasAnyHours(effective)).toBe(true);
    });

    it("Any location (null location): effective = clinic ∩ practitioner only", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];
      clinic.tue = [{ start: "08:00", end: "18:00" }];

      const practitioner = emptyWeekly();
      practitioner.mon = [{ start: "09:00", end: "17:00" }];
      practitioner.tue = [{ start: "09:00", end: "12:00" }];

      const effective = computeEffectiveWeeklyHours(clinic, null, practitioner);
      expect(effective.mon).toEqual([{ start: "09:00", end: "17:00" }]);
      expect(effective.tue).toEqual([{ start: "09:00", end: "12:00" }]);
      expect(hasAnyHours(effective)).toBe(true);
    });

    it("location with no hours (all empty) is treated as no restriction", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly(); // all days empty

      const practitioner = emptyWeekly();
      practitioner.mon = [{ start: "09:00", end: "17:00" }];

      const effective = computeEffectiveWeeklyHours(clinic, location, practitioner);
      expect(effective.mon).toEqual([{ start: "09:00", end: "17:00" }]);
      expect(hasAnyHours(effective)).toBe(true);
    });

    it("override does not create slots outside location hours", () => {
      const clinic = emptyWeekly();
      clinic.mon = [{ start: "08:00", end: "18:00" }];

      const location = emptyWeekly();
      location.mon = [{ start: "09:00", end: "12:00" }];

      const practitioner = emptyWeekly();
      practitioner.mon = [{ start: "08:00", end: "18:00" }];

      const effective = computeEffectiveWeeklyHours(clinic, location, practitioner);
      expect(effective.mon).toEqual([{ start: "09:00", end: "12:00" }]);
    });
  });
});

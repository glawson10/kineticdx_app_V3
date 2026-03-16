/**
 * Unit tests for location opening hours validation (location ⊆ clinic).
 */

import { locationHoursWithinClinic } from "./updateLocationWeeklyHours";

describe("updateLocationWeeklyHours", () => {
  describe("locationHoursWithinClinic", () => {
    const clinicMonToFri = {
      mon: [{ start: "08:00", end: "18:00" }],
      tue: [{ start: "08:00", end: "18:00" }],
      wed: [{ start: "08:00", end: "18:00" }],
      thu: [{ start: "08:00", end: "18:00" }],
      fri: [{ start: "08:00", end: "18:00" }],
      sat: [],
      sun: [],
    };

    it("allows location hours within clinic hours", () => {
      const location = {
        mon: [{ start: "09:00", end: "17:00" }],
        tue: [],
        wed: [{ start: "08:00", end: "12:00" }, { start: "14:00", end: "18:00" }],
        thu: [],
        fri: [],
        sat: [],
        sun: [],
      };
      const result = locationHoursWithinClinic(clinicMonToFri, location);
      expect(result.ok).toBe(true);
    });

    it("rejects location hours when clinic is closed that day", () => {
      const location = {
        mon: [],
        tue: [],
        wed: [],
        thu: [],
        fri: [],
        sat: [{ start: "10:00", end: "14:00" }],
        sun: [],
      };
      const result = locationHoursWithinClinic(clinicMonToFri, location);
      expect(result.ok).toBe(false);
      expect(result.message).toContain("sat");
      expect(result.message).toContain("clinic is closed");
    });

    it("rejects location hours extending outside clinic window", () => {
      const location = {
        mon: [{ start: "07:00", end: "10:00" }],
        tue: [],
        wed: [],
        thu: [],
        fri: [],
        sat: [],
        sun: [],
      };
      const result = locationHoursWithinClinic(clinicMonToFri, location);
      expect(result.ok).toBe(false);
      expect(result.message).toMatch(/extend outside|must fall within/);
    });

    it("allows empty location hours (no restriction)", () => {
      const location = {
        mon: [],
        tue: [],
        wed: [],
        thu: [],
        fri: [],
        sat: [],
        sun: [],
      };
      const result = locationHoursWithinClinic(clinicMonToFri, location);
      expect(result.ok).toBe(true);
    });
  });
});

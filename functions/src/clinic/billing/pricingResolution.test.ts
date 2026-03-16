/**
 * Phase 6A: Pricing resolution and duration rounding tests.
 */

import { describe, expect, it } from "@jest/globals";
import { roundDuration } from "./durationRounding";

describe("pricingResolution", () => {
  describe("roundDuration", () => {
    it("actual policy returns rounded minutes as-is", () => {
      expect(roundDuration(37, "actual")).toBe(37);
      expect(roundDuration(37.456, "actual")).toBe(37.46);
    });

    it("roundUpTo policy rounds up to next N minutes", () => {
      expect(roundDuration(1, "roundUpTo", { roundUpToMinutes: 15 })).toBe(15);
      expect(roundDuration(15, "roundUpTo", { roundUpToMinutes: 15 })).toBe(15);
      expect(roundDuration(16, "roundUpTo", { roundUpToMinutes: 15 })).toBe(30);
      expect(roundDuration(45, "roundUpTo", { roundUpToMinutes: 30 })).toBe(60);
    });

    it("minimumBillable policy uses at least minimum minutes", () => {
      expect(roundDuration(5, "minimumBillable", { minimumBillableMinutes: 15 })).toBe(15);
      expect(roundDuration(20, "minimumBillable", { minimumBillableMinutes: 15 })).toBe(20);
    });

    it("scheduled policy uses scheduled duration when provided", () => {
      expect(
        roundDuration(37, "scheduled", { scheduledDurationMinutes: 30 })
      ).toBe(30);
      expect(roundDuration(10, "scheduled", {})).toBe(10);
    });

    it("roundUpTo with 0 or negative does not break", () => {
      expect(roundDuration(10, "roundUpTo", { roundUpToMinutes: 0 })).toBe(10);
    });
  });
});

/**
 * Tests for buildPublicBookingProjection (full mirror: practitioners, services, etc.).
 * Verifies practitioner visibility: showInOnlineBooking, active, membership.
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

import { buildPublicBookingProjection } from "./publicProjection";

describe("publicProjection", () => {
  describe("buildPublicBookingProjection practitioners", () => {
    it("includes practitioner with showInOnlineBooking true", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: true,
              active: true,
            },
          },
        ],
        memberships: [],
      });

      expect(out.practitioners).toHaveLength(1);
      expect(out.practitioners![0].id).toBe("p1");
      expect(out.practitioners![0].displayName).toBe("Dr One");
    });

    it("excludes practitioner with showInOnlineBooking false", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: false,
              active: true,
            },
          },
        ],
        memberships: [],
      });

      expect(out.practitioners).toHaveLength(0);
    });

    it("excludes practitioner with active false", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: true,
              active: false,
            },
          },
        ],
        memberships: [],
      });

      expect(out.practitioners).toHaveLength(0);
    });

    it("excludes practitioner when membership exists and is inactive", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: true,
              active: true,
            },
          },
        ],
        memberships: [
          {
            id: "p1",
            data: { status: "suspended", displayName: "Dr One" },
          },
        ],
      });

      expect(out.practitioners).toHaveLength(0);
    });

    it("includes practitioner when membership exists and is active", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: true,
              active: true,
            },
          },
        ],
        memberships: [
          {
            id: "p1",
            data: { status: "active", displayName: "Dr One" },
          },
        ],
      });

      expect(out.practitioners).toHaveLength(1);
      expect(out.practitioners![0].displayName).toBe("Dr One");
    });

    it("includes allowedLocationIds when set on practitioner", () => {
      const out = buildPublicBookingProjection({
        clinicId: "c1",
        clinicName: "Test Clinic",
        logoUrl: "",
        publicBookingSettingsDoc: {},
        services: [],
        practitioners: [
          {
            id: "p1",
            data: {
              displayName: "Dr One",
              showInOnlineBooking: true,
              active: true,
              allowedLocationIds: ["loc1", "loc2"],
            },
          },
        ],
        memberships: [],
      });

      expect(out.practitioners).toHaveLength(1);
      expect(out.practitioners![0].allowedLocationIds).toEqual(["loc1", "loc2"]);
    });
  });
});

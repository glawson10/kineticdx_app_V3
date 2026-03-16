/**
 * Phase 6A: Pricing Rules Foundation.
 * Deterministic resolution order: client override → appointment-type practitioner → appointment-type default → practitioner hourly → clinic fallback.
 * Changing a pricing rule must never rewrite issued or historic invoices; invoice lines store a frozen snapshot at issue time.
 */

import type { Firestore } from "firebase-admin/firestore";
import { roundMoney } from "./common";
import {
  billingPricingSettingsRef,
  billingPractitionerRatesCol,
  billingClientPricingOverridesCol,
  billingAppointmentTypePractitionerPricesCol,
} from "./common";
import { roundDuration as roundDurationPure, type DurationRoundingPolicy } from "./durationRounding";

export type { DurationRoundingPolicy };

export type PricingSource =
  | "clientOverride"
  | "appointmentTypePractitioner"
  | "appointmentTypeDefault"
  | "practitionerHourly"
  | "clinicFallback";

export type PricingResult = {
  amount: number;
  source: PricingSource;
  /** Snapshot of the rule that produced this price (for storage on invoice line; never used to rewrite issued invoices). */
  sourceSnapshot: {
    source: PricingSource;
    /** For hourly: rounded billable minutes. */
    durationMinutes?: number;
    /** Rate or fixed value used. */
    rateOrFixed?: number;
    /** Human-readable description of the rule (e.g. "Client override", "Appointment type: Initial Assessment"). */
    description?: string;
  };
};

export type PricingContext = {
  clinicId: string;
  patientId?: string | null;
  practitionerId?: string | null;
  appointmentTypeId?: string | null;
  /** Duration in minutes (actual or scheduled depending on policy). */
  durationMinutes?: number | null;
  /** When policy is "scheduled", use this as the scheduled duration (e.g. from appointment type). */
  scheduledDurationMinutes?: number | null;
};

type PricingSettingsDoc = {
  defaultHourlyRate?: number;
  defaultFixedRate?: number;
  durationRoundingPolicy?: DurationRoundingPolicy;
  durationRoundingMinutes?: number;
  minimumBillableMinutes?: number;
};

/** Re-export for callers that need duration rounding without loading Firestore. */
export { roundDuration } from "./durationRounding";

function roundDurationWithOptions(
  durationMinutes: number,
  policy: DurationRoundingPolicy | undefined,
  options: { roundUpToMinutes?: number; minimumBillableMinutes?: number; scheduledDurationMinutes?: number }
): number {
  return roundDurationPure(durationMinutes, policy, options);
}

/**
 * Loads clinic pricing settings (default rates + duration policy).
 */
async function loadPricingSettings(
  db: Firestore,
  clinicId: string
): Promise<PricingSettingsDoc | null> {
  const ref = billingPricingSettingsRef(clinicId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const d = snap.data() as Record<string, unknown> | undefined;
  if (!d) return null;
  return {
    defaultHourlyRate: typeof d.defaultHourlyRate === "number" ? d.defaultHourlyRate : undefined,
    defaultFixedRate: typeof d.defaultFixedRate === "number" ? d.defaultFixedRate : undefined,
    durationRoundingPolicy: (d.durationRoundingPolicy as DurationRoundingPolicy) ?? "actual",
    durationRoundingMinutes:
      typeof d.durationRoundingMinutes === "number" ? d.durationRoundingMinutes : 15,
    minimumBillableMinutes:
      typeof d.minimumBillableMinutes === "number" ? d.minimumBillableMinutes : 15,
  };
}

/**
 * Resolves price for the given context using the mandatory resolution order.
 * Used when building draft invoice lines; result must be snapshot into the line so issued invoices are never rewritten.
 */
export async function resolvePrice(
  db: Firestore,
  ctx: PricingContext
): Promise<PricingResult | null> {
  const durationMinutes = Number(ctx.durationMinutes ?? 0) || 0;
  const scheduledDurationMinutes = Number(ctx.scheduledDurationMinutes ?? 0) || 0;
  const settings = await loadPricingSettings(db, ctx.clinicId);
  const policy = (settings?.durationRoundingPolicy ?? "actual") as DurationRoundingPolicy;
  const roundUpTo = settings?.durationRoundingMinutes ?? 15;
  const minBillable = settings?.minimumBillableMinutes ?? 15;
  const roundedMinutes = roundDurationWithOptions(durationMinutes, policy, {
    roundUpToMinutes: roundUpTo,
    minimumBillableMinutes: minBillable,
    scheduledDurationMinutes,
  });

  // 1. Client-specific override
  if (ctx.patientId?.trim()) {
    const overrideRef = billingClientPricingOverridesCol(ctx.clinicId).doc(ctx.patientId.trim());
    const overrideSnap = await overrideRef.get();
    if (overrideSnap.exists) {
      const data = overrideSnap.data() as Record<string, unknown> | undefined;
      const type = String(data?.type ?? "fixed").trim();
      const value = Number(data?.value ?? data?.amount ?? 0);
      if (Number.isFinite(value) && value >= 0) {
        const amount =
          type === "hourly"
            ? roundMoney((value / 60) * roundedMinutes)
            : roundMoney(value);
        return {
          amount,
          source: "clientOverride",
          sourceSnapshot: {
            source: "clientOverride",
            durationMinutes: type === "hourly" ? roundedMinutes : undefined,
            rateOrFixed: value,
            description: "Client override",
          },
        };
      }
    }
  }

  // 2. Appointment-type practitioner override
  if (ctx.appointmentTypeId?.trim() && ctx.practitionerId?.trim()) {
    const atRef = billingAppointmentTypePractitionerPricesCol(ctx.clinicId).doc(
      ctx.appointmentTypeId.trim()
    );
    const atSnap = await atRef.get();
    if (atSnap.exists) {
      const data = atSnap.data() as Record<string, unknown> | undefined;
      const overrides = (data?.practitionerOverrides ?? data) as Record<string, number> | undefined;
      const price = overrides?.[ctx.practitionerId!.trim()];
      if (typeof price === "number" && Number.isFinite(price) && price >= 0) {
        return {
          amount: roundMoney(price),
          source: "appointmentTypePractitioner",
          sourceSnapshot: {
            source: "appointmentTypePractitioner",
            rateOrFixed: price,
            description: "Appointment type (practitioner override)",
          },
        };
      }
    }
  }

  // 3. Appointment-type default
  if (ctx.appointmentTypeId?.trim()) {
    const atRef = db
      .collection("clinics")
      .doc(ctx.clinicId)
      .collection("appointmentTypes")
      .doc(ctx.appointmentTypeId.trim());
    const atSnap = await atRef.get();
    if (atSnap.exists) {
      const data = atSnap.data() as Record<string, unknown> | undefined;
      const defaultPrice = data?.defaultPrice;
      if (typeof defaultPrice === "number" && Number.isFinite(defaultPrice) && defaultPrice >= 0) {
        return {
          amount: roundMoney(defaultPrice),
          source: "appointmentTypeDefault",
          sourceSnapshot: {
            source: "appointmentTypeDefault",
            rateOrFixed: defaultPrice,
            description: "Appointment type default",
          },
        };
      }
    }
  }

  // 4. Practitioner hourly default
  if (ctx.practitionerId?.trim()) {
    const pracRef = billingPractitionerRatesCol(ctx.clinicId).doc(ctx.practitionerId.trim());
    const pracSnap = await pracRef.get();
    if (pracSnap.exists) {
      const data = pracSnap.data() as Record<string, unknown> | undefined;
      const hourlyRate = Number(data?.hourlyRate ?? data?.rate ?? 0);
      if (Number.isFinite(hourlyRate) && hourlyRate >= 0) {
        const amount = roundMoney((hourlyRate / 60) * roundedMinutes);
        return {
          amount,
          source: "practitionerHourly",
          sourceSnapshot: {
            source: "practitionerHourly",
            durationMinutes: roundedMinutes,
            rateOrFixed: hourlyRate,
            description: "Practitioner hourly",
          },
        };
      }
    }
  }

  // 5. Clinic default fallback
  if (settings) {
    if (
      typeof settings.defaultFixedRate === "number" &&
      Number.isFinite(settings.defaultFixedRate) &&
      settings.defaultFixedRate >= 0
    ) {
      return {
        amount: roundMoney(settings.defaultFixedRate),
        source: "clinicFallback",
        sourceSnapshot: {
          source: "clinicFallback",
          rateOrFixed: settings.defaultFixedRate,
          description: "Clinic default (fixed)",
        },
      };
    }
    if (
      typeof settings.defaultHourlyRate === "number" &&
      Number.isFinite(settings.defaultHourlyRate) &&
      settings.defaultHourlyRate >= 0
    ) {
      const amount = roundMoney((settings.defaultHourlyRate / 60) * roundedMinutes);
      return {
        amount,
        source: "clinicFallback",
        sourceSnapshot: {
          source: "clinicFallback",
          durationMinutes: roundedMinutes,
          rateOrFixed: settings.defaultHourlyRate,
          description: "Clinic default (hourly)",
        },
      };
    }
  }

  return null;
}

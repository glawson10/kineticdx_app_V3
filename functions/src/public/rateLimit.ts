import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import crypto from "crypto";

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function sha256Hex(input: string): string {
  return crypto.createHash("sha256").update(input).digest("hex");
}

export type RateLimitConfig = {
  name: string; // endpoint name
  max: number; // max requests per window
  windowSeconds: number;
};

type MaybeReqLike =
  | {
      headers?: Record<string, any>;
      ip?: string;
      socket?: { remoteAddress?: string };
      connection?: { remoteAddress?: string };
    }
  | undefined
  | null;

function getClientIp(req: MaybeReqLike): string {
  const headers = req?.headers ?? {};

  // Express will often provide these; Cloud Run / proxies usually set x-forwarded-for
  const xf = safeStr(headers["x-forwarded-for"] ?? headers["X-Forwarded-For"]);
  const ipFromXf = (xf.split(",")[0] || "").trim();

  const direct =
    safeStr((req as any)?.ip) ||
    safeStr((req as any)?.socket?.remoteAddress) ||
    safeStr((req as any)?.connection?.remoteAddress);

  return (ipFromXf || direct || "unknown").trim();
}

export async function enforceRateLimit(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  req?: MaybeReqLike; // <-- now optional
  cfg: RateLimitConfig;
}) {
  const { db, clinicId, req, cfg } = params;

  const ip = getClientIp(req);

  const keyRaw = `${cfg.name}|${clinicId}|${ip}`;
  const key = sha256Hex(keyRaw);

  const ref = db.collection("publicRateLimits").doc(key);

  const nowMs = Date.now();
  const windowMs = Math.max(1, cfg.windowSeconds) * 1000;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    let count = 0;
    let windowStartMs = nowMs;

    if (snap.exists) {
      const d = snap.data() as any;
      count = typeof d.count === "number" ? d.count : 0;
      windowStartMs = typeof d.windowStartMs === "number" ? d.windowStartMs : nowMs;
    }

    // Reset window if expired
    if (nowMs - windowStartMs >= windowMs) {
      count = 0;
      windowStartMs = nowMs;
    }

    if (count >= cfg.max) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again shortly.");
    }

    // Optional: enable TTL on expiresAt in Firestore later
    const expiresAt = admin.firestore.Timestamp.fromMillis(windowStartMs + windowMs + 60_000);

    tx.set(
      ref,
      {
        name: cfg.name,
        clinicId,
        ip,
        count: count + 1,
        windowStartMs,
        expiresAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

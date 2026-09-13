import { getDb, FieldValue } from "../firebaseAdmin.js";
import { BackendError } from "../types.js";
import * as crypto from "crypto";

function sanitizeKey(key: string): string {
  // Hash long or complex keys to a safe document ID
  const hash = crypto.createHash("sha256").update(key).digest("hex");
  const prefix = key.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 30);
  return `${prefix}_${hash.slice(0, 16)}`;
}

export async function checkRateLimit(
  key: string,
  maxAttempts: number,
  windowSeconds: number,
  customMessage?: string,
): Promise<void> {
  const database = getDb();
  const docId = sanitizeKey(key);
  const ref = database.collection("rateLimits").doc(docId);
  const now = Date.now();

  await database.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      const data = snap.data()!;
      const resetAt = Number(data.resetAt || 0);

      if (now < resetAt) {
        const attempts = Number(data.attempts || 0);
        if (attempts >= maxAttempts) {
          const waitMinutes = Math.ceil((resetAt - now) / 60000);
          throw new BackendError(
            "resource-exhausted",
            customMessage ||
              `Rate limit exceeded. Please try again in ${waitMinutes} minute(s).`,
          );
        }
        transaction.update(ref, {
          attempts: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }
    }

    // New window
    transaction.set(ref, {
      key,
      attempts: 1,
      resetAt: now + windowSeconds * 1000,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export async function checkLockout(
  key: string,
  lockoutMessage?: string,
): Promise<void> {
  const database = getDb();
  const docId = sanitizeKey(key);
  const ref = database.collection("rateLimits").doc(docId);
  const snap = await ref.get();

  if (snap.exists) {
    const data = snap.data()!;
    const lockedUntil = Number(data.lockedUntil || 0);
    const now = Date.now();

    if (now < lockedUntil) {
      const waitMinutes = Math.ceil((lockedUntil - now) / 60000);
      throw new BackendError(
        "resource-exhausted",
        lockoutMessage ||
          `Too many failed attempts. Access is locked for ${waitMinutes} more minute(s).`,
      );
    }
  }
}

export async function recordFailedAttempt(
  key: string,
  maxFailures: number,
  lockoutSeconds: number,
): Promise<void> {
  const database = getDb();
  const docId = sanitizeKey(key);
  const ref = database.collection("rateLimits").doc(docId);
  const now = Date.now();

  await database.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    let failures = 1;

    if (snap.exists) {
      const data = snap.data()!;
      const lockedUntil = Number(data.lockedUntil || 0);
      if (now < lockedUntil) {
        return; // Already locked
      }
      failures = Number(data.failures || 0) + 1;
    }

    const updates: Record<string, any> = {
      key,
      failures,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (failures >= maxFailures) {
      updates.lockedUntil = now + lockoutSeconds * 1000;
      updates.failures = 0; // Reset failures for next window
    }

    transaction.set(ref, updates, { merge: true });
  });
}

export async function clearFailedAttempts(key: string): Promise<void> {
  const database = getDb();
  const docId = sanitizeKey(key);
  const ref = database.collection("rateLimits").doc(docId);
  await ref.delete().catch(() => {});
}

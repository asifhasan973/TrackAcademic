import * as crypto from "crypto";
import { getAuthService, getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  BackendError,
  RegistrationData,
  RequestContext,
  requiredString,
  validateEmail,
  validateInstitutionId,
  validatePassword,
} from "../../types.js";
import {
  checkRateLimit,
  checkLockout,
  recordFailedAttempt,
  clearFailedAttempts,
} from "../../middleware/rateLimit.js";

function safeCompare(a: string, b: string): boolean {
  const hashA = crypto.createHash("sha256").update(a).digest();
  const hashB = crypto.createHash("sha256").update(b).digest();
  return crypto.timingSafeEqual(hashA, hashB);
}

export async function registerUser(
  data: RegistrationData,
  context: RequestContext,
): Promise<{ success: boolean; uid: string; role: string }> {
  if (context.auth) {
    throw new BackendError(
      "failed-precondition",
      "Sign out before creating another account.",
    );
  }

  const clientIp = context.ip || "unknown_ip";
  await checkRateLimit(`reg_ip_${clientIp}`, 10, 3600, "Too many registration attempts from this network. Please try again later.");

  const displayName = requiredString(data.displayName, "Full name", 2, 80);
  const email = validateEmail(data.email);
  const institutionId = validateInstitutionId(data.institutionId);
  const password = validatePassword(data.password);

  if (
    typeof data.role !== "string" ||
    (data.role !== "teacher" && data.role !== "student")
  ) {
    throw new BackendError(
      "invalid-argument",
      "Role must be either 'teacher' or 'student'.",
    );
  }
  const role = data.role;

  // Teacher role protection
  if (role === "teacher") {
    const configuredSecret = process.env.TEACHER_INVITE_SECRET?.trim();
    if (!configuredSecret) {
      throw new BackendError(
        "permission-denied",
        "Teacher self-registration is disabled. Please contact your department administrator for account provisioning.",
      );
    }

    const lockoutKey = `teacher_invite_${clientIp}`;
    await checkLockout(lockoutKey, "Too many failed teacher code attempts. Registration locked.");

    const submittedSecret = typeof data.inviteSecret === "string" ? data.inviteSecret.trim() : "";
    if (!submittedSecret || !safeCompare(submittedSecret, configuredSecret)) {
      await recordFailedAttempt(lockoutKey, 4, 900);
      throw new BackendError(
        "permission-denied",
        "Invalid teacher authorization code.",
      );
    }

    await clearFailedAttempts(lockoutKey);
  }

  const database = getDb();
  const auth = getAuthService();

  const existingInstitutionId = await database
    .collection("users")
    .where("institutionId", "==", institutionId)
    .limit(1)
    .get();

  if (!existingInstitutionId.empty) {
    throw new BackendError(
      "already-exists",
      "An account already uses this institution ID.",
    );
  }

  const institutionReference = database
    .collection("institutionIds")
    .doc(institutionId);

  const isEmulator =
    process.env.FUNCTIONS_EMULATOR === "true" ||
    !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const emailVerified = isEmulator;

  let createdUserId: string | null = null;

  try {
    const user = await auth.createUser({
      displayName,
      email,
      password,
      emailVerified,
      disabled: false,
    });

    createdUserId = user.uid;

    await auth.setCustomUserClaims(user.uid, {
      institutionId,
      role,
    });

    await database.runTransaction(async (transaction) => {
      const reservation = await transaction.get(institutionReference);

      if (reservation.exists) {
        throw new BackendError(
          "already-exists",
          "An account already uses this institution ID.",
        );
      }

      const timestamp = FieldValue.serverTimestamp();
      const userReference = database.collection("users").doc(user.uid);
      const auditReference = database.collection("auditLogs").doc();

      transaction.create(institutionReference, {
        userId: user.uid,
        institutionId,
        createdAt: timestamp,
      });

      transaction.create(userReference, {
        uid: user.uid,
        displayName,
        email,
        institutionId,
        role,
        isActive: true,
        emailVerified,
        phone: null,
        photoUrl: null,
        department: null,
        batch: null,
        section: null,
        semester: null,
        courseIds: [],
        notificationPreferences: {
          attendance: true,
          marks: true,
          schedule: true,
        },
        createdAt: timestamp,
        updatedAt: timestamp,
      });

      transaction.create(auditReference, {
        action: "user.registered",
        actorId: user.uid,
        actorRole: role,
        targetId: user.uid,
        metadata: {
          institutionId,
          role,
          email,
        },
        createdAt: timestamp,
      });
    });

    return {
      success: true,
      uid: user.uid,
      role,
    };
  } catch (error: any) {
    if (createdUserId) {
      try {
        await auth.deleteUser(createdUserId);
      } catch (_) {}
    }

    if (error instanceof BackendError) {
      throw error;
    }

    if (error.code === "auth/email-already-exists") {
      throw new BackendError(
        "already-exists",
        "An account already uses this email address.",
      );
    }

    throw new BackendError(
      "internal",
      error.message || "Registration failed. Please try again.",
    );
  }
}

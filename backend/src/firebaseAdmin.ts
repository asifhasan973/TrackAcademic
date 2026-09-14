import { getApps, initializeApp, cert, App } from "firebase-admin/app";
import { getAuth, Auth } from "firebase-admin/auth";
import { getFirestore, Firestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging, Messaging } from "firebase-admin/messaging";

export const EXPECTED_PROJECT_ID = "trackacademic-c0d1c";

let appInstance: App | null = null;

export function checkProductionSafeguards(): void {
  const isProduction = process.env.NODE_ENV === "production" || process.env.VERCEL === "1";
  if (!isProduction) return;

  const emulatorFlags = [
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIRESTORE_EMULATOR_HOST",
    "FIREBASE_EMULATOR_HOST",
    "FIREBASE_STORAGE_EMULATOR_HOST",
    "FIREBASE_DATABASE_EMULATOR_HOST",
  ];

  for (const flag of emulatorFlags) {
    if (process.env[flag]) {
      throw new Error(
        `SECURITY FAULT: Emulator environment variable '${flag}' detected in production mode. Refusing to start.`,
      );
    }
  }

  const bypassFlags = [
    "FUNCTIONS_EMULATOR",
    "USE_FIREBASE_EMULATORS",
    "DEMO_BUILD",
  ];

  for (const flag of bypassFlags) {
    const val = process.env[flag];
    if (val === "true" || val === "1") {
      throw new Error(
        `SECURITY FAULT: Bypass setting '${flag}=${val}' detected in production mode. Refusing to start.`,
      );
    }
  }
}

export function initFirebaseAdmin(): App {
  // Always apply production safeguards first, even before checking existing app instances
  checkProductionSafeguards();

  if (appInstance) {
    const projId = appInstance.options.projectId;
    if (projId && projId !== EXPECTED_PROJECT_ID) {
      throw new Error(
        `SECURITY FAULT: Cached Firebase app targets unexpected project '${projId}', expected '${EXPECTED_PROJECT_ID}'.`,
      );
    }
    return appInstance;
  }

  const existingApps = getApps();
  if (existingApps.length > 0 && existingApps[0]) {
    const existing = existingApps[0];
    const existingProjId = existing.options.projectId;
    if (existingProjId && existingProjId !== EXPECTED_PROJECT_ID) {
      throw new Error(
        `SECURITY FAULT: Existing Firebase app targets unexpected project '${existingProjId}', expected '${EXPECTED_PROJECT_ID}'.`,
      );
    }
    appInstance = existing;
    return appInstance;
  }

  const isProduction = process.env.NODE_ENV === "production" || process.env.VERCEL === "1";

  if (isProduction) {
    const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = process.env.FIREBASE_PRIVATE_KEY;
    const projectId = process.env.FIREBASE_PROJECT_ID || EXPECTED_PROJECT_ID;

    if (projectId !== EXPECTED_PROJECT_ID) {
      throw new Error(
        `SECURITY FAULT: Expected project ID ${EXPECTED_PROJECT_ID}, got ${projectId}`,
      );
    }

    if (rawServiceAccount) {
      try {
        const parsed = JSON.parse(rawServiceAccount);
        if (parsed.project_id !== EXPECTED_PROJECT_ID) {
          throw new Error(
            `SECURITY FAULT: Service account project_id ${parsed.project_id} does not match ${EXPECTED_PROJECT_ID}`,
          );
        }
        appInstance = initializeApp({
          credential: cert(parsed),
          projectId: EXPECTED_PROJECT_ID,
        });
        return appInstance;
      } catch (err: any) {
        throw new Error(`SECURITY FAULT: Failed to parse FIREBASE_SERVICE_ACCOUNT: ${err.message}`);
      }
    } else if (clientEmail && privateKey) {
      const formattedKey = privateKey.replace(/\\n/g, "\n");
      appInstance = initializeApp({
        credential: cert({
          projectId: EXPECTED_PROJECT_ID,
          clientEmail,
          privateKey: formattedKey,
        }),
        projectId: EXPECTED_PROJECT_ID,
      });
      return appInstance;
    } else {
      throw new Error(
        "SECURITY FAULT: Production Firebase credentials missing. Set FIREBASE_SERVICE_ACCOUNT or FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY.",
      );
    }
  }

  // Development / Emulator mode
  appInstance = initializeApp({
    projectId: EXPECTED_PROJECT_ID,
  });
  return appInstance;
}

export function getDb(): Firestore {
  initFirebaseAdmin();
  return getFirestore();
}

export function getAuthService(): Auth {
  initFirebaseAdmin();
  return getAuth();
}

export function getMessagingService(): Messaging {
  initFirebaseAdmin();
  return getMessaging();
}

export { FieldValue, Timestamp };

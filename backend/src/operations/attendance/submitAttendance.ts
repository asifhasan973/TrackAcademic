import { getDb, FieldValue, Timestamp } from "../../firebaseAdmin.js";
import { requireActiveStudent } from "../../middleware/auth.js";
import {
  checkLockout,
  recordFailedAttempt,
  clearFailedAttempts,
} from "../../middleware/rateLimit.js";
import {
  BackendError,
  SubmitAttendanceData,
  RequestContext,
  requiredString,
  optionalString,
  optionalNumber,
  requiredNumber,
  verifyPasscode,
  distanceMeters,
} from "../../types.js";

export async function submitAttendance(
  data: SubmitAttendanceData,
  context: RequestContext,
): Promise<{
  success: boolean;
  status: string;
  distanceMeters?: number;
  message?: string;
}> {
  const studentId = context.auth?.uid;

  if (!studentId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  const student = await requireActiveStudent(studentId, context.auth);
  const sessionId = requiredString(data.sessionId, "Session ID", 1, 128);

  const database = getDb();
  const sessionReference = database.collection("attendanceSessions").doc(sessionId);
  const recordReference = database
    .collection("attendanceRecords")
    .doc(`${sessionId}_${studentId}`);

  // Fetch session and private configuration
  const sessionDocument = await sessionReference.get();
  const session = sessionDocument.data();

  if (!sessionDocument.exists || !session) {
    throw new BackendError("not-found", "Attendance session not found.");
  }

  if (session.status !== "active") {
    throw new BackendError(
      "failed-precondition",
      "This attendance session is closed.",
    );
  }

  const configDoc = await sessionReference
    .collection("private")
    .doc("config")
    .get();
  const configuration = configDoc.data() ?? {};

  // Passcode verification with brute-force protection
  if (session.requiresPasscode === true) {
    const lockoutKey = `passcode_${sessionId}_${studentId}`;
    await checkLockout(
      lockoutKey,
      "Too many incorrect passcode attempts for this session. Submission locked.",
    );

    const submittedPasscode = optionalString(data.passcode, "Passcode", 16);
    if (!submittedPasscode) {
      throw new BackendError("invalid-argument", "Passcode is required.");
    }

    const storedHash = configuration.passcodeHash;
    const storedSalt = configuration.passcodeSalt;

    if (typeof storedHash !== "string" || typeof storedSalt !== "string") {
      throw new BackendError(
        "failed-precondition",
        "Passcode is not configured for this session.",
      );
    }

    const valid = verifyPasscode(submittedPasscode, storedSalt, storedHash);
    if (!valid) {
      await recordFailedAttempt(lockoutKey, 5, 600);
      throw new BackendError("invalid-argument", "Incorrect passcode.");
    }

    await clearFailedAttempts(lockoutKey);
  }

  // GPS verification
  let measuredDistance: number | null = null;
  let measuredAccuracy: number | null = null;
  if (session.requiresGps === true) {
    const studentLat = requiredNumber(data.latitude, "Latitude", -90, 90);
    const studentLng = requiredNumber(data.longitude, "Longitude", -180, 180);

    const centerLat = configuration.latitude;
    const centerLng = configuration.longitude;
    const radiusMeters = configuration.radiusMeters;

    if (
      typeof centerLat !== "number" ||
      typeof centerLng !== "number" ||
      typeof radiusMeters !== "number"
    ) {
      throw new BackendError(
        "failed-precondition",
        "GPS location is not configured for this session.",
      );
    }

    // Reject missing or invalid metadata for GPS sessions (treat client metadata as untrusted)
    const accuracy = optionalNumber(data.accuracy, "Accuracy", 0, 100000);
    const clientTime = optionalNumber(data.timestamp, "Timestamp", 0, 9999999999999);

    if (accuracy === null || accuracy === undefined || isNaN(accuracy) || accuracy <= 0) {
      throw new BackendError(
        "invalid-argument",
        "GPS accuracy metadata is required for GPS attendance sessions.",
      );
    }

    if (clientTime === null || clientTime === undefined || isNaN(clientTime) || clientTime <= 0) {
      throw new BackendError(
        "invalid-argument",
        "GPS timestamp metadata is required for GPS attendance sessions.",
      );
    }

    // Freshness validation
    const now = Date.now();
    if (now - clientTime > 120000) {
      throw new BackendError(
        "failed-precondition",
        "Location reading is stale (> 120s old). Please obtain a fresh GPS fix and retry.",
      );
    }
    if (clientTime - now > 10000) {
      throw new BackendError(
        "failed-precondition",
        "Location timestamp is invalid (in the future). Check device clock and retry.",
      );
    }

    // Uncertainty policy:
    // Maximum allowable student uncertainty is min(50m, radiusMeters).
    // If accuracy uncertainty exceeds this, signal quality is inconclusive for room presence.
    const maxAcceptableAccuracy = Math.min(50, radiusMeters);
    if (accuracy > maxAcceptableAccuracy) {
      throw new BackendError(
        "failed-precondition",
        `GPS signal quality is inconclusive (uncertainty ±${Math.round(accuracy)}m for a ${radiusMeters}m radius). Please move outdoors or near a window and retry.`,
      );
    }

    measuredAccuracy = Math.round(accuracy);
    measuredDistance = distanceMeters(studentLat, studentLng, centerLat, centerLng);

    // Strict boundary enforcement: NEVER silently expand the radius.
    if (measuredDistance > radiusMeters) {
      const distRounded = Math.round(measuredDistance);
      throw new BackendError(
        "failed-precondition",
        `You are outside the required attendance area. Measured distance: ${distRounded}m (allowed radius: ${radiusMeters}m).`,
      );
    }
  }

  // Transactional submission
  return await database.runTransaction(async (transaction) => {
    const liveSessionDoc = await transaction.get(sessionReference);
    if (!liveSessionDoc.exists || !liveSessionDoc.data()) {
      throw new BackendError("not-found", "Attendance session not found.");
    }
    const liveSession = liveSessionDoc.data()!;

    if (liveSession.status !== "active") {
      throw new BackendError(
        "failed-precondition",
        "This attendance session is closed.",
      );
    }

    const courseId = String(liveSession.courseId);
    const courseDoc = await transaction.get(database.collection("courses").doc(courseId));
    if (!courseDoc.exists || courseDoc.data()?.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const enrollmentDoc = await transaction.get(
      database.collection("courses").doc(courseId).collection("students").doc(studentId),
    );
    if (!enrollmentDoc.exists || enrollmentDoc.data()?.isActive === false) {
      throw new BackendError("permission-denied", "You are not enrolled in this course.");
    }

    const endsAt = liveSession.endsAt;
    const nowMillis = Date.now();
    const isLate =
      endsAt instanceof Timestamp
        ? endsAt.toMillis() < nowMillis
        : (endsAt ? new Date(endsAt).getTime() < nowMillis : false);

    if (isLate && liveSession.allowLateEntry !== true) {
      throw new BackendError(
        "deadline-exceeded",
        "This attendance session has expired.",
      );
    }

    const existingRecord = await transaction.get(recordReference);
    if (existingRecord.exists) {
      const recData = existingRecord.data();
      if (recData?.status === "present" || recData?.status === "late") {
        return {
          success: true,
          status: recData.status,
          distanceMeters: measuredDistance ? Math.round(measuredDistance) : undefined,
          message: "Attendance was already submitted successfully.",
        };
      }
    }

    const recordStatus = isLate ? "late" : "present";
    const timestamp = FieldValue.serverTimestamp();

    const attendanceData: Record<string, any> = {
      sessionId,
      courseId,
      courseCode: liveSession.courseCode ?? "",
      courseName: liveSession.courseName ?? "",
      studentId,
      institutionId: student.institutionId ?? "",
      studentName: student.displayName ?? "",
      status: recordStatus,
      markedBy: "student",
      markedByUid: studentId,
      source: "self",
      verifiedPasscode: session.requiresPasscode === true,
      verifiedGps: session.requiresGps === true,
      markedAt: timestamp,
      updatedAt: timestamp,
    };

    if (measuredDistance !== null) {
      attendanceData.measuredDistanceMeters = Math.round(measuredDistance);
    }

    if (measuredAccuracy !== null) {
      attendanceData.studentAccuracyMeters = measuredAccuracy;
    }

    transaction.set(recordReference, attendanceData, { merge: true });

    return {
      success: true,
      status: recordStatus,
      distanceMeters: measuredDistance ? Math.round(measuredDistance) : undefined,
    };
  });
}

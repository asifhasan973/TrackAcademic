import * as crypto from "crypto";
import { getDb, FieldValue, Timestamp } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  requireActiveOwnedCourse,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  CreateAttendanceSessionData,
  RequestContext,
  requiredString,
  requiredNumber,
  optionalNumber,
  requiredBoolean,
  hashPasscode,
} from "../../types.js";

export async function createAttendanceSession(
  data: CreateAttendanceSessionData,
  context: RequestContext,
): Promise<{
  sessionId: string;
  passcode: string | null;
  courseId: string;
  startedAt: string;
  endsAt: string;
}> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  const teacher = await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  await requireActiveOwnedCourse(teacherId, courseId, context.auth);

  const classType = requiredString(data.classType, "Class type", 2, 40);
  if (classType !== "Theory" && classType !== "Sessional") {
    throw new BackendError(
      "invalid-argument",
      "Class type must be either 'Theory' or 'Sessional'.",
    );
  }

  const durationMinutes = requiredNumber(data.durationMinutes, "Duration", 1, 180);
  const requiresPasscode = requiredBoolean(data.requiresPasscode, "Passcode requirement");
  const requiresGps = requiredBoolean(data.requiresGps, "GPS requirement");
  const allowLateEntry = requiredBoolean(data.allowLateEntry, "Late-entry setting");

  let passcode: string | null = null;
  let passcodeHash: string | null = null;
  let passcodeSalt: string | null = null;

  if (requiresPasscode) {
    if (data.passcode !== undefined && data.passcode !== null && data.passcode !== "") {
      passcode = requiredString(data.passcode, "Passcode", 4, 8);
      if (!/^\d+$/.test(passcode)) {
        throw new BackendError("invalid-argument", "Passcode must contain digits only.");
      }
    } else {
      passcode = String(crypto.randomInt(100000, 1000000));
    }

    passcodeSalt = crypto.randomBytes(16).toString("hex");
    passcodeHash = hashPasscode(passcode, passcodeSalt);
  }

  let latitude: number | null = null;
  let longitude: number | null = null;
  let radiusMeters: number | null = null;
  let centerAccuracyMeters: number | null = null;

  if (requiresGps) {
    latitude = requiredNumber(data.latitude, "Latitude", -90, 90);
    longitude = requiredNumber(data.longitude, "Longitude", -180, 180);
    radiusMeters = requiredNumber(data.radiusMeters, "Radius", 5, 5000);

    const teacherAccuracy = optionalNumber(data.accuracy, "Accuracy", 0, 100000);
    const teacherTimestamp = optionalNumber(data.timestamp, "Timestamp", 0, 9999999999999);

    if (
      teacherAccuracy === null ||
      teacherAccuracy === undefined ||
      isNaN(teacherAccuracy) ||
      teacherAccuracy <= 0
    ) {
      throw new BackendError(
        "invalid-argument",
        "Teacher GPS accuracy metadata is required for GPS attendance sessions.",
      );
    }

    if (
      teacherTimestamp === null ||
      teacherTimestamp === undefined ||
      isNaN(teacherTimestamp) ||
      teacherTimestamp <= 0
    ) {
      throw new BackendError(
        "invalid-argument",
        "Teacher GPS timestamp metadata is required for GPS attendance sessions.",
      );
    }

    const now = Date.now();
    if (now - teacherTimestamp > 120000) {
      throw new BackendError(
        "failed-precondition",
        "Teacher GPS reading is stale (> 120s old). Please obtain a fresh fix.",
      );
    }
    if (teacherTimestamp - now > 10000) {
      throw new BackendError(
        "failed-precondition",
        "Teacher GPS timestamp is invalid (in the future).",
      );
    }

    // Teacher center must have high quality (uncertainty <= 50m and <= radius)
    if (teacherAccuracy > 50 || teacherAccuracy > radiusMeters) {
      throw new BackendError(
        "failed-precondition",
        `Teacher GPS accuracy is insufficient (±${Math.round(teacherAccuracy)}m) for a ${radiusMeters}m radius. Please obtain a better GPS fix outdoors or near a window.`,
      );
    }

    centerAccuracyMeters = Math.round(teacherAccuracy);
  }

  const database = getDb();
  const courseRef = database.collection("courses").doc(courseId);

  return await database.runTransaction(async (transaction) => {
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists) {
      throw new BackendError("not-found", "Course not found.");
    }
    const course = courseDoc.data()!;
    if (course.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }
    if (course.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    // Active session check & request-driven expired session cleanup
    const existingQuery = database
      .collection("attendanceSessions")
      .where("courseId", "==", courseId)
      .where("status", "==", "active")
      .limit(1);

    const existingSnap = await transaction.get(existingQuery);
    const nowMillis = Date.now();

    let existingSessionDoc: FirebaseFirestore.DocumentSnapshot | null = null;
    if (!existingSnap.empty) {
      existingSessionDoc = existingSnap.docs[0]!;
    } else if (course.activeSessionId) {
      const activeRef = database.collection("attendanceSessions").doc(course.activeSessionId);
      const activeDoc = await transaction.get(activeRef);
      if (activeDoc.exists && activeDoc.data()?.status === "active") {
        existingSessionDoc = activeDoc;
      }
    }

    if (existingSessionDoc) {
      const activeData = existingSessionDoc.data()!;
      const endsAtMillis = activeData.endsAt instanceof Timestamp
        ? activeData.endsAt.toMillis()
        : (activeData.endsAt ? new Date(activeData.endsAt).getTime() : 0);

      if (nowMillis < endsAtMillis) {
        // Session is still within its live scheduled duration!
        throw new BackendError(
          "already-exists",
          "This course already has an active attendance session.",
        );
      }

      // Scheduled duration has ended.
      // If allowLateEntry is false, or if starting a new class supersedes the old one:
      // Finalize/close the old expired session atomically so it doesn't block the new session.
      transaction.update(existingSessionDoc.ref, {
        status: "closed",
        closedAt: FieldValue.serverTimestamp(),
        closedReason: "superseded_by_new_session",
      });
    }

    const recipientIds = await getCourseNotificationRecipients(
      database,
      transaction,
      courseId,
      "attendance",
    );

    const reference = database.collection("attendanceSessions").doc();
    const privateReference = reference.collection("private").doc("config");

    const startedAt = Timestamp.now();
    const endsAt = Timestamp.fromMillis(
      startedAt.toMillis() + durationMinutes * 60 * 1000,
    );

    const teacherName = typeof teacher.displayName === "string" ? teacher.displayName : "";
    const courseLabel = course.name || course.code;
    const notificationRequests = recipientIds.map((studentId) => ({
      id: `attendance_session_${reference.id}_${studentId}`,
      payload: {
        userId: studentId,
        type: "attendance_session_created",
        title: "New Attendance Session",
        message: `Attendance session opened for ${courseLabel}.`,
        courseId,
        entityId: reference.id,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(courseRef, {
      activeSessionId: reference.id,
      updatedAt: timestamp,
      revision: FieldValue.increment(1),
    });

    transaction.create(reference, {
      courseId,
      courseCode: typeof course.code === "string" ? course.code : "",
      courseName: typeof course.name === "string" ? course.name : "",
      teacherId,
      teacherName,
      classType,
      durationMinutes,
      requiresPasscode,
      requiresGps,
      centerAccuracyMeters,
      allowLateEntry,
      status: "active",
      startedAt,
      endsAt,
      createdAt: timestamp,
    });

    transaction.create(privateReference, {
      passcodeHash,
      passcodeSalt,
      latitude,
      longitude,
      radiusMeters,
      centerAccuracyMeters,
      createdAt: timestamp,
    });

    for (const item of notifItems) {
      if (item.existingData) {
        transaction.update(item.ref, {
          title: item.payload.title,
          message: item.payload.message,
          updatedAt: timestamp,
        });
      } else {
        transaction.set(item.ref, {
          id: item.id,
          userId: item.payload.userId,
          type: item.payload.type,
          title: item.payload.title,
          message: item.payload.message,
          courseId: item.payload.courseId,
          entityId: item.payload.entityId,
          isRead: false,
          createdAt: timestamp,
          updatedAt: timestamp,
        });
      }
    }

    return {
      sessionId: reference.id,
      passcode,
      courseId,
      startedAt: startedAt.toDate().toISOString(),
      endsAt: endsAt.toDate().toISOString(),
    };
  });
}

import * as crypto from "crypto";
import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  ResetAttendancePasscodeData,
  RequestContext,
  requiredString,
  hashPasscode,
} from "../../types.js";

export async function resetAttendancePasscode(
  data: ResetAttendancePasscodeData,
  context: RequestContext,
): Promise<{ success: boolean; passcode: string }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const sessionId = requiredString(data.sessionId, "Session ID", 1, 128);
  const database = getDb();
  const sessionReference = database.collection("attendanceSessions").doc(sessionId);

  return await database.runTransaction(async (transaction) => {
    const sessionDocument = await transaction.get(sessionReference);
    const session = sessionDocument.data();

    if (!sessionDocument.exists || !session) {
      throw new BackendError("not-found", "Attendance session not found.");
    }

    const courseId = String(session.courseId);
    const courseRef = database.collection("courses").doc(courseId);
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

    if (session.status !== "active") {
      throw new BackendError(
        "failed-precondition",
        "Cannot reset passcode on an inactive or closed session.",
      );
    }

    const newPasscode = String(crypto.randomInt(100000, 1000000));
    const salt = crypto.randomBytes(16).toString("hex");
    const passcodeHash = hashPasscode(newPasscode, salt);

    const privateReference = sessionReference.collection("private").doc("config");
    await transaction.get(privateReference);

    const auditReference = database.collection("auditLogs").doc();
    const timestamp = FieldValue.serverTimestamp();

    transaction.set(
      privateReference,
      {
        passcodeHash,
        passcodeSalt: salt,
        updatedAt: timestamp,
      },
      { merge: true },
    );

    if (session.requiresPasscode !== true) {
      transaction.update(sessionReference, {
        requiresPasscode: true,
        updatedAt: timestamp,
      });
    }

    transaction.create(auditReference, {
      action: "reset_attendance_passcode",
      sessionId,
      courseId,
      actorId: teacherId,
      actorRole: "teacher",
      createdAt: timestamp,
    });

    return {
      success: true,
      passcode: newPasscode,
    };
  });
}

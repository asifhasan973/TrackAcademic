import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  CorrectClosedAttendanceData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function correctClosedAttendance(
  data: CorrectClosedAttendanceData,
  context: RequestContext,
): Promise<{
  success: boolean;
  changed: boolean;
  previousStatus: string;
  newStatus: string;
  message?: string;
}> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const sessionId = requiredString(data.sessionId, "Session ID", 1, 128);
  const studentId = requiredString(data.studentId, "Student ID", 1, 128);
  const newStatus = requiredString(data.newStatus, "Attendance status", 4, 16).toLowerCase();
  const reason = requiredString(data.reason, "Correction reason", 1, 500).trim();

  if (
    newStatus !== "present" &&
    newStatus !== "late" &&
    newStatus !== "absent"
  ) {
    throw new BackendError(
      "invalid-argument",
      "Invalid attendance status for correction. Must be present, late, or absent.",
    );
  }

  if (reason.length === 0) {
    throw new BackendError(
      "invalid-argument",
      "A non-empty correction reason is required.",
    );
  }

  const database = getDb();
  const sessionReference = database.collection("attendanceSessions").doc(sessionId);
  const recordReference = database
    .collection("attendanceRecords")
    .doc(`${sessionId}_${studentId}`);

  return await database.runTransaction(async (transaction) => {
    const sessionDoc = await transaction.get(sessionReference);
    if (!sessionDoc.exists || !sessionDoc.data()) {
      throw new BackendError("not-found", "Attendance session not found.");
    }

    const session = sessionDoc.data()!;
    const courseId = String(session.courseId);

    if (session.status !== "closed") {
      throw new BackendError(
        "failed-precondition",
        "Attendance corrections can only be made on closed sessions.",
      );
    }

    if (session.finalizationStatus && session.finalizationStatus !== "finalized") {
      throw new BackendError(
        "failed-precondition",
        "Attendance session finalization is in progress. Please retry shortly.",
      );
    }

    const courseReference = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseReference);
    if (!courseDoc.exists || courseDoc.data()?.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this course.");
    }

    const recordDoc = await transaction.get(recordReference);
    if (!recordDoc.exists || !recordDoc.data()) {
      throw new BackendError("not-found", "Attendance record not found.");
    }

    const record = recordDoc.data()!;

    if (
      record.sessionId !== sessionId ||
      record.courseId !== courseId ||
      record.studentId !== studentId
    ) {
      throw new BackendError(
        "invalid-argument",
        "Attendance record does not match the requested session, course, or student.",
      );
    }

    const currentStatus = String(record.status ?? "absent").toLowerCase();

    if (currentStatus === newStatus) {
      return {
        success: true,
        changed: false,
        previousStatus: currentStatus,
        newStatus: currentStatus,
        message: `Status is already set to ${newStatus}.`,
      };
    }

    const summaryReference = database
      .collection("attendanceSummaries")
      .doc(`${courseId}_${studentId}`);

    const summaryDoc = await transaction.get(summaryReference);
    const summary = summaryDoc.data() ?? {};

    const wasAttended = currentStatus === "present" || currentStatus === "late";
    const isNowAttended = newStatus === "present" || newStatus === "late";
    const delta = (isNowAttended ? 1 : 0) - (wasAttended ? 1 : 0);

    const previousTotal = Math.max(1, Number(summary.total ?? 1));
    const previousAttended = Math.max(0, Number(summary.attended ?? 0));
    const newTotal = previousTotal;
    const newAttended = Math.min(
      newTotal,
      Math.max(0, previousAttended + delta),
    );
    const percentage = newTotal === 0 ? 0 : (newAttended / newTotal) * 100;
    const attendanceMarks = percentage / 10;

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(recordReference, {
      status: newStatus,
      previousStatus: currentStatus,
      correctionReason: reason,
      correctedBy: teacherId,
      source: "correction",
      updatedAt: timestamp,
    });

    transaction.set(
      summaryReference,
      {
        courseId,
        studentId,
        attended: newAttended,
        total: newTotal,
        percentage,
        attendanceMarks,
        finalizedSessionIds: FieldValue.arrayUnion(sessionId),
        updatedAt: timestamp,
      },
      { merge: true },
    );

    const auditReference = database.collection("auditLogs").doc();
    transaction.create(auditReference, {
      action: "attendance.corrected",
      sessionId,
      courseId,
      studentId,
      teacherId,
      previousStatus: currentStatus,
      newStatus,
      reason,
      createdAt: timestamp,
    });

    return {
      success: true,
      changed: true,
      previousStatus: currentStatus,
      newStatus,
    };
  });
}

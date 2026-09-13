import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  SetAttendanceStatusData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function setAttendanceStatus(
  data: SetAttendanceStatusData,
  context: RequestContext,
): Promise<{ success: boolean }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const sessionId = requiredString(data.sessionId, "Session ID", 1, 128);
  const studentId = requiredString(data.studentId, "Student ID", 1, 128);
  const status = requiredString(data.status, "Attendance status", 4, 16).toLowerCase();

  if (
    status !== "waiting" &&
    status !== "present" &&
    status !== "late" &&
    status !== "absent"
  ) {
    throw new BackendError("invalid-argument", "Invalid attendance status.");
  }

  const database = getDb();
  const sessionReference = database.collection("attendanceSessions").doc(sessionId);

  return await database.runTransaction(async (transaction) => {
    const sessionDocument = await transaction.get(sessionReference);
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

    const enrollmentReference = courseRef.collection("students").doc(studentId);
    const enrollment = await transaction.get(enrollmentReference);

    if (!enrollment.exists || enrollment.data()?.isActive === false) {
      throw new BackendError(
        "failed-precondition",
        "This student is not enrolled in the course.",
      );
    }

    const student = enrollment.data() ?? {};
    const recordReference = database
      .collection("attendanceRecords")
      .doc(`${sessionId}_${studentId}`);

    await transaction.get(recordReference);

    transaction.set(
      recordReference,
      {
        sessionId,
        courseId,
        courseCode: session.courseCode ?? "",
        courseName: session.courseName ?? "",
        studentId,
        institutionId: student.institutionId ?? "",
        studentName: student.displayName ?? "",
        status,
        markedBy: "teacher",
        markedByUid: teacherId,
        source: "manual",
        markedAt: status === "waiting" ? null : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
    };
  });
}

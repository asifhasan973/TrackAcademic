import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  CloseAttendanceSessionData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function closeAttendanceSession(
  data: CloseAttendanceSessionData,
  context: RequestContext,
): Promise<{ success: boolean; alreadyClosed?: boolean }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const sessionId = requiredString(data.sessionId, "Session ID", 1, 128);
  const database = getDb();
  const sessionReference = database.collection("attendanceSessions").doc(sessionId);

  return await database.runTransaction(async (transaction) => {
    // ==========================================
    // PHASE 1: ALL READS (MUST EXECUTE BEFORE ANY WRITES)
    // ==========================================

    // Read 1: Session document
    const sessionDocument = await transaction.get(sessionReference);
    if (!sessionDocument.exists || !sessionDocument.data()) {
      throw new BackendError("not-found", "Attendance session not found.");
    }
    const sessionData = sessionDocument.data()!;
    const courseId = String(sessionData.courseId);

    // Read 2: Course document (unconditional ownership check)
    const courseReference = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseReference);
    if (
      !courseDoc.exists ||
      courseDoc.data()?.teacherId !== teacherId ||
      sessionData.teacherId !== teacherId
    ) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }

    // If already fully finalized, return cleanly and idempotently
    if (sessionData.finalizationStatus === "finalized") {
      return { success: true, alreadyClosed: true };
    }

    // Read 3: Active enrolled students
    const studentsQuery = courseReference.collection("students").where("isActive", "==", true);
    const studentsSnapshot = await transaction.get(studentsQuery);

    // Read 4: All student records and summaries
    const studentRecordsAndSummaries: Array<{
      studentId: string;
      studentData: FirebaseFirestore.DocumentData;
      recordRef: FirebaseFirestore.DocumentReference;
      recordData: FirebaseFirestore.DocumentData | null;
      summaryRef: FirebaseFirestore.DocumentReference;
      summaryData: FirebaseFirestore.DocumentData;
    }> = [];

    for (const studentDoc of studentsSnapshot.docs) {
      const studentId = studentDoc.id;
      const recordRef = database.collection("attendanceRecords").doc(`${sessionId}_${studentId}`);
      const summaryRef = database.collection("attendanceSummaries").doc(`${courseId}_${studentId}`);

      const recordDoc = await transaction.get(recordRef);
      const summaryDoc = await transaction.get(summaryRef);

      studentRecordsAndSummaries.push({
        studentId,
        studentData: studentDoc.data(),
        recordRef,
        recordData: recordDoc.exists ? recordDoc.data()! : null,
        summaryRef,
        summaryData: summaryDoc.data() ?? {},
      });
    }

    // ==========================================
    // PHASE 2: ALL WRITES (EXECUTED AFTER ALL READS)
    // ==========================================
    const timestamp = FieldValue.serverTimestamp();

    // Write 1: Mark session as closed if still active, clear activeSessionId on course
    if (sessionData.status !== "closed") {
      transaction.update(sessionReference, {
        status: "closed",
        closedAt: timestamp,
        updatedAt: timestamp,
      });

      if (courseDoc.data()?.activeSessionId === sessionId) {
        transaction.update(courseReference, {
          activeSessionId: FieldValue.delete(),
          updatedAt: timestamp,
        });
      }
    }

    // Write 2: Write student records and update summaries
    for (const item of studentRecordsAndSummaries) {
      const { studentId, studentData, recordRef, recordData, summaryRef, summaryData } = item;

      const currentStatus = recordData ? recordData.status : null;
      const wasAttended = currentStatus === "present" || currentStatus === "late";

      // If absent or unrecorded, mark absent without touching existing present/late records
      if (!recordData || currentStatus === "waiting") {
        transaction.set(
          recordRef,
          {
            sessionId,
            courseId,
            courseCode: sessionData.courseCode ?? "",
            courseName: sessionData.courseName ?? "",
            studentId,
            institutionId: studentData.institutionId ?? "",
            studentName: studentData.displayName ?? "",
            status: "absent",
            markedBy: "system",
            source: "finalization",
            markedAt: null,
            finalizedAt: timestamp,
            updatedAt: timestamp,
          },
          { merge: true },
        );
      }

      // Idempotent summary calculation
      const finalizedList: string[] = Array.isArray(summaryData.finalizedSessionIds)
        ? summaryData.finalizedSessionIds
        : [];

      if (!finalizedList.includes(sessionId)) {
        const prevTotal = Number(summaryData.total ?? 0);
        const prevAttended = Number(summaryData.attended ?? 0);

        const total = prevTotal + 1;
        const attended = prevAttended + (wasAttended ? 1 : 0);
        const percentage = total === 0 ? 0 : (attended / total) * 100;
        const attendanceMarks = percentage / 10;

        transaction.set(
          summaryRef,
          {
            courseId,
            courseCode: sessionData.courseCode ?? "",
            courseName: sessionData.courseName ?? "",
            studentId,
            attended,
            total,
            percentage,
            attendanceMarks,
            finalizedSessionIds: FieldValue.arrayUnion(sessionId),
            updatedAt: timestamp,
          },
          { merge: true },
        );
      }
    }

    // Write 3: Mark finalization complete on the session document
    transaction.update(sessionReference, {
      finalizationStatus: "finalized",
      finalizedAt: timestamp,
      updatedAt: timestamp,
    });

    return {
      success: true,
    };
  });
}

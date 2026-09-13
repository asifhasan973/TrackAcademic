import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  CorrectPublishedMarkData,
  RequestContext,
  requiredString,
  requiredNumber,
} from "../../types.js";

export async function correctPublishedMark(
  data: CorrectPublishedMarkData,
  context: RequestContext,
): Promise<{
  success: boolean;
  changed: boolean;
  previousScore: number;
  newScore: number;
  message?: string;
}> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const assessmentId = requiredString(data.assessmentId, "Assessment ID", 1, 128);
  const studentId = requiredString(data.studentId, "Student ID", 1, 128);
  const newScore = requiredNumber(data.newScore, "New score", 0, 10000);
  const reason = requiredString(data.reason, "Correction reason", 1, 500).trim();

  if (reason.length === 0) {
    throw new BackendError(
      "invalid-argument",
      "A non-empty correction reason is required.",
    );
  }

  const database = getDb();
  const assessmentReference = database.collection("assessments").doc(assessmentId);
  const markReference = database.collection("marks").doc(`${assessmentId}_${studentId}`);

  return await database.runTransaction(async (transaction) => {
    const assessmentDoc = await transaction.get(assessmentReference);
    if (!assessmentDoc.exists || !assessmentDoc.data()) {
      throw new BackendError("not-found", "Assessment not found.");
    }

    const assessment = assessmentDoc.data()!;
    const courseId = String(assessment.courseId);

    if (assessment.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this assessment.");
    }

    if (assessment.status !== "published") {
      throw new BackendError(
        "failed-precondition",
        "Only published assessments can have marks corrected.",
      );
    }

    const maxScore = Number(assessment.maxScore);
    if (newScore > maxScore) {
      throw new BackendError(
        "invalid-argument",
        `Score ${newScore} exceeds maximum score of ${maxScore}.`,
      );
    }

    const courseReference = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseReference);
    if (!courseDoc.exists || courseDoc.data()?.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this course.");
    }

    const enrollmentReference = database
      .collection("courses")
      .doc(courseId)
      .collection("students")
      .doc(studentId);
    const enrollmentDoc = await transaction.get(enrollmentReference);
    if (!enrollmentDoc.exists) {
      throw new BackendError(
        "not-found",
        "Student enrollment record does not exist for this course.",
      );
    }

    const markDoc = await transaction.get(markReference);
    if (!markDoc.exists || !markDoc.data()) {
      throw new BackendError(
        "not-found",
        "Mark record not found for this student.",
      );
    }

    const markData = markDoc.data()!;
    const currentScore = Number(markData.score ?? 0);

    if (currentScore === newScore) {
      return {
        success: true,
        changed: false,
        previousScore: currentScore,
        newScore: currentScore,
        message: `Score is already ${newScore}.`,
      };
    }

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(assessmentReference, {
      revision: FieldValue.increment(1),
      updatedAt: timestamp,
    });

    transaction.update(markReference, {
      score: newScore,
      previousScore: currentScore,
      correctionReason: reason,
      correctedBy: teacherId,
      correctedAt: timestamp,
      updatedAt: timestamp,
      published: true,
    });

    const auditReference = database.collection("auditLogs").doc();
    transaction.create(auditReference, {
      action: "correct_published_mark",
      assessmentId,
      studentId,
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      previousScore: currentScore,
      newScore,
      reason,
      createdAt: timestamp,
    });

    return {
      success: true,
      changed: true,
      previousScore: currentScore,
      newScore,
    };
  });
}

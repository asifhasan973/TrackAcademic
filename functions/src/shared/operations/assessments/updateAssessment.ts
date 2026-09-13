import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  UpdateAssessmentData,
  RequestContext,
  requiredString,
  optionalString,
  requiredNumber,
  validateStrictCalendarDate,
} from "../../types.js";

export async function updateAssessment(
  data: UpdateAssessmentData,
  context: RequestContext,
): Promise<{ success: boolean; updatedMarksCount: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const assessmentId = requiredString(data.assessmentId, "Assessment ID", 1, 128);
  const name = requiredString(data.name, "Assessment name", 1, 80);
  const type = optionalString(data.type, "Assessment type", 40) ?? "Quiz";
  const maxScore = requiredNumber(data.maxScore, "Maximum score", 1, 1000);
  const date = validateStrictCalendarDate(data.date, "Assessment date");

  const database = getDb();
  const assessmentReference = database.collection("assessments").doc(assessmentId);

  return await database.runTransaction(async (transaction) => {
    const assessmentDoc = await transaction.get(assessmentReference);
    if (!assessmentDoc.exists || !assessmentDoc.data()) {
      throw new BackendError("not-found", "Assessment not found.");
    }

    const assessment = assessmentDoc.data()!;
    const courseId = String(assessment.courseId);

    const courseRef = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists || courseDoc.data()?.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    if (assessment.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this assessment.");
    }

    if (assessment.status !== "draft") {
      throw new BackendError(
        "failed-precondition",
        "Only draft assessments can be updated.",
      );
    }

    const marksQuery = database
      .collection("marks")
      .where("assessmentId", "==", assessmentId);

    const marksSnapshot = await transaction.get(marksQuery);

    const SAFE_LIMIT = 400;
    if (marksSnapshot.docs.length > SAFE_LIMIT) {
      throw new BackendError(
        "resource-exhausted",
        `Assessment has ${marksSnapshot.docs.length} mark documents, which exceeds the safe limit of ${SAFE_LIMIT}.`,
      );
    }

    for (const markDoc of marksSnapshot.docs) {
      const markData = markDoc.data();
      const existingScore = Number(markData.score ?? 0);
      if (existingScore > maxScore) {
        throw new BackendError(
          "invalid-argument",
          `Cannot reduce maximum score to ${maxScore}: student ${markData.studentId} has a score of ${existingScore}.`,
        );
      }
    }

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(assessmentReference, {
      name,
      type,
      maxScore,
      date,
      revision: FieldValue.increment(1),
      updatedAt: timestamp,
    });

    for (const markDoc of marksSnapshot.docs) {
      transaction.update(markDoc.ref, {
        assessmentName: name,
        maxScore,
        updatedAt: timestamp,
      });
    }

    const auditRef = database.collection("auditLogs").doc();
    transaction.create(auditRef, {
      action: "update_assessment",
      assessmentId,
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      name,
      type,
      maxScore,
      date,
      affectedMarksCount: marksSnapshot.docs.length,
      createdAt: timestamp,
    });

    return {
      success: true,
      updatedMarksCount: marksSnapshot.docs.length,
    };
  });
}

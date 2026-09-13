import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  DeleteAssessmentData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function deleteAssessment(
  data: DeleteAssessmentData,
  context: RequestContext,
): Promise<{ success: boolean; deletedMarksCount: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const assessmentId = requiredString(data.assessmentId, "Assessment ID", 1, 128);
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
        "Only draft assessments can be deleted.",
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

    transaction.delete(assessmentReference);

    for (const markDoc of marksSnapshot.docs) {
      transaction.delete(markDoc.ref);
    }

    const auditRef = database.collection("auditLogs").doc();
    const timestamp = FieldValue.serverTimestamp();
    transaction.create(auditRef, {
      action: "delete_assessment",
      assessmentId,
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      deletedMarksCount: marksSnapshot.docs.length,
      createdAt: timestamp,
    });

    return {
      success: true,
      deletedMarksCount: marksSnapshot.docs.length,
    };
  });
}

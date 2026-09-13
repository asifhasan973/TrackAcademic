import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  PublishAssessmentData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function publishAssessment(
  data: PublishAssessmentData,
  context: RequestContext,
): Promise<{ success: boolean; publishedMarksCount: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const assessmentId = requiredString(data.assessmentId, "Assessment ID", 1, 128);

  const database = getDb();
  const reference = database.collection("assessments").doc(assessmentId);

  return await database.runTransaction(async (transaction) => {
    const document = await transaction.get(reference);
    if (!document.exists || !document.data()) {
      throw new BackendError("not-found", "Assessment not found.");
    }

    const assessment = document.data()!;
    const courseId = String(assessment.courseId);

    const courseRef = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists || courseDoc.data()?.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    if (assessment.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this assessment.");
    }

    if (assessment.status === "published") {
      throw new BackendError(
        "failed-precondition",
        "Assessment is already published.",
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
        `Assessment has ${marksSnapshot.docs.length} marks, which exceeds the safe limit of ${SAFE_LIMIT}.`,
      );
    }

    const recipientIds = await getCourseNotificationRecipients(
      database,
      transaction,
      courseId,
      "marks",
    );

    const courseLabel = assessment.courseName || assessment.courseCode;
    const notificationRequests = recipientIds.map((studentId) => ({
      id: `assessment_publish_${assessmentId}_${studentId}`,
      payload: {
        userId: studentId,
        type: "marks_published",
        title: "Marks Published",
        message: `Marks for ${assessment.name} in ${courseLabel} have been published.`,
        courseId,
        entityId: assessmentId,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(reference, {
      status: "published",
      revision: FieldValue.increment(1),
      publishedAt: timestamp,
      updatedAt: timestamp,
    });

    for (const mark of marksSnapshot.docs) {
      transaction.update(mark.ref, {
        published: true,
        updatedAt: timestamp,
      });
    }

    const auditRef = database.collection("auditLogs").doc();
    transaction.create(auditRef, {
      action: "publish_assessment",
      assessmentId,
      courseId: String(assessment.courseId),
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      marksCount: marksSnapshot.docs.length,
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
      success: true,
      publishedMarksCount: marksSnapshot.docs.length,
    };
  });
}

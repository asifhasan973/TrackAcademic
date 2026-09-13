import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  ReactivateCourseData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function reactivateCourse(
  data: ReactivateCourseData,
  context: RequestContext,
): Promise<{
  success: boolean;
  reactivated: boolean;
  courseId: string;
  lifecycleRevision: number;
}> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError(
      "unauthenticated",
      "Sign in before reactivating a course.",
    );
  }

  await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
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
    if (course.isActive === true) {
      throw new BackendError(
        "failed-precondition",
        "This course is already active.",
      );
    }

    const recipientIds = await getCourseNotificationRecipients(
      database,
      transaction,
      courseId,
    );

    const currentLifecycleRevision = (course.lifecycleRevision ?? 0) + 1;
    const timestamp = FieldValue.serverTimestamp();
    const courseLabel = course.name || course.code;

    const notificationRequests = recipientIds.map((studentId) => ({
      id: `course_reactivate_${courseId}_${currentLifecycleRevision}_${studentId}`,
      payload: {
        userId: studentId,
        type: "course_reactivated",
        title: "Course Reactivated",
        message: `${courseLabel} has been reactivated by the instructor.`,
        courseId,
        entityId: courseId,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    transaction.update(courseRef, {
      isActive: true,
      lifecycleRevision: currentLifecycleRevision,
      reactivatedAt: timestamp,
      reactivatedBy: teacherId,
      updatedAt: timestamp,
    });

    const auditRef = database.collection("auditLogs").doc();
    transaction.create(auditRef, {
      action: "course.reactivated",
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      lifecycleRevision: currentLifecycleRevision,
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
      reactivated: true,
      courseId,
      lifecycleRevision: currentLifecycleRevision,
    };
  });
}

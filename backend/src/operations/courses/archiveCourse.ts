import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  ArchiveCourseData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function archiveCourse(
  data: ArchiveCourseData,
  context: RequestContext,
): Promise<{
  success: boolean;
  archived: boolean;
  courseId: string;
  lifecycleRevision: number;
}> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in before archiving a course.");
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
    if (course.isActive !== true) {
      throw new BackendError(
        "failed-precondition",
        "This course is already archived.",
      );
    }

    const activeSessionsQuery = database
      .collection("attendanceSessions")
      .where("courseId", "==", courseId)
      .where("status", "==", "active")
      .limit(1);

    const activeSessions = await transaction.get(activeSessionsQuery);

    if (!activeSessions.empty || course.activeSessionId) {
      throw new BackendError(
        "failed-precondition",
        "Cannot archive course with an active attendance session. Please close all active sessions first.",
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
      id: `course_archive_${courseId}_${currentLifecycleRevision}_${studentId}`,
      payload: {
        userId: studentId,
        type: "course_archived",
        title: "Course Archived",
        message: `${courseLabel} has been archived by the instructor.`,
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
      isActive: false,
      lifecycleRevision: currentLifecycleRevision,
      archivedAt: timestamp,
      archivedBy: teacherId,
      updatedAt: timestamp,
    });

    const auditRef = database.collection("auditLogs").doc();
    transaction.create(auditRef, {
      action: "course.archived",
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
      archived: true,
      courseId,
      lifecycleRevision: currentLifecycleRevision,
    };
  });
}

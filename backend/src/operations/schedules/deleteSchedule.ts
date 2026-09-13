import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  requireActiveOwnedCourse,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  DeleteScheduleData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function deleteSchedule(
  data: DeleteScheduleData,
  context: RequestContext,
): Promise<{ success: boolean; deleted: boolean }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const scheduleId = requiredString(data.scheduleId, "Schedule ID", 1, 128);
  const database = getDb();
  const reference = database.collection("schedules").doc(scheduleId);

  return await database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new BackendError("not-found", "Schedule not found.");
    }

    const existingSchedule = snapshot.data()!;
    if (existingSchedule.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this schedule.");
    }

    const courseId = String(existingSchedule.courseId);
    await requireActiveOwnedCourse(teacherId, courseId, context.auth);

    const recipientIds = await getCourseNotificationRecipients(
      database,
      transaction,
      courseId,
      "schedule",
    );

    const timestamp = FieldValue.serverTimestamp();
    const courseLabel = existingSchedule.courseName || existingSchedule.courseCode;
    const day = existingSchedule.day;
    const timeSlot = `${existingSchedule.startTime} - ${existingSchedule.endTime}`;

    const notificationRequests = recipientIds.map((studentId) => ({
      id: `schedule_delete_${scheduleId}_${studentId}`,
      payload: {
        userId: studentId,
        type: "schedule_deleted",
        title: "Class Schedule Cancelled",
        message: `The class for ${courseLabel} on ${day} (${timeSlot}) was cancelled.`,
        courseId,
        entityId: scheduleId,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    transaction.update(reference, {
      status: "cancelled",
      updatedAt: timestamp,
    });

    const auditReference = database.collection("auditLogs").doc();
    transaction.create(auditReference, {
      action: "schedule.deleted",
      scheduleId,
      courseId,
      teacherId,
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
      deleted: true,
    };
  });
}

import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  requireActiveOwnedCourse,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  CreateScheduleData,
  RequestContext,
  requiredString,
  validateDayIndex,
  deriveDayLabel,
  validateTime,
  timeToMinutes,
  INACTIVE_SCHEDULE_STATUSES,
} from "../../types.js";

export async function createSchedule(
  data: CreateScheduleData,
  context: RequestContext,
): Promise<{ scheduleId: string; revision: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in before creating a schedule.");
  }

  const teacher = await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  await requireActiveOwnedCourse(teacherId, courseId, context.auth);

  const dayIndex = validateDayIndex(data.dayIndex);
  const day = deriveDayLabel(dayIndex);

  const startTime = validateTime(data.startTime, "Start time");
  const endTime = validateTime(data.endTime, "End time");

  const startMinutes = timeToMinutes(startTime);
  const endMinutes = timeToMinutes(endTime);

  if (endMinutes <= startMinutes) {
    throw new BackendError("invalid-argument", "End time must be after start time.");
  }

  const room = requiredString(data.room, "Room", 1, 80);
  const classType = requiredString(data.classType, "Class type", 2, 40);

  const normalizedRoom = room.trim().toLowerCase();
  const normalizedClassType = classType.trim().toLowerCase();
  const database = getDb();
  const lockRef = database
    .collection("scheduleLocks")
    .doc(`${teacherId}_${dayIndex}`);

  return await database.runTransaction(async (transaction) => {
    await transaction.get(lockRef);

    const courseRef = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists) {
      throw new BackendError("not-found", "Course not found.");
    }
    const courseData = courseDoc.data()!;
    if (courseData.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }
    if (courseData.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const teacherSchedulesQuery = database
      .collection("schedules")
      .where("teacherId", "==", teacherId)
      .where("dayIndex", "==", dayIndex);

    const existingSnap = await transaction.get(teacherSchedulesQuery);

    for (const doc of existingSnap.docs) {
      const docData = doc.data();
      const docStatus = String(docData.status ?? "").toLowerCase();
      if (INACTIVE_SCHEDULE_STATUSES.has(docStatus)) {
        continue;
      }

      if (docData.courseId === courseId) {
        const docRoom = String(docData.room ?? "").trim().toLowerCase();
        const docClassType = String(docData.classType ?? "").trim().toLowerCase();
        if (
          docData.startTime === startTime &&
          docData.endTime === endTime &&
          docRoom === normalizedRoom &&
          docClassType === normalizedClassType
        ) {
          throw new BackendError(
            "invalid-argument",
            "An exact duplicate schedule entry already exists for this course.",
          );
        }
      }

      const existingStart = timeToMinutes(String(docData.startTime));
      const existingEnd = timeToMinutes(String(docData.endTime));
      if (startMinutes < existingEnd && existingStart < endMinutes) {
        const conflicting = docData.courseCode ?? "another class";
        throw new BackendError(
          "invalid-argument",
          `Schedule overlaps with ${conflicting} (${docData.startTime} - ${docData.endTime}) on ${day}.`,
        );
      }
    }

    const recipientIds = await getCourseNotificationRecipients(
      database,
      transaction,
      courseId,
      "schedule",
    );

    const reference = database.collection("schedules").doc();
    const teacherName = typeof teacher.displayName === "string" ? teacher.displayName : "";
    const timestamp = FieldValue.serverTimestamp();

    const courseLabel = courseData.name || courseData.code;
    const timeSlot = `${startTime} - ${endTime}`;
    const notificationRequests = recipientIds.map((studentId) => ({
      id: `schedule_create_${reference.id}_1_${studentId}`,
      payload: {
        userId: studentId,
        type: "schedule_created",
        title: "New Class Schedule Added",
        message: `New class for ${courseLabel} on ${day} (${timeSlot}) in Room ${room}.`,
        courseId,
        entityId: reference.id,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    transaction.set(lockRef, {
      teacherId,
      dayIndex,
      updatedAt: timestamp,
    });

    transaction.create(reference, {
      courseId,
      courseCode: courseData.code ?? "",
      courseName: courseData.name ?? "",
      teacherId,
      teacherName,
      dayIndex,
      day,
      startTime,
      endTime,
      room,
      classType,
      status: "active",
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    });

    const auditReference = database.collection("auditLogs").doc();
    transaction.create(auditReference, {
      action: "schedule.created",
      scheduleId: reference.id,
      courseId,
      teacherId,
      dayIndex,
      day,
      startTime,
      endTime,
      room,
      classType,
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
      scheduleId: reference.id,
      revision: 1,
    };
  });
}

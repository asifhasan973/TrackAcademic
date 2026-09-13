import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  requireActiveOwnedCourse,
  getCourseNotificationRecipients,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  UpdateScheduleData,
  RequestContext,
  requiredString,
  validateDayIndex,
  deriveDayLabel,
  validateTime,
  timeToMinutes,
  INACTIVE_SCHEDULE_STATUSES,
} from "../../types.js";

export async function updateSchedule(
  data: UpdateScheduleData,
  context: RequestContext,
): Promise<{ scheduleId: string; revision: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in before updating a schedule.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const scheduleId = requiredString(data.scheduleId, "Schedule ID", 1, 128);
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
  const reference = database.collection("schedules").doc(scheduleId);

  return await database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new BackendError("not-found", "Schedule not found.");
    }

    const existingSchedule = snapshot.data()!;

    // SECURITY FIX: Enforce ownership of the existing schedule
    if (existingSchedule.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this schedule.");
    }

    // SECURITY FIX: Enforce ownership of original course
    const originalCourseId = String(existingSchedule.courseId || "");
    if (originalCourseId) {
      const origCourseDoc = await transaction.get(
        database.collection("courses").doc(originalCourseId),
      );
      if (!origCourseDoc.exists || origCourseDoc.data()?.teacherId !== teacherId) {
        throw new BackendError(
          "permission-denied",
          "You do not own the original course for this schedule.",
        );
      }
    }

    // Destination course check
    const destCourseRef = database.collection("courses").doc(courseId);
    const destCourseDoc = await transaction.get(destCourseRef);
    if (!destCourseDoc.exists) {
      throw new BackendError("not-found", "Course not found.");
    }
    const courseData = destCourseDoc.data()!;
    if (courseData.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }
    if (courseData.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const currentRev =
      typeof existingSchedule.revision === "number"
        ? existingSchedule.revision + 1
        : 1;
    const originDayIndex =
      typeof existingSchedule.dayIndex === "number"
        ? existingSchedule.dayIndex
        : dayIndex;
    const targetDayIndex = dayIndex;

    const lockRefOrigin = database
      .collection("scheduleLocks")
      .doc(`${teacherId}_${originDayIndex}`);
    const lockRefTarget = database
      .collection("scheduleLocks")
      .doc(`${teacherId}_${targetDayIndex}`);

    await transaction.get(lockRefOrigin);
    if (targetDayIndex !== originDayIndex) {
      await transaction.get(lockRefTarget);
    }

    // Check overlaps
    const teacherSchedulesQuery = database
      .collection("schedules")
      .where("teacherId", "==", teacherId)
      .where("dayIndex", "==", targetDayIndex);

    const existingSnap = await transaction.get(teacherSchedulesQuery);

    for (const doc of existingSnap.docs) {
      if (doc.id === scheduleId) {
        continue;
      }

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

    const timestamp = FieldValue.serverTimestamp();
    const courseLabel = courseData.name || courseData.code;
    const timeSlot = `${startTime} - ${endTime}`;
    const notificationRequests = recipientIds.map((studentId) => ({
      id: `schedule_update_${scheduleId}_${currentRev}_${studentId}`,
      payload: {
        userId: studentId,
        type: "schedule_updated",
        title: "Class Schedule Updated",
        message: `The class schedule for ${courseLabel} on ${day} (${timeSlot}) was updated.`,
        courseId,
        entityId: scheduleId,
      },
    }));

    const notifItems = await prepareNotifications(
      database,
      transaction,
      notificationRequests,
    );

    transaction.set(lockRefOrigin, {
      teacherId,
      dayIndex: originDayIndex,
      updatedAt: timestamp,
    });
    if (targetDayIndex !== originDayIndex) {
      transaction.set(lockRefTarget, {
        teacherId,
        dayIndex: targetDayIndex,
        updatedAt: timestamp,
      });
    }

    transaction.update(reference, {
      courseId,
      courseCode: courseData.code ?? "",
      courseName: courseData.name ?? "",
      dayIndex,
      day,
      startTime,
      endTime,
      room,
      classType,
      revision: currentRev,
      updatedAt: timestamp,
    });

    const auditReference = database.collection("auditLogs").doc();
    transaction.create(auditReference, {
      action: "schedule.updated",
      scheduleId,
      courseId,
      teacherId,
      dayIndex,
      day,
      startTime,
      endTime,
      room,
      classType,
      revision: currentRev,
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
      scheduleId,
      revision: currentRev,
    };
  });
}

import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveStudent,
  prepareNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  RequestJoinCourseData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function requestJoinCourse(
  data: RequestJoinCourseData,
  context: RequestContext,
): Promise<{ requestId: string; courseId: string }> {
  const studentId = context.auth?.uid;

  if (!studentId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  const student = await requireActiveStudent(studentId, context.auth);

  const joinCode = requiredString(data.joinCode, "Join code", 4, 32).toUpperCase();

  const database = getDb();

  const courses = await database
    .collection("courses")
    .where("joinCode", "==", joinCode)
    .limit(1)
    .get();

  if (courses.empty) {
    throw new BackendError("not-found", "No course was found for this join code.");
  }

  const courseDocument = courses.docs[0]!;
  const courseId = courseDocument.id;
  const courseRef = database.collection("courses").doc(courseId);
  const enrollmentRef = courseRef.collection("students").doc(studentId);
  const requestReference = database
    .collection("courseJoinRequests")
    .doc(`${courseId}_${studentId}`);

  return await database.runTransaction(async (transaction) => {
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists) {
      throw new BackendError("not-found", "No course was found for this join code.");
    }
    const course = courseDoc.data()!;

    if (course.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is inactive.");
    }

    if (course.teacherId === studentId) {
      throw new BackendError("failed-precondition", "You already own this course.");
    }

    const enrollment = await transaction.get(enrollmentRef);

    if (enrollment.exists && enrollment.data()?.isActive !== false) {
      throw new BackendError(
        "already-exists",
        "You are already enrolled in this course.",
      );
    }

    const previous = await transaction.get(requestReference);

    if (previous.exists && previous.data()?.status === "pending") {
      throw new BackendError(
        "already-exists",
        "Your join request is already pending.",
      );
    }

    const attempt =
      (previous.data()?.attempt ?? previous.data()?.revision ?? 0) + 1;
    const timestamp = FieldValue.serverTimestamp();

    const requester = student.displayName || "A student";
    const courseLabel = course.name || course.code;
    const notifId = `join_request_${courseId}_${studentId}_${attempt}`;

    const notifItems = await prepareNotifications(database, transaction, [
      {
        id: notifId,
        payload: {
          userId: course.teacherId,
          type: "join_request",
          title: "New Join Request",
          message: `${requester} requested to join ${courseLabel}.`,
          courseId,
          entityId: requestReference.id,
        },
      },
    ]);

    transaction.set(requestReference, {
      courseId,
      courseCode: course.code ?? "",
      courseName: course.name ?? "",
      teacherId: course.teacherId ?? "",
      studentId,
      studentName: student.displayName ?? "",
      institutionId: student.institutionId ?? "",
      email: student.email ?? "",
      status: "pending",
      attempt,
      revision: attempt,
      createdAt: timestamp,
      updatedAt: timestamp,
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
      requestId: requestReference.id,
      courseId,
    };
  });
}

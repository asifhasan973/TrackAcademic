import { getDb, FieldValue } from "../../firebaseAdmin.js";
import {
  requireActiveTeacher,
  prepareNotifications,
  dispatchPushNotifications,
} from "../../middleware/auth.js";
import {
  BackendError,
  RespondJoinRequestData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function respondCourseJoinRequest(
  data: RespondJoinRequestData,
  context: RequestContext,
): Promise<{ success: boolean }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const requestId = requiredString(data.requestId, "Request ID", 1, 256);
  const response = requiredString(data.response, "Response", 6, 8).toLowerCase();

  if (response !== "approved" && response !== "rejected") {
    throw new BackendError(
      "invalid-argument",
      "Response must be approved or rejected.",
    );
  }

  const database = getDb();
  const requestReference = database.collection("courseJoinRequests").doc(requestId);

  const result = await database.runTransaction(async (transaction) => {
    const joinRequest = await transaction.get(requestReference);
    const requestData = joinRequest.data();

    if (!joinRequest.exists || !requestData) {
      throw new BackendError("not-found", "Join request not found.");
    }

    if (requestData.status !== "pending") {
      throw new BackendError(
        "failed-precondition",
        "This join request has already been handled.",
      );
    }

    const courseId = String(requestData.courseId);
    const studentId = String(requestData.studentId);
    const courseRef = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseRef);

    if (!courseDoc.exists) {
      throw new BackendError("not-found", "Course not found.");
    }

    const course = courseDoc.data()!;
    if (course.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }

    if (response === "approved") {
      if (course.isActive !== true) {
        throw new BackendError("failed-precondition", "This course is archived.");
      }
    }

    const studentReference = database.collection("users").doc(studentId);
    const studentDocument = await transaction.get(studentReference);
    const student = studentDocument.data();

    if (
      response === "approved" &&
      (!studentDocument.exists || !student || student.isActive !== true)
    ) {
      throw new BackendError(
        "failed-precondition",
        "The requesting account is unavailable.",
      );
    }

    const enrollmentReference = database
      .collection("courses")
      .doc(courseId)
      .collection("students")
      .doc(studentId);

    if (response === "approved") {
      await transaction.get(enrollmentReference);
    }

    const attempt = requestData.attempt ?? requestData.revision ?? 1;
    const notifId = `join_decision_${requestId}_${attempt}`;

    const notifItems = await prepareNotifications(database, transaction, [
      {
        id: notifId,
        payload: {
          userId: studentId,
          type:
            response === "approved"
              ? "join_request_approved"
              : "join_request_rejected",
          title:
            response === "approved"
              ? "Join Request Approved"
              : "Join Request Rejected",
          message:
            response === "approved"
              ? `Your request to join ${course.name || course.code} was approved.`
              : `Your request to join ${course.name || course.code} was rejected.`,
          courseId,
          entityId: requestId,
        },
      },
    ]);

    const timestamp = FieldValue.serverTimestamp();

    if (response === "approved") {
      transaction.set(
        enrollmentReference,
        {
          studentId,
          institutionId: student!.institutionId ?? "",
          displayName: student!.displayName ?? "",
          email: student!.email ?? "",
          isActive: true,
          enrolledAt: timestamp,
          updatedAt: timestamp,
        },
        { merge: true },
      );

      transaction.set(
        studentReference,
        {
          courseIds: FieldValue.arrayUnion(courseId),
          updatedAt: timestamp,
        },
        { merge: true },
      );
    }

    transaction.update(requestReference, {
      status: response,
      respondedBy: teacherId,
      respondedAt: timestamp,
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
      success: true,
      _notifications: notifItems.map((item) => ({
        id: item.id,
        payload: item.payload,
      })),
    };
  });

  if (result._notifications && result._notifications.length > 0) {
    await dispatchPushNotifications(database, result._notifications).catch((e) =>
      console.warn("[FCM] Join decision push dispatch warning:", e),
    );
  }

  return { success: true };
}

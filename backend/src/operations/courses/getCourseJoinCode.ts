import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  GetCourseJoinCodeData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function getCourseJoinCode(
  data: GetCourseJoinCodeData,
  context: RequestContext,
): Promise<{ joinCode: string }> {
  const userId = context.auth?.uid;

  if (!userId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(userId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  const database = getDb();
  const courseRef = database.collection("courses").doc(courseId);

  return await database.runTransaction(async (transaction) => {
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists) {
      throw new BackendError("not-found", "Course not found.");
    }
    const course = courseDoc.data()!;
    if (course.teacherId !== userId) {
      throw new BackendError("permission-denied", "You do not manage this course.");
    }
    if (course.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const existing =
      typeof course.joinCode === "string" ? course.joinCode.trim().toUpperCase() : "";

    if (existing) {
      return { joinCode: existing };
    }

    const joinCode = courseId.substring(0, Math.min(8, courseId.length)).toUpperCase();

    transaction.update(courseRef, {
      joinCode,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { joinCode };
  });
}

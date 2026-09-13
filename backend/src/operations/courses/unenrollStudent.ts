import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  UnenrollStudentData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function unenrollStudent(
  data: UnenrollStudentData,
  context: RequestContext,
): Promise<{ success: boolean }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  const studentId = requiredString(data.studentId, "Student ID", 1, 128);

  const database = getDb();
  const courseRef = database.collection("courses").doc(courseId);
  const enrollmentReference = courseRef.collection("students").doc(studentId);
  const studentReference = database.collection("users").doc(studentId);

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
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const enrollment = await transaction.get(enrollmentReference);
    if (!enrollment.exists) {
      throw new BackendError("not-found", "Student is not enrolled in this course.");
    }

    await transaction.get(studentReference);

    const timestamp = FieldValue.serverTimestamp();

    transaction.set(
      enrollmentReference,
      {
        isActive: false,
        unenrolledAt: timestamp,
        updatedAt: timestamp,
      },
      { merge: true },
    );

    transaction.set(
      studentReference,
      {
        courseIds: FieldValue.arrayRemove(courseId),
        updatedAt: timestamp,
      },
      { merge: true },
    );

    return {
      success: true,
    };
  });
}

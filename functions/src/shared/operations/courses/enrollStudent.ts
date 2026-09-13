import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  EnrollStudentData,
  RequestContext,
  requiredString,
  validateInstitutionId,
} from "../../types.js";

export async function enrollStudent(
  data: EnrollStudentData,
  context: RequestContext,
): Promise<{ studentId: string }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError(
      "unauthenticated",
      "Sign in before enrolling a student.",
    );
  }

  await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  const institutionId = validateInstitutionId(data.institutionId);

  const database = getDb();

  const students = await database
    .collection("users")
    .where("institutionId", "==", institutionId)
    .limit(1)
    .get();

  if (students.empty) {
    throw new BackendError(
      "not-found",
      "No registered student was found with this institution ID.",
    );
  }

  const studentDocument = students.docs[0]!;
  const student = studentDocument.data();

  if (student.isActive !== true) {
    throw new BackendError(
      "failed-precondition",
      "This student account is inactive.",
    );
  }

  const courseRef = database.collection("courses").doc(courseId);
  const studentRef = studentDocument.ref;
  const enrollmentReference = courseRef
    .collection("students")
    .doc(studentDocument.id);

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

    const studentDoc = await transaction.get(studentRef);
    if (!studentDoc.exists || studentDoc.data()?.isActive !== true) {
      throw new BackendError(
        "failed-precondition",
        "This student account is inactive.",
      );
    }

    await transaction.get(enrollmentReference);

    const timestamp = FieldValue.serverTimestamp();

    transaction.set(
      enrollmentReference,
      {
        studentId: studentDocument.id,
        institutionId,
        displayName:
          typeof student.displayName === "string" ? student.displayName : "",
        email: typeof student.email === "string" ? student.email : "",
        isActive: true,
        enrolledAt: timestamp,
        updatedAt: timestamp,
      },
      { merge: true },
    );

    transaction.set(
      studentRef,
      {
        courseIds: FieldValue.arrayUnion(courseId),
        updatedAt: timestamp,
      },
      { merge: true },
    );

    return {
      studentId: studentDocument.id,
    };
  });
}

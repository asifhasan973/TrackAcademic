import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher, requireActiveOwnedCourse } from "../../middleware/auth.js";
import {
  BackendError,
  CreateAssessmentData,
  RequestContext,
  requiredString,
  optionalString,
  requiredNumber,
  validateStrictCalendarDate,
} from "../../types.js";

export async function createAssessment(
  data: CreateAssessmentData,
  context: RequestContext,
): Promise<{ assessmentId: string }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  await requireActiveOwnedCourse(teacherId, courseId, context.auth);

  const name = requiredString(data.name, "Assessment name", 1, 80);
  const type = optionalString(data.type, "Assessment type", 40) ?? "Quiz";
  const maxScore = requiredNumber(data.maxScore, "Maximum score", 1, 1000);
  const date = validateStrictCalendarDate(data.date, "Assessment date");

  const database = getDb();
  const courseRef = database.collection("courses").doc(courseId);
  const reference = database.collection("assessments").doc();
  const auditRef = database.collection("auditLogs").doc();

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

    const timestamp = FieldValue.serverTimestamp();
    transaction.create(reference, {
      courseId,
      courseCode: course.code ?? "",
      courseName: course.name ?? "",
      name,
      type,
      maxScore,
      date,
      status: "draft",
      revision: 1,
      teacherId,
      createdAt: timestamp,
      updatedAt: timestamp,
    });

    transaction.create(auditRef, {
      action: "create_assessment",
      assessmentId: reference.id,
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      name,
      type,
      maxScore,
      date,
      createdAt: timestamp,
    });

    return {
      assessmentId: reference.id,
    };
  });
}

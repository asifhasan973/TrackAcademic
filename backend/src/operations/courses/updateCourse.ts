import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  UpdateCourseData,
  RequestContext,
  requiredString,
  optionalString,
} from "../../types.js";

export async function updateCourse(
  data: UpdateCourseData,
  context: RequestContext,
): Promise<{ success: boolean; updated: boolean; courseId: string }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in before updating a course.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const courseId = requiredString(data.courseId, "Course ID", 1, 128);
  const name = requiredString(data.name, "Course name", 2, 120);
  const department = optionalString(data.department, "Department", 120);
  const batch = optionalString(data.batch, "Batch", 80);
  const section = optionalString(data.section, "Section", 80);
  const semester = optionalString(data.semester, "Semester", 80);
  const room = optionalString(data.room, "Room", 80);

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
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    const auditRef = database.collection("auditLogs").doc();
    const timestamp = FieldValue.serverTimestamp();

    transaction.update(courseRef, {
      name,
      department,
      batch,
      section,
      semester,
      room,
      revision: FieldValue.increment(1),
      updatedAt: timestamp,
    });

    transaction.create(auditRef, {
      action: "course.updated",
      courseId,
      teacherId,
      actorId: teacherId,
      actorRole: "teacher",
      previous: {
        name: course.name,
        department: course.department,
        batch: course.batch,
        section: course.section,
        semester: course.semester,
        room: course.room,
      },
      updated: {
        name,
        department,
        batch,
        section,
        semester,
        room,
      },
      createdAt: timestamp,
    });

    return {
      success: true,
      updated: true,
      courseId,
    };
  });
}

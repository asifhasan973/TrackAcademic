import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  CreateCourseData,
  RequestContext,
  requiredString,
  optionalString,
} from "../../types.js";

export async function createCourse(
  data: CreateCourseData,
  context: RequestContext,
): Promise<{ courseId: string }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in before creating a course.");
  }

  const teacher = await requireActiveTeacher(teacherId, context.auth);

  const code = requiredString(data.code, "Course code", 2, 30).toUpperCase();
  const name = requiredString(data.name, "Course name", 2, 120);
  const department = optionalString(data.department, "Department", 120);
  const batch = optionalString(data.batch, "Batch", 80);
  const section = optionalString(data.section, "Section", 80);
  const semester = optionalString(data.semester, "Semester", 80);
  const room = optionalString(data.room, "Room", 80);

  const database = getDb();

  const duplicate = await database
    .collection("courses")
    .where("teacherId", "==", teacherId)
    .where("code", "==", code)
    .limit(1)
    .get();

  if (!duplicate.empty) {
    throw new BackendError(
      "already-exists",
      "You already have a course with this code.",
    );
  }

  const courseReference = database.collection("courses").doc();
  const joinCode = courseReference.id.substring(0, 8).toUpperCase();
  const timestamp = FieldValue.serverTimestamp();
  const teacherName = typeof teacher.displayName === "string" ? teacher.displayName : "";

  await courseReference.create({
    code,
    name,
    joinCode,
    teacherId,
    teacherName,
    department,
    batch,
    section,
    semester,
    room,
    isActive: true,
    revision: 1,
    lifecycleRevision: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
  });

  return {
    courseId: courseReference.id,
  };
}

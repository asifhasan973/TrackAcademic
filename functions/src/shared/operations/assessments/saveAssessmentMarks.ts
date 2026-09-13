import { getDb, FieldValue } from "../../firebaseAdmin.js";
import { requireActiveTeacher } from "../../middleware/auth.js";
import {
  BackendError,
  SaveAssessmentMarksData,
  RequestContext,
  requiredString,
} from "../../types.js";

export async function saveAssessmentMarks(
  data: SaveAssessmentMarksData,
  context: RequestContext,
): Promise<{ success: boolean; savedCount: number }> {
  const teacherId = context.auth?.uid;

  if (!teacherId) {
    throw new BackendError("unauthenticated", "Sign in first.");
  }

  await requireActiveTeacher(teacherId, context.auth);

  const assessmentId = requiredString(data.assessmentId, "Assessment ID", 1, 128);

  if (!Array.isArray(data.marks)) {
    throw new BackendError("invalid-argument", "Marks must be a list.");
  }

  if (data.marks.length > 200) {
    throw new BackendError(
      "invalid-argument",
      "Too many marks were submitted at once (maximum 200).",
    );
  }

  const parsedMarks: Array<{ studentId: string; score: number }> = [];
  const seenStudentIds = new Set<string>();

  for (const item of data.marks) {
    if (typeof item !== "object" || item === null) {
      throw new BackendError("invalid-argument", "Invalid mark entry.");
    }

    const mark = item as Record<string, unknown>;
    const studentId = requiredString(mark.studentId, "Student ID", 1, 128);

    if (seenStudentIds.has(studentId)) {
      throw new BackendError(
        "invalid-argument",
        `Duplicate student ID ${studentId} in submitted marks.`,
      );
    }
    seenStudentIds.add(studentId);

    const rawScore = Number(mark.score);
    if (typeof mark.score !== "number" || isNaN(rawScore) || rawScore < 0) {
      throw new BackendError(
        "invalid-argument",
        `Score for student ${studentId} must be a non-negative number.`,
      );
    }

    parsedMarks.push({
      studentId,
      score: rawScore,
    });
  }

  const database = getDb();
  const assessmentReference = database.collection("assessments").doc(assessmentId);

  return await database.runTransaction(async (transaction) => {
    const assessmentDocument = await transaction.get(assessmentReference);
    if (!assessmentDocument.exists || !assessmentDocument.data()) {
      throw new BackendError("not-found", "Assessment not found.");
    }

    const assessment = assessmentDocument.data()!;
    const courseId = String(assessment.courseId);

    const courseRef = database.collection("courses").doc(courseId);
    const courseDoc = await transaction.get(courseRef);
    if (!courseDoc.exists || courseDoc.data()?.isActive !== true) {
      throw new BackendError("failed-precondition", "This course is archived.");
    }

    if (assessment.teacherId !== teacherId) {
      throw new BackendError("permission-denied", "You do not own this assessment.");
    }

    if (assessment.status === "published") {
      throw new BackendError(
        "failed-precondition",
        "Published marks cannot be edited.",
      );
    }

    const maxScore = Number(assessment.maxScore);

    const enrollmentRefs = parsedMarks.map((m) =>
      database
        .collection("courses")
        .doc(courseId)
        .collection("students")
        .doc(m.studentId),
    );

    const enrollmentDocs = await Promise.all(
      enrollmentRefs.map((ref) => transaction.get(ref)),
    );

    for (let i = 0; i < parsedMarks.length; i++) {
      const m = parsedMarks[i]!;
      const enrollmentDoc = enrollmentDocs[i]!;

      if (!enrollmentDoc.exists || enrollmentDoc.data()?.isActive === false) {
        throw new BackendError(
          "failed-precondition",
          `Student ${m.studentId} is not enrolled in this course.`,
        );
      }

      if (m.score > maxScore) {
        throw new BackendError(
          "invalid-argument",
          `Score ${m.score} for student ${m.studentId} exceeds maximum score ${maxScore}.`,
        );
      }
    }

    const timestamp = FieldValue.serverTimestamp();

    transaction.update(assessmentReference, {
      revision: FieldValue.increment(1),
      updatedAt: timestamp,
    });

    for (const m of parsedMarks) {
      const markReference = database
        .collection("marks")
        .doc(`${assessmentId}_${m.studentId}`);

      transaction.set(
        markReference,
        {
          assessmentId,
          assessmentName: assessment.name ?? "",
          courseId,
          courseCode: assessment.courseCode ?? "",
          courseName: assessment.courseName ?? "",
          studentId: m.studentId,
          score: m.score,
          maxScore,
          published: false,
          updatedAt: timestamp,
        },
        { merge: true },
      );
    }

    return {
      success: true,
      savedCount: parsedMarks.length,
    };
  });
}

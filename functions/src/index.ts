import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {setGlobalOptions} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

initializeApp();

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

type RegistrationData = {
  displayName?: unknown;
  email?: unknown;
  institutionId?: unknown;
  password?: unknown;
};

type CreateCourseData = {
  code?: unknown;
  name?: unknown;
  department?: unknown;
  batch?: unknown;
  section?: unknown;
  semester?: unknown;
  room?: unknown;
};

type EnrollStudentData = {
  courseId?: unknown;
  institutionId?: unknown;
};

type UnenrollStudentData = {
  courseId?: unknown;
  studentId?: unknown;
};

type CreateScheduleData = {
  courseId?: unknown;
  dayIndex?: unknown;
  day?: unknown;
  startTime?: unknown;
  endTime?: unknown;
  room?: unknown;
  classType?: unknown;
};

type UpdateScheduleData = CreateScheduleData & {
  scheduleId?: unknown;
};

type DeleteScheduleData = {
  scheduleId?: unknown;
};

type CreateAttendanceSessionData = {
  courseId?: unknown;
  classType?: unknown;
  durationMinutes?: unknown;
  requiresPasscode?: unknown;
  passcode?: unknown;
  requiresGps?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  radiusMeters?: unknown;
  allowLateEntry?: unknown;
};

type CloseAttendanceSessionData = {
  sessionId?: unknown;
};

type SubmitAttendanceData = {
  sessionId?: unknown;
  passcode?: unknown;
  latitude?: unknown;
  longitude?: unknown;
};

type CreateAssessmentData = {
  courseId?: unknown;
  name?: unknown;
  maxScore?: unknown;
};

type SaveAssessmentMarksData = {
  assessmentId?: unknown;
  marks?: unknown;
};

type PublishAssessmentData = {
  assessmentId?: unknown;
};


type GetCourseJoinCodeData = {
  courseId?: unknown;
};

type RequestJoinCourseData = {
  joinCode?: unknown;
};

type RespondJoinRequestData = {
  requestId?: unknown;
  response?: unknown;
};

type SetAttendanceStatusData = {
  sessionId?: unknown;
  studentId?: unknown;
  status?: unknown;
};


function requiredString(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): string {
  if (typeof value !== "string") {
    throw new HttpsError(
      "invalid-argument",
      `${field} is required.`,
    );
  }

  const result = value.trim();

  if (result.length < minimum || result.length > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must contain ${minimum}-${maximum} characters.`,
    );
  }

  return result;
}

function optionalString(
  value: unknown,
  field: string,
  maximum: number,
): string | null {
  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be text.`,
    );
  }

  const result = value.trim();

  if (result.length > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} is too long.`,
    );
  }

  return result.length === 0 ? null : result;
}

function requiredNumber(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

function requiredBoolean(
  value: unknown,
  field: string,
): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be true or false.`,
    );
  }

  return value;
}

function validateEmail(value: unknown): string {
  const email = requiredString(
    value,
    "Email",
    5,
    254,
  ).toLowerCase();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError(
      "invalid-argument",
      "Enter a valid email address.",
    );
  }

  return email;
}

function validateInstitutionId(value: unknown): string {
  const institutionId = requiredString(
    value,
    "Institution ID",
    3,
    40,
  ).toUpperCase();

  if (!/^[A-Z0-9_-]+$/.test(institutionId)) {
    throw new HttpsError(
      "invalid-argument",
      "Institution ID contains invalid characters.",
    );
  }

  return institutionId;
}

function validatePassword(value: unknown): string {
  if (
    typeof value !== "string" ||
    value.length < 8 ||
    value.length > 128
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Password must contain 8-128 characters.",
    );
  }

  return value;
}

function validateTime(
  value: unknown,
  field: string,
): string {
  const time = requiredString(
    value,
    field,
    5,
    5,
  );

  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must use HH:MM format.`,
    );
  }

  return time;
}

function validateDayIndex(value: unknown): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > 6
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Day index must be between 0 and 6.",
    );
  }

  return value;
}


async function requireActiveUser(
  uid: string,
): Promise<FirebaseFirestore.DocumentData> {
  const database = getFirestore();

  const profile = await database
    .collection("users")
    .doc(uid)
    .get();

  const data = profile.data();

  if (
    !profile.exists ||
    !data ||
    data.isActive !== true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active Trackademic account is required.",
    );
  }

  return data;
}

// Compatibility wrappers.
// Account permissions are no longer determined by permanent roles.
// Course ownership/enrollment determines authority.
async function requireActiveTeacher(
  uid: string,
): Promise<FirebaseFirestore.DocumentData> {
  return requireActiveUser(uid);
}

async function requireActiveStudent(
  uid: string,
): Promise<FirebaseFirestore.DocumentData> {
  return requireActiveUser(uid);
}

async function requireOwnedCourse(
  teacherId: string,
  courseId: string,
): Promise<FirebaseFirestore.DocumentData> {
  const database = getFirestore();

  const course = await database
    .collection("courses")
    .doc(courseId)
    .get();

  const data = course.data();

  if (!course.exists || !data) {
    throw new HttpsError(
      "not-found",
      "Course not found.",
    );
  }

  if (data.teacherId !== teacherId) {
    throw new HttpsError(
      "permission-denied",
      "You do not manage this course.",
    );
  }

  if (data.isActive !== true) {
    throw new HttpsError(
      "failed-precondition",
      "This course is inactive.",
    );
  }

  return data;
}

function degreesToRadians(value: number): number {
  return value * Math.PI / 180;
}

function distanceMeters(
  latitude1: number,
  longitude1: number,
  latitude2: number,
  longitude2: number,
): number {
  const earthRadius = 6371000;

  const deltaLatitude = degreesToRadians(
    latitude2 - latitude1,
  );

  const deltaLongitude = degreesToRadians(
    longitude2 - longitude1,
  );

  const firstLatitude = degreesToRadians(
    latitude1,
  );

  const secondLatitude = degreesToRadians(
    latitude2,
  );

  const a =
    Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(firstLatitude) *
      Math.cos(secondLatitude) *
      Math.sin(deltaLongitude / 2) ** 2;

  const c = 2 * Math.atan2(
    Math.sqrt(a),
    Math.sqrt(1 - a),
  );

  return earthRadius * c;
}

export const registerUser =
  onCall<RegistrationData>(
    {
      timeoutSeconds: 30,
      maxInstances: 10,
    },
    async (request) => {
      if (request.auth) {
        throw new HttpsError(
          "failed-precondition",
          "Sign out before creating another account.",
        );
      }

      const displayName = requiredString(
        request.data.displayName,
        "Full name",
        2,
        80,
      );

      const email = validateEmail(
        request.data.email,
      );

      const institutionId =
        validateInstitutionId(
          request.data.institutionId,
        );

      const password = validatePassword(
        request.data.password,
      );

      const database = getFirestore();

      const existingInstitutionId =
        await database
          .collection("users")
          .where(
            "institutionId",
            "==",
            institutionId,
          )
          .limit(1)
          .get();

      if (!existingInstitutionId.empty) {
        throw new HttpsError(
          "already-exists",
          "An account already uses this institution ID.",
        );
      }

      const institutionReference =
        database
          .collection("institutionIds")
          .doc(institutionId);

      let createdUserId: string | null = null;

      try {
        const user = await getAuth().createUser({
          displayName,
          email,
          password,
          emailVerified: false,
          disabled: false,
        });

        createdUserId = user.uid;

        await getAuth().setCustomUserClaims(
          user.uid,
          {
            institutionId,
          },
        );

        await database.runTransaction(
          async (transaction) => {
            const reservation =
              await transaction.get(
                institutionReference,
              );

            if (reservation.exists) {
              throw new HttpsError(
                "already-exists",
                "An account already uses this institution ID.",
              );
            }

            const timestamp =
              FieldValue.serverTimestamp();

            const userReference =
              database
                .collection("users")
                .doc(user.uid);

            const auditReference =
              database
                .collection("auditLogs")
                .doc();

            transaction.create(
              institutionReference,
              {
                userId: user.uid,
                institutionId,
                createdAt: timestamp,
              },
            );

            transaction.create(
              userReference,
              {
                uid: user.uid,
                displayName,
                email,
                institutionId,
                isActive: true,
                emailVerified: false,
                phone: null,
                photoUrl: null,
                department: null,
                batch: null,
                section: null,
                semester: null,
                courseIds: [],
                notificationPreferences: {
                  attendance: true,
                  marks: true,
                  schedule: true,
                },
                createdAt: timestamp,
                updatedAt: timestamp,
              },
            );

            transaction.create(
              auditReference,
              {
                action: "user.registered",
                actorId: user.uid,
                actorRole: "user",
                targetId: user.uid,
                metadata: {
                  institutionId,
                },
                createdAt: timestamp,
              },
            );
          },
        );

        return {
          uid: user.uid,
        };
      } catch (error) {
        if (createdUserId != null) {
          try {
            await getAuth().deleteUser(
              createdUserId,
            );
          } catch (rollbackError) {
            logger.error(
              "Registration rollback failed.",
              rollbackError,
            );
          }
        }

        if (error instanceof HttpsError) {
          throw error;
        }

        const errorCode =
          typeof error === "object" &&
          error !== null &&
          "code" in error ?
            String(error.code) :
            "";

        if (
          errorCode ===
          "auth/email-already-exists"
        ) {
          throw new HttpsError(
            "already-exists",
            "An account already exists for this email.",
          );
        }

        logger.error(
          "Direct registration failed.",
          error,
        );

        throw new HttpsError(
          "internal",
          "Registration failed. Please try again.",
        );
      }
    },
  );


export const getCourseJoinCode =
  onCall<GetCourseJoinCodeData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const userId = request.auth?.uid;

      if (!userId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      await requireActiveUser(userId);

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const course = await requireOwnedCourse(
        userId,
        courseId,
      );

      const existing =
        typeof course.joinCode === "string" ?
          course.joinCode.trim().toUpperCase() :
          "";

      if (existing) {
        return {
          joinCode: existing,
        };
      }

      const joinCode =
        courseId
          .substring(0, Math.min(8, courseId.length))
          .toUpperCase();

      await getFirestore()
        .collection("courses")
        .doc(courseId)
        .update({
          joinCode,
          updatedAt: FieldValue.serverTimestamp(),
        });

      return {
        joinCode,
      };
    },
  );

export const requestJoinCourse =
  onCall<RequestJoinCourseData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const studentId = request.auth?.uid;

      if (!studentId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const student =
        await requireActiveUser(studentId);

      const joinCode = requiredString(
        request.data.joinCode,
        "Join code",
        3,
        32,
      ).toUpperCase();

      const database = getFirestore();

      const courses = await database
        .collection("courses")
        .where(
          "joinCode",
          "==",
          joinCode,
        )
        .limit(1)
        .get();

      if (courses.empty) {
        throw new HttpsError(
          "not-found",
          "No course was found for this join code.",
        );
      }

      const courseDocument = courses.docs[0];
      const course = courseDocument.data();
      const courseId = courseDocument.id;

      if (course.isActive !== true) {
        throw new HttpsError(
          "failed-precondition",
          "This course is inactive.",
        );
      }

      if (course.teacherId === studentId) {
        throw new HttpsError(
          "failed-precondition",
          "You already own this course.",
        );
      }

      const enrollment = await database
        .collection("courses")
        .doc(courseId)
        .collection("students")
        .doc(studentId)
        .get();

      if (
        enrollment.exists &&
        enrollment.data()?.isActive !== false
      ) {
        throw new HttpsError(
          "already-exists",
          "You are already enrolled in this course.",
        );
      }

      const requestReference = database
        .collection("courseJoinRequests")
        .doc(`${courseId}_${studentId}`);

      const previous =
        await requestReference.get();

      if (
        previous.exists &&
        previous.data()?.status === "pending"
      ) {
        throw new HttpsError(
          "already-exists",
          "Your join request is already pending.",
        );
      }

      await requestReference.set({
        courseId,
        courseCode: course.code ?? "",
        courseName: course.name ?? "",
        teacherId: course.teacherId ?? "",
        studentId,
        studentName: student.displayName ?? "",
        institutionId: student.institutionId ?? "",
        email: student.email ?? "",
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        requestId: requestReference.id,
        courseId,
      };
    },
  );

export const respondCourseJoinRequest =
  onCall<RespondJoinRequestData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      await requireActiveUser(teacherId);

      const requestId = requiredString(
        request.data.requestId,
        "Request ID",
        1,
        256,
      );

      const response = requiredString(
        request.data.response,
        "Response",
        6,
        8,
      ).toLowerCase();

      if (
        response !== "approved" &&
        response !== "rejected"
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Response must be approved or rejected.",
        );
      }

      const database = getFirestore();

      const requestReference = database
        .collection("courseJoinRequests")
        .doc(requestId);

      const joinRequest =
        await requestReference.get();

      const data = joinRequest.data();

      if (!joinRequest.exists || !data) {
        throw new HttpsError(
          "not-found",
          "Join request not found.",
        );
      }

      if (data.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "This join request has already been handled.",
        );
      }

      const courseId = String(data.courseId);
      const studentId = String(data.studentId);

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      const batch = database.batch();

      if (response === "approved") {
        const studentReference = database
          .collection("users")
          .doc(studentId);

        const studentDocument =
          await studentReference.get();

        const student =
          studentDocument.data();

        if (
          !studentDocument.exists ||
          !student ||
          student.isActive !== true
        ) {
          throw new HttpsError(
            "failed-precondition",
            "The requesting account is unavailable.",
          );
        }

        const enrollmentReference = database
          .collection("courses")
          .doc(courseId)
          .collection("students")
          .doc(studentId);

        batch.set(
          enrollmentReference,
          {
            studentId,
            institutionId:
              student.institutionId ?? "",
            displayName:
              student.displayName ?? "",
            email:
              student.email ?? "",
            isActive: true,
            enrolledAt:
              FieldValue.serverTimestamp(),
            updatedAt:
              FieldValue.serverTimestamp(),
          },
          {
            merge: true,
          },
        );

        batch.set(
          studentReference,
          {
            courseIds:
              FieldValue.arrayUnion(courseId),
            updatedAt:
              FieldValue.serverTimestamp(),
          },
          {
            merge: true,
          },
        );
      }

      batch.update(
        requestReference,
        {
          status: response,
          respondedBy: teacherId,
          respondedAt:
            FieldValue.serverTimestamp(),
          updatedAt:
            FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      return {
        success: true,
      };
    },
  );

export const createCourse =
  onCall<CreateCourseData>(
    {
      timeoutSeconds: 30,
      maxInstances: 10,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in before creating a course.",
        );
      }

      const teacher =
        await requireActiveTeacher(
          teacherId,
        );

      const code = requiredString(
        request.data.code,
        "Course code",
        2,
        30,
      ).toUpperCase();

      const name = requiredString(
        request.data.name,
        "Course name",
        2,
        120,
      );

      const department = optionalString(
        request.data.department,
        "Department",
        120,
      );

      const batch = optionalString(
        request.data.batch,
        "Batch",
        80,
      );

      const section = optionalString(
        request.data.section,
        "Section",
        80,
      );

      const semester = optionalString(
        request.data.semester,
        "Semester",
        80,
      );

      const room = optionalString(
        request.data.room,
        "Room",
        80,
      );

      const database = getFirestore();

      const duplicate = await database
        .collection("courses")
        .where(
          "teacherId",
          "==",
          teacherId,
        )
        .where(
          "code",
          "==",
          code,
        )
        .limit(1)
        .get();

      if (!duplicate.empty) {
        throw new HttpsError(
          "already-exists",
          "You already have a course with this code.",
        );
      }

      const courseReference = database
        .collection("courses")
        .doc();

      const joinCode =
        courseReference.id
          .substring(0, 8)
          .toUpperCase();

      const timestamp =
        FieldValue.serverTimestamp();

      const teacherName =
        typeof teacher.displayName === "string" ?
          teacher.displayName :
          "";

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
        createdAt: timestamp,
        updatedAt: timestamp,
      });

      return {
        courseId: courseReference.id,
      };
    },
  );

export const enrollStudent =
  onCall<EnrollStudentData>(
    {
      timeoutSeconds: 30,
      maxInstances: 10,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in before enrolling a student.",
        );
      }

      await requireActiveTeacher(
        teacherId,
      );

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const institutionId =
        validateInstitutionId(
          request.data.institutionId,
        );

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      const database = getFirestore();

      const students = await database
        .collection("users")
        .where(
          "institutionId",
          "==",
          institutionId,
        )
        .limit(1)
        .get();

      if (students.empty) {
        throw new HttpsError(
          "not-found",
          "No registered student was found with this institution ID.",
        );
      }

      const studentDocument =
        students.docs[0];

      const student =
        studentDocument.data();

      if (student.isActive !== true) {
        throw new HttpsError(
          "failed-precondition",
          "This student account is inactive.",
        );
      }

      const enrollmentReference =
        database
          .collection("courses")
          .doc(courseId)
          .collection("students")
          .doc(studentDocument.id);

      const timestamp =
        FieldValue.serverTimestamp();

      const batchWrite =
        database.batch();

      batchWrite.set(
        enrollmentReference,
        {
          studentId: studentDocument.id,
          institutionId,
          displayName:
            typeof student.displayName ===
              "string" ?
              student.displayName :
              "",
          email:
            typeof student.email ===
              "string" ?
              student.email :
              "",
          isActive: true,
          enrolledAt: timestamp,
          updatedAt: timestamp,
        },
        {
          merge: true,
        },
      );

      batchWrite.set(
        studentDocument.ref,
        {
          courseIds:
            FieldValue.arrayUnion(
              courseId,
            ),
          updatedAt: timestamp,
        },
        {
          merge: true,
        },
      );

      await batchWrite.commit();

      return {
        studentId: studentDocument.id,
      };
    },
  );

export const unenrollStudent =
  onCall<UnenrollStudentData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const studentId = requiredString(
        request.data.studentId,
        "Student ID",
        1,
        128,
      );

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      const database = getFirestore();

      const enrollmentReference =
        database
          .collection("courses")
          .doc(courseId)
          .collection("students")
          .doc(studentId);

      const enrollment =
        await enrollmentReference.get();

      if (!enrollment.exists) {
        throw new HttpsError(
          "not-found",
          "Student is not enrolled in this course.",
        );
      }

      const studentReference =
        database
          .collection("users")
          .doc(studentId);

      const timestamp =
        FieldValue.serverTimestamp();

      const batchWrite =
        database.batch();

      batchWrite.set(
        enrollmentReference,
        {
          isActive: false,
          updatedAt: timestamp,
        },
        {
          merge: true,
        },
      );

      batchWrite.set(
        studentReference,
        {
          courseIds:
            FieldValue.arrayRemove(
              courseId,
            ),
          updatedAt: timestamp,
        },
        {
          merge: true,
        },
      );

      await batchWrite.commit();

      return {
        success: true,
      };
    },
  );

export const createSchedule =
  onCall<CreateScheduleData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in before creating a schedule.",
        );
      }

      const teacher =
        await requireActiveTeacher(
          teacherId,
        );

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const course =
        await requireOwnedCourse(
          teacherId,
          courseId,
        );

      const dayIndex =
        validateDayIndex(
          request.data.dayIndex,
        );

      const day = requiredString(
        request.data.day,
        "Day",
        3,
        20,
      );

      const startTime = validateTime(
        request.data.startTime,
        "Start time",
      );

      const endTime = validateTime(
        request.data.endTime,
        "End time",
      );

      if (endTime <= startTime) {
        throw new HttpsError(
          "invalid-argument",
          "End time must be after start time.",
        );
      }

      const room = requiredString(
        request.data.room,
        "Room",
        1,
        80,
      );

      const classType = requiredString(
        request.data.classType,
        "Class type",
        2,
        40,
      );

      const database = getFirestore();

      const reference = database
        .collection("schedules")
        .doc();

      const teacherName =
        typeof teacher.displayName === "string" ?
          teacher.displayName :
          "";

      const timestamp =
        FieldValue.serverTimestamp();

      await reference.create({
        courseId,
        courseCode:
          typeof course.code === "string" ?
            course.code :
            "",
        courseName:
          typeof course.name === "string" ?
            course.name :
            "",
        teacherId,
        teacherName,
        dayIndex,
        day,
        startTime,
        endTime,
        room,
        classType,
        status: "scheduled",
        createdAt: timestamp,
        updatedAt: timestamp,
      });

      return {
        scheduleId: reference.id,
      };
    },
  );

export const updateSchedule =
  onCall<UpdateScheduleData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const scheduleId = requiredString(
        request.data.scheduleId,
        "Schedule ID",
        1,
        128,
      );

      const reference = getFirestore()
        .collection("schedules")
        .doc(scheduleId);

      const document =
        await reference.get();

      const existing =
        document.data();

      if (!document.exists || !existing) {
        throw new HttpsError(
          "not-found",
          "Schedule not found.",
        );
      }

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const course =
        await requireOwnedCourse(
          teacherId,
          courseId,
        );

      if (
        existing.teacherId !== teacherId
      ) {
        throw new HttpsError(
          "permission-denied",
          "You do not manage this schedule.",
        );
      }

      const dayIndex =
        validateDayIndex(
          request.data.dayIndex,
        );

      const day = requiredString(
        request.data.day,
        "Day",
        3,
        20,
      );

      const startTime = validateTime(
        request.data.startTime,
        "Start time",
      );

      const endTime = validateTime(
        request.data.endTime,
        "End time",
      );

      if (endTime <= startTime) {
        throw new HttpsError(
          "invalid-argument",
          "End time must be after start time.",
        );
      }

      const room = requiredString(
        request.data.room,
        "Room",
        1,
        80,
      );

      const classType = requiredString(
        request.data.classType,
        "Class type",
        2,
        40,
      );

      await reference.update({
        courseId,
        courseCode:
          typeof course.code === "string" ?
            course.code :
            "",
        courseName:
          typeof course.name === "string" ?
            course.name :
            "",
        dayIndex,
        day,
        startTime,
        endTime,
        room,
        classType,
        updatedAt:
          FieldValue.serverTimestamp(),
      });

      return {
        success: true,
      };
    },
  );

export const deleteSchedule =
  onCall<DeleteScheduleData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const scheduleId = requiredString(
        request.data.scheduleId,
        "Schedule ID",
        1,
        128,
      );

      const reference = getFirestore()
        .collection("schedules")
        .doc(scheduleId);

      const document =
        await reference.get();

      const data = document.data();

      if (!document.exists || !data) {
        throw new HttpsError(
          "not-found",
          "Schedule not found.",
        );
      }

      await requireOwnedCourse(
        teacherId,
        String(data.courseId),
      );

      await reference.delete();

      return {
        success: true,
      };
    },
  );

export const createAttendanceSession =
  onCall<CreateAttendanceSessionData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const teacher =
        await requireActiveTeacher(
          teacherId,
        );

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const course =
        await requireOwnedCourse(
          teacherId,
          courseId,
        );

      const classType = requiredString(
        request.data.classType,
        "Class type",
        2,
        40,
      );

      const durationMinutes =
        requiredNumber(
          request.data.durationMinutes,
          "Duration",
          1,
          180,
        );

      const requiresPasscode =
        requiredBoolean(
          request.data.requiresPasscode,
          "Passcode requirement",
        );

      const requiresGps =
        requiredBoolean(
          request.data.requiresGps,
          "GPS requirement",
        );

      const allowLateEntry =
        requiredBoolean(
          request.data.allowLateEntry,
          "Late-entry setting",
        );

      let passcode: string | null = null;

      if (requiresPasscode) {
        passcode = requiredString(
          request.data.passcode,
          "Passcode",
          4,
          8,
        );

        if (!/^\d+$/.test(passcode)) {
          throw new HttpsError(
            "invalid-argument",
            "Passcode must contain digits only.",
          );
        }
      }

      let latitude: number | null = null;
      let longitude: number | null = null;
      let radiusMeters: number | null = null;

      if (requiresGps) {
        latitude = requiredNumber(
          request.data.latitude,
          "Latitude",
          -90,
          90,
        );

        longitude = requiredNumber(
          request.data.longitude,
          "Longitude",
          -180,
          180,
        );

        radiusMeters = requiredNumber(
          request.data.radiusMeters,
          "Radius",
          5,
          5000,
        );
      }

      const database = getFirestore();

      const existing = await database
        .collection("attendanceSessions")
        .where(
          "courseId",
          "==",
          courseId,
        )
        .where(
          "status",
          "==",
          "active",
        )
        .limit(1)
        .get();

      if (!existing.empty) {
        throw new HttpsError(
          "already-exists",
          "This course already has an active attendance session.",
        );
      }

      const reference = database
        .collection("attendanceSessions")
        .doc();

      const privateReference =
        reference
          .collection("private")
          .doc("config");

      const startedAt =
        Timestamp.now();

      const endsAt =
        Timestamp.fromMillis(
          startedAt.toMillis() +
          durationMinutes * 60 * 1000,
        );

      const teacherName =
        typeof teacher.displayName ===
          "string" ?
          teacher.displayName :
          "";

      const batchWrite =
        database.batch();

      batchWrite.create(
        reference,
        {
          courseId,
          courseCode:
            typeof course.code === "string" ?
              course.code :
              "",
          courseName:
            typeof course.name === "string" ?
              course.name :
              "",
          teacherId,
          teacherName,
          classType,
          durationMinutes,
          requiresPasscode,
          requiresGps,
          allowLateEntry,
          status: "active",
          startedAt,
          endsAt,
          createdAt:
            FieldValue.serverTimestamp(),
        },
      );

      batchWrite.create(
        privateReference,
        {
          passcode,
          latitude,
          longitude,
          radiusMeters,
          createdAt:
            FieldValue.serverTimestamp(),
        },
      );

      await batchWrite.commit();

      return {
        sessionId: reference.id,
      };
    },
  );

export const submitAttendance =
  onCall<SubmitAttendanceData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const studentId =
        request.auth?.uid;

      if (!studentId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const student =
        await requireActiveStudent(
          studentId,
        );

      const sessionId = requiredString(
        request.data.sessionId,
        "Session ID",
        1,
        128,
      );

      const database = getFirestore();

      const sessionReference =
        database
          .collection("attendanceSessions")
          .doc(sessionId);

      const sessionDocument =
        await sessionReference.get();

      const session =
        sessionDocument.data();

      if (
        !sessionDocument.exists ||
        !session
      ) {
        throw new HttpsError(
          "not-found",
          "Attendance session not found.",
        );
      }

      if (session.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "This attendance session is closed.",
        );
      }

      const endsAt =
        session.endsAt;

      const submittedAtMillis =
        Date.now();

      const isLate =
        endsAt instanceof Timestamp &&
        endsAt.toMillis() < submittedAtMillis;

      if (
        isLate &&
        session.allowLateEntry !== true
      ) {
        throw new HttpsError(
          "deadline-exceeded",
          "This attendance session has expired.",
        );
      }

      const courseId =
        String(session.courseId);

      const enrollment = await database
        .collection("courses")
        .doc(courseId)
        .collection("students")
        .doc(studentId)
        .get();

      if (
        !enrollment.exists ||
        enrollment.data()?.isActive === false
      ) {
        throw new HttpsError(
          "permission-denied",
          "You are not enrolled in this course.",
        );
      }

      const config = await sessionReference
        .collection("private")
        .doc("config")
        .get();

      const configuration =
        config.data() ?? {};

      if (session.requiresPasscode === true) {
        const submittedPasscode =
          requiredString(
            request.data.passcode,
            "Passcode",
            1,
            20,
          );

        if (
          submittedPasscode !==
          configuration.passcode
        ) {
          throw new HttpsError(
            "permission-denied",
            "Incorrect attendance passcode.",
          );
        }
      }

      if (session.requiresGps === true) {
        const latitude =
          requiredNumber(
            request.data.latitude,
            "Latitude",
            -90,
            90,
          );

        const longitude =
          requiredNumber(
            request.data.longitude,
            "Longitude",
            -180,
            180,
          );

        const targetLatitude =
          Number(configuration.latitude);

        const targetLongitude =
          Number(configuration.longitude);

        const radiusMeters =
          Number(configuration.radiusMeters);

        const distance = distanceMeters(
          latitude,
          longitude,
          targetLatitude,
          targetLongitude,
        );

        if (distance > radiusMeters) {
          throw new HttpsError(
            "permission-denied",
            "You are outside the allowed attendance area.",
          );
        }
      }

      const recordReference =
        database
          .collection("attendanceRecords")
          .doc(
            `${sessionId}_${studentId}`,
          );

      const existing =
        await recordReference.get();

      if (
        existing.exists &&
        existing.data()?.status !== "waiting"
      ) {
        throw new HttpsError(
          "already-exists",
          "Attendance has already been submitted.",
        );
      }

      const attendanceData = {
        sessionId,
        courseId,
        courseCode:
          session.courseCode ?? "",
        courseName:
          session.courseName ?? "",
        studentId,
        institutionId:
          student.institutionId ?? "",
        studentName:
          student.displayName ?? "",
        status:
          isLate ? "late" : "present",
        markedBy: "student",
        markedByUid: studentId,
        source: "self",
        verifiedPasscode:
          session.requiresPasscode === true,
        verifiedGps:
          session.requiresGps === true,
        markedAt:
          FieldValue.serverTimestamp(),
        updatedAt:
          FieldValue.serverTimestamp(),
      };

      if (existing.exists) {
        await recordReference.set(
          attendanceData,
          {
            merge: true,
          },
        );
      } else {
        await recordReference.create(
          attendanceData,
        );
      }

      return {
        success: true,
      };
    },
  );


export const setAttendanceStatus =
  onCall<SetAttendanceStatusData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId = request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const sessionId = requiredString(
        request.data.sessionId,
        "Session ID",
        1,
        128,
      );

      const studentId = requiredString(
        request.data.studentId,
        "Student ID",
        1,
        128,
      );

      const status = requiredString(
        request.data.status,
        "Attendance status",
        4,
        16,
      ).toLowerCase();

      if (
        status !== "waiting" &&
        status !== "present" &&
        status !== "late" &&
        status !== "absent"
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid attendance status.",
        );
      }

      const database = getFirestore();

      const sessionReference = database
        .collection("attendanceSessions")
        .doc(sessionId);

      const sessionDocument =
        await sessionReference.get();

      const session =
        sessionDocument.data();

      if (
        !sessionDocument.exists ||
        !session
      ) {
        throw new HttpsError(
          "not-found",
          "Attendance session not found.",
        );
      }

      if (session.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "This attendance session is closed.",
        );
      }

      const courseId =
        String(session.courseId);

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      const enrollment = await database
        .collection("courses")
        .doc(courseId)
        .collection("students")
        .doc(studentId)
        .get();

      if (
        !enrollment.exists ||
        enrollment.data()?.isActive === false
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This student is not enrolled in the course.",
        );
      }

      const student =
        enrollment.data() ?? {};

      const recordReference = database
        .collection("attendanceRecords")
        .doc(`${sessionId}_${studentId}`);

      await recordReference.set(
        {
          sessionId,
          courseId,
          courseCode:
            session.courseCode ?? "",
          courseName:
            session.courseName ?? "",
          studentId,
          institutionId:
            student.institutionId ?? "",
          studentName:
            student.displayName ?? "",
          status,
          markedBy: "teacher",
          markedByUid: teacherId,
          source: "manual",
          markedAt:
            status === "waiting" ?
              null :
              FieldValue.serverTimestamp(),
          updatedAt:
            FieldValue.serverTimestamp(),
        },
        {
          merge: true,
        },
      );

      return {
        success: true,
      };
    },
  );

export const closeAttendanceSession =
  onCall<CloseAttendanceSessionData>(
    {
      timeoutSeconds: 60,
    },
    async (request) => {
      const teacherId =
        request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const sessionId = requiredString(
        request.data.sessionId,
        "Session ID",
        1,
        128,
      );

      const database = getFirestore();

      const sessionReference =
        database
          .collection("attendanceSessions")
          .doc(sessionId);

      const sessionDocument =
        await sessionReference.get();

      const session =
        sessionDocument.data();

      if (
        !sessionDocument.exists ||
        !session
      ) {
        throw new HttpsError(
          "not-found",
          "Attendance session not found.",
        );
      }

      const courseId =
        String(session.courseId);

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      if (session.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "This attendance session is already closed.",
        );
      }

      const students = await database
        .collection("courses")
        .doc(courseId)
        .collection("students")
        .where(
          "isActive",
          "==",
          true,
        )
        .get();

      if (students.size > 200) {
        throw new HttpsError(
          "resource-exhausted",
          "This session contains too many students to finalize at once.",
        );
      }

      const batchWrite =
        database.batch();

      for (const student of students.docs) {
        const studentId =
          student.id;

        const studentData =
          student.data();

        const recordReference =
          database
            .collection("attendanceRecords")
            .doc(
              `${sessionId}_${studentId}`,
            );

        const record =
          await recordReference.get();

        const currentStatus =
          record.exists ?
            record.data()?.status :
            null;

        const wasAttended =
          currentStatus === "present" ||
          currentStatus === "late";

        if (
          !record.exists ||
          currentStatus === "waiting"
        ) {
          batchWrite.set(
            recordReference,
            {
              sessionId,
              courseId,
              courseCode:
                session.courseCode ?? "",
              courseName:
                session.courseName ?? "",
              studentId,
              institutionId:
                studentData.institutionId ??
                "",
              studentName:
                studentData.displayName ??
                "",
              status: "absent",
              markedBy: "system",
              source: "finalization",
              markedAt: null,
              finalizedAt:
                FieldValue.serverTimestamp(),
              updatedAt:
                FieldValue.serverTimestamp(),
            },
            {
              merge: true,
            },
          );
        }

        const summaryReference =
          database
            .collection(
              "attendanceSummaries",
            )
            .doc(
              `${courseId}_${studentId}`,
            );

        const summary =
          await summaryReference.get();

        const previous =
          summary.data() ?? {};

        const previousTotal =
          Number(previous.total ?? 0);

        const previousAttended =
          Number(previous.attended ?? 0);

        const total =
          previousTotal + 1;

        const attended =
          previousAttended +
          (wasAttended ? 1 : 0);

        const percentage =
          total === 0 ?
            0 :
            attended / total * 100;

        const attendanceMarks =
          percentage / 10;

        batchWrite.set(
          summaryReference,
          {
            courseId,
            courseCode:
              session.courseCode ?? "",
            courseName:
              session.courseName ?? "",
            studentId,
            attended,
            total,
            percentage,
            attendanceMarks,
            updatedAt:
              FieldValue.serverTimestamp(),
          },
          {
            merge: true,
          },
        );
      }

      batchWrite.update(
        sessionReference,
        {
          status: "closed",
          closedAt:
            FieldValue.serverTimestamp(),
        },
      );

      await batchWrite.commit();

      return {
        success: true,
      };
    },
  );

export const createAssessment =
  onCall<CreateAssessmentData>(
    {
      timeoutSeconds: 30,
    },
    async (request) => {
      const teacherId =
        request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const courseId = requiredString(
        request.data.courseId,
        "Course ID",
        1,
        128,
      );

      const course =
        await requireOwnedCourse(
          teacherId,
          courseId,
        );

      const name = requiredString(
        request.data.name,
        "Assessment name",
        1,
        80,
      );

      const maxScore =
        requiredNumber(
          request.data.maxScore,
          "Maximum score",
          1,
          1000,
        );

      const reference = getFirestore()
        .collection("assessments")
        .doc();

      await reference.create({
        courseId,
        courseCode:
          course.code ?? "",
        courseName:
          course.name ?? "",
        name,
        maxScore,
        status: "draft",
        teacherId,
        createdAt:
          FieldValue.serverTimestamp(),
        updatedAt:
          FieldValue.serverTimestamp(),
      });

      return {
        assessmentId: reference.id,
      };
    },
  );

export const saveAssessmentMarks =
  onCall<SaveAssessmentMarksData>(
    {
      timeoutSeconds: 60,
    },
    async (request) => {
      const teacherId =
        request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const assessmentId =
        requiredString(
          request.data.assessmentId,
          "Assessment ID",
          1,
          128,
        );

      const database = getFirestore();

      const assessmentReference =
        database
          .collection("assessments")
          .doc(assessmentId);

      const assessmentDocument =
        await assessmentReference.get();

      const assessment =
        assessmentDocument.data();

      if (
        !assessmentDocument.exists ||
        !assessment
      ) {
        throw new HttpsError(
          "not-found",
          "Assessment not found.",
        );
      }

      const courseId =
        String(assessment.courseId);

      await requireOwnedCourse(
        teacherId,
        courseId,
      );

      if (
        assessment.status ===
        "published"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Published marks cannot be edited.",
        );
      }

      if (!Array.isArray(request.data.marks)) {
        throw new HttpsError(
          "invalid-argument",
          "Marks must be a list.",
        );
      }

      if (request.data.marks.length > 200) {
        throw new HttpsError(
          "invalid-argument",
          "Too many marks were submitted at once.",
        );
      }

      const maxScore =
        Number(assessment.maxScore);

      const batchWrite =
        database.batch();

      for (const item of request.data.marks) {
        if (
          typeof item !== "object" ||
          item === null
        ) {
          throw new HttpsError(
            "invalid-argument",
            "Invalid mark entry.",
          );
        }

        const mark =
          item as Record<string, unknown>;

        const studentId =
          requiredString(
            mark.studentId,
            "Student ID",
            1,
            128,
          );

        const score =
          requiredNumber(
            mark.score,
            "Score",
            0,
            maxScore,
          );

        const enrollment =
          await database
            .collection("courses")
            .doc(courseId)
            .collection("students")
            .doc(studentId)
            .get();

        if (
          !enrollment.exists ||
          enrollment.data()?.isActive ===
            false
        ) {
          throw new HttpsError(
            "failed-precondition",
            "A submitted student is not enrolled in this course.",
          );
        }

        const markReference =
          database
            .collection("marks")
            .doc(
              `${assessmentId}_${studentId}`,
            );

        batchWrite.set(
          markReference,
          {
            assessmentId,
            assessmentName:
              assessment.name ?? "",
            courseId,
            courseCode:
              assessment.courseCode ?? "",
            courseName:
              assessment.courseName ?? "",
            studentId,
            score,
            maxScore,
            published: false,
            updatedAt:
              FieldValue.serverTimestamp(),
          },
          {
            merge: true,
          },
        );
      }

      await batchWrite.commit();

      return {
        success: true,
      };
    },
  );

export const publishAssessment =
  onCall<PublishAssessmentData>(
    {
      timeoutSeconds: 60,
    },
    async (request) => {
      const teacherId =
        request.auth?.uid;

      if (!teacherId) {
        throw new HttpsError(
          "unauthenticated",
          "Sign in first.",
        );
      }

      const assessmentId =
        requiredString(
          request.data.assessmentId,
          "Assessment ID",
          1,
          128,
        );

      const database = getFirestore();

      const reference = database
        .collection("assessments")
        .doc(assessmentId);

      const document =
        await reference.get();

      const assessment =
        document.data();

      if (
        !document.exists ||
        !assessment
      ) {
        throw new HttpsError(
          "not-found",
          "Assessment not found.",
        );
      }

      await requireOwnedCourse(
        teacherId,
        String(assessment.courseId),
      );

      const marks = await database
        .collection("marks")
        .where(
          "assessmentId",
          "==",
          assessmentId,
        )
        .get();

      const batchWrite =
        database.batch();

      batchWrite.update(
        reference,
        {
          status: "published",
          publishedAt:
            FieldValue.serverTimestamp(),
          updatedAt:
            FieldValue.serverTimestamp(),
        },
      );

      for (const mark of marks.docs) {
        batchWrite.update(
          mark.ref,
          {
            published: true,
            updatedAt:
              FieldValue.serverTimestamp(),
          },
        );
      }

      await batchWrite.commit();

      return {
        success: true,
      };
    },
  );

import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { initFirebaseAdmin } from "./shared/firebaseAdmin.js";
import { BackendError, RequestContext } from "./shared/types.js";
import {
  registerUser as registerUserOp,
  createCourse as createCourseOp,
  getCourseJoinCode as getCourseJoinCodeOp,
  requestJoinCourse as requestJoinCourseOp,
  respondCourseJoinRequest as respondCourseJoinRequestOp,
  updateCourse as updateCourseOp,
  archiveCourse as archiveCourseOp,
  reactivateCourse as reactivateCourseOp,
  enrollStudent as enrollStudentOp,
  unenrollStudent as unenrollStudentOp,
  createSchedule as createScheduleOp,
  updateSchedule as updateScheduleOp,
  deleteSchedule as deleteScheduleOp,
  createAttendanceSession as createAttendanceSessionOp,
  submitAttendance as submitAttendanceOp,
  setAttendanceStatus as setAttendanceStatusOp,
  closeAttendanceSession as closeAttendanceSessionOp,
  resetAttendancePasscode as resetAttendancePasscodeOp,
  correctClosedAttendance as correctClosedAttendanceOp,
  createAssessment as createAssessmentOp,
  updateAssessment as updateAssessmentOp,
  deleteAssessment as deleteAssessmentOp,
  saveAssessmentMarks as saveAssessmentMarksOp,
  publishAssessment as publishAssessmentOp,
  correctPublishedMark as correctPublishedMarkOp,
} from "./shared/operations/index.js";

initFirebaseAdmin();

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

function toRequestContext(request: any): RequestContext {
  const auth = request.auth;
  return {
    auth: auth
      ? {
        uid: auth.uid,
        email: auth.token?.email,
        email_verified: auth.token?.email_verified,
        role: auth.token?.role,
        token: auth.token,
      }
      : undefined,
    ip: request.rawRequest?.ip,
    headers: request.rawRequest?.headers,
  };
}

async function handleCall<T>(
  operation: (data: any, ctx: RequestContext) => Promise<T>,
  request: any,
): Promise<T> {
  try {
    return await operation(request.data, toRequestContext(request));
  } catch (err: any) {
    if (err instanceof BackendError) {
      throw new HttpsError(err.code as any, err.message);
    }
    if (err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError("internal", err.message || "Internal server error");
  }
}

export const registerUser = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(registerUserOp, req),
);

export const createCourse = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(createCourseOp, req),
);

export const getCourseJoinCode = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(getCourseJoinCodeOp, req),
);

export const requestJoinCourse = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(requestJoinCourseOp, req),
);

export const respondCourseJoinRequest = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(respondCourseJoinRequestOp, req),
);

export const updateCourse = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(updateCourseOp, req),
);

export const archiveCourse = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(archiveCourseOp, req),
);

export const reactivateCourse = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(reactivateCourseOp, req),
);

export const enrollStudent = onCall(
  { timeoutSeconds: 30, maxInstances: 10 },
  (req) => handleCall(enrollStudentOp, req),
);

export const unenrollStudent = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(unenrollStudentOp, req),
);

export const createSchedule = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(createScheduleOp, req),
);

export const updateSchedule = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(updateScheduleOp, req),
);

export const deleteSchedule = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(deleteScheduleOp, req),
);

export const createAttendanceSession = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(createAttendanceSessionOp, req),
);

export const submitAttendance = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(submitAttendanceOp, req),
);

export const setAttendanceStatus = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(setAttendanceStatusOp, req),
);

export const closeAttendanceSession = onCall(
  { timeoutSeconds: 60 },
  (req) => handleCall(closeAttendanceSessionOp, req),
);

export const resetAttendancePasscode = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(resetAttendancePasscodeOp, req),
);

export const correctClosedAttendance = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(correctClosedAttendanceOp, req),
);

export const createAssessment = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(createAssessmentOp, req),
);

export const updateAssessment = onCall(
  { timeoutSeconds: 60 },
  (req) => handleCall(updateAssessmentOp, req),
);

export const deleteAssessment = onCall(
  { timeoutSeconds: 60 },
  (req) => handleCall(deleteAssessmentOp, req),
);

export const saveAssessmentMarks = onCall(
  { timeoutSeconds: 60 },
  (req) => handleCall(saveAssessmentMarksOp, req),
);

export const publishAssessment = onCall(
  { timeoutSeconds: 60 },
  (req) => handleCall(publishAssessmentOp, req),
);

export const correctPublishedMark = onCall(
  { timeoutSeconds: 30 },
  (req) => handleCall(correctPublishedMarkOp, req),
);

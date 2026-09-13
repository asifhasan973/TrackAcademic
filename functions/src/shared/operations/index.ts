export { registerUser } from "./auth/registerUser.js";

export { createCourse } from "./courses/createCourse.js";
export { getCourseJoinCode } from "./courses/getCourseJoinCode.js";
export { requestJoinCourse } from "./courses/requestJoinCourse.js";
export { respondCourseJoinRequest } from "./courses/respondCourseJoinRequest.js";
export { updateCourse } from "./courses/updateCourse.js";
export { archiveCourse } from "./courses/archiveCourse.js";
export { reactivateCourse } from "./courses/reactivateCourse.js";
export { enrollStudent } from "./courses/enrollStudent.js";
export { unenrollStudent } from "./courses/unenrollStudent.js";

export { createSchedule } from "./schedules/createSchedule.js";
export { updateSchedule } from "./schedules/updateSchedule.js";
export { deleteSchedule } from "./schedules/deleteSchedule.js";

export { createAttendanceSession } from "./attendance/createAttendanceSession.js";
export { submitAttendance } from "./attendance/submitAttendance.js";
export { setAttendanceStatus } from "./attendance/setAttendanceStatus.js";
export { closeAttendanceSession } from "./attendance/closeAttendanceSession.js";
export { resetAttendancePasscode } from "./attendance/resetAttendancePasscode.js";
export { correctClosedAttendance } from "./attendance/correctClosedAttendance.js";

export { createAssessment } from "./assessments/createAssessment.js";
export { updateAssessment } from "./assessments/updateAssessment.js";
export { deleteAssessment } from "./assessments/deleteAssessment.js";
export { saveAssessmentMarks } from "./assessments/saveAssessmentMarks.js";
export { publishAssessment } from "./assessments/publishAssessment.js";
export { correctPublishedMark } from "./assessments/correctPublishedMark.js";

import { registerUser } from "./auth/registerUser.js";
import { createCourse } from "./courses/createCourse.js";
import { getCourseJoinCode } from "./courses/getCourseJoinCode.js";
import { requestJoinCourse } from "./courses/requestJoinCourse.js";
import { respondCourseJoinRequest } from "./courses/respondCourseJoinRequest.js";
import { updateCourse } from "./courses/updateCourse.js";
import { archiveCourse } from "./courses/archiveCourse.js";
import { reactivateCourse } from "./courses/reactivateCourse.js";
import { enrollStudent } from "./courses/enrollStudent.js";
import { unenrollStudent } from "./courses/unenrollStudent.js";
import { createSchedule } from "./schedules/createSchedule.js";
import { updateSchedule } from "./schedules/updateSchedule.js";
import { deleteSchedule } from "./schedules/deleteSchedule.js";
import { createAttendanceSession } from "./attendance/createAttendanceSession.js";
import { submitAttendance } from "./attendance/submitAttendance.js";
import { setAttendanceStatus } from "./attendance/setAttendanceStatus.js";
import { closeAttendanceSession } from "./attendance/closeAttendanceSession.js";
import { resetAttendancePasscode } from "./attendance/resetAttendancePasscode.js";
import { correctClosedAttendance } from "./attendance/correctClosedAttendance.js";
import { createAssessment } from "./assessments/createAssessment.js";
import { updateAssessment } from "./assessments/updateAssessment.js";
import { deleteAssessment } from "./assessments/deleteAssessment.js";
import { saveAssessmentMarks } from "./assessments/saveAssessmentMarks.js";
import { publishAssessment } from "./assessments/publishAssessment.js";
import { correctPublishedMark } from "./assessments/correctPublishedMark.js";

import { RequestContext } from "../types.js";

export type OperationHandler = (data: any, context: RequestContext) => Promise<any>;

export const OPERATIONS: Record<string, OperationHandler> = {
  registerUser,
  createCourse,
  getCourseJoinCode,
  requestJoinCourse,
  respondCourseJoinRequest,
  updateCourse,
  archiveCourse,
  reactivateCourse,
  enrollStudent,
  unenrollStudent,
  createSchedule,
  updateSchedule,
  deleteSchedule,
  createAttendanceSession,
  submitAttendance,
  setAttendanceStatus,
  closeAttendanceSession,
  resetAttendancePasscode,
  correctClosedAttendance,
  createAssessment,
  updateAssessment,
  deleteAssessment,
  saveAssessmentMarks,
  publishAssessment,
  correctPublishedMark,
};

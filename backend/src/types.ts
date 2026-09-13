import * as crypto from "crypto";

export type ErrorCode =
  | "ok"
  | "cancelled"
  | "unknown"
  | "invalid-argument"
  | "deadline-exceeded"
  | "not-found"
  | "already-exists"
  | "permission-denied"
  | "resource-exhausted"
  | "failed-precondition"
  | "aborted"
  | "out-of-range"
  | "unimplemented"
  | "internal"
  | "unavailable"
  | "data-loss"
  | "unauthenticated";

export class BackendError extends Error {
  public readonly code: ErrorCode;
  public readonly httpStatus: number;

  constructor(code: ErrorCode, message: string) {
    super(message);
    this.name = "BackendError";
    this.code = code;
    this.httpStatus = BackendError.toHttpStatus(code);
  }

  static toHttpStatus(code: ErrorCode): number {
    switch (code) {
      case "ok":
        return 200;
      case "invalid-argument":
      case "failed-precondition":
      case "out-of-range":
        return 400;
      case "unauthenticated":
        return 401;
      case "permission-denied":
        return 403;
      case "not-found":
        return 404;
      case "already-exists":
      case "aborted":
        return 409;
      case "resource-exhausted":
        return 429;
      case "cancelled":
        return 499;
      case "deadline-exceeded":
        return 504;
      case "unimplemented":
        return 501;
      case "unavailable":
        return 503;
      case "internal":
      case "data-loss":
      case "unknown":
      default:
        return 500;
    }
  }
}

export interface RequestContext {
  auth?: {
    uid: string;
    email?: string;
    email_verified?: boolean;
    role?: string;
    token?: Record<string, any>;
  };
  ip?: string;
  headers?: Record<string, string | string[] | undefined>;
}

export type RegistrationData = {
  displayName?: unknown;
  email?: unknown;
  institutionId?: unknown;
  password?: unknown;
  role?: unknown;
  inviteSecret?: unknown;
};

export type CreateCourseData = {
  code?: unknown;
  name?: unknown;
  department?: unknown;
  batch?: unknown;
  section?: unknown;
  semester?: unknown;
  room?: unknown;
};

export type UpdateCourseData = {
  courseId?: unknown;
  name?: unknown;
  department?: unknown;
  batch?: unknown;
  section?: unknown;
  semester?: unknown;
  room?: unknown;
};

export type ArchiveCourseData = {
  courseId?: unknown;
};

export type ReactivateCourseData = {
  courseId?: unknown;
};

export type EnrollStudentData = {
  courseId?: unknown;
  institutionId?: unknown;
};

export type UnenrollStudentData = {
  courseId?: unknown;
  studentId?: unknown;
};

export type CreateScheduleData = {
  courseId?: unknown;
  dayIndex?: unknown;
  day?: unknown;
  startTime?: unknown;
  endTime?: unknown;
  room?: unknown;
  classType?: unknown;
};

export type UpdateScheduleData = CreateScheduleData & {
  scheduleId?: unknown;
};

export type DeleteScheduleData = {
  scheduleId?: unknown;
};

export type CreateAttendanceSessionData = {
  courseId?: unknown;
  classType?: unknown;
  durationMinutes?: unknown;
  requiresPasscode?: unknown;
  passcode?: unknown;
  requiresGps?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  radiusMeters?: unknown;
  accuracy?: unknown;
  timestamp?: unknown;
  allowLateEntry?: unknown;
};

export type CloseAttendanceSessionData = {
  sessionId?: unknown;
};

export type ResetAttendancePasscodeData = {
  sessionId?: unknown;
};

export type CorrectClosedAttendanceData = {
  sessionId?: unknown;
  studentId?: unknown;
  newStatus?: unknown;
  reason?: unknown;
};

export type SubmitAttendanceData = {
  sessionId?: unknown;
  passcode?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  accuracy?: unknown;
  timestamp?: unknown;
};

export type CreateAssessmentData = {
  courseId?: unknown;
  name?: unknown;
  type?: unknown;
  maxScore?: unknown;
  date?: unknown;
};

export type UpdateAssessmentData = {
  assessmentId?: unknown;
  name?: unknown;
  type?: unknown;
  maxScore?: unknown;
  date?: unknown;
};

export type DeleteAssessmentData = {
  assessmentId?: unknown;
};

export type CorrectPublishedMarkData = {
  assessmentId?: unknown;
  studentId?: unknown;
  newScore?: unknown;
  reason?: unknown;
};

export type SaveAssessmentMarksData = {
  assessmentId?: unknown;
  marks?: unknown;
};

export type PublishAssessmentData = {
  assessmentId?: unknown;
};

export type GetCourseJoinCodeData = {
  courseId?: unknown;
};

export type RequestJoinCourseData = {
  joinCode?: unknown;
};

export type RespondJoinRequestData = {
  requestId?: unknown;
  response?: unknown;
};

export type SetAttendanceStatusData = {
  sessionId?: unknown;
  studentId?: unknown;
  status?: unknown;
};

export function requiredString(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): string {
  if (typeof value !== "string") {
    throw new BackendError(
      "invalid-argument",
      `${field} is required.`,
    );
  }

  const result = value.trim();

  if (result.length < minimum || result.length > maximum) {
    throw new BackendError(
      "invalid-argument",
      `${field} must contain ${minimum}-${maximum} characters.`,
    );
  }

  return result;
}

export function optionalString(
  value: unknown,
  field: string,
  maximum: number,
): string | null {
  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new BackendError(
      "invalid-argument",
      `${field} must be text.`,
    );
  }

  const result = value.trim();

  if (result.length > maximum) {
    throw new BackendError(
      "invalid-argument",
      `${field} is too long.`,
    );
  }

  return result.length === 0 ? null : result;
}

export function requiredNumber(
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
    throw new BackendError(
      "invalid-argument",
      `${field} must be between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export function optionalNumber(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value == null) {
    return null;
  }

  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new BackendError(
      "invalid-argument",
      `${field} must be between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export function requiredBoolean(
  value: unknown,
  field: string,
): boolean {
  if (typeof value !== "boolean") {
    throw new BackendError(
      "invalid-argument",
      `${field} must be true or false.`,
    );
  }

  return value;
}

export function validateEmail(value: unknown): string {
  const email = requiredString(
    value,
    "Email",
    5,
    254,
  ).toLowerCase();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new BackendError(
      "invalid-argument",
      "Enter a valid email address.",
    );
  }

  return email;
}

export function validateInstitutionId(value: unknown): string {
  const institutionId = requiredString(
    value,
    "Institution ID",
    3,
    40,
  ).toUpperCase();

  if (!/^[A-Z0-9_-]+$/.test(institutionId)) {
    throw new BackendError(
      "invalid-argument",
      "Institution ID contains invalid characters.",
    );
  }

  return institutionId;
}

export function validatePassword(value: unknown): string {
  if (
    typeof value !== "string" ||
    value.length < 8 ||
    value.length > 128
  ) {
    throw new BackendError(
      "invalid-argument",
      "Password must contain 8-128 characters.",
    );
  }

  return value;
}

export function validateTime(
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
    throw new BackendError(
      "invalid-argument",
      `${field} must use HH:MM format.`,
    );
  }

  return time;
}

export function validateDayIndex(value: unknown): number {
  const parsed = Number(value);

  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 6) {
    throw new BackendError(
      "invalid-argument",
      "Day index must be an integer between 0 and 6.",
    );
  }

  return parsed;
}

export function validateStrictCalendarDate(value: unknown, field: string): string {
  const dateStr = requiredString(value, field, 10, 10);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
  if (!match) {
    throw new BackendError(
      "invalid-argument",
      `${field} must be a valid date formatted as YYYY-MM-DD.`,
    );
  }

  const year = parseInt(match[1], 10);
  const month = parseInt(match[2], 10);
  const day = parseInt(match[3], 10);

  if (year < 2000 || year > 2100) {
    throw new BackendError(
      "invalid-argument",
      `${field} year must be between 2000 and 2100.`,
    );
  }

  if (month < 1 || month > 12) {
    throw new BackendError(
      "invalid-argument",
      `${field} month must be between 01 and 12.`,
    );
  }

  const isLeapYear =
    (year % 4 === 0 && year % 100 !== 0) || (year % 400 === 0);
  const daysInMonth = [
    31,
    isLeapYear ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  if (day < 1 || day > daysInMonth[month - 1]) {
    throw new BackendError(
      "invalid-argument",
      `${field} day is invalid for month ${match[2]}.`,
    );
  }

  return dateStr;
}

export function timeToMinutes(timeStr: string): number {
  const parts = timeStr.split(":");
  return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
}

export function deriveDayLabel(dayIndex: number): string {
  const days = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];
  if (dayIndex < 0 || dayIndex >= days.length) {
    throw new BackendError(
      "invalid-argument",
      "Day index must be between 0 and 6.",
    );
  }
  return days[dayIndex];
}

export const INACTIVE_SCHEDULE_STATUSES = new Set([
  "cancelled",
  "archived",
  "inactive",
]);

export function hashPasscode(passcode: string, salt: string): string {
  return crypto.scryptSync(passcode, salt, 32).toString("hex");
}

export function verifyPasscode(
  passcode: string,
  salt: string,
  expectedHash: string,
): boolean {
  try {
    const candidateHash = hashPasscode(passcode, salt);
    const candidateBuf = Buffer.from(candidateHash, "hex");
    const expectedBuf = Buffer.from(expectedHash, "hex");
    if (candidateBuf.length !== expectedBuf.length) {
      return false;
    }
    return crypto.timingSafeEqual(candidateBuf, expectedBuf);
  } catch {
    return false;
  }
}

export function degreesToRadians(value: number): number {
  return (value * Math.PI) / 180;
}

export function distanceMeters(
  latitude1: number,
  longitude1: number,
  latitude2: number,
  longitude2: number,
): number {
  const earthRadius = 6371000;

  const deltaLatitude = degreesToRadians(latitude2 - latitude1);
  const deltaLongitude = degreesToRadians(longitude2 - longitude1);
  const firstLatitude = degreesToRadians(latitude1);
  const secondLatitude = degreesToRadians(latitude2);

  const a =
    Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(firstLatitude) *
      Math.cos(secondLatitude) *
      Math.sin(deltaLongitude / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return earthRadius * c;
}

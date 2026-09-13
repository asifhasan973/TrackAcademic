import { getAuthService, getDb } from "../firebaseAdmin.js";
import { BackendError, RequestContext } from "../types.js";

export async function verifyBearerToken(authHeader?: string): Promise<RequestContext["auth"]> {
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return undefined;
  }

  const idToken = authHeader.substring(7).trim();
  if (!idToken) {
    return undefined;
  }

  try {
    const auth = getAuthService();
    const decoded = await auth.verifyIdToken(idToken, true);
    return {
      uid: decoded.uid,
      email: decoded.email,
      email_verified: decoded.email_verified,
      role: decoded.role as string | undefined,
      token: decoded,
    };
  } catch (error: any) {
    throw new BackendError(
      "unauthenticated",
      "Authentication failed. The session may have expired. Please sign in again.",
    );
  }
}

export async function isUserEmailVerified(
  uid: string,
  auth?: { email_verified?: boolean },
): Promise<boolean> {
  const isEmulator =
    process.env.FUNCTIONS_EMULATOR === "true" ||
    !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

  if (isEmulator) {
    return true;
  }

  if (auth && typeof auth.email_verified === "boolean") {
    return auth.email_verified;
  }

  try {
    const userRecord = await getAuthService().getUser(uid);
    return userRecord.emailVerified;
  } catch {
    return false;
  }
}

export async function requireActiveUser(
  uid: string,
  auth?: { email_verified?: boolean },
): Promise<FirebaseFirestore.DocumentData> {
  const verified = await isUserEmailVerified(uid, auth);

  if (!verified) {
    throw new BackendError(
      "permission-denied",
      "A verified email address is required to perform academic operations. Please verify your email.",
    );
  }

  const database = getDb();
  const profile = await database.collection("users").doc(uid).get();
  const data = profile.data();

  if (!profile.exists || !data || data.isActive !== true) {
    throw new BackendError(
      "permission-denied",
      "An active TrackAcademic account is required.",
    );
  }

  return data;
}

export async function requireActiveTeacher(
  uid: string,
  auth?: { email_verified?: boolean },
): Promise<FirebaseFirestore.DocumentData> {
  const data = await requireActiveUser(uid, auth);

  if (data.role !== "teacher") {
    throw new BackendError(
      "permission-denied",
      "Only active teachers are authorized to perform this operation.",
    );
  }

  return data;
}

export async function requireActiveStudent(
  uid: string,
  auth?: { email_verified?: boolean },
): Promise<FirebaseFirestore.DocumentData> {
  const data = await requireActiveUser(uid, auth);

  if (data.role !== "student") {
    throw new BackendError(
      "permission-denied",
      "Only active students are authorized to perform this operation.",
    );
  }

  return data;
}

export async function requireOwnedCourse(
  teacherId: string,
  courseId: string,
  auth?: { email_verified?: boolean },
): Promise<FirebaseFirestore.DocumentData> {
  await requireActiveTeacher(teacherId, auth);

  const database = getDb();
  const course = await database.collection("courses").doc(courseId).get();
  const data = course.data();

  if (!course.exists || !data) {
    throw new BackendError("not-found", "Course not found.");
  }

  if (data.teacherId !== teacherId) {
    throw new BackendError("permission-denied", "You do not manage this course.");
  }

  return data;
}

export async function requireActiveOwnedCourse(
  teacherId: string,
  courseId: string,
  auth?: { email_verified?: boolean },
): Promise<FirebaseFirestore.DocumentData> {
  const data = await requireOwnedCourse(teacherId, courseId, auth);

  if (data.isActive !== true) {
    throw new BackendError("failed-precondition", "This course is archived.");
  }

  return data;
}

export type GetterLike = {
  get: {
    (ref: FirebaseFirestore.DocumentReference): Promise<FirebaseFirestore.DocumentSnapshot>;
    (query: FirebaseFirestore.Query): Promise<FirebaseFirestore.QuerySnapshot>;
  };
};

export async function getCourseNotificationRecipients(
  database: FirebaseFirestore.Firestore,
  getter: GetterLike | null,
  courseId: string,
  category?: "attendance" | "marks" | "schedule",
): Promise<string[]> {
  const studentsQuery = database
    .collection("courses")
    .doc(courseId)
    .collection("students")
    .where("isActive", "==", true);

  const studentsSnap = getter
    ? await getter.get(studentsQuery)
    : await studentsQuery.get();

  const MAX_RECIPIENTS = 100;
  if (studentsSnap.docs.length > MAX_RECIPIENTS) {
    throw new BackendError(
      "resource-exhausted",
      `Course exceeds maximum recipient limit of ${MAX_RECIPIENTS}.`,
    );
  }

  if (studentsSnap.empty) {
    return [];
  }

  if (!category) {
    return studentsSnap.docs.map((d) => d.id);
  }

  const userRefs = studentsSnap.docs.map((d) => database.collection("users").doc(d.id));
  const userDocs = await Promise.all(
    userRefs.map((ref) => (getter ? getter.get(ref) : ref.get())),
  );

  const eligibleStudentIds: string[] = [];
  for (let i = 0; i < userDocs.length; i++) {
    const userDoc = userDocs[i];
    const studentId = studentsSnap.docs[i]!.id;
    if (!userDoc.exists) continue;
    const userData = userDoc.data();
    const prefs = userData?.notificationPreferences;
    if (prefs && prefs[category] === false) {
      continue;
    }
    eligibleStudentIds.push(studentId);
  }

  return eligibleStudentIds;
}

export interface NotificationPayload {
  userId: string;
  type: string;
  title: string;
  message: string;
  courseId: string;
  entityId: string;
}

export interface NotificationItemToWrite {
  ref: FirebaseFirestore.DocumentReference;
  id: string;
  payload: NotificationPayload;
  existingData?: FirebaseFirestore.DocumentData;
}

export async function prepareNotifications(
  database: FirebaseFirestore.Firestore,
  getter: GetterLike | null,
  notifications: Array<{ id: string; payload: NotificationPayload }>,
): Promise<NotificationItemToWrite[]> {
  const items: NotificationItemToWrite[] = [];
  const refs = notifications.map((n) => {
    const ref = database
      .collection("notifications")
      .doc(n.payload.userId)
      .collection("items")
      .doc(n.id);
    return { ref, id: n.id, payload: n.payload };
  });

  if (!getter) {
    return refs;
  }

  const snapshots = await Promise.all(refs.map((item) => getter.get(item.ref)));
  for (let i = 0; i < snapshots.length; i++) {
    const snapshot = snapshots[i]!;
    items.push({
      ref: refs[i]!.ref,
      id: refs[i]!.id,
      payload: refs[i]!.payload,
      existingData: snapshot.exists ? snapshot.data() : undefined,
    });
  }

  return items;
}

export function commitNotificationsInBatch(
  batch: FirebaseFirestore.WriteBatch,
  items: NotificationItemToWrite[],
  timestamp: FirebaseFirestore.FieldValue,
) {
  for (const item of items) {
    if (item.existingData) {
      batch.update(item.ref, {
        title: item.payload.title,
        message: item.payload.message,
        updatedAt: timestamp,
      });
    } else {
      batch.set(item.ref, {
        id: item.id,
        userId: item.payload.userId,
        type: item.payload.type,
        title: item.payload.title,
        message: item.payload.message,
        courseId: item.payload.courseId,
        entityId: item.payload.entityId,
        isRead: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    }
  }
}

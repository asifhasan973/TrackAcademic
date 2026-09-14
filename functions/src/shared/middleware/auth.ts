import { getAuthService, getDb, getMessagingService, FieldValue } from "../firebaseAdmin.js";
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
    if (error?.code === "auth/id-token-revoked") {
      throw new BackendError(
        "unauthenticated",
        "Your session was revoked. Please sign in again.",
      );
    }
    if (error?.code === "auth/user-disabled") {
      throw new BackendError(
        "unauthenticated",
        "This user account has been disabled.",
      );
    }
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

  if (auth && auth.email_verified === true) {
    return true;
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

/**
 * Dispatches real Firebase Cloud Messaging push notifications to recipient devices.
 * - Queries users/{uid}/deviceTokens for multiple devices per user.
 * - Cleans up dead/unregistered tokens automatically.
 * - Handles errors gracefully without failing database transactions.
 */
export async function dispatchPushNotifications(
  database: FirebaseFirestore.Firestore,
  notifications: Array<{ id: string; payload: NotificationPayload }>,
): Promise<void> {
  if (!notifications || notifications.length === 0) return;

  try {
    const messaging = getMessagingService();

    // Group notifications by recipient user ID
    const byUser = new Map<string, Array<{ id: string; payload: NotificationPayload }>>();
    for (const n of notifications) {
      const uid = n.payload.userId;
      if (!uid) continue;
      const list = byUser.get(uid) || [];
      list.push(n);
      byUser.set(uid, list);
    }

    const userIds = Array.from(byUser.keys());
    const tokenDocs = await Promise.all(
      userIds.map(async (uid) => {
        try {
          const snap = await database
            .collection("users")
            .doc(uid)
            .collection("deviceTokens")
            .get();
          return {
            uid,
            tokens: snap.docs.map((doc) => ({
              id: doc.id,
              token: doc.data().token as string,
              ref: doc.ref,
            })),
          };
        } catch (err) {
          console.error(`[FCM] Failed to fetch device tokens for user ${uid}:`, err);
          return { uid, tokens: [] };
        }
      }),
    );

    const messagesToSend: Array<{
      notificationId: string;
      message: any;
      tokenRef: FirebaseFirestore.DocumentReference;
    }> = [];

    interface NotifTrack {
      id: string;
      userId: string;
      totalTokens: number;
      fcmAccepted: number;
      fcmRejected: number;
      timedOutOrUnknown: boolean;
    }

    const notifMap = new Map<string, NotifTrack>();
    for (const n of notifications) {
      notifMap.set(n.id, {
        id: n.id,
        userId: n.payload.userId,
        totalTokens: 0,
        fcmAccepted: 0,
        fcmRejected: 0,
        timedOutOrUnknown: false,
      });
    }

    const seenTokenPerNotif = new Set<string>();
    for (const { uid, tokens } of tokenDocs) {
      if (!tokens.length) continue;
      const userNotifs = byUser.get(uid) || [];
      for (const notif of userNotifs) {
        for (const tokenItem of tokens) {
          if (!tokenItem.token || typeof tokenItem.token !== "string") continue;
          const dedupeKey = `${notif.id}_${tokenItem.token}`;
          if (seenTokenPerNotif.has(dedupeKey)) continue;
          seenTokenPerNotif.add(dedupeKey);

          messagesToSend.push({
            notificationId: notif.id,
            tokenRef: tokenItem.ref,
            message: {
              token: tokenItem.token,
              notification: {
                title: notif.payload.title,
                body: notif.payload.message,
              },
              data: {
                notificationId: notif.id,
                type: notif.payload.type,
                courseId: notif.payload.courseId || "",
                entityId: notif.payload.entityId || "",
                userId: notif.payload.userId,
              },
              android: {
                priority: "high" as const,
                notification: {
                  channelId: "trackacademic_general",
                  clickAction: "FLUTTER_NOTIFICATION_CLICK",
                  sound: "default",
                },
              },
            },
          });

          const track = notifMap.get(notif.id);
          if (track) {
            track.totalTokens++;
          }
        }
      }
    }

    if (!messagesToSend.length) {
      const batch = database.batch();
      for (const n of notifications) {
        const itemRef = database
          .collection("notifications")
          .doc(n.payload.userId)
          .collection("items")
          .doc(n.id);

        batch.set(
          itemRef,
          {
            deliveryStatus: "no_tokens",
            dispatchedAt: FieldValue.serverTimestamp(),
            deliverySummary: {
              tokensTargeted: 0,
              fcmAccepted: 0,
              fcmRejected: 0,
              note: "Recipient has no registered device tokens. Best-effort delivery without automatic recovery.",
            },
          },
          { merge: true },
        );
      }
      await batch.commit().catch(() => {});
      return;
    }

    // Mark deliveryStatus pending on actual notification item records: notifications/{userId}/items/{notificationId}
    const pendingBatch = database.batch();
    for (const n of notifications) {
      const itemRef = database
        .collection("notifications")
        .doc(n.payload.userId)
        .collection("items")
        .doc(n.id);

      pendingBatch.set(
        itemRef,
        {
          deliveryStatus: "pending",
          deliveryAttempts: FieldValue.increment(1),
          lastDispatchedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await pendingBatch.commit().catch(() => {});

    // Bounded delivery work: max 6 seconds to prevent serverless execution hangs
    let dispatchTimedOut = false;
    let timeoutTimer: NodeJS.Timeout | null = null;

    const sendWork = (async () => {
      for (let i = 0; i < messagesToSend.length; i += 500) {
        const chunk = messagesToSend.slice(i, i + 500);
        const response = await messaging.sendEach(chunk.map((c) => c.message));
        const deadRefs: FirebaseFirestore.DocumentReference[] = [];

        response.responses.forEach((resp, idx) => {
          const item = chunk[idx]!;
          const track = notifMap.get(item.notificationId);
          if (resp.success) {
            if (track) track.fcmAccepted++;
          } else if (resp.error) {
            if (track) track.fcmRejected++;
            const code = resp.error.code;
            if (
              code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered"
            ) {
              deadRefs.push(item.tokenRef);
            }
          }
        });

        if (deadRefs.length > 0) {
          const batch = database.batch();
          for (const ref of deadRefs) {
            batch.delete(ref);
          }
          await batch.commit().catch(() => {});
        }
      }
    })();

    await Promise.race([
      sendWork,
      new Promise<void>((_, reject) => {
        timeoutTimer = setTimeout(() => {
          dispatchTimedOut = true;
          reject(new Error("Push dispatch timed out after 6s"));
        }, 6000);
      }),
    ]).catch((err) => {
      console.warn("[FCM_DISPATCH_TIMEOUT_OR_ERR]", err);
    }).finally(() => {
      if (timeoutTimer) clearTimeout(timeoutTimer);
    });

    // If dispatch timed out, mark incomplete notifications as timedOutOrUnknown
    if (dispatchTimedOut) {
      for (const track of notifMap.values()) {
        if (track.fcmAccepted + track.fcmRejected < track.totalTokens) {
          track.timedOutOrUnknown = true;
        }
      }
    }

    // Write individual delivery outcome to each recipient's notification document:
    // notifications/{userId}/items/{notificationId}
    const updateBatch = database.batch();
    for (const track of notifMap.values()) {
      let finalStatus: string;
      if (track.totalTokens === 0) {
        finalStatus = "no_tokens";
      } else if (track.timedOutOrUnknown && track.fcmAccepted === 0) {
        // Timeout or unknown outcome must NEVER become "sent"
        finalStatus = "timed_out";
      } else if (track.fcmAccepted > 0 && track.fcmRejected > 0) {
        finalStatus = "partial";
      } else if (track.fcmAccepted > 0 && track.fcmRejected === 0) {
        finalStatus = track.timedOutOrUnknown ? "partial" : "sent";
      } else if (track.fcmRejected > 0 && track.fcmAccepted === 0) {
        finalStatus = "failed";
      } else {
        finalStatus = "unknown";
      }

      const itemRef = database
        .collection("notifications")
        .doc(track.userId)
        .collection("items")
        .doc(track.id);

      updateBatch.set(
        itemRef,
        {
          deliveryStatus: finalStatus,
          dispatchedAt: FieldValue.serverTimestamp(),
          deliverySummary: {
            tokensTargeted: track.totalTokens,
            fcmAccepted: track.fcmAccepted,
            fcmRejected: track.fcmRejected,
            timedOutOrUnknown: track.timedOutOrUnknown,
            fcmDispatched: track.fcmAccepted > 0,
            note: "Best-effort delivery: FCM acceptance confirms cloud dispatch, not guaranteed physical device receipt. Automatic background recovery is omitted on zero-cost infrastructure to avoid duplicate pushes.",
          },
        },
        { merge: true },
      );
    }
    await updateBatch.commit().catch(() => {});
  } catch (err) {
    console.error("[FCM] dispatchPushNotifications non-blocking error:", err);
  }
}

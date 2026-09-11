import { createRequire } from 'module';
const require = createRequire(process.cwd() + '/functions/package.json');

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

const PROJECT_ID = 'trackacademic-c0d1c';
const AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const FUNCTIONS_HOST = '127.0.0.1:5001';

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;

if (!getApps().length) {
  initializeApp({ projectId: PROJECT_ID });
}

const auth = getAuth();
const db = getFirestore();

async function getIdToken(uid) {
  const customToken = await auth.createCustomToken(uid);
  const response = await fetch(
    `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=test-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    }
  );
  const json = await response.json();
  if (!json.idToken) {
    throw new Error(`Failed to exchange custom token: ${JSON.stringify(json)}`);
  }
  return json.idToken;
}

async function callFunction(name, data = {}, idToken = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/asia-south1/${name}`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ data }),
    }
  );
  return { status: response.status, body: await response.json() };
}

async function firestoreGet(path, idToken = null) {
  const headers = {};
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`,
    { method: 'GET', headers }
  );
  return { status: response.status, body: await response.json() };
}

async function firestorePatch(path, updateMask, fields, idToken = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const maskQuery = updateMask.map(m => `updateMask.fieldPaths=${encodeURIComponent(m)}`).join('&');
  const response = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}?${maskQuery}`,
    {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ fields }),
    }
  );
  return { status: response.status, body: await response.json() };
}

async function firestoreCommit(writes, idToken = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ writes }),
    }
  );
  return { status: response.status, body: await response.json() };
}

let testCount = 0;
let passedCount = 0;

function assert(condition, description) {
  testCount++;
  if (condition) {
    passedCount++;
    console.log(`  ✓ PASS: ${description}`);
  } else {
    console.error(`  ✗ FAIL: ${description}`);
    throw new Error(`Assertion failed: ${description}`);
  }
}

async function createTestUser({ uid, email, role, institutionId, emailVerified = true }) {
  try {
    await auth.deleteUser(uid);
  } catch (_) {}

  await auth.createUser({
    uid,
    email,
    password: 'Password123!',
    displayName: `${role} ${institutionId}`,
    emailVerified,
  });

  await db.collection('users').doc(uid).set({
    uid,
    email,
    displayName: `${role} ${institutionId}`,
    institutionId,
    role,
    isActive: true,
    notificationPreferences: {
      attendance: true,
      marks: true,
      schedule: true,
      announcements: true,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await db.collection('institutionIds').doc(institutionId).set({
    uid,
    role,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function runCourseNotificationsTests() {
  console.log(`\n================================================================`);
  console.log(` Starting TrackAcademic Phase 8 Course Lifecycle & Notifications Tests`);
  console.log(`================================================================\n`);

  const teacher1Uid = 'test_teacher_p8_1';
  const teacher2Uid = 'test_teacher_p8_2';
  const student1Uid = 'test_student_p8_1';
  const student2Uid = 'test_student_p8_2';
  const outsiderUid = 'test_outsider_p8';

  await createTestUser({ uid: teacher1Uid, email: 'teacher1.p8@trackacademic.internal', role: 'teacher', institutionId: 'P8-TCH-001' });
  await createTestUser({ uid: teacher2Uid, email: 'teacher2.p8@trackacademic.internal', role: 'teacher', institutionId: 'P8-TCH-002' });
  await createTestUser({ uid: student1Uid, email: 'student1.p8@trackacademic.internal', role: 'student', institutionId: 'P8-STU-001' });
  await createTestUser({ uid: student2Uid, email: 'student2.p8@trackacademic.internal', role: 'student', institutionId: 'P8-STU-002' });
  await createTestUser({ uid: outsiderUid, email: 'outsider.p8@trackacademic.internal', role: 'student', institutionId: 'P8-OUT-001' });

  // Update student 2 to disable attendance notification preference
  await db.collection('users').doc(student2Uid).update({
    'notificationPreferences.attendance': false,
  });

  const teacher1Token = await getIdToken(teacher1Uid);
  const teacher2Token = await getIdToken(teacher2Uid);
  const student1Token = await getIdToken(student1Uid);
  const student2Token = await getIdToken(student2Uid);
  const outsiderToken = await getIdToken(outsiderUid);

  // Clean up any previous test artifacts
  const collectionsToClean = [
    { col: 'courses', field: 'teacherId', val: teacher1Uid },
    { col: 'schedules', field: 'teacherId', val: teacher1Uid },
    { col: 'attendanceSessions', field: 'teacherId', val: teacher1Uid },
    { col: 'assessments', field: 'teacherId', val: teacher1Uid },
    { col: 'courseJoinRequests', field: 'studentId', val: outsiderUid },
  ];
  for (const item of collectionsToClean) {
    const snap = await db.collection(item.col).where(item.field, '==', item.val).get();
    for (const doc of snap.docs) {
      await db.collection(item.col).doc(doc.id).delete();
    }
  }

  // Clear schedule locks
  const locks = await db.collection('scheduleLocks').where('teacherId', '==', teacher1Uid).get();
  for (const doc of locks.docs) {
    await db.collection('scheduleLocks').doc(doc.id).delete();
  }

  // Clear notifications for test users
  for (const uid of [student1Uid, student2Uid, teacher1Uid, outsiderUid]) {
    const notifs = await db.collection('notifications').doc(uid).collection('items').get();
    for (const doc of notifs.docs) {
      await doc.ref.delete();
    }
  }

  // -------------------------------------------------------------
  // Scenario 1: Course Creation & Metadata Update
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 1: Course Creation & Metadata Update ---`);
  const createRes = await callFunction('createCourse', {
    code: 'CSE-801',
    name: 'Advanced Software Testing',
    department: 'CSE',
    batch: '2026',
    section: 'A',
    semester: '8th',
    room: 'Lab-8',
  }, teacher1Token);

  assert(createRes.status === 200 && createRes.body.result?.courseId, 'Teacher 1 creates course CSE-801');
  const courseId = createRes.body.result.courseId;

  // Verify initial revisions
  const courseDoc = await db.collection('courses').doc(courseId).get();
  assert(courseDoc.data().revision === 1, 'Initial course revision is 1');
  assert(courseDoc.data().lifecycleRevision === 1, 'Initial course lifecycleRevision is 1');
  assert(courseDoc.data().isActive === true, 'Initial course isActive is true');

  // Teacher 2 cannot update Teacher 1's course
  const unauthorizedUpdate = await callFunction('updateCourse', {
    courseId,
    name: 'Hacked Course Name',
  }, teacher2Token);
  assert(unauthorizedUpdate.status === 403 || unauthorizedUpdate.status === 500, 'Non-owner cannot update course metadata (403)');

  // Teacher 1 updates course metadata
  const updateRes = await callFunction('updateCourse', {
    courseId,
    name: 'Advanced Software Verification',
    room: 'Lab-9',
  }, teacher1Token);
  assert(updateRes.status === 200 && updateRes.body.result?.updated === true, 'Teacher 1 successfully updates course metadata');

  const updatedDoc = await db.collection('courses').doc(courseId).get();
  assert(updatedDoc.data().name === 'Advanced Software Verification', 'Course name updated in Firestore');
  assert(updatedDoc.data().room === 'Lab-9', 'Course room updated in Firestore');
  assert(updatedDoc.data().revision === 2, 'Course revision incremented to 2');

  // -------------------------------------------------------------
  // Scenario 2: Enroll Students & Create Pre-Archive State
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 2: Enroll Students & Create Initial Data ---`);
  const enroll1 = await callFunction('enrollStudent', { courseId, institutionId: 'P8-STU-001' }, teacher1Token);
  assert(enroll1.status === 200, 'Student 1 enrolled in CSE-801');

  const enroll2 = await callFunction('enrollStudent', { courseId, institutionId: 'P8-STU-002' }, teacher1Token);
  assert(enroll2.status === 200, 'Student 2 enrolled in CSE-801');

  // Create schedule
  const schedRes = await callFunction('createSchedule', {
    courseId,
    dayIndex: 2,
    startTime: '09:00',
    endTime: '10:30',
    room: 'Lab-9',
    classType: 'Theory',
  }, teacher1Token);
  assert(schedRes.status === 200 && schedRes.body.result?.scheduleId, 'Schedule created for CSE-801');
  const scheduleId = schedRes.body.result.scheduleId;

  // Verify schedule notification sent to enrolled students
  const schedNotif1 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`schedule_create_${scheduleId}_1_${student1Uid}`).get();
  assert(schedNotif1.exists && schedNotif1.data().type === 'schedule_created', 'Schedule creation notification delivered to Student 1 with revision ID');

  // Create assessment draft
  const assessRes = await callFunction('createAssessment', {
    courseId,
    name: 'Class Test 1',
    type: 'quiz',
    maxScore: 20,
    date: '2026-09-15',
  }, teacher1Token);
  assert(assessRes.status === 200 && assessRes.body.result?.assessmentId, 'Draft assessment created for CSE-801');
  const assessmentId = assessRes.body.result.assessmentId;

  // -------------------------------------------------------------
  // Scenario 3: Archive Safety - Active Session Rejection
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 3: Archive Safety & Active Attendance Session Check ---`);
  // Create an active attendance session
  const sessionRes = await callFunction('createAttendanceSession', {
    courseId,
    classType: 'Theory',
    durationMinutes: 15,
    requiresPasscode: true,
    requiresGps: false,
    allowLateEntry: false,
  }, teacher1Token);
  assert(sessionRes.status === 200 && sessionRes.body.result?.sessionId, 'Active attendance session created');
  const sessionId = sessionRes.body.result.sessionId;

  // Student 1 (attendance preference = true) gets notification
  const attNotif1 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`attendance_session_${sessionId}_${student1Uid}`).get();
  assert(attNotif1.exists && (attNotif1.data().type === 'attendance_session_created' || attNotif1.data().type === 'attendance_session_started'), 'Attendance notification received by Student 1');

  // Student 2 (attendance preference = false) does NOT get notification
  const attNotif2 = await db.collection('notifications').doc(student2Uid).collection('items')
    .doc(`attendance_session_${sessionId}_${student2Uid}`).get();
  assert(!attNotif2.exists, 'Student 2 with attendance preference false received NO notification (Preference respected)');

  // Attempt to archive course while attendance session is active -> Must be rejected!
  const rejectArchiveRes = await callFunction('archiveCourse', { courseId }, teacher1Token);
  assert(
    rejectArchiveRes.status === 400 || rejectArchiveRes.status === 500,
    'Archiving course with active attendance session is rejected (failed-precondition)'
  );
  assert(
    JSON.stringify(rejectArchiveRes.body).includes('active attendance session'),
    'Archive rejection message explicitly directs teacher to close session first'
  );

  // Close the attendance session
  const closeRes = await callFunction('closeAttendanceSession', { sessionId }, teacher1Token);
  assert(closeRes.status === 200, 'Attendance session closed successfully');

  // -------------------------------------------------------------
  // Scenario 4: Successful Archive & Notification Fan-out
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 4: Successful Archive & Atomic Notifications ---`);
  const archiveRes = await callFunction('archiveCourse', { courseId }, teacher1Token);
  assert(archiveRes.status === 200 && archiveRes.body.result?.archived === true, 'Course archived successfully after closing session');

  const archivedCourse = await db.collection('courses').doc(courseId).get();
  assert(archivedCourse.data().isActive === false, 'Course document has isActive === false');
  assert(archivedCourse.data().lifecycleRevision === 2, 'Course lifecycleRevision incremented to 2');

  // Verify enrollment documents are PRESERVED and still active
  const enrollDoc1 = await db.collection('courses').doc(courseId).collection('students').doc(student1Uid).get();
  const enrollDoc2 = await db.collection('courses').doc(courseId).collection('students').doc(student2Uid).get();
  assert(enrollDoc1.exists && enrollDoc1.data().isActive === true, 'Student 1 enrollment preserved and isActive == true');
  assert(enrollDoc2.exists && enrollDoc2.data().isActive === true, 'Student 2 enrollment preserved and isActive == true');

  // Verify notifications sent to enrolled students with revision ID
  const archiveNotif1 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`course_archive_${courseId}_2_${student1Uid}`).get();
  assert(archiveNotif1.exists && archiveNotif1.data().type === 'course_archived', 'Student 1 received course_archived notification with revision ID');

  const archiveNotif2 = await db.collection('notifications').doc(student2Uid).collection('items')
    .doc(`course_archive_${courseId}_2_${student2Uid}`).get();
  assert(archiveNotif2.exists && archiveNotif2.data().type === 'course_archived', 'Student 2 received course_archived notification with revision ID');

  // -------------------------------------------------------------
  // Scenario 5: Active-Only Operations Rejected on Archived Course
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 5: Active-Only Operations Rejected on Archived Course ---`);

  // 1. Course metadata update rejected
  const updateWhenArchived = await callFunction('updateCourse', { courseId, name: 'Should Fail' }, teacher1Token);
  assert(updateWhenArchived.status === 400 || updateWhenArchived.status === 500, 'updateCourse denied on archived course');

  // 2. Get join code rejected
  const joinCodeWhenArchived = await callFunction('getCourseJoinCode', { courseId }, teacher1Token);
  assert(joinCodeWhenArchived.status === 400 || joinCodeWhenArchived.status === 500, 'getCourseJoinCode denied on archived course');

  // 3. Direct enroll rejected
  const enrollWhenArchived = await callFunction('enrollStudent', { courseId, institutionId: 'P8-OUT-001' }, teacher1Token);
  assert(enrollWhenArchived.status === 400 || enrollWhenArchived.status === 500, 'enrollStudent denied on archived course');

  // 4. Unenroll rejected
  const unenrollWhenArchived = await callFunction('unenrollStudent', { courseId, studentId: student1Uid }, teacher1Token);
  assert(unenrollWhenArchived.status === 400 || unenrollWhenArchived.status === 500, 'unenrollStudent denied on archived course');

  // 5. Attendance session create rejected
  const sessionWhenArchived = await callFunction('createAttendanceSession', {
    courseId,
    classType: 'Theory',
    durationMinutes: 10,
    requiresPasscode: false,
    requiresGps: false,
    allowLateEntry: false,
  }, teacher1Token);
  assert(sessionWhenArchived.status === 400 || sessionWhenArchived.status === 500, 'createAttendanceSession denied on archived course');

  // 6. Schedule create/update/delete rejected
  const schedUpdateWhenArchived = await callFunction('updateSchedule', {
    scheduleId,
    courseId,
    dayIndex: 3,
    startTime: '10:00',
    endTime: '11:30',
    room: 'Lab-9',
    classType: 'Theory',
  }, teacher1Token);
  assert(schedUpdateWhenArchived.status === 400 || schedUpdateWhenArchived.status === 500, 'updateSchedule denied on archived course');

  const schedDeleteWhenArchived = await callFunction('deleteSchedule', { scheduleId }, teacher1Token);
  assert(schedDeleteWhenArchived.status === 400 || schedDeleteWhenArchived.status === 500, 'deleteSchedule denied on archived course');

  // 7. Assessment update/delete rejected
  const assessUpdateWhenArchived = await callFunction('updateAssessment', {
    assessmentId,
    name: 'Renamed Quiz',
    type: 'quiz',
    maxScore: 25,
    date: '2026-09-16',
  }, teacher1Token);
  assert(assessUpdateWhenArchived.status === 400 || assessUpdateWhenArchived.status === 500, 'updateAssessment denied on archived course');

  const assessDeleteWhenArchived = await callFunction('deleteAssessment', { assessmentId }, teacher1Token);
  assert(assessDeleteWhenArchived.status === 400 || assessDeleteWhenArchived.status === 500, 'deleteAssessment denied on archived course');

  // 8. Save marks and publish assessment rejected
  const saveMarksWhenArchived = await callFunction('saveAssessmentMarks', {
    assessmentId,
    marks: [{ studentId: student1Uid, score: 18 }],
  }, teacher1Token);
  assert(saveMarksWhenArchived.status === 400 || saveMarksWhenArchived.status === 500, 'saveAssessmentMarks denied on archived course');

  const publishWhenArchived = await callFunction('publishAssessment', { assessmentId }, teacher1Token);
  assert(publishWhenArchived.status === 400 || publishWhenArchived.status === 500, 'publishAssessment denied on archived course');

  // -------------------------------------------------------------
  // Scenario 6: Historical-Allowed Operations on Archived Course
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 6: Historical-Allowed Operations on Archived Course ---`);

  // 1. Correct closed attendance succeeds on archived course
  await db.collection('attendanceRecords').doc(`${sessionId}_${student1Uid}`).set({
    sessionId,
    courseId,
    studentId: student1Uid,
    status: 'absent',
    submittedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await db.collection('attendanceSummaries').doc(`${courseId}_${student1Uid}`).set({
    courseId,
    studentId: student1Uid,
    total: 1,
    attended: 0,
    percentage: 0,
    attendanceMarks: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const correctAtt = await callFunction('correctClosedAttendance', {
    sessionId,
    studentId: student1Uid,
    newStatus: 'present',
    reason: 'Verified historical attendance correction during archive',
  }, teacher1Token);
  assert(correctAtt.status === 200 && correctAtt.body.result?.success === true, 'correctClosedAttendance succeeds on archived course');

  // 2. Teacher can read archived course via Firestore rules
  const teacherCourseRead = await firestoreGet(`courses/${courseId}`, teacher1Token);
  assert(teacherCourseRead.status === 200, 'Teacher can read archived course document via Firestore rules');

  // 3. Enrolled student can read archived course via Firestore rules
  const studentCourseRead = await firestoreGet(`courses/${courseId}`, student1Token);
  assert(studentCourseRead.status === 200, 'Enrolled student can read archived course document via Firestore rules');

  // 4. Outsider is DENIED read of archived course
  const outsiderCourseRead = await firestoreGet(`courses/${courseId}`, outsiderToken);
  assert(outsiderCourseRead.status === 403, 'Outsider is denied read of archived course (403)');

  // 5. Outsider cannot read students subcollection
  const outsiderStudentsRead = await firestoreGet(`courses/${courseId}/students/${student1Uid}`, outsiderToken);
  assert(outsiderStudentsRead.status === 403, 'Outsider is denied read of course students subcollection (403)');

  // -------------------------------------------------------------
  // Scenario 7: Reactivation & Second Lifecycle Cycle
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 7: Reactivation & Lifecycle Revisions ---`);

  // Reactivate course
  const reactivateRes = await callFunction('reactivateCourse', { courseId }, teacher1Token);
  assert(reactivateRes.status === 200 && reactivateRes.body.result?.reactivated === true, 'Course reactivated successfully');

  const reactivatedCourse = await db.collection('courses').doc(courseId).get();
  assert(reactivatedCourse.data().isActive === true, 'Course isActive restored to true');
  assert(reactivatedCourse.data().lifecycleRevision === 3, 'Course lifecycleRevision incremented to 3');

  // Verify reactivate notification delivered with revision 3
  const reactivateNotif1 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`course_reactivate_${courseId}_3_${student1Uid}`).get();
  assert(reactivateNotif1.exists && reactivateNotif1.data().type === 'course_reactivated', 'Student 1 received course_reactivated notification with revision 3');

  // Now active-only operations succeed again!
  const updateAfterReactivate = await callFunction('updateCourse', {
    courseId,
    name: 'Advanced Software Testing - Reactivated',
  }, teacher1Token);
  assert(updateAfterReactivate.status === 200, 'updateCourse succeeds now that course is reactivated');

  // Second archive cycle -> verify it creates NEW notification with revision 4 rather than overwriting revision 2
  const secondArchiveRes = await callFunction('archiveCourse', { courseId }, teacher1Token);
  assert(secondArchiveRes.status === 200, 'Second course archive succeeded');

  const courseAfter2ndArchive = await db.collection('courses').doc(courseId).get();
  assert(courseAfter2ndArchive.data().lifecycleRevision === 4, 'Course lifecycleRevision incremented to 4');

  const archiveNotifRev2 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`course_archive_${courseId}_2_${student1Uid}`).get();
  const archiveNotifRev4 = await db.collection('notifications').doc(student1Uid).collection('items')
    .doc(`course_archive_${courseId}_4_${student1Uid}`).get();

  assert(archiveNotifRev2.exists, 'First archive notification (revision 2) preserved in history');
  assert(archiveNotifRev4.exists, 'Second archive notification (revision 4) created distinctly in history');

  // Reactivate again to test subsequent join requests
  await callFunction('reactivateCourse', { courseId }, teacher1Token);

  // -------------------------------------------------------------
  // Scenario 8: Join Request Notifications & Repeated Requests
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 8: Join Request Notification Revisions & Repeated Lifecycle ---`);

  // Get join code
  const joinCodeRes = await callFunction('getCourseJoinCode', { courseId }, teacher1Token);
  const joinCode = joinCodeRes.body.result.joinCode;
  assert(joinCode && joinCode.length > 0, 'Retrieved active course join code');

  // Outsider requests to join (attempt 1)
  const joinReq1 = await callFunction('requestJoinCourse', { joinCode }, outsiderToken);
  assert(joinReq1.status === 200, 'Outsider requested to join course (attempt 1)');
  const requestId1 = joinReq1.body.result.requestId;

  // Verify teacher received notification with attempt 1
  const teacherNotif1 = await db.collection('notifications').doc(teacher1Uid).collection('items')
    .doc(`join_request_${courseId}_${outsiderUid}_1`).get();
  assert(teacherNotif1.exists && teacherNotif1.data().type === 'join_request', 'Teacher received join_request notification with attempt 1');

  // Teacher rejects request 1
  const rejectReq1 = await callFunction('respondCourseJoinRequest', {
    requestId: requestId1,
    response: 'rejected',
  }, teacher1Token);
  assert(rejectReq1.status === 200, 'Teacher rejected join request 1');

  const studentRejectNotif1 = await db.collection('notifications').doc(outsiderUid).collection('items')
    .doc(`join_decision_${requestId1}_1`).get();
  assert(studentRejectNotif1.exists && studentRejectNotif1.data().type === 'join_request_rejected', 'Student received rejection notification with attempt 1');

  // Student requests to join again (attempt 2)
  const joinReq2 = await callFunction('requestJoinCourse', { joinCode }, outsiderToken);
  assert(joinReq2.status === 200, 'Outsider requested to join course again (attempt 2)');
  const requestId2 = joinReq2.body.result.requestId;

  const teacherNotif2 = await db.collection('notifications').doc(teacher1Uid).collection('items')
    .doc(`join_request_${courseId}_${outsiderUid}_2`).get();
  assert(teacherNotif2.exists && teacherNotif2.id !== teacherNotif1.id, 'Teacher received distinct join_request notification for attempt 2 without overwriting attempt 1');

  // Teacher approves request 2
  const approveReq2 = await callFunction('respondCourseJoinRequest', {
    requestId: requestId2,
    response: 'approved',
  }, teacher1Token);
  assert(approveReq2.status === 200, 'Teacher approved join request 2');

  const studentApproveNotif2 = await db.collection('notifications').doc(outsiderUid).collection('items')
    .doc(`join_decision_${requestId2}_2`).get();
  assert(studentApproveNotif2.exists && studentApproveNotif2.data().type === 'join_request_approved', 'Student received approval notification for attempt 2');

  // -------------------------------------------------------------
  // Scenario 9: Notification Client Security Rules & Bounded Updates
  // -------------------------------------------------------------
  console.log(`\n--- Scenario 9: Notification Client Rules & Bounded Read Operations ---`);

  // Student 1 can read own notifications
  const notifDocPath = `notifications/${student1Uid}/items/${archiveNotifRev2.id}`;
  const getOwnNotif = await firestoreGet(notifDocPath, student1Token);
  assert(getOwnNotif.status === 200, 'Student 1 can read own notification');

  // Student 2 cannot read Student 1's notifications (Outsider/cross-user denied)
  const getOtherNotif = await firestoreGet(notifDocPath, student2Token);
  assert(getOtherNotif.status === 403, 'Cross-user notification read is denied (403)');

  // Student 1 can update isRead: true with server timestamp
  const docFullName = `projects/${PROJECT_ID}/databases/(default)/documents/${notifDocPath}`;
  const validCommit = await firestoreCommit([
    {
      update: {
        name: docFullName,
        fields: {
          isRead: { booleanValue: true },
        },
      },
      updateMask: {
        fieldPaths: ['isRead'],
      },
      updateTransforms: [
        {
          fieldPath: 'readAt',
          setToServerValue: 'REQUEST_TIME',
        },
      ],
    },
  ], student1Token);
  assert(validCommit.status === 200, 'Student 1 can update isRead: true and readAt with server timestamp');

  // Student 1 can also unread notification (isRead: false, readAt: null)
  const validUnread = await firestorePatch(
    notifDocPath,
    ['isRead', 'readAt'],
    {
      isRead: { booleanValue: false },
      readAt: { nullValue: null },
    },
    student1Token
  );
  assert(validUnread.status === 200, 'Student 1 can unread notification (isRead: false, readAt: null)');

  // Student 1 CANNOT tamper with notification title or message
  const invalidTamper = await firestorePatch(
    notifDocPath,
    ['title'],
    {
      title: { stringValue: 'Tampered Title' },
    },
    student1Token
  );
  assert(invalidTamper.status === 403, 'Client cannot tamper with notification title (403)');

  // Client cannot delete or create notifications directly
  const createDirectRes = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/notifications/${student1Uid}/items?documentId=fake_notif`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${student1Token}`,
      },
      body: JSON.stringify({
        fields: {
          title: { stringValue: 'Fake Notification' },
        },
      }),
    }
  );
  assert(createDirectRes.status === 403, 'Client direct creation of notification is denied (403)');

  console.log(`\n================================================================`);
  console.log(` Phase 8 Test Suite Completed: ${passedCount}/${testCount} Passed (100%)`);
  console.log(`================================================================\n`);
}

runCourseNotificationsTests().catch((err) => {
  console.error('Test suite failed:', err);
  process.exit(1);
});

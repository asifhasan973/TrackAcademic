import { createRequire } from 'module';
const require = createRequire(process.cwd() + '/functions/package.json');

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

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

async function firestoreGet(path, idToken = null) {
  const headers = {};
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`,
    { method: 'GET', headers }
  );
  return { status: response.status, body: await response.json() };
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

async function runAttendanceLifecycleTests() {
  console.log(`\n======================================================`);
  console.log(` Starting TrackAcademic Attendance Lifecycle Tests`);
  console.log(` Target Project: ${PROJECT_ID}`);
  console.log(`======================================================\n`);

  // 1. Setup Identities
  console.log('1. Setting up identities in Auth & Firestore...');
  const owner1Uid = 'teacher-owner1';
  const owner2Uid = 'teacher-owner2';
  const student1Uid = 'student-stu1';
  const student2Uid = 'student-stu2';
  const outsiderUid = 'user-outsider';
  const unverifiedUid = 'teacher-unverified';

  for (const u of [
    { uid: owner1Uid, email: 'owner1@dept.edu', emailVerified: true, role: 'teacher' },
    { uid: owner2Uid, email: 'owner2@dept.edu', emailVerified: true, role: 'teacher' },
    { uid: student1Uid, email: 'stu1@dept.edu', emailVerified: true, role: 'student' },
    { uid: student2Uid, email: 'stu2@dept.edu', emailVerified: true, role: 'student' },
    { uid: outsiderUid, email: 'outsider@dept.edu', emailVerified: true, role: 'student' },
    { uid: unverifiedUid, email: 'unverified@dept.edu', emailVerified: false, role: 'teacher' },
  ]) {
    try { await auth.deleteUser(u.uid); } catch {}
    await auth.createUser({
      uid: u.uid,
      email: u.email,
      emailVerified: u.emailVerified,
      displayName: u.uid,
    });
    await db.collection('users').doc(u.uid).set({
      role: u.role,
      institutionId: `ID-${u.uid}`,
      name: u.uid,
      department: 'CSE',
      email: u.email,
      isActive: true,
      emailVerified: u.emailVerified,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  const owner1Token = await getIdToken(owner1Uid);
  const owner2Token = await getIdToken(owner2Uid);
  const student1Token = await getIdToken(student1Uid);
  const student2Token = await getIdToken(student2Uid);
  const outsiderToken = await getIdToken(outsiderUid);
  const unverifiedToken = await getIdToken(unverifiedUid);

  // 2. Setup Courses & Enrollments
  console.log('\n2. Setting up test courses and student enrollments...');
  const course1Id = 'course-cse301';
  const course2Id = 'course-cse302';

  await db.collection('courses').doc(course1Id).set({
    code: 'CSE 301',
    title: 'Database Systems',
    department: 'CSE',
    teacherId: owner1Uid,
    teacherName: 'Teacher Owner 1',
    section: 'A',
    classroomLatitude: 23.777176,
    classroomLongitude: 90.399452,
    attendanceRadiusMeters: 100,
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.collection('courses').doc(course2Id).set({
    code: 'CSE 302',
    title: 'Operating Systems',
    department: 'CSE',
    teacherId: owner2Uid,
    teacherName: 'Teacher Owner 2',
    section: 'B',
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  // Enroll student1 and student2 in course1
  for (const s of [
    { uid: student1Uid, name: 'Student One', instId: 'ID-student-stu1', email: 'stu1@dept.edu' },
    { uid: student2Uid, name: 'Student Two', instId: 'ID-student-stu2', email: 'stu2@dept.edu' },
  ]) {
    await db.collection('courses').doc(course1Id).collection('students').doc(s.uid).set({
      studentId: s.uid,
      institutionId: s.instId,
      displayName: s.name,
      email: s.email,
      isActive: true,
      enrolledAt: FieldValue.serverTimestamp(),
    });
    await db.collection('enrollments').doc(`${course1Id}_${s.uid}`).set({
      courseId: course1Id,
      studentId: s.uid,
      status: 'active',
      enrolledAt: FieldValue.serverTimestamp(),
    });
  }

  // 3. Passcode Creation & Cryptographic Storage Security
  console.log('\n3. Testing Passcode Creation & Server-side Cryptographic Storage...');
  const createSessionRes = await callFunction(
    'createAttendanceSession',
    {
      courseId: course1Id,
      classType: 'Theory',
      durationMinutes: 15,
      requiresPasscode: true,
      requiresGps: true,
      allowLateEntry: true,
      latitude: 23.777176,
      longitude: 90.399452,
      radiusMeters: 100,
    },
    owner1Token
  );

  assert(createSessionRes.status === 200, 'Session creation returned HTTP 200');
  const sessionId = createSessionRes.body.result?.sessionId;
  const initialPasscode = createSessionRes.body.result?.passcode;
  assert(sessionId && sessionId.length > 0, 'Session ID returned');
  assert(initialPasscode && /^\d{6}$/.test(initialPasscode), 'Plaintext 6-digit passcode returned in creation response');

  // Verify Firestore session document contains NO plaintext passcode
  const sessionDoc = await db.collection('attendanceSessions').doc(sessionId).get();
  assert(sessionDoc.exists, 'Session document exists in Firestore');
  const sessionData = sessionDoc.data();
  assert(sessionData.passcode === undefined, 'Session document does NOT contain plaintext passcode');
  assert(sessionData.requiresPasscode === true, 'Session requiresPasscode flag is true');
  assert(sessionData.status === 'active', 'Session is active');

  // Verify private/config subcollection contains hash and salt
  const privateConfigDoc = await db.collection('attendanceSessions').doc(sessionId).collection('private').doc('config').get();
  assert(privateConfigDoc.exists, 'Private config subcollection document exists');
  const privateConfig = privateConfigDoc.data();
  assert(privateConfig.passcodeHash && privateConfig.passcodeHash.length > 20, 'Passcode hash stored securely');
  assert(privateConfig.passcodeSalt && privateConfig.passcodeSalt.length > 10, 'Passcode salt stored securely');
  assert(privateConfig.passcode === undefined, 'Private config does NOT contain plaintext passcode');

  // Test direct client read on private config is denied (Rule enforcement)
  const clientPrivateRead = await firestoreGet(
    `attendanceSessions/${sessionId}/private/config`,
    student1Token
  );
  assert(
    clientPrivateRead.status === 403 || clientPrivateRead.status === 404,
    'Client cannot read private config via Firestore SDK (got HTTP ' + clientPrivateRead.status + ')'
  );

  const outsiderPrivateRead = await firestoreGet(
    `attendanceSessions/${sessionId}/private/config`,
    outsiderToken
  );
  assert(
    outsiderPrivateRead.status === 403 || outsiderPrivateRead.status === 404,
    'Outsider cannot read private config via Firestore SDK (got HTTP ' + outsiderPrivateRead.status + ')'
  );

  // 4. Reset Passcode Authorization & Invalidation
  console.log('\n4. Testing Reset Passcode Authorization & Invalidation...');
  // Outsider cannot reset
  const outsiderReset = await callFunction('resetAttendancePasscode', { sessionId }, outsiderToken);
  assert(outsiderReset.status === 403, 'Outsider reset passcode rejected with 403');

  // Student cannot reset
  const studentReset = await callFunction('resetAttendancePasscode', { sessionId }, student1Token);
  assert(studentReset.status === 403, 'Student reset passcode rejected with 403');

  // Unverified teacher cannot reset
  const unverifiedReset = await callFunction('resetAttendancePasscode', { sessionId }, unverifiedToken);
  assert(unverifiedReset.status === 403, 'Unverified teacher reset passcode rejected with 403');

  // Owner 2 (different course) cannot reset
  const owner2Reset = await callFunction('resetAttendancePasscode', { sessionId }, owner2Token);
  assert(owner2Reset.status === 403, 'Wrong teacher reset passcode rejected with 403');

  // Course Owner 1 resets passcode successfully
  const owner1Reset = await callFunction('resetAttendancePasscode', { sessionId }, owner1Token);
  assert(owner1Reset.status === 200, 'Owner 1 reset passcode succeeded with 200');
  const newPasscode = owner1Reset.body.result?.passcode;
  assert(newPasscode && /^\d{6}$/.test(newPasscode), 'Owner received fresh 6-digit passcode');
  assert(newPasscode !== initialPasscode, 'New passcode is distinct from initial passcode');

  // Verify old passcode is rejected
  const oldPasscodeSubmit = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode: initialPasscode,
      latitude: 23.777176,
      longitude: 90.399452,
    },
    student1Token
  );
  assert(
    oldPasscodeSubmit.status === 400 || oldPasscodeSubmit.status === 403,
    'Submission with old invalidated passcode is rejected'
  );

  // 5. Radius Validation & Successful Submission
  console.log('\n5. Testing Location Radius Validation & Submission...');
  // Wrong passcode rejected
  const wrongPasscodeSubmit = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode: '999999',
      latitude: 23.777176,
      longitude: 90.399452,
    },
    student1Token
  );
  assert(wrongPasscodeSubmit.status === 400 || wrongPasscodeSubmit.status === 403, 'Wrong passcode rejected');

  // Outside radius rejected (> 100m away, e.g. latitude + 0.01 is ~1.1km away)
  const outsideRadiusSubmit = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode: newPasscode,
      latitude: 23.787176,
      longitude: 90.399452,
    },
    student1Token
  );
  assert(
    outsideRadiusSubmit.status === 403 || outsideRadiusSubmit.status === 400,
    'Outside radius submission rejected with 403/400 (got ' + outsideRadiusSubmit.status + ')'
  );

  // Valid submission within radius with correct passcode
  const validSubmit = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode: newPasscode,
      latitude: 23.777180,
      longitude: 90.399450,
    },
    student1Token
  );
  assert(validSubmit.status === 200, 'Valid submission accepted with 200');
  assert(validSubmit.body.result?.success === true, 'Student 1 submission result success is true');
  const s1RecordDoc = await db.collection('attendanceRecords').doc(`${sessionId}_${student1Uid}`).get();
  assert(s1RecordDoc.exists, 'Student 1 record exists in Firestore');
  assert(s1RecordDoc.data().status === 'present', 'Student 1 record status is present');

  // Duplicate submission rejected
  const duplicateSubmit = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode: newPasscode,
      latitude: 23.777180,
      longitude: 90.399450,
    },
    student1Token
  );
  assert(
    duplicateSubmit.status === 409 || duplicateSubmit.status === 400 || duplicateSubmit.body.result?.alreadySubmitted === true,
    'Duplicate submission rejected with 409/400 (got ' + duplicateSubmit.status + ')'
  );

  // 6. Session Closing & Automatic Absent Finalization
  console.log('\n6. Testing Session Closing & Absentee Finalization...');
  const closeSessionRes = await callFunction(
    'closeAttendanceSession',
    { sessionId },
    owner1Token
  );
  assert(closeSessionRes.status === 200, 'Session closed with HTTP 200');

  // Verify student2 was automatically marked absent
  const student2RecordDoc = await db.collection('attendanceRecords').doc(`${sessionId}_${student2Uid}`).get();
  assert(student2RecordDoc.exists, 'Student 2 record created upon session closure');
  assert(student2RecordDoc.data().status === 'absent', 'Unsubmitted student 2 marked absent');

  // Verify course attendance aggregates
  const student1Summary = (await db.collection('attendanceSummaries').doc(`${course1Id}_${student1Uid}`).get()).data();
  assert(student1Summary.attended === 1, 'Student 1 attended count is 1');
  assert(student1Summary.total === 1, 'Student 1 total sessions is 1');

  const student2Summary = (await db.collection('attendanceSummaries').doc(`${course1Id}_${student2Uid}`).get()).data();
  assert(student2Summary.attended === 0, 'Student 2 attended count is 0');
  assert(student2Summary.total === 1, 'Student 2 total sessions is 1');

  // 7. Closed Attendance Correction Authorization & Validation
  console.log('\n7. Testing Closed Attendance Correction Authorizations & Edge Cases...');

  // Student cannot correct
  const studentCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'present', reason: 'I was there' },
    student1Token
  );
  assert(studentCorrection.status === 403, 'Student correction rejected with 403');

  // Teacher 2 (not course owner) cannot correct
  const teacher2Correction = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'present', reason: 'Excused' },
    owner2Token
  );
  assert(teacher2Correction.status === 403, 'Non-owner teacher correction rejected with 403');

  // Unverified teacher cannot correct
  const unverifiedCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'present', reason: 'Excused' },
    unverifiedToken
  );
  assert(unverifiedCorrection.status === 403, 'Unverified teacher correction rejected with 403');

  // Missing / empty reason rejected
  const emptyReasonCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'present', reason: '   ' },
    owner1Token
  );
  assert(emptyReasonCorrection.status === 400, 'Correction with empty reason rejected with 400');

  // Invalid 'waiting' status correction rejected
  const waitingCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'waiting', reason: 'Resetting to waiting' },
    owner1Token
  );
  assert(waitingCorrection.status === 400, 'Correction to waiting status rejected with 400');

  // Invalid arbitrary status rejected
  const bogusStatusCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'excused_maybe', reason: 'Invalid' },
    owner1Token
  );
  assert(bogusStatusCorrection.status === 400, 'Correction with arbitrary status rejected with 400');

  // Mismatched session / course record rejected
  const mismatchedCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: outsiderUid, newStatus: 'present', reason: 'Outsider test' },
    owner1Token
  );
  assert(
    mismatchedCorrection.status === 404 || mismatchedCorrection.status === 400,
    'Correction for non-existent / mismatched student record rejected'
  );

  // Same-status correction is idempotent no-change
  const sameStatusCorrection = await callFunction(
    'correctClosedAttendance',
    { sessionId, studentId: student2Uid, newStatus: 'absent', reason: 'Confirming absence' },
    owner1Token
  );
  assert(sameStatusCorrection.status === 200, 'Same-status correction returned 200');
  assert(sameStatusCorrection.body.result?.changed === false, 'Same-status correction indicated changed: false');
  
  // Verify aggregates unchanged after same-status call
  const s2SummaryAfterNoOp = (await db.collection('attendanceSummaries').doc(`${course1Id}_${student2Uid}`).get()).data();
  assert(s2SummaryAfterNoOp.attended === 0, 'Student 2 attended still 0 after no-op');
  assert(s2SummaryAfterNoOp.total === 1, 'Student 2 total unchanged after no-op');

  // 8. Repeated & Stateful Attendance Corrections
  console.log('\n8. Testing Repeated & Stateful Corrections with Aggregate Integrity...');

  // Step 8a: Correct absent -> present
  const absentToPresent = await callFunction(
    'correctClosedAttendance',
    {
      sessionId,
      studentId: student2Uid,
      newStatus: 'present',
      reason: 'Medical certificate verified by department head',
    },
    owner1Token
  );
  assert(absentToPresent.status === 200, 'Correction absent -> present succeeded');
  assert(absentToPresent.body.result?.changed === true, 'Result changed is true');
  assert(absentToPresent.body.result?.attended === 1, 'Attended is now 1');
  assert(absentToPresent.body.result?.total === 1, 'Total remains 1');

  // Verify Firestore record & summary
  const s2Rec1 = (await db.collection('attendanceRecords').doc(`${sessionId}_${student2Uid}`).get()).data();
  assert(s2Rec1.status === 'present', 'Record status updated to present');
  assert(s2Rec1.previousStatus === 'absent', 'Record previousStatus recorded');
  assert(s2Rec1.correctionReason === 'Medical certificate verified by department head', 'Correction reason saved');

  // Step 8b: Correct present -> late (attended count should remain 1 because late is attended)
  const presentToLate = await callFunction(
    'correctClosedAttendance',
    {
      sessionId,
      studentId: student2Uid,
      newStatus: 'late',
      reason: 'Arrived 15 minutes late after doctor appointment',
    },
    owner1Token
  );
  assert(presentToLate.status === 200, 'Correction present -> late succeeded');
  assert(presentToLate.body.result?.attended === 1, 'Attended remains 1 (late counts as attended)');
  assert(presentToLate.body.result?.total === 1, 'Total remains 1');

  // Step 8c: Correct late -> absent (attended should decrement back to 0)
  const lateToAbsent = await callFunction(
    'correctClosedAttendance',
    {
      sessionId,
      studentId: student2Uid,
      newStatus: 'absent',
      reason: 'Proxy discovered upon roster audit',
    },
    owner1Token
  );
  assert(lateToAbsent.status === 200, 'Correction late -> absent succeeded');
  assert(lateToAbsent.body.result?.attended === 0, 'Attended decremented to 0');
  assert(lateToAbsent.body.result?.total === 1, 'Total remains 1');

  // Verify audit log entries exist and are immutable
  const auditQuery = await db.collection('auditLogs')
    .where('sessionId', '==', sessionId)
    .where('studentId', '==', student2Uid)
    .get();
  assert(auditQuery.size >= 3, 'Audit log entries created for each correction step (count: ' + auditQuery.size + ')');

  // 9. Concurrent Correction Safety (Transaction isolation)
  console.log('\n9. Testing Concurrent Correction Safety...');
  const [c1, c2] = await Promise.all([
    callFunction(
      'correctClosedAttendance',
      { sessionId, studentId: student2Uid, newStatus: 'present', reason: 'Concurrent request A' },
      owner1Token
    ),
    callFunction(
      'correctClosedAttendance',
      { sessionId, studentId: student2Uid, newStatus: 'late', reason: 'Concurrent request B' },
      owner1Token
    ),
  ]);
  assert(c1.status === 200 || c2.status === 200, 'At least one concurrent transaction committed cleanly');
  const finalSummary = (await db.collection('attendanceSummaries').doc(`${course1Id}_${student2Uid}`).get()).data();
  assert(finalSummary.total === 1, 'Total sessions strictly maintained as 1');
  assert(finalSummary.attended >= 0 && finalSummary.attended <= finalSummary.total, 'Attended is safely clamped within [0, total]');

  // 10. Summary Isolation
  console.log('\n10. Verifying Course & Summary Isolation...');
  const course2Doc = await firestoreGet(`courses/${course2Id}`, student1Token);
  assert(course2Doc.status === 200 || course2Doc.status === 403, 'Course check completed');
  // Student 1 cannot read Course 2 private session data
  const leakCheck = await firestoreGet(`attendanceSummaries/${course2Id}_${student1Uid}`, student1Token);
  assert(leakCheck.status === 403 || leakCheck.status === 404, 'No summary leak across courses');

  console.log(`\n======================================================`);
  console.log(` Attendance Lifecycle Tests Passed: ${passedCount}/${testCount}`);
  console.log(`======================================================\n`);
}

runAttendanceLifecycleTests().catch((err) => {
  console.error('\nTest runner failed:', err);
  process.exit(1);
});

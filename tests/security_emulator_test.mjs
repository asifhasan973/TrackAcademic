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

async function firestoreWrite(path, data, idToken = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers['Authorization'] = `Bearer ${idToken}`;
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    if (typeof v === 'string') fields[k] = { stringValue: v };
    else if (typeof v === 'number') fields[k] = { integerValue: String(v) };
    else if (typeof v === 'boolean') fields[k] = { booleanValue: v };
  }
  const response = await fetch(
    `http://${FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`,
    {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ fields }),
    }
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

async function runSecurityTests() {
  console.log(`\n======================================================`);
  console.log(` Starting TrackAcademic Security & Authorization Tests`);
  console.log(` Target Project: ${PROJECT_ID}`);
  console.log(`======================================================\n`);

  // 1. Setup Test Identities in Auth Emulator
  console.log('1. Setting up test identities in Firebase Auth & Firestore...');
  const unverifiedUid = 'user-unverified';
  const owner1Uid = 'user-owner1';
  const owner2Uid = 'user-owner2';
  const student1Uid = 'user-student1';
  const outsiderUid = 'user-outsider';

  for (const u of [
    { uid: unverifiedUid, email: 'unverified@test.com', emailVerified: false },
    { uid: owner1Uid, email: 'owner1@test.com', emailVerified: true },
    { uid: owner2Uid, email: 'owner2@test.com', emailVerified: true },
    { uid: student1Uid, email: 'student1@test.com', emailVerified: true },
    { uid: outsiderUid, email: 'outsider@test.com', emailVerified: true },
  ]) {
    try { await auth.deleteUser(u.uid); } catch {}
    await auth.createUser({
      uid: u.uid,
      email: u.email,
      emailVerified: u.emailVerified,
      displayName: u.uid,
      password: 'password123',
    });
    // Seed profile in Firestore
    await db.collection('users').doc(u.uid).set({
      displayName: u.uid,
      email: u.email,
      institutionId: `INST-${u.uid.toUpperCase()}`,
      isActive: true,
      courseIds: u.uid === student1Uid ? ['course-1'] : [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // Seed test academic data
  console.log('2. Seeding test course, enrollment, marks, and attendance...');
  const courseId = 'course-1';
  await db.collection('courses').doc(courseId).set({
    code: 'CSE101',
    name: 'Intro to Programming',
    teacherId: owner1Uid,
    isActive: true,
    joinCode: 'CSE101JC',
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.collection('courses').doc(courseId).collection('students').doc(student1Uid).set({
    studentId: student1Uid,
    institutionId: 'INST-USER-STUDENT1',
    isActive: true,
    enrolledAt: FieldValue.serverTimestamp(),
  });

  const assessmentPublishedId = 'assess-pub-1';
  await db.collection('assessments').doc(assessmentPublishedId).set({
    courseId,
    name: 'Midterm',
    status: 'published',
    maxScore: 100,
  });

  const assessmentDraftId = 'assess-draft-1';
  await db.collection('assessments').doc(assessmentDraftId).set({
    courseId,
    name: 'Final Exam (Draft)',
    status: 'draft',
    maxScore: 100,
  });

  await db.collection('marks').doc('mark-student1').set({
    courseId,
    assessmentId: assessmentPublishedId,
    studentId: student1Uid,
    score: 92,
    published: true,
  });

  await db.collection('marks').doc('mark-other').set({
    courseId,
    assessmentId: assessmentPublishedId,
    studentId: 'other-student',
    score: 75,
    published: true,
  });

  await db.collection('attendanceSessions').doc('session-1').set({
    courseId,
    classType: 'Lecture',
    isActive: true,
  });

  await db.collection('attendanceRecords').doc('att-student1').set({
    courseId,
    sessionId: 'session-1',
    studentId: student1Uid,
    status: 'present',
  });

  await db.collection('schedules').doc('sched-1').set({
    courseId,
    day: 'Monday',
    startTime: '09:00',
    endTime: '10:30',
  });

  // Mint ID tokens
  console.log('3. Minting ID tokens for test scenarios...');
  const unverifiedToken = await getIdToken(unverifiedUid);
  const owner1Token = await getIdToken(owner1Uid);
  const owner2Token = await getIdToken(owner2Uid);
  const student1Token = await getIdToken(student1Uid);
  const outsiderToken = await getIdToken(outsiderUid);

  console.log('\n--- Scenario 1: Unauthenticated access denied ---');
  const resUnauthFirestore = await firestoreGet(`courses/${courseId}`);
  assert(resUnauthFirestore.status === 403, 'Unauthenticated Firestore read to course returns 403');

  const resUnauthFunc = await callFunction('createCourse', { code: 'CSE999', name: 'Test' });
  assert(resUnauthFunc.status === 401 || resUnauthFunc.body?.error?.status === 'UNAUTHENTICATED',
    'Unauthenticated call to createCourse returns UNAUTHENTICATED');

  console.log('\n--- Scenario 2: Unverified user denied from academic operations ---');
  const resUnverifiedFunc = await callFunction('createCourse', {
    code: 'CSE102',
    name: 'Algorithms',
    department: 'CSE',
    batch: '2026',
    section: 'A',
    semester: '1st',
    room: '301',
  }, unverifiedToken);
  assert(
    resUnverifiedFunc.status === 403 || resUnverifiedFunc.body?.error?.status === 'PERMISSION_DENIED',
    'Unverified user call to createCourse returns 403/PERMISSION_DENIED'
  );
  assert(
    resUnverifiedFunc.body?.error?.message?.includes('verified email'),
    'Error message specifies verified email requirement'
  );

  const resUnverifiedFirestoreCourse = await firestoreGet(`courses/${courseId}`, unverifiedToken);
  assert(resUnverifiedFirestoreCourse.status === 403, 'Unverified user reading course returns 403');

  const resUnverifiedFirestoreSess = await firestoreGet('attendanceSessions/session-1', unverifiedToken);
  assert(resUnverifiedFirestoreSess.status === 403, 'Unverified user reading attendance returns 403');

  console.log('\n--- Scenario 3: Registration / bootstrap exceptions remain functional ---');
  // Unverified user reading own profile (for bootstrap & verification prompt)
  const resUnverifiedSelf = await firestoreGet(`users/${unverifiedUid}`, unverifiedToken);
  assert(resUnverifiedSelf.status === 200, 'Unverified user can read own profile document (bootstrap)');

  // Unverified user cannot read someone else's profile
  const resUnverifiedOther = await firestoreGet(`users/${owner1Uid}`, unverifiedToken);
  assert(resUnverifiedOther.status === 403, 'Unverified user cannot read other user profiles (403)');

  console.log('\n--- Scenario 4: Verified active course owner access ---');
  const resOwnerCourse = await firestoreGet(`courses/${courseId}`, owner1Token);
  assert(resOwnerCourse.status === 200, 'Verified course owner can read own course document');

  const resOwnerRoster = await firestoreGet(`courses/${courseId}/students/${student1Uid}`, owner1Token);
  assert(resOwnerRoster.status === 200, 'Verified course owner can read student enrollment in roster');

  const resOwnerMarks = await firestoreGet('marks/mark-student1', owner1Token);
  assert(resOwnerMarks.status === 200, 'Verified course owner can read student marks');

  const resOwnerDraft = await firestoreGet(`assessments/${assessmentDraftId}`, owner1Token);
  assert(resOwnerDraft.status === 200, 'Verified course owner can read draft assessment');

  console.log('\n--- Scenario 5: Owner access to another owner’s course denied ---');
  const resOwner2Access = await firestoreGet(`courses/${courseId}`, owner2Token);
  assert(resOwner2Access.status === 403, 'Owner 2 reading Owner 1 course returns 403');

  const resOwner2Func = await callFunction('createSchedule', {
    courseId,
    dayIndex: 1,
    day: 'Tuesday',
    startTime: '10:00',
    endTime: '11:30',
    room: '302',
    classType: 'Theory',
  }, owner2Token);
  assert(
    resOwner2Func.status === 403 || resOwner2Func.body?.error?.status === 'PERMISSION_DENIED',
    'Owner 2 cannot modify schedules for Owner 1 course (PERMISSION_DENIED)'
  );

  console.log('\n--- Scenario 6: Verified enrolled student read access ---');
  const resStudentCourse = await firestoreGet(`courses/${courseId}`, student1Token);
  assert(resStudentCourse.status === 200, 'Enrolled student can read course document');

  const resStudentOwnEnroll = await firestoreGet(`courses/${courseId}/students/${student1Uid}`, student1Token);
  assert(resStudentOwnEnroll.status === 200, 'Enrolled student can read own student record');

  const resStudentSchedule = await firestoreGet('schedules/sched-1', student1Token);
  assert(resStudentSchedule.status === 200, 'Enrolled student can read class schedule');

  const resStudentOwnMark = await firestoreGet('marks/mark-student1', student1Token);
  assert(resStudentOwnMark.status === 200, 'Enrolled student can read own published mark');

  const resStudentOtherMark = await firestoreGet('marks/mark-other', student1Token);
  assert(resStudentOtherMark.status === 403, 'Enrolled student cannot read another student’s mark (403)');

  const resStudentDraft = await firestoreGet(`assessments/${assessmentDraftId}`, student1Token);
  assert(resStudentDraft.status === 403, 'Enrolled student cannot read draft assessment (403)');

  const resStudentPub = await firestoreGet(`assessments/${assessmentPublishedId}`, student1Token);
  assert(resStudentPub.status === 200, 'Enrolled student can read published assessment');

  console.log('\n--- Scenario 7: Outsider access denied ---');
  const resOutsiderCourse = await firestoreGet(`courses/${courseId}`, outsiderToken);
  assert(resOutsiderCourse.status === 403, 'Outsider reading course returns 403');

  const resOutsiderRoster = await firestoreGet(`courses/${courseId}/students/${student1Uid}`, outsiderToken);
  assert(resOutsiderRoster.status === 403, 'Outsider reading course roster returns 403');

  const resOutsiderMarks = await firestoreGet('marks/mark-student1', outsiderToken);
  assert(resOutsiderMarks.status === 403, 'Outsider reading marks returns 403');

  const resOutsiderAttendance = await firestoreGet('attendanceSessions/session-1', outsiderToken);
  assert(resOutsiderAttendance.status === 403, 'Outsider reading attendance returns 403');

  console.log('\n--- Scenario 8: Student direct writes denied ---');
  const resWriteCourse = await firestoreWrite(`courses/${courseId}`, { name: 'Hacked Course' }, student1Token);
  assert(resWriteCourse.status === 403, 'Student direct write to course returns 403');

  const resWriteMark = await firestoreWrite('marks/mark-student1', { score: 100 }, student1Token);
  assert(resWriteMark.status === 403, 'Student direct write to marks returns 403');

  const resWriteAtt = await firestoreWrite('attendanceRecords/att-student1', { status: 'present' }, student1Token);
  assert(resWriteAtt.status === 403, 'Student direct write to attendance returns 403');

  const resWriteStudent = await firestoreWrite(`courses/${courseId}/students/${student1Uid}`, { isActive: true }, student1Token);
  assert(resWriteStudent.status === 403, 'Student direct write to roster returns 403');

  console.log(`\n======================================================`);
  console.log(` All Security Tests Passed! (${passedCount}/${testCount})`);
  console.log(`======================================================\n`);
}

runSecurityTests().catch((err) => {
  console.error('\n❌ Security Test Suite Failed:\n', err);
  process.exit(1);
});

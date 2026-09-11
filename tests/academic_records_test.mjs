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

async function runAcademicRecordsTests() {
  console.log(`\n======================================================`);
  console.log(` Starting TrackAcademic Phase 7 Academic Records Tests`);
  console.log(` Target Project: ${PROJECT_ID}`);
  console.log(`======================================================\n`);

  // 1. Setup Identities
  console.log('1. Setting up identities...');
  const teacher1Uid = 'teacher-p7-1';
  const teacher2Uid = 'teacher-p7-2';
  const student1Uid = 'student-p7-1';
  const student2Uid = 'student-p7-2';

  for (const u of [
    { uid: teacher1Uid, email: 'teacher1@univ.edu', emailVerified: true, role: 'teacher' },
    { uid: teacher2Uid, email: 'teacher2@univ.edu', emailVerified: true, role: 'teacher' },
    { uid: student1Uid, email: 'student1@univ.edu', emailVerified: true, role: 'student' },
    { uid: student2Uid, email: 'student2@univ.edu', emailVerified: true, role: 'student' },
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
      displayName: `User ${u.uid}`,
      email: u.email,
      isActive: true,
      emailVerified: u.emailVerified,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  const teacher1Token = await getIdToken(teacher1Uid);
  const teacher2Token = await getIdToken(teacher2Uid);
  const student1Token = await getIdToken(student1Uid);

  // Setup course
  const courseRef = db.collection('courses').doc('course-p7-cse101');
  await courseRef.set({
    code: 'CSE101',
    name: 'Introduction to Programming',
    teacherId: teacher1Uid,
    teacherName: 'Teacher 1',
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  // Enroll students in course
  for (const stuUid of [student1Uid, student2Uid]) {
    await courseRef.collection('students').doc(stuUid).set({
      studentId: stuUid,
      institutionId: `ID-${stuUid}`,
      displayName: `Student ${stuUid}`,
      email: `${stuUid}@univ.edu`,
      isActive: true,
      enrolledAt: FieldValue.serverTimestamp(),
    });
  }

  // Clean up any lingering schedules and scheduleLocks from prior runs
  const oldSchedules = await db
    .collection('schedules')
    .where('teacherId', 'in', [teacher1Uid, teacher2Uid])
    .get();
  for (const doc of oldSchedules.docs) {
    await doc.ref.delete();
  }
  const oldLocks = await db.collection('scheduleLocks').get();
  for (const doc of oldLocks.docs) {
    await doc.ref.delete();
  }

  assert(true, 'Identities and initial course created');

  // ==========================================
  // SECTION A: Assessment Date Validation
  // ==========================================
  console.log('\n2. Testing Strict Assessment Date Validation...');

  // Invalid date: 2026-02-30 (February 30th does not exist)
  const invalidDate1 = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Quiz Invalid Date',
      type: 'Quiz',
      maxScore: 20,
      date: '2026-02-30',
    },
    teacher1Token
  );
  assert(
    invalidDate1.status >= 400 || invalidDate1.body.error,
    'Rejects non-existent calendar date 2026-02-30'
  );

  // Invalid date: Non-leap year 2023-02-29
  const invalidDate2 = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Quiz Non-Leap Date',
      type: 'Quiz',
      maxScore: 20,
      date: '2023-02-29',
    },
    teacher1Token
  );
  assert(
    invalidDate2.status >= 400 || invalidDate2.body.error,
    'Rejects Feb 29 on non-leap year 2023-02-29'
  );

  // Invalid date format or month
  const invalidDate3 = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Quiz Invalid Month',
      type: 'Quiz',
      maxScore: 20,
      date: '2026-13-01',
    },
    teacher1Token
  );
  assert(
    invalidDate3.status >= 400 || invalidDate3.body.error,
    'Rejects invalid month 2026-13-01'
  );

  // Valid date: Leap year 2024-02-29
  const validLeap = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Quiz Leap Year',
      type: 'Quiz',
      maxScore: 20,
      date: '2024-02-29',
    },
    teacher1Token
  );
  assert(
    validLeap.status === 200 && validLeap.body.result?.assessmentId,
    'Accepts valid leap year date 2024-02-29'
  );

  // Valid date: Standard calendar date 2026-09-15
  const createAsstRes = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Midterm Exam 1',
      type: 'Midterm',
      maxScore: 25,
      date: '2026-09-15',
    },
    teacher1Token
  );
  assert(
    createAsstRes.status === 200 && createAsstRes.body.result?.assessmentId,
    'Creates draft assessment with strict calendar date 2026-09-15'
  );
  const assessmentId = createAsstRes.body.result.assessmentId;

  // Check stored date in Firestore
  const asstDoc = await db.collection('assessments').doc(assessmentId).get();
  assert(
    asstDoc.data()?.date === '2026-09-15' && asstDoc.data()?.type === 'Midterm',
    'Assessment stores normalized YYYY-MM-DD date and type'
  );

  // ==========================================
  // SECTION B: Atomic Draft Assessment Lifecycle
  // ==========================================
  console.log('\n3. Testing Atomic Draft Assessment Update & Deletion...');

  // Save draft marks for student1 (score 20) and student2 (score 15)
  const saveMarksRes = await callFunction(
    'saveAssessmentMarks',
    {
      assessmentId,
      marks: [
        { studentId: student1Uid, score: 20 },
        { studentId: student2Uid, score: 15 },
      ],
    },
    teacher1Token
  );
  assert(
    saveMarksRes.status === 200 && saveMarksRes.body.result?.success,
    'Saves draft assessment marks'
  );

  // Check mark docs created in Firestore
  const mark1Snap = await db.collection('marks').doc(`${assessmentId}_${student1Uid}`).get();
  assert(
    mark1Snap.exists && mark1Snap.data()?.score === 20 && mark1Snap.data()?.maxScore === 25,
    'Draft mark doc exists with initial maxScore 25'
  );

  // Attempt to reduce maxScore to 18 when student1 has score 20 -> MUST BE REJECTED
  const updateFail = await callFunction(
    'updateAssessment',
    {
      assessmentId,
      name: 'Midterm Exam 1 (Renamed)',
      type: 'Midterm',
      maxScore: 18,
      date: '2026-09-15',
    },
    teacher1Token
  );
  assert(
    updateFail.status >= 400 || updateFail.body.error,
    'Rejects maxScore reduction (18) when existing student score is 20'
  );

  // Verify assessment was NOT modified after failure
  const asstAfterFail = await db.collection('assessments').doc(assessmentId).get();
  assert(
    asstAfterFail.data()?.maxScore === 25 && asstAfterFail.data()?.name === 'Midterm Exam 1',
    'Assessment remains unchanged after failed maxScore reduction'
  );

  // Valid update: increase maxScore to 30, change name to 'Midterm Exam 1 - Advanced'
  const updateSuccess = await callFunction(
    'updateAssessment',
    {
      assessmentId,
      name: 'Midterm Exam 1 - Advanced',
      type: 'Midterm',
      maxScore: 30,
      date: '2026-09-16',
    },
    teacher1Token
  );
  assert(
    updateSuccess.status === 200 && updateSuccess.body.result?.success,
    'Atomically updates assessment and synchronized mark metadata'
  );

  // Verify all mark documents synchronized
  const mark1Updated = await db.collection('marks').doc(`${assessmentId}_${student1Uid}`).get();
  const mark2Updated = await db.collection('marks').doc(`${assessmentId}_${student2Uid}`).get();
  assert(
    mark1Updated.data()?.maxScore === 30 &&
      mark1Updated.data()?.assessmentName === 'Midterm Exam 1 - Advanced' &&
      mark2Updated.data()?.maxScore === 30 &&
      mark2Updated.data()?.assessmentName === 'Midterm Exam 1 - Advanced',
    'All mark documents synchronized atomically with new maxScore and assessmentName'
  );

  // Verify immutable audit log written
  const auditLogs = await db
    .collection('auditLogs')
    .where('action', '==', 'update_assessment')
    .where('assessmentId', '==', assessmentId)
    .get();
  assert(!auditLogs.empty, 'Immutable audit log written for assessment update');

  // Test atomic draft deletion with orphan cleanup
  const deleteRes = await callFunction(
    'deleteAssessment',
    { assessmentId },
    teacher1Token
  );
  assert(
    deleteRes.status === 200 && deleteRes.body.result?.success,
    'Deletes draft assessment atomically'
  );

  // Verify assessment document deleted
  const deletedAsst = await db.collection('assessments').doc(assessmentId).get();
  assert(!deletedAsst.exists, 'Assessment document deleted from Firestore');

  // Verify NO orphan mark documents remain
  const remainingMarks = await db
    .collection('marks')
    .where('assessmentId', '==', assessmentId)
    .get();
  assert(remainingMarks.empty, 'All associated mark documents deleted with NO orphans');

  // Verify delete audit log exists
  const deleteAudit = await db
    .collection('auditLogs')
    .where('action', '==', 'delete_draft_assessment')
    .where('assessmentId', '==', assessmentId)
    .get();
  assert(!deleteAudit.empty, 'Immutable audit log recorded for draft assessment deletion');

  // ==========================================
  // SECTION B.1: Assessment Revision & Concurrency Races
  // ==========================================
  console.log('\n3.1. Testing Assessment Revision Strategy & Race Protection...');

  // Create assessment with revision tracking
  const revAsstRes = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Revision Test Quiz',
      type: 'Quiz',
      maxScore: 100,
      date: '2026-09-20',
    },
    teacher1Token
  );
  const revAsstId = revAsstRes.body.result.assessmentId;
  const initialRevDoc = await db.collection('assessments').doc(revAsstId).get();
  assert(initialRevDoc.data()?.revision === 1, 'Initial assessment revision is set to 1');

  // Update assessment increments revision
  await callFunction(
    'updateAssessment',
    {
      assessmentId: revAsstId,
      name: 'Revision Test Quiz Updated',
      type: 'Quiz',
      maxScore: 100,
      date: '2026-09-21',
    },
    teacher1Token
  );
  const updatedRevDoc = await db.collection('assessments').doc(revAsstId).get();
  assert(
    updatedRevDoc.data()?.revision === 2,
    'updateAssessment increments assessment revision to 2'
  );

  // Saving marks increments revision
  await callFunction(
    'saveAssessmentMarks',
    {
      assessmentId: revAsstId,
      marks: [{ studentId: student1Uid, score: 50 }],
    },
    teacher1Token
  );
  const savedRevDoc = await db.collection('assessments').doc(revAsstId).get();
  assert(
    savedRevDoc.data()?.revision === 3,
    'saveAssessmentMarks increments assessment revision to 3'
  );

  // Concurrent save-vs-update race test:
  // Assessment has maxScore: 100.
  // One client attempts to update maxScore to 70.
  // Concurrently, another client attempts to save score 85 (valid for 100, invalid for 70).
  const raceUpdateAsst = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Race Update Test',
      type: 'Quiz',
      maxScore: 100,
      date: '2026-09-22',
    },
    teacher1Token
  );
  const raceUpdateId = raceUpdateAsst.body.result.assessmentId;

  const [raceUpdateRes, raceSaveRes] = await Promise.all([
    callFunction(
      'updateAssessment',
      {
        assessmentId: raceUpdateId,
        name: 'Race Update Test',
        type: 'Quiz',
        maxScore: 70,
        date: '2026-09-22',
      },
      teacher1Token
    ),
    callFunction(
      'saveAssessmentMarks',
      {
        assessmentId: raceUpdateId,
        marks: [{ studentId: student1Uid, score: 85 }],
      },
      teacher1Token
    ),
  ]);

  // Under transaction revision locking, one of two valid transactional outcomes occurs:
  // 1. Update won first: maxScore became 70, then save retried and failed because 85 > 70.
  // 2. Save won first: mark with score 85 saved, then update retried and failed because existing mark 85 > proposed 70.
  const updateWon = raceUpdateRes.status === 200 && raceSaveRes.status >= 400;
  const saveWon = raceSaveRes.status === 200 && raceUpdateRes.status >= 400;
  assert(
    updateWon || saveWon,
    'Concurrent save-vs-update race safely rejects conflicting operation via revision locking'
  );

  // Verify database integrity: assessment maxScore is never less than any recorded mark score
  const finalRaceAsst = await db.collection('assessments').doc(raceUpdateId).get();
  const finalRaceMark = await db.collection('marks').doc(`${raceUpdateId}_${student1Uid}`).get();
  if (finalRaceMark.exists) {
    assert(
      finalRaceMark.data()?.score <= finalRaceAsst.data()?.maxScore,
      'Database integrity preserved: mark score does not exceed assessment maxScore'
    );
  }

  // Concurrent save-vs-delete race test:
  // Client A calls deleteAssessment, Client B concurrently calls saveAssessmentMarks.
  const raceDeleteAsst = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Race Delete Test',
      type: 'Quiz',
      maxScore: 100,
      date: '2026-09-23',
    },
    teacher1Token
  );
  const raceDeleteId = raceDeleteAsst.body.result.assessmentId;

  await Promise.all([
    callFunction('deleteAssessment', { assessmentId: raceDeleteId }, teacher1Token),
    callFunction(
      'saveAssessmentMarks',
      {
        assessmentId: raceDeleteId,
        marks: [{ studentId: student1Uid, score: 60 }],
      },
      teacher1Token
    ),
  ]);

  // Query marks for raceDeleteId: if assessment deleted, NO orphan marks must remain!
  const finalDeleteAsst = await db.collection('assessments').doc(raceDeleteId).get();
  const raceRemainingMarks = await db
    .collection('marks')
    .where('assessmentId', '==', raceDeleteId)
    .get();

  if (!finalDeleteAsst.exists) {
    assert(
      raceRemainingMarks.empty,
      'Concurrent save-vs-delete leaves zero orphan marks when draft is deleted'
    );
  } else {
    assert(true, 'Draft assessment survived deletion race cleanly');
  }

  // Cleanup rev test assessment
  await callFunction('deleteAssessment', { assessmentId: revAsstId }, teacher1Token);

  // ==========================================
  // SECTION C: Published Assessments Protection
  // ==========================================
  console.log('\n4. Testing Published Assessments & Immutability...');

  // Create a new assessment and publish it
  const pubAsstRes = await callFunction(
    'createAssessment',
    {
      courseId: courseRef.id,
      name: 'Final Exam',
      type: 'Final Exam',
      maxScore: 100,
      date: '2026-10-01',
    },
    teacher1Token
  );
  const pubAssessmentId = pubAsstRes.body.result.assessmentId;

  // Save marks
  await callFunction(
    'saveAssessmentMarks',
    {
      assessmentId: pubAssessmentId,
      marks: [
        { studentId: student1Uid, score: 85 },
        { studentId: student2Uid, score: 78 },
      ],
    },
    teacher1Token
  );

  // Publish
  const publishRes = await callFunction(
    'publishAssessment',
    { assessmentId: pubAssessmentId },
    teacher1Token
  );
  assert(publishRes.status === 200, 'Assessment published successfully');

  // Cannot update published assessment
  const tryUpdatePub = await callFunction(
    'updateAssessment',
    {
      assessmentId: pubAssessmentId,
      name: 'Modified Final',
      type: 'Final Exam',
      maxScore: 100,
      date: '2026-10-01',
    },
    teacher1Token
  );
  assert(
    tryUpdatePub.status >= 400 || tryUpdatePub.body.error,
    'Published assessment cannot be updated'
  );

  // Cannot delete published assessment
  const tryDeletePub = await callFunction(
    'deleteAssessment',
    { assessmentId: pubAssessmentId },
    teacher1Token
  );
  assert(
    tryDeletePub.status >= 400 || tryDeletePub.body.error,
    'Published assessment cannot be deleted'
  );

  // ==========================================
  // SECTION D: Published-Mark Correction
  // ==========================================
  console.log('\n5. Testing Published-Mark Correction...');

  // Non-owner teacher cannot correct
  const nonOwnerCorrection = await callFunction(
    'correctPublishedMark',
    {
      assessmentId: pubAssessmentId,
      studentId: student1Uid,
      newScore: 90,
      reason: 'Teacher 2 attempt',
    },
    teacher2Token
  );
  assert(
    nonOwnerCorrection.status >= 400 || nonOwnerCorrection.body.error,
    'Non-owner teacher rejected from correcting published mark'
  );

  // Correction with score > maxScore (105 > 100) -> Rejected
  const overMaxCorrection = await callFunction(
    'correctPublishedMark',
    {
      assessmentId: pubAssessmentId,
      studentId: student1Uid,
      newScore: 105,
      reason: 'Bonus marks',
    },
    teacher1Token
  );
  assert(
    overMaxCorrection.status >= 400 || overMaxCorrection.body.error,
    'Score exceeding maxScore rejected'
  );

  // Correction with empty reason -> Rejected
  const emptyReason = await callFunction(
    'correctPublishedMark',
    {
      assessmentId: pubAssessmentId,
      studentId: student1Uid,
      newScore: 88,
      reason: '   ',
    },
    teacher1Token
  );
  assert(
    emptyReason.status >= 400 || emptyReason.body.error,
    'Empty correction reason rejected'
  );

  // Same-score request -> No-op (zero writes)
  const sameScoreRes = await callFunction(
    'correctPublishedMark',
    {
      assessmentId: pubAssessmentId,
      studentId: student1Uid,
      newScore: 85, // Already 85
      reason: 'No change needed',
    },
    teacher1Token
  );
  assert(
    sameScoreRes.status === 200 && sameScoreRes.body.result?.changed === false,
    'Same-score correction performs zero writes and returns changed: false'
  );

  // Historical / Inactive student mark correction
  // Unenroll student2
  await courseRef.collection('students').doc(student2Uid).update({ isActive: false });

  // Course owner corrects mark for historically unenrolled student2
  const histCorrection = await callFunction(
    'correctPublishedMark',
    {
      assessmentId: pubAssessmentId,
      studentId: student2Uid,
      newScore: 82, // Was 78
      reason: 'Recalculated question 4 after term ended',
    },
    teacher1Token
  );
  assert(
    histCorrection.status === 200 && histCorrection.body.result?.changed === true,
    'Course owner can correct marks for historically inactive enrollments'
  );

  // Verify student2 mark document updated correctly
  const mark2Doc = await db.collection('marks').doc(`${pubAssessmentId}_${student2Uid}`).get();
  assert(
    mark2Doc.data()?.score === 82 &&
      mark2Doc.data()?.previousScore === 78 &&
      mark2Doc.data()?.published === true &&
      mark2Doc.data()?.correctionReason === 'Recalculated question 4 after term ended',
    'Mark doc records previousScore 78, new score 82, reason, and preserves published: true'
  );

  // ==========================================
  // SECTION E: Schedule Integrity & Concurrency
  // ==========================================
  console.log('\n6. Testing Schedule Integrity & Overlap Detection...');

  // Invalid time format
  const invalidTime = await callFunction(
    'createSchedule',
    {
      courseId: courseRef.id,
      dayIndex: 1,
      startTime: '25:00',
      endTime: '10:00',
      room: 'Lab 1',
      classType: 'Theory',
    },
    teacher1Token
  );
  assert(
    invalidTime.status >= 400 || invalidTime.body.error,
    'Rejects invalid time format 25:00'
  );

  // End time before start time
  const invertedTime = await callFunction(
    'createSchedule',
    {
      courseId: courseRef.id,
      dayIndex: 1,
      startTime: '10:00',
      endTime: '09:00',
      room: 'Lab 1',
      classType: 'Theory',
    },
    teacher1Token
  );
  assert(
    invertedTime.status >= 400 || invertedTime.body.error,
    'Rejects end time before start time (10:00 to 09:00)'
  );

  // Valid schedule on Monday 09:00 - 10:00
  const sched1Res = await callFunction(
    'createSchedule',
    {
      courseId: courseRef.id,
      dayIndex: 1,
      day: 'IgnoredClientDay', // Should derive Monday from dayIndex 1
      startTime: '09:00',
      endTime: '10:00',
      room: '  Lab 101  ', // Whitespace normalization test
      classType: '  Theory  ',
    },
    teacher1Token
  );
  assert(
    sched1Res.status === 200 && sched1Res.body.result?.scheduleId,
    'Creates schedule with derived day Monday and normalized strings'
  );
  const sched1Id = sched1Res.body.result.scheduleId;
  const sched1Doc = await db.collection('schedules').doc(sched1Id).get();
  assert(
    sched1Doc.data()?.day === 'Monday' && sched1Doc.data()?.room === 'Lab 101',
    'Server derives day Monday from dayIndex 1 and trims whitespace'
  );

  // Exact duplicate test (same course, day, time, room, type)
  const dupRes = await callFunction(
    'createSchedule',
    {
      courseId: courseRef.id,
      dayIndex: 1,
      startTime: '09:00',
      endTime: '10:00',
      room: 'lab 101',
      classType: 'theory',
    },
    teacher1Token
  );
  assert(
    dupRes.status >= 400 || dupRes.body.error,
    'Rejects exact duplicate schedule entry'
  );

  // Create Course 2 for teacher1
  const course2Ref = db.collection('courses').doc('course-p7-cse102');
  await course2Ref.set({
    code: 'CSE102',
    name: 'Data Structures',
    teacherId: teacher1Uid,
    teacherName: 'Teacher 1',
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  // Overlapping interval for the same teacher on Monday (09:30 - 10:30 overlaps with 09:00 - 10:00)
  const overlapRes = await callFunction(
    'createSchedule',
    {
      courseId: course2Ref.id,
      dayIndex: 1,
      startTime: '09:30',
      endTime: '10:30',
      room: 'Room 202',
      classType: 'Theory',
    },
    teacher1Token
  );
  assert(
    overlapRes.status >= 400 || overlapRes.body.error,
    'Rejects overlapping schedule for same teacher across different courses'
  );

  // Update schedule: changing room should not conflict with itself
  const updateSched = await callFunction(
    'updateSchedule',
    {
      scheduleId: sched1Id,
      courseId: courseRef.id,
      dayIndex: 1,
      startTime: '09:00',
      endTime: '10:00',
      room: 'Lab 102',
      classType: 'Theory',
    },
    teacher1Token
  );
  assert(
    updateSched.status === 200 &&
      (updateSched.body.result?.success || updateSched.body.result?.scheduleId),
    'Updating schedule ignores current scheduleId and does not self-conflict'
  );

  // Inactive / cancelled schedules do not block new schedules
  await db.collection('schedules').doc(sched1Id).update({ status: 'cancelled' });
  const nonBlockedSched = await callFunction(
    'createSchedule',
    {
      courseId: course2Ref.id,
      dayIndex: 1,
      startTime: '09:00',
      endTime: '10:00',
      room: 'Room 303',
      classType: 'Theory',
    },
    teacher1Token
  );
  assert(
    nonBlockedSched.status === 200 && nonBlockedSched.body.result?.scheduleId,
    'Cancelled schedule does not block new schedule at the same time'
  );

  // Concurrent overlapping schedule creation test
  console.log('\n7. Testing Concurrent Overlapping Schedule Creation...');
  const concurrentP1 = callFunction(
    'createSchedule',
    {
      courseId: courseRef.id,
      dayIndex: 2,
      startTime: '11:00',
      endTime: '12:00',
      room: 'Room 401',
      classType: 'Theory',
    },
    teacher1Token
  );
  const concurrentP2 = callFunction(
    'createSchedule',
    {
      courseId: course2Ref.id,
      dayIndex: 2,
      startTime: '11:30',
      endTime: '12:30',
      room: 'Room 402',
      classType: 'Theory',
    },
    teacher1Token
  );

  const [res1, res2] = await Promise.all([concurrentP1, concurrentP2]);
  const s1Ok = res1.status === 200 && res1.body.result?.scheduleId;
  const s2Ok = res2.status === 200 && res2.body.result?.scheduleId;

  // Exactly one must succeed and one must fail
  assert(
    (s1Ok && !s2Ok) || (!s1Ok && s2Ok),
    'Concurrent overlapping schedule creation safely admits exactly one schedule'
  );

  const failingRes = s1Ok ? res2 : res1;
  assert(
    failingRes.status >= 400 || failingRes.body.error,
    'Conflicting concurrent schedule creation was rejected with error'
  );

  // Verify only 1 schedule exists in database for this day and time window
  const day2Schedules = await db
    .collection('schedules')
    .where('teacherId', '==', teacher1Uid)
    .where('dayIndex', '==', 2)
    .get();
  assert(
    day2Schedules.docs.length === 1,
    'Exactly one schedule document was committed to database on dayIndex 2'
  );

  // Verify scheduleLock document exists with incremented version
  const day2LockDoc = await db
    .collection('scheduleLocks')
    .doc(`${teacher1Uid}_2`)
    .get();
  assert(
    day2LockDoc.exists && Number(day2LockDoc.data()?.version) >= 1,
    'Deterministic schedule conflict lock document exists with incremented version'
  );

  // Test schedule update with day change (verifying two-phase sorted lock acquisition)
  const dayChangeRes = await callFunction(
    'updateSchedule',
    {
      scheduleId: nonBlockedSched.body.result.scheduleId,
      courseId: course2Ref.id,
      dayIndex: 3, // Moving from dayIndex 1 to dayIndex 3
      startTime: '14:00',
      endTime: '15:00',
      room: 'Room 505',
      classType: 'Lab',
    },
    teacher1Token
  );
  assert(
    dayChangeRes.status === 200 && dayChangeRes.body.result?.scheduleId,
    'Schedule update across different days succeeds with two-phase lock acquisition'
  );

  // Verify both old day (1) and new day (3) locks exist
  const lock1 = await db.collection('scheduleLocks').doc(`${teacher1Uid}_1`).get();
  const lock3 = await db.collection('scheduleLocks').doc(`${teacher1Uid}_3`).get();
  assert(
    lock1.exists && lock3.exists,
    'Both old day and new day conflict locks updated during day-change schedule update'
  );

  // Verify client direct access to scheduleLocks is denied by Firestore security rules
  console.log('\n8. Testing Schedule Locks Authorization Rules...');
  const lockReadTeacher = await firestoreGet(`scheduleLocks/${teacher1Uid}_1`, teacher1Token);
  assert(
    lockReadTeacher.status === 403,
    'Direct client read to scheduleLocks denied for teacher (403)'
  );

  const lockReadStudent = await firestoreGet(`scheduleLocks/${teacher1Uid}_1`, student1Token);
  assert(
    lockReadStudent.status === 403,
    'Direct client read to scheduleLocks denied for student (403)'
  );

  const lockWriteClient = await firestoreWrite(
    `scheduleLocks/${teacher1Uid}_1`,
    { version: 999 },
    teacher1Token
  );
  assert(
    lockWriteClient.status === 403,
    'Direct client write to scheduleLocks denied (403)'
  );

  console.log(`\n======================================================`);
  console.log(` Academic Records Test Suite Complete`);
  console.log(` Total Assertions: ${testCount}`);
  console.log(` Passed: ${passedCount}`);
  console.log(` Failed: ${testCount - passedCount}`);
  console.log(`======================================================\n`);
}

runAcademicRecordsTests().catch((err) => {
  console.error('\nTest Suite Failed with exception:', err);
  process.exit(1);
});

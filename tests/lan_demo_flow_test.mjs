import { createRequire } from 'module';
const require = createRequire(process.cwd() + '/functions/package.json');

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'trackacademic-c0d1c';
const AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const FUNCTIONS_HOST = process.env.FUNCTIONS_HOST || '127.0.0.1:5001';

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
  return json.idToken;
}

async function callFunction(name, data, idToken) {
  const response = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/asia-south1/${name}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ data }),
    }
  );
  return { status: response.status, body: await response.json() };
}

async function runFocusedDemoFlow() {
  console.log('\n--- Running Focused Teacher-to-Student Demo Flow Check ---');

  // 1. Get user UIDs
  const teacher = await auth.getUserByEmail('teacher@demo.local');
  const student = await auth.getUserByEmail('student1@demo.local');

  const teacherToken = await getIdToken(teacher.uid);
  const studentToken = await getIdToken(student.uid);

  // 2. Teacher creates an attendance session
  const courseId = 'demo-course-cse311';
  const createRes = await callFunction(
    'createAttendanceSession',
    {
      courseId,
      classType: 'Lab',
      durationMinutes: 15,
      requiresPasscode: true,
      requiresGps: true,
      allowLateEntry: true,
      latitude: 23.777176,
      longitude: 90.399452,
      radiusMeters: 500,
    },
    teacherToken
  );

  if (createRes.status !== 200) {
    throw new Error(`Failed to create attendance session: ${JSON.stringify(createRes.body)}`);
  }

  const sessionId = createRes.body.result?.sessionId;
  const passcode = createRes.body.result?.passcode;
  console.log(`  ✓ Teacher created attendance session: ${sessionId} (Passcode: ${passcode})`);

  // 3. Student submits attendance
  const submitRes = await callFunction(
    'submitAttendance',
    {
      sessionId,
      passcode,
      latitude: 23.777176,
      longitude: 90.399452,
    },
    studentToken
  );

  if (submitRes.status !== 200 || !submitRes.body.result?.success) {
    throw new Error(`Student attendance submission failed: ${JSON.stringify(submitRes.body)}`);
  }
  console.log(`  ✓ Student submitted attendance with passcode successfully`);

  // 4. Teacher closes attendance session
  const closeRes = await callFunction('closeAttendanceSession', { sessionId }, teacherToken);
  if (closeRes.status !== 200) {
    throw new Error(`Failed to close attendance session: ${JSON.stringify(closeRes.body)}`);
  }
  console.log(`  ✓ Teacher closed attendance session`);

  // 5. Verify record in Firestore
  const recordDoc = await db.collection('attendanceRecords').doc(`${sessionId}_${student.uid}`).get();
  if (!recordDoc.exists || recordDoc.data().status !== 'present') {
    throw new Error(`Attendance record missing or not present: ${JSON.stringify(recordDoc.data())}`);
  }
  console.log(`  ✓ Verified Firestore record status: ${recordDoc.data().status}`);

  console.log('--- Focused Teacher-to-Student Flow Check: PASSED ---\n');
}

runFocusedDemoFlow().catch((err) => {
  console.error('Flow check failed:', err);
  process.exit(1);
});

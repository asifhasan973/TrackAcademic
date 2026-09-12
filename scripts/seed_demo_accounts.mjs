import { createRequire } from 'module';
const require = createRequire(process.cwd() + '/functions/package.json');

process.stdout.on('error', (err) => { if (err.code === 'EPIPE' || err.code === 'EIO') return; });
process.stderr.on('error', (err) => { if (err.code === 'EPIPE' || err.code === 'EIO') return; });

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = 'trackacademic-c0d1c';
const EMULATOR_HOST = process.env.FIREBASE_EMULATOR_HOST || '127.0.0.1';

process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || `${EMULATOR_HOST}:9099`;
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || `${EMULATOR_HOST}:8080`;

if (!getApps().length) {
  initializeApp({ projectId: PROJECT_ID });
}

const auth = getAuth();
const db = getFirestore();

async function seedUser({ email, password, displayName, institutionId, role, batch, section, semester }) {
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, {
      password,
      displayName,
      emailVerified: true,
      disabled: false,
    });
  } catch {
    user = await auth.createUser({
      email,
      password,
      displayName,
      emailVerified: true,
      disabled: false,
    });
  }

  await auth.setCustomUserClaims(user.uid, {
    role,
    institutionId,
  });

  const timestamp = FieldValue.serverTimestamp();
  await db.collection('institutionIds').doc(institutionId).set({
    userId: user.uid,
    institutionId,
    createdAt: timestamp,
  }, { merge: true });

  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    displayName,
    email,
    institutionId,
    role,
    isActive: true,
    emailVerified: true,
    phone: null,
    photoUrl: null,
    department: 'Computer Science',
    batch: batch ?? (role === 'student' ? '2024' : null),
    section: section ?? (role === 'student' ? 'A' : null),
    semester: semester ?? (role === 'student' ? '6th' : null),
    courseIds: [],
    notificationPreferences: {
      attendance: true,
      marks: true,
      schedule: true,
    },
    updatedAt: timestamp,
  }, { merge: true });

  console.log(`  ✓ Seeded ${role}: ${email} (${displayName}) [ID: ${institutionId}]`);
  return user;
}

async function seedCourseAndActivities({ teacherUser, studentUsers }) {
  const courseId = 'demo-course-cse311';
  const timestamp = FieldValue.serverTimestamp();

  // Create course
  await db.collection('courses').doc(courseId).set({
    code: 'CSE 311',
    name: 'Software Engineering',
    joinCode: 'CSE311',
    teacherId: teacherUser.uid,
    teacherName: teacherUser.displayName,
    department: 'CSE',
    batch: '2024',
    section: 'A',
    semester: '6th',
    room: 'Lab 3',
    isActive: true,
    revision: 1,
    lifecycleRevision: 1,
    classroomLatitude: 23.777176,
    classroomLongitude: 90.399452,
    attendanceRadiusMeters: 500,
    createdAt: timestamp,
    updatedAt: timestamp,
  }, { merge: true });

  console.log(`  ✓ Seeded course: CSE 311 (Join Code: CSE311)`);

  // Enroll students
  for (const student of studentUsers) {
    await db.collection('courses').doc(courseId).collection('students').doc(student.uid).set({
      studentId: student.uid,
      institutionId: student.institutionId,
      displayName: student.displayName,
      email: student.email,
      isActive: true,
      enrolledAt: timestamp,
    }, { merge: true });

    await db.collection('enrollments').doc(`${courseId}_${student.uid}`).set({
      courseId,
      studentId: student.uid,
      status: 'active',
      enrolledAt: timestamp,
    }, { merge: true });

    await db.collection('users').doc(student.uid).set({
      courseIds: [courseId],
    }, { merge: true });
  }
  console.log(`  ✓ Enrolled ${studentUsers.length} students in CSE 311 (updated user courseIds)`);

  await db.collection('users').doc(teacherUser.uid).set({
    courseIds: [courseId],
  }, { merge: true });

  // Create class schedules (multiple days including Saturday/today)
  const schedules = [
    {
      id: 'demo-schedule-1',
      dayIndex: 1,
      day: 'Monday',
      startTime: '10:00',
      endTime: '11:30',
      room: 'Lab 3',
      classType: 'Theory',
    },
    {
      id: 'demo-schedule-2',
      dayIndex: 3,
      day: 'Wednesday',
      startTime: '14:00',
      endTime: '15:30',
      room: 'Lab 3',
      classType: 'Lab',
    },
    {
      id: 'demo-schedule-3',
      dayIndex: 6,
      day: 'Saturday',
      startTime: '11:00',
      endTime: '12:30',
      room: 'Room 402',
      classType: 'Theory',
    },
  ];

  for (const sched of schedules) {
    await db.collection('schedules').doc(sched.id).set({
      courseId,
      courseCode: 'CSE 311',
      courseName: 'Software Engineering',
      teacherId: teacherUser.uid,
      teacherName: teacherUser.displayName,
      dayIndex: sched.dayIndex,
      day: sched.day,
      startTime: sched.startTime,
      endTime: sched.endTime,
      room: sched.room,
      classType: sched.classType,
      section: 'A',
      status: 'active',
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    }, { merge: true });
  }
  console.log(`  ✓ Seeded ${schedules.length} schedules across multiple days (including Saturday/today)`);

  // Seed 3 deterministic closed attendance sessions on recent dates
  const closedSessions = [
    {
      id: 'demo-session-1',
      sessionNumber: 1,
      classType: 'Theory',
      startedAt: new Date('2026-09-03T10:00:00Z'),
      endsAt: new Date('2026-09-03T11:30:00Z'),
      closedAt: new Date('2026-09-03T11:35:00Z'),
      presentCount: 2,
      absentCount: 0,
      lateCount: 0,
    },
    {
      id: 'demo-session-2',
      sessionNumber: 2,
      classType: 'Lab',
      startedAt: new Date('2026-09-07T14:00:00Z'),
      endsAt: new Date('2026-09-07T15:30:00Z'),
      closedAt: new Date('2026-09-07T15:35:00Z'),
      presentCount: 0,
      absentCount: 1,
      lateCount: 1,
    },
    {
      id: 'demo-session-3',
      sessionNumber: 3,
      classType: 'Theory',
      startedAt: new Date('2026-09-10T10:00:00Z'),
      endsAt: new Date('2026-09-10T11:30:00Z'),
      closedAt: new Date('2026-09-10T11:35:00Z'),
      presentCount: 2,
      absentCount: 0,
      lateCount: 0,
    },
  ];

  for (const session of closedSessions) {
    await db.collection('attendanceSessions').doc(session.id).set({
      courseId,
      courseCode: 'CSE 311',
      courseName: 'Software Engineering',
      teacherId: teacherUser.uid,
      teacherName: teacherUser.displayName,
      sessionNumber: session.sessionNumber,
      classType: session.classType,
      status: 'closed',
      requiresPasscode: false,
      requiresGps: false,
      presentCount: session.presentCount,
      absentCount: session.absentCount,
      lateCount: session.lateCount,
      startedAt: session.startedAt,
      endsAt: session.endsAt,
      closedAt: session.closedAt,
      createdAt: session.startedAt,
      updatedAt: session.closedAt,
    }, { merge: true });
  }
  console.log(`  ✓ Seeded 3 deterministic closed attendance sessions`);

  // Attendance records for student1: present, late, present (3/3 attended = 100%)
  // Attendance records for student2: present, absent, present (2/3 attended = 66.7%)
  const studentRecords = [
    {
      student: studentUsers[0],
      records: [
        { sessionId: 'demo-session-1', status: 'present', markedAt: new Date('2026-09-03T10:05:00Z') },
        { sessionId: 'demo-session-2', status: 'late', markedAt: new Date('2026-09-07T14:20:00Z') },
        { sessionId: 'demo-session-3', status: 'present', markedAt: new Date('2026-09-10T10:03:00Z') },
      ],
      attended: 3,
      total: 3,
      percentage: 100.0,
      attendanceMarks: 10.0,
    },
    {
      student: studentUsers[1],
      records: [
        { sessionId: 'demo-session-1', status: 'present', markedAt: new Date('2026-09-03T10:07:00Z') },
        { sessionId: 'demo-session-2', status: 'absent', markedAt: null },
        { sessionId: 'demo-session-3', status: 'present', markedAt: new Date('2026-09-10T10:08:00Z') },
      ],
      attended: 2,
      total: 3,
      percentage: 66.7,
      attendanceMarks: 6.7,
    },
  ];

  for (const sr of studentRecords) {
    for (const rec of sr.records) {
      await db.collection('attendanceRecords').doc(`${rec.sessionId}_${sr.student.uid}`).set({
        sessionId: rec.sessionId,
        courseId,
        courseCode: 'CSE 311',
        courseName: 'Software Engineering',
        studentId: sr.student.uid,
        institutionId: sr.student.institutionId,
        studentName: sr.student.displayName,
        status: rec.status,
        markedBy: rec.status === 'absent' ? 'system' : 'student',
        source: rec.status === 'absent' ? 'finalization' : 'self',
        markedAt: rec.markedAt,
        finalizedAt: new Date('2026-09-10T11:35:00Z'),
        updatedAt: timestamp,
      }, { merge: true });
    }

    // Matching attendanceSummaries
    await db.collection('attendanceSummaries').doc(`${courseId}_${sr.student.uid}`).set({
      courseId,
      courseCode: 'CSE 311',
      courseName: 'Software Engineering',
      studentId: sr.student.uid,
      attended: sr.attended,
      total: sr.total,
      percentage: sr.percentage,
      attendanceMarks: sr.attendanceMarks,
      updatedAt: timestamp,
    }, { merge: true });
  }
  console.log(`  ✓ Seeded attendance records and matching attendanceSummaries for ${studentUsers.length} students`);

  // Create a published assessment with marks
  const assessmentId = 'demo-assessment-midterm';
  await db.collection('assessments').doc(assessmentId).set({
    courseId,
    courseCode: 'CSE 311',
    courseName: 'Software Engineering',
    name: 'Midterm Exam',
    type: 'Midterm',
    date: '2026-09-20',
    status: 'published',
    teacherId: teacherUser.uid,
    maxScore: 30,
    publishedAt: timestamp,
    revision: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
  }, { merge: true });

  for (let i = 0; i < studentUsers.length; i++) {
    const s = studentUsers[i];
    const score = 25 + i * 2;
    await db.collection('marks').doc(`${assessmentId}_${s.uid}`).set({
      assessmentId,
      assessmentName: 'Midterm Exam',
      courseId,
      courseCode: 'CSE 311',
      courseName: 'Software Engineering',
      studentId: s.uid,
      institutionId: s.institutionId,
      studentName: s.displayName,
      score,
      maxScore: 30,
      published: true,
      updatedAt: timestamp,
    }, { merge: true });
  }
  console.log(`  ✓ Seeded published assessment: Midterm Exam (Max 30) with marks`);
}

async function main() {
  console.log('\n=== Seeding TrackAcademic Demo Accounts & Course Data ===');
  console.log(`Target Emulator Host: ${EMULATOR_HOST}`);

  const teacherUser = await seedUser({
    email: 'teacher@demo.local',
    password: 'demo-password',
    displayName: 'Dr. Demo Teacher',
    institutionId: 'DEMO-T001',
    role: 'teacher',
  });

  const student1 = await seedUser({
    email: 'student1@demo.local',
    password: 'demo-password',
    displayName: 'Demo Student One',
    institutionId: 'DEMO-S001',
    role: 'student',
  });
  student1.institutionId = 'DEMO-S001';

  const student2 = await seedUser({
    email: 'student2@demo.local',
    password: 'demo-password',
    displayName: 'Demo Student Two',
    institutionId: 'DEMO-S002',
    role: 'student',
  });
  student2.institutionId = 'DEMO-S002';

  await seedCourseAndActivities({
    teacherUser,
    studentUsers: [student1, student2],
  });

  console.log('\n=== Demo Seeding Complete ===');
  console.log('Teacher: teacher@demo.local / demo-password');
  console.log('Student: student1@demo.local / demo-password');
  console.log('Course Join Code: CSE311');
}

main().catch((err) => {
  console.error('Seeding error:', err);
  process.exit(1);
});

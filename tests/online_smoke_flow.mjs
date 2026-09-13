import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BASE_URL = "https://trackacademic-backend.vercel.app/api";
const WEB_API_KEY = "AIzaSyC-spr2vGkBf1yhusBn5Z92JrXR679MeLo";
const PROJECT_ID = "trackacademic-c0d1c";

console.log("=================================================");
console.log("TRACKACADEMIC END-TO-END ONLINE SMOKE FLOW TEST");
console.log(`Backend Target: ${BASE_URL}`);
console.log("=================================================\n");

async function getGoogleCloudToken() {
  const configPath = path.join(os.homedir(), ".config/configstore/firebase-tools.json");
  const data = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const tokens = data.tokens;
  let accessToken = tokens.access_token;
  const refreshToken = tokens.refresh_token;

  if (refreshToken) {
    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho85qd6.apps.googleusercontent.com",
        client_secret: null,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }),
    });
    const tokenData = await res.json();
    if (tokenData.access_token) {
      accessToken = tokenData.access_token;
    }
  }
  return accessToken;
}

async function callApi(operation, payload, token = null) {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${BASE_URL}/${operation}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`Non-JSON response from ${operation} (${res.status}): ${text}`);
  }

  if (!res.ok) {
    const msg = json.error?.message || `HTTP ${res.status}`;
    const err = new Error(msg);
    err.status = res.status;
    err.code = json.error?.code;
    throw err;
  }

  return json.result || json.data || json;
}

async function assertApiError(operation, payload, token, expectedStatus, expectedPattern) {
  try {
    await callApi(operation, payload, token);
    assert.fail(`Expected callApi('${operation}') to fail, but it succeeded.`);
  } catch (err) {
    if (expectedStatus) {
      assert.equal(
        err.status,
        expectedStatus,
        `Expected HTTP status ${expectedStatus}, got ${err.status} (${err.message})`
      );
    }
    if (expectedPattern) {
      assert.match(
        `${err.code || ""} ${err.message}`,
        expectedPattern,
        `Expected error matching ${expectedPattern}, got: ${err.message}`
      );
    }
  }
}

async function signInUser(email, password) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    }
  );
  const data = await res.json();
  if (!data.idToken) {
    throw new Error(`Sign in failed: ${data.error?.message || JSON.stringify(data)}`);
  }
  return { idToken: data.idToken, localId: data.localId };
}

async function provisionTeacher(googleToken, email, password, institutionId, displayName) {
  // 1. Create teacher account in Auth
  const createRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${googleToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        password,
        displayName,
        emailVerified: true,
        customAttributes: JSON.stringify({ role: "teacher", institutionId }),
      }),
    }
  );
  const authUser = await createRes.json();
  if (!authUser.localId) {
    throw new Error(`Failed to create teacher account: ${JSON.stringify(authUser)}`);
  }
  const uid = authUser.localId;

  // 2. Set user document in Firestore
  const docUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`;
  await fetch(docUrl, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${googleToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        uid: { stringValue: uid },
        displayName: { stringValue: displayName },
        email: { stringValue: email },
        institutionId: { stringValue: institutionId },
        role: { stringValue: "teacher" },
        isActive: { booleanValue: true },
        emailVerified: { booleanValue: true },
        createdAt: { timestampValue: new Date().toISOString() },
        updatedAt: { timestampValue: new Date().toISOString() },
      },
    }),
  });

  // 3. Set institution ID document
  const instUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/institutionIds/${institutionId}`;
  await fetch(instUrl, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${googleToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        userId: { stringValue: uid },
        institutionId: { stringValue: institutionId },
        type: { stringValue: "teacher" },
        createdAt: { timestampValue: new Date().toISOString() },
      },
    }),
  });

  return uid;
}

async function markEmailVerified(googleToken, uid) {
  await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:update`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${googleToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        localId: uid,
        emailVerified: true,
      }),
    }
  );

  const docUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}?updateMask.fieldPaths=emailVerified`;
  await fetch(docUrl, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${googleToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        emailVerified: { booleanValue: true },
      },
    }),
  });
}

async function getSummaryDocument(googleToken, courseId, studentId) {
  const docUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/attendanceSummaries/${courseId}_${studentId}`;
  const res = await fetch(docUrl, {
    headers: { Authorization: `Bearer ${googleToken}` },
  });
  if (!res.ok) {
    throw new Error(`Failed to fetch summary: HTTP ${res.status}`);
  }
  return await res.json();
}

async function cleanupUser(googleToken, uid, institutionId) {
  try {
    await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:delete`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${googleToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ localId: uid }),
      }
    );

    await fetch(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`,
      {
        method: "DELETE",
        headers: { Authorization: `Bearer ${googleToken}` },
      }
    );

    await fetch(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/institutionIds/${institutionId}`,
      {
        method: "DELETE",
        headers: { Authorization: `Bearer ${googleToken}` },
      }
    );
  } catch (_) {}
}

async function run() {
  const ts = Date.now();
  const googleToken = await getGoogleCloudToken();

  // Primary Teacher A
  const teacherEmail = `teacher_smoke_${ts}@smoke.cuet.ac.bd`;
  const teacherInstId = `T-SMOKE-${ts.toString().slice(-4)}`;
  const teacherPassword = "TeacherPass123!";
  const teacherName = "Prof. Smoke Alan";

  // Unauthorized Teacher B (for ownership tests)
  const teacherBEmail = `teacherB_smoke_${ts}@smoke.cuet.ac.bd`;
  const teacherBInstId = `TB-SMOKE-${ts.toString().slice(-4)}`;
  const teacherBPassword = "TeacherBPass123!";
  const teacherBName = "Prof. Smoke Bob";

  // Student
  const studentEmail = `student_smoke_${ts}@smoke.cuet.ac.bd`;
  const studentInstId = `S-SMOKE-${ts.toString().slice(-4)}`;
  const studentPassword = "StudentPass123!";
  const studentName = "Ada Smoke Lovelace";

  let teacherUid = null;
  let teacherBUid = null;
  let studentUid = null;

  try {
    // 1. CONTROLLED TEACHER PROVISIONING
    console.log("[STEP 1] Controlled Teacher Provisioning (Teacher A and Teacher B)...");
    teacherUid = await provisionTeacher(
      googleToken,
      teacherEmail,
      teacherPassword,
      teacherInstId,
      teacherName
    );
    teacherBUid = await provisionTeacher(
      googleToken,
      teacherBEmail,
      teacherBPassword,
      teacherBInstId,
      teacherBName
    );
    console.log(`✔ Teacher A provisioned: UID = ${teacherUid}`);
    console.log(`✔ Teacher B provisioned: UID = ${teacherBUid}`);

    // 2. STUDENT REGISTRATION VIA LIVE VERCEL BACKEND
    console.log("\n[STEP 2] Student Registration via /api/registerUser...");
    const regResult = await callApi("registerUser", {
      displayName: studentName,
      email: studentEmail,
      institutionId: studentInstId,
      password: studentPassword,
      role: "student",
    });
    studentUid = regResult.uid;
    assert.equal(regResult.role, "student");
    console.log(`✔ Student registered successfully via online API: UID = ${studentUid}`);

    await markEmailVerified(googleToken, studentUid);

    // 3. AUTHENTICATION & TOKEN ACQUISITION
    console.log("\n[STEP 3] Signing in Teacher A, Teacher B, and Student via Firebase Auth...");
    const teacherAuth = await signInUser(teacherEmail, teacherPassword);
    const teacherBAuth = await signInUser(teacherBEmail, teacherBPassword);
    const studentAuth = await signInUser(studentEmail, studentPassword);
    console.log("✔ Accounts authenticated and obtained live ID tokens.");

    // 4. TEACHER A CREATES COURSE
    console.log("\n[STEP 4] Teacher A Creates Course via /api/createCourse...");
    const courseRes = await callApi(
      "createCourse",
      {
        code: `CS${ts.toString().slice(-3)}`,
        name: "Distributed Systems & Cloud",
        department: "CSE",
        batch: "2026",
        section: "A",
        semester: "8th",
        room: "Lab 402",
      },
      teacherAuth.idToken
    );
    const courseId = courseRes.courseId;
    assert.ok(courseId, "Course ID must be returned");
    console.log(`✔ Course created successfully: ID = ${courseId}`);

    const codeRes = await callApi("getCourseJoinCode", { courseId }, teacherAuth.idToken);
    const joinCode = codeRes.joinCode;
    assert.ok(joinCode, "Join code must be returned");
    console.log(`✔ Course join code retrieved: ${joinCode}`);

    // 5. STUDENT REQUESTS TO JOIN COURSE
    console.log("\n[STEP 5] Student Requests to Join Course via /api/requestJoinCourse...");
    const joinReq = await callApi(
      "requestJoinCourse",
      { joinCode },
      studentAuth.idToken
    );
    const requestId = joinReq.requestId;
    assert.ok(requestId, "Request ID must be returned");
    console.log(`✔ Student submitted join request: ID = ${requestId}`);

    // 6. TEACHER A APPROVES JOIN REQUEST
    console.log("\n[STEP 6] Teacher A Approves Join Request via /api/respondCourseJoinRequest...");
    const approvalRes = await callApi(
      "respondCourseJoinRequest",
      { requestId, response: "approved" },
      teacherAuth.idToken
    );
    assert.equal(approvalRes.success, true);
    console.log("✔ Join request approved. Student is actively enrolled in the course.");

    // 7. TEACHER OPENS ATTENDANCE SESSION (TESTING GPS VALIDATION)
    console.log("\n[STEP 7] Testing GPS Metadata Validation on Session Creation...");
    const sessionLat = 22.463200;
    const sessionLng = 91.970400;
    const sessionRadius = 60; // 60 meters

    // Case 7A: Missing teacher accuracy should be rejected with 400
    await assertApiError(
      "createAttendanceSession",
      {
        courseId,
        classType: "Theory",
        durationMinutes: 30,
        requiresPasscode: true,
        requiresGps: true,
        allowLateEntry: true,
        latitude: sessionLat,
        longitude: sessionLng,
        radiusMeters: sessionRadius,
        // accuracy omitted
      },
      teacherAuth.idToken,
      400,
      /invalid-argument/
    );
    console.log("✔ Session creation correctly rejects missing GPS accuracy metadata.");

    // Case 7B: Valid creation with teacher center accuracy
    const sessionRes = await callApi(
      "createAttendanceSession",
      {
        courseId,
        classType: "Theory",
        durationMinutes: 30,
        requiresPasscode: true,
        requiresGps: true,
        allowLateEntry: true,
        latitude: sessionLat,
        longitude: sessionLng,
        radiusMeters: sessionRadius,
        accuracy: 10.0,
        timestamp: Date.now(),
      },
      teacherAuth.idToken
    );
    const sessionId = sessionRes.sessionId;
    const passcode = sessionRes.passcode;
    assert.ok(sessionId, "Session ID must be returned");
    assert.ok(passcode, "Generated passcode must be returned");
    console.log(`✔ Attendance session created: ID = ${sessionId}, Passcode = ${passcode}`);

    // 8. STUDENT GPS ATTENDANCE SUBMISSION EDGE CASES
    console.log("\n[STEP 8] Testing Student GPS Metadata, Staleness, Uncertainty, and Boundary...");
    const studentInsideLat = 22.463210;
    const studentInsideLng = 91.970405; // ~1m away

    // Case 8A: Missing accuracy metadata rejected
    await assertApiError(
      "submitAttendance",
      {
        sessionId,
        passcode,
        latitude: studentInsideLat,
        longitude: studentInsideLng,
        timestamp: Date.now(),
      },
      studentAuth.idToken,
      400,
      /invalid-argument/
    );
    console.log("✔ Student submission correctly rejects missing GPS accuracy metadata.");

    // Case 8B: Stale GPS timestamp (> 120s old) rejected
    await assertApiError(
      "submitAttendance",
      {
        sessionId,
        passcode,
        latitude: studentInsideLat,
        longitude: studentInsideLng,
        accuracy: 12.0,
        timestamp: Date.now() - 150000,
      },
      studentAuth.idToken,
      400,
      /failed-precondition.*stale/i
    );
    console.log("✔ Student submission correctly rejects stale GPS timestamp.");

    // Case 8C: Poor accuracy (> min(50m, radius)) rejected as inconclusive
    await assertApiError(
      "submitAttendance",
      {
        sessionId,
        passcode,
        latitude: studentInsideLat,
        longitude: studentInsideLng,
        accuracy: 85.0, // 85m uncertainty for 60m radius
        timestamp: Date.now(),
      },
      studentAuth.idToken,
      400,
      /failed-precondition.*inconclusive/i
    );
    console.log("✔ Student submission correctly rejects poor accuracy as inconclusive.");

    // Case 8D: Outside attendance radius rejected (never silently expanded)
    const studentOutsideLat = 22.467000;
    const studentOutsideLng = 91.972000; // ~450m away
    await assertApiError(
      "submitAttendance",
      {
        sessionId,
        passcode,
        latitude: studentOutsideLat,
        longitude: studentOutsideLng,
        accuracy: 12.0,
        timestamp: Date.now(),
      },
      studentAuth.idToken,
      400,
      /failed-precondition.*outside/i
    );
    console.log("✔ Student submission outside radius strictly rejected without radius expansion.");

    // Case 8E: Valid GPS submission inside radius
    const submitRes = await callApi(
      "submitAttendance",
      {
        sessionId,
        passcode,
        latitude: studentInsideLat,
        longitude: studentInsideLng,
        accuracy: 12.0,
        timestamp: Date.now(),
      },
      studentAuth.idToken
    );
    assert.equal(submitRes.success, true);
    assert.equal(submitRes.status, "present");
    console.log(`✔ Valid student attendance marked present (distance: ~${submitRes.distanceMeters ?? 1}m).`);

    // 9. TEACHER OWNERSHIP ON ACTIVE SESSION & CLOSURE
    console.log("\n[STEP 9] Testing Teacher Ownership & Finalization on Active Session...");

    // Case 9A: Unauthorized Teacher B attempts to close Teacher A's active session -> 403
    await assertApiError(
      "closeAttendanceSession",
      { sessionId },
      teacherBAuth.idToken,
      403,
      /permission-denied/
    );
    console.log("✔ Unauthorized Teacher B correctly rejected from closing Teacher A's session.");

    // Case 9B: Owning Teacher A finalizes session
    const closeRes = await callApi(
      "closeAttendanceSession",
      { sessionId },
      teacherAuth.idToken
    );
    assert.equal(closeRes.success, true);
    console.log("✔ Teacher A successfully closed and finalized session.");

    // 10. TEACHER OWNERSHIP ON ALREADY-CLOSED SESSION & IDEMPOTENCY
    console.log("\n[STEP 10] Testing Teacher Ownership on ALREADY-CLOSED Session & Idempotent Repeated Closure...");

    // Case 10A: Unauthorized Teacher B attempts to close ALREADY-CLOSED session -> 403
    await assertApiError(
      "closeAttendanceSession",
      { sessionId },
      teacherBAuth.idToken,
      403,
      /permission-denied/
    );
    console.log("✔ Unauthorized Teacher B strictly rejected on already-closed session (ownership verified).");

    // Case 10B: Owning Teacher A calls closeAttendanceSession a second time (idempotent)
    const secondCloseRes = await callApi(
      "closeAttendanceSession",
      { sessionId },
      teacherAuth.idToken
    );
    assert.equal(secondCloseRes.success, true);
    console.log("✔ Repeated closure by owner succeeded idempotently without double counting.");

    // 11. TEACHER CORRECTION & EXACT PERSISTED SUMMARY VERIFICATION
    console.log("\n[STEP 11] Testing Attendance Record Correction & Exact Persisted Summary Values...");

    // Case 11A: Unauthorized Teacher B attempts to correct record -> 403
    await assertApiError(
      "correctClosedAttendance",
      {
        sessionId,
        studentId: studentUid,
        newStatus: "late",
        reason: "Unauthorized attempt",
      },
      teacherBAuth.idToken,
      403,
      /permission-denied/
    );
    console.log("✔ Unauthorized Teacher B rejected from correcting record.");

    // Case 11B: Owning Teacher A corrects record from 'present' to 'late'
    const correctRes = await callApi(
      "correctClosedAttendance",
      {
        sessionId,
        studentId: studentUid,
        newStatus: "late",
        reason: "Adjusted status for transport delay",
      },
      teacherAuth.idToken
    );
    assert.equal(correctRes.success, true);
    assert.equal(correctRes.changed, true);
    assert.equal(correctRes.previousStatus, "present");
    assert.equal(correctRes.newStatus, "late");
    console.log("✔ Teacher A successfully corrected closed record to 'late'.");

    // Case 11C: Verify exact persisted summary values in Firestore
    const summaryDoc = await getSummaryDocument(googleToken, courseId, studentUid);
    const fields = summaryDoc.fields;
    const total = Number(fields.total?.integerValue ?? fields.total?.doubleValue);
    const attended = Number(fields.attended?.integerValue ?? fields.attended?.doubleValue);
    const percentage = Number(fields.percentage?.doubleValue ?? fields.percentage?.integerValue);

    console.log(`- Persisted Summary: total=${total}, attended=${attended}, percentage=${percentage}%`);
    assert.equal(total, 1, "Total classes count must be exactly 1");
    assert.equal(attended, 1, "Attended count for 'late' status must be exactly 1");
    assert.equal(percentage, 100, "Percentage must be 100%");
    console.log("✔ Exact persisted summary values verified correctly in database.");

    console.log("\n=================================================");
    console.log("ALL REAL PRODUCTION CONTRACT CHECKS PASSED 100%");
    console.log("=================================================");
  } finally {
    console.log("\n[CLEANUP] Cleaning up test users from production...");
    if (teacherUid) await cleanupUser(googleToken, teacherUid, teacherInstId);
    if (teacherBUid) await cleanupUser(googleToken, teacherBUid, teacherBInstId);
    if (studentUid) await cleanupUser(googleToken, studentUid, studentInstId);
    console.log("✔ Cleanup complete.");
  }
}

run().catch((err) => {
  console.error("\n❌ SMOKE FLOW ERROR:", err.message);
  process.exit(1);
});

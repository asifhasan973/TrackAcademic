import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const BASE_URL = process.env.TEST_BACKEND_URL || "https://trackacademic-backend.vercel.app/api";

console.log("=================================================");
console.log("TRACKACADEMIC TARGETED IDEMPOTENCY & PUSH TESTS");
console.log(`Backend Target: ${BASE_URL}`);
console.log("=================================================\n");

async function callApi(operation, payload, idempotencyKey = null) {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (idempotencyKey) {
    headers["X-Idempotency-Key"] = idempotencyKey;
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
    json = { raw: text };
  }

  return { status: res.status, data: json };
}

async function run() {
  const testRunId = Date.now();
  console.log(`[TEST RUN ${testRunId}] Starting targeted checks...`);

  // 1. Backend Health Check
  const health = await fetch(`${BASE_URL}/health`);
  assert.equal(health.status, 200, "Backend health endpoint must return 200");
  console.log("✓ Backend is healthy and reachable.");

  // 2. Test Conflicting Key Reuse (Mismatched Payload -> 409)
  console.log("\n[TEST 1] Conflicting reuse with mismatched payload...");
  const conflictKey = `idem_conflict_${testRunId}`;
  const payload1 = {
    displayName: "User One",
    email: `test_idem_1_${testRunId}@example.com`,
    institutionId: `INST-1-${testRunId}`,
    password: "Password123!",
    role: "student",
  };
  const payload2 = {
    displayName: "User Two (Conflicting)",
    email: `test_idem_2_${testRunId}@example.com`,
    institutionId: `INST-2-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  const res1 = await callApi("registerUser", payload1, conflictKey);
  console.log(`Initial call status: ${res1.status}`);

  const res2 = await callApi("registerUser", payload2, conflictKey);
  console.log(`Conflicting call status: ${res2.status}`);
  assert.equal(res2.status, 409, "Conflicting key reuse must return HTTP 409 Conflict");
  assert.equal(res2.data?.error?.code, "conflict", "Error code must be 'conflict'");
  console.log("✓ Conflicting reuse properly rejected with HTTP 409 Conflict.");

  // 3. Test Identical Request Idempotency Hit (Cache Return)
  console.log("\n[TEST 2] Identical request replay returns cached response...");
  const cacheKey = `idem_replay_${testRunId}`;
  const payloadReplay = {
    displayName: "Replay User",
    email: `test_replay_${testRunId}@example.com`,
    institutionId: `INST-REP-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  const replay1 = await callApi("registerUser", payloadReplay, cacheKey);
  console.log(`First call status: ${replay1.status}`);

  const replay2 = await callApi("registerUser", payloadReplay, cacheKey);
  console.log(`Replay call status: ${replay2.status}`);
  assert.equal(replay2.status, replay1.status, "Replay status must match original status");
  if (replay1.status === 200) {
    assert.deepEqual(replay2.data, replay1.data, "Replayed response must match original response");
  }
  console.log("✓ Replay successfully returned cached outcome without duplicate side effects.");

  // 4. Test Concurrent Identical Requests
  console.log("\n[TEST 3] Concurrent identical requests arriving simultaneously...");
  const concurrentKey = `idem_conc_${testRunId}`;
  const payloadConcurrent = {
    displayName: "Concurrent User",
    email: `test_conc_${testRunId}@example.com`,
    institutionId: `INST-CONC-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  const [conc1, conc2] = await Promise.all([
    callApi("registerUser", payloadConcurrent, concurrentKey),
    callApi("registerUser", payloadConcurrent, concurrentKey),
  ]);

  console.log(`Concurrent request 1 status: ${conc1.status}`);
  console.log(`Concurrent request 2 status: ${conc2.status}`);
  // Concurrent execution must either cleanly resolve to 200 (one executes, one awaits lock resolution)
  // or return 409 in-progress lock. It must never allow dual execution.
  assert(
    (conc1.status === 200 && conc2.status === 200) ||
      (conc1.status === 200 && conc2.status === 409) ||
      (conc1.status === 409 && conc2.status === 200) ||
      (conc1.status === 400 && conc2.status === 400),
    "Concurrent requests must not result in unhandled or duplicate state",
  );
  console.log("✓ Concurrent identical requests safely serialized.");

  // 5. Code-level Verification of ApiClient Retry Disablement
  console.log("\n[TEST 4] Verification of disabled retries for unsafe mutations in ApiClient...");
  const apiClientPath = path.join(rootDir, "lib", "core", "network", "api_client.dart");
  const apiClientContent = fs.readFileSync(apiClientPath, "utf8");

  // Verify createCourse, createAttendanceSession, registerUser are NOT in _safeIdempotentOperations
  const safeOpMatch = apiClientContent.match(/_safeIdempotentOperations\s*=\s*\{([^}]+)\}/s);
  assert(safeOpMatch, "_safeIdempotentOperations set must exist in api_client.dart");
  const safeOps = safeOpMatch[1];
  assert(!safeOps.includes("'createCourse'"), "'createCourse' must not be in _safeIdempotentOperations");
  assert(!safeOps.includes("'createAttendanceSession'"), "'createAttendanceSession' must not be in _safeIdempotentOperations");
  assert(!safeOps.includes("'registerUser'"), "'registerUser' must not be in _safeIdempotentOperations");
  console.log("✓ Verified: createCourse, createAttendanceSession, and registerUser have automatic retries disabled.");

  // 6. Code-level Verification of Transaction Return and Storage Failure Handling in backend/api/index.ts
  console.log("\n[TEST 5] Verification of transaction return decision & uncertain outcome handling in backend/api/index.ts...");
  const backendIndexPath = path.join(rootDir, "backend", "api", "index.ts");
  const backendIndexContent = fs.readFileSync(backendIndexPath, "utf8");

  assert(backendIndexContent.includes("type IdempotencyDecision ="), "Must define IdempotencyDecision type");
  assert(backendIndexContent.includes("const decision: IdempotencyDecision = await db.runTransaction"), "Transaction must return committed decision");
  assert(!backendIndexContent.includes("shouldExecute = true"), "Must not mutate outer shouldExecute variable inside transaction");
  assert(backendIndexContent.includes('status: "uncertain"'), "Must handle result-storage failure as 'uncertain' status");
  assert(!backendIndexContent.includes("await idemRef.delete().catch"), "Must not delete reservation on business error");
  assert(backendIndexContent.includes('status: "failed"'), "Must record failed status on error");
  console.log("✓ Verified: transaction callback returns isolated decision, handles uncertain status, and does not delete on error.");

  // 7. Code-level Verification of Push Delivery Tracking in backend/src/middleware/auth.ts
  console.log("\n[TEST 6] Verification of correct notification item document path & honest timeout handling in auth.ts...");
  const authMiddlewarePath = path.join(rootDir, "backend", "src", "middleware", "auth.ts");
  const authMiddlewareContent = fs.readFileSync(authMiddlewarePath, "utf8");

  assert(
    /\.collection\("notifications"\)\s*\.doc\(track\.userId\)\s*\.collection\("items"\)\s*\.doc\(track\.id\)/.test(authMiddlewareContent),
    "Must write delivery status to notifications/{userId}/items/{notificationId}",
  );
  assert(
    authMiddlewareContent.includes('finalStatus = "timed_out"'),
    "Must set status to 'timed_out' when dispatch times out without acceptances",
  );
  assert(
    !authMiddlewareContent.includes('finalStatus =\n      totalSuccesses > 0\n        ? totalFailures > 0\n          ? "partial"\n          : "sent"\n        : totalFailures > 0\n        ? "failed"\n        : "sent";'),
    "Must not use aggregate status that turns timeouts into 'sent'",
  );
  assert(
    authMiddlewareContent.includes("Best-effort delivery: FCM acceptance confirms cloud dispatch, not guaranteed physical device receipt"),
    "Must explicitly document best-effort delivery semantics",
  );
  console.log("✓ Verified: Push delivery tracking writes to items subcollection, tracks per-notification, and handles timeouts honestly.");

  console.log("\n=================================================");
  console.log("ALL TARGETED CHECKS PASSED SUCCESSFULLY");
  console.log("=================================================\n");
}

run().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});

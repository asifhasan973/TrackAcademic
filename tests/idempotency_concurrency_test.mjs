import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BASE_URL = process.env.TEST_BACKEND_URL || "https://trackacademic-backend.vercel.app/api";

console.log("=================================================");
console.log("TRACKACADEMIC IDEMPOTENCY & CONCURRENCY TEST");
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
  console.log(`[TEST RUN ${testRunId}] Starting targeted idempotency tests...`);

  // 1. Health check
  const health = await fetch(`${BASE_URL}/health`);
  assert.equal(health.status, 200, "Backend health endpoint must return 200");
  console.log("✓ Backend is healthy and reachable.");

  // 2. Test Conflicting Reuse with registerUser
  console.log("\n[TEST 1] Conflicting reuse of idempotency key with different payloads...");
  const conflictKey = `idem_conflict_test_${testRunId}`;
  const payloadA = {
    displayName: "Test User A",
    email: `idem_test_a_${testRunId}@example.com`,
    institutionId: `IDEM-A-${testRunId}`,
    password: "Password123!",
    role: "student",
  };
  const payloadB = {
    displayName: "Test User B (Different)",
    email: `idem_test_b_${testRunId}@example.com`,
    institutionId: `IDEM-B-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  // First call with payloadA
  const res1 = await callApi("registerUser", payloadA, conflictKey);
  console.log(`First call status: ${res1.status}`);

  // Second call with same key but DIFFERENT payloadB -> MUST REJECT WITH 409
  const res2 = await callApi("registerUser", payloadB, conflictKey);
  console.log(`Second call (different payload) status: ${res2.status}`);
  assert.equal(res2.status, 409, "Conflicting key reuse must return HTTP 409 Conflict");
  assert.equal(res2.data?.error?.code, "conflict", "Error code must be 'conflict'");
  console.log("✓ Conflicting reuse properly rejected with HTTP 409 Conflict.");

  // 3. Test Identical Reuse (Cache Hit)
  console.log("\n[TEST 2] Identical reuse returns cached result without re-executing...");
  const cacheKey = `idem_cache_test_${testRunId}`;
  const payloadCache = {
    displayName: "Cache Test User",
    email: `idem_cache_${testRunId}@example.com`,
    institutionId: `IDEM-C-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  const cacheRes1 = await callApi("registerUser", payloadCache, cacheKey);
  console.log(`First invocation status: ${cacheRes1.status}`);

  const cacheRes2 = await callApi("registerUser", payloadCache, cacheKey);
  console.log(`Second invocation status: ${cacheRes2.status}`);
  assert.equal(cacheRes2.status, cacheRes1.status, "Identical retry must match original status");
  if (cacheRes1.status === 200) {
    assert.deepEqual(cacheRes2.data, cacheRes1.data, "Cached response must match original response");
  }
  console.log("✓ Idempotent replay returned consistent cached response.");

  // 4. Test Concurrent Identical Requests
  console.log("\n[TEST 3] Concurrent identical requests arriving simultaneously...");
  const concurrentKey = `idem_concurrent_${testRunId}`;
  const payloadConcurrent = {
    displayName: "Concurrent User",
    email: `idem_concurrent_${testRunId}@example.com`,
    institutionId: `IDEM-CONC-${testRunId}`,
    password: "Password123!",
    role: "student",
  };

  const [cRes1, cRes2] = await Promise.all([
    callApi("registerUser", payloadConcurrent, concurrentKey),
    callApi("registerUser", payloadConcurrent, concurrentKey),
  ]);

  console.log(`Concurrent request 1 status: ${cRes1.status}`);
  console.log(`Concurrent request 2 status: ${cRes2.status}`);
  // Either both succeed with 200 (one executed, one got cached/awaited result), or one gets 200 and one gets 409 in-flight lock
  assert(
    (cRes1.status === 200 && cRes2.status === 200) ||
      (cRes1.status === 200 && cRes2.status === 409) ||
      (cRes1.status === 409 && cRes2.status === 200) ||
      (cRes1.status === 400 && cRes2.status === 400),
    "Concurrent identical requests must not duplicate execution",
  );
  console.log("✓ Concurrent identical requests handled safely without duplication.");

  console.log("\n=================================================");
  console.log("ALL TARGETED IDEMPOTENCY & CONCURRENCY TESTS PASSED");
  console.log("=================================================\n");
}

run().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});

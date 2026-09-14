import type { IncomingMessage, ServerResponse } from "http";
import crypto from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { getDb } from "../src/firebaseAdmin.js";
import { verifyBearerToken } from "../src/middleware/auth.js";
import { BackendError, RequestContext } from "../src/types.js";
import { OPERATIONS } from "../src/operations/index.js";

interface VercelRequest extends IncomingMessage {
  query?: Record<string, string | string[]>;
  body?: any;
}

interface VercelResponse extends ServerResponse {
  status: (code: number) => VercelResponse;
  json: (data: any) => void;
  send: (body: any) => void;
}

function setCorsHeaders(res: ServerResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Methods",
    "GET, POST, OPTIONS, HEAD",
  );
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, Accept, Origin, User-Agent, X-Requested-With",
  );
  res.setHeader("Access-Control-Max-Age", "86400");
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  setCorsHeaders(res);

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    res.end();
    return;
  }

  const rawUrl = req.url || "";
  const pathname = rawUrl.split("?")[0] || "";

  // Health check endpoint
  if (pathname === "/api/health" || pathname === "/health") {
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        status: "healthy",
        project: "trackacademic-c0d1c",
        timestamp: new Date().toISOString(),
      }),
    );
    return;
  }

  if (req.method !== "POST") {
    res.statusCode = 405;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        error: {
          code: "invalid-argument",
          message: `Method ${req.method} not allowed. Use POST.`,
          status: "INVALID_ARGUMENT",
        },
      }),
    );
    return;
  }

  // Extract operation name
  // Supported URL patterns: /api/submitAttendance, /api/index?op=submitAttendance, or body { operation: ... }
  let operation = "";
  const match = pathname.match(/\/api\/([a-zA-Z0-9_-]+)/);
  if (match && match[1] && match[1] !== "index") {
    operation = match[1];
  } else if (req.query?.operation && typeof req.query.operation === "string") {
    operation = req.query.operation;
  }

  // Parse body if not parsed
  let body = req.body;
  if (!body) {
    body = await new Promise((resolve) => {
      let data = "";
      req.on("data", (chunk) => {
        data += chunk;
        if (data.length > 2 * 1024 * 1024) {
          // 2MB payload limit
          resolve(null);
        }
      });
      req.on("end", () => {
        try {
          resolve(data ? JSON.parse(data) : {});
        } catch {
          resolve({});
        }
      });
      req.on("error", () => resolve({}));
    });
  }

  if (!operation && body && typeof body === "object" && typeof body.operation === "string") {
    operation = body.operation;
  }

  if (!operation) {
    res.statusCode = 400;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        error: {
          code: "invalid-argument",
          message: "Missing operation name in request path.",
          status: "INVALID_ARGUMENT",
        },
      }),
    );
    return;
  }

  const handlerFn = OPERATIONS[operation];
  if (!handlerFn) {
    res.statusCode = 404;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        error: {
          code: "not-found",
          message: `Operation '${operation}' is not supported.`,
          status: "NOT_FOUND",
        },
      }),
    );
    return;
  }

  // Extract client IP
  const forwarded = req.headers["x-forwarded-for"];
  const clientIp = typeof forwarded === "string"
    ? forwarded.split(",")[0]!.trim()
    : req.socket?.remoteAddress || "127.0.0.1";

  // Build request context
  const context: RequestContext = {
    ip: clientIp,
    headers: req.headers,
  };

  try {
    const authHeader = req.headers.authorization;
    context.auth = await verifyBearerToken(authHeader);

    // Enforce authentication on all operations except registerUser
    if (operation !== "registerUser" && !context.auth) {
      throw new BackendError(
        "unauthenticated",
        "Sign in required to perform this academic operation.",
      );
    }

    // Support both direct JSON body and Firebase callable standard `{ data: { ... } }`
    const payload =
      body && typeof body === "object" && "data" in body && typeof body.data === "object"
        ? body.data
        : body ?? {};

    // Atomic operation-level idempotency protection
    const rawIdem = req.headers["x-idempotency-key"] || (payload && payload.idempotencyKey);
    const idempotencyKey = typeof rawIdem === "string" && rawIdem.trim().length > 0 ? rawIdem.trim() : null;

    let idemRef: FirebaseFirestore.DocumentReference | null = null;
    let boundUid = "";
    let payloadHash = "";

    if (idempotencyKey) {
      boundUid = context.auth?.uid
        ? context.auth.uid
        : `unauth_${payload?.email || payload?.institutionId || clientIp}`;

      function canonicalize(obj: any): any {
        if (obj === null || typeof obj !== "object") return obj;
        if (Array.isArray(obj)) return obj.map(canonicalize);
        const sortedKeys = Object.keys(obj)
          .filter((k) => k !== "idempotencyKey")
          .sort();
        const result: Record<string, any> = {};
        for (const key of sortedKeys) {
          result[key] = canonicalize(obj[key]);
        }
        return result;
      }

      payloadHash = crypto
        .createHash("sha256")
        .update(JSON.stringify(canonicalize(payload || {})))
        .digest("hex");

      const db = getDb();
      idemRef = db.collection("idempotencyKeys").doc(idempotencyKey);

      type IdempotencyDecision =
        | { action: "execute" }
        | { action: "cached"; result: any }
        | { action: "in_progress" };

      const decision: IdempotencyDecision = await db.runTransaction(async (t) => {
        const doc = await t.get(idemRef!);
        if (!doc.exists) {
          t.set(idemRef!, {
            idempotencyKey,
            uid: boundUid,
            operation,
            payloadHash,
            status: "pending",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          return { action: "execute" };
        }

        const data = doc.data()!;
        if (
          data.uid !== boundUid ||
          data.operation !== operation ||
          data.payloadHash !== payloadHash
        ) {
          throw new BackendError(
            "conflict",
            "Idempotency key was previously used with a different operation or payload.",
          );
        }

        if (data.status === "completed") {
          return { action: "cached", result: data.result ?? {} };
        }

        if (data.status === "uncertain") {
          throw new BackendError(
            "conflict",
            "This operation previously executed with an uncertain outcome. Automatic rerun is blocked to prevent duplicate side effects.",
          );
        }

        if (data.status === "failed") {
          throw new BackendError(
            "conflict",
            "Previous execution with this idempotency key failed with possible partial side effects. Automatic rerun is blocked.",
          );
        }

        // Pending operation in progress: do not blindly rerun after 60s
        return { action: "in_progress" };
      });

      if (decision.action === "cached") {
        console.log(`[IDEMPOTENCY_HIT] Returning cached result for key ${idempotencyKey}`);
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json");
        res.end(
          JSON.stringify({
            result: decision.result,
            data: decision.result,
          }),
        );
        return;
      }

      if (decision.action === "in_progress") {
        // Another concurrent request with this key is currently executing; poll bounded
        for (let wait = 0; wait < 7; wait++) {
          await new Promise((r) => setTimeout(r, 500));
          const pollDoc = await idemRef.get();
          if (pollDoc.exists) {
            const pollData = pollDoc.data();
            if (pollData?.status === "completed") {
              console.log(`[IDEMPOTENCY_AWAIT_HIT] Resolved concurrent request for key ${idempotencyKey}`);
              res.statusCode = 200;
              res.setHeader("Content-Type", "application/json");
              res.end(
                JSON.stringify({
                  result: pollData.result ?? {},
                  data: pollData.result ?? {},
                }),
              );
              return;
            }
            if (pollData?.status === "failed" || pollData?.status === "uncertain") {
              throw new BackendError(
                "conflict",
                "The concurrent operation failed or resolved with an uncertain outcome.",
              );
            }
          }
        }
        throw new BackendError(
          "conflict",
          "A concurrent operation with this idempotency key is already in progress. Please retry later.",
        );
      }
    }

    let result: any;
    try {
      result = await handlerFn(payload, context);
    } catch (handlerErr: any) {
      // Do not delete a reservation on an error unless it is safe to conclude no side effects occurred.
      // Record failed status to prevent blind retries from duplicating partial side effects.
      if (idemRef) {
        try {
          await idemRef.set(
            {
              status: "failed",
              error: handlerErr?.message || String(handlerErr),
              failedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } catch (_) {}
      }
      throw handlerErr;
    }

    if (idemRef) {
      let stored = false;
      try {
        await idemRef.set(
          {
            idempotencyKey,
            uid: boundUid,
            operation,
            payloadHash,
            status: "completed",
            result: result ?? {},
            completedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        stored = true;
      } catch (storeErr) {
        console.warn("[IDEMPOTENCY_STORE_WARN] Retrying idempotency cache save:", storeErr);
        try {
          await idemRef.set(
            {
              status: "completed",
              result: result ?? {},
              completedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          stored = true;
        } catch (_) {}
      }

      // Handle success followed by result-storage failure as an uncertain outcome,
      // not permission to execute the mutation again.
      if (!stored) {
        console.error("[IDEMPOTENCY_UNCERTAIN] Mutation succeeded but storing result failed. Recording uncertain status.");
        try {
          await idemRef.set(
            {
              status: "uncertain",
              note: "Mutation executed successfully but saving result to cache failed",
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } catch (_) {}
      }
    }

    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        result: result ?? {},
        data: result ?? {},
      }),
    );
  } catch (err: any) {
    if (err instanceof BackendError) {
      res.statusCode = err.httpStatus;
      res.setHeader("Content-Type", "application/json");
      res.end(
        JSON.stringify({
          error: {
            code: err.code,
            message: err.message,
            status: err.code.replace(/-/g, "_").toUpperCase(),
          },
        }),
      );
      return;
    }

    console.error(`[BACKEND_UNHANDLED_ERROR] ${operation}:`, err);
    res.statusCode = 500;
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        error: {
          code: "internal",
          message: err.message || "An unexpected server error occurred.",
          status: "INTERNAL",
        },
      }),
    );
  }
}

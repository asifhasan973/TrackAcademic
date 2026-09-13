import type { IncomingMessage, ServerResponse } from "http";
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

    const result = await handlerFn(payload, context);

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

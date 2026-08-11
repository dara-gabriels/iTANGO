// supabase/functions/_shared/http.ts
// Shared helpers so every Edge Function has consistent responses, CORS, and
// error handling instead of reimplementing this per function.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*", // tightened to specific origins at Cloudflare/API Gateway layer
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

export function errorResponse(message: string, status = 400, error = "bad_request"): Response {
  const requestId = crypto.randomUUID();
  console.error(JSON.stringify({ level: "error", request_id: requestId, error, message }));
  return jsonResponse({ error, message, request_id: requestId }, status);
}

/**
 * Client scoped to the calling user's JWT — respects RLS. Use this for
 * anything that should be constrained by the user's own row-level access.
 */
export function getUserScopedClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
}

/**
 * Service-role client — BYPASSES RLS. Only use for operations that
 * legitimately need cross-user access with no client-supplied auth context:
 * PSP webhooks, scheduled jobs, admin-triggered batch operations. Never
 * expose this client's key to any frontend.
 */
export function getServiceRoleClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function requireAuthenticatedUser(req: Request, client: SupabaseClient) {
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new AuthError("Missing or invalid authentication token");
  }
  return data.user;
}

export class AuthError extends Error {}
export class ValidationError extends Error {}
export class ConflictError extends Error {}

export function handleKnownErrors(err: unknown): Response {
  if (err instanceof AuthError) return errorResponse(err.message, 401, "unauthorized");
  if (err instanceof ValidationError) return errorResponse(err.message, 400, "validation_error");
  if (err instanceof ConflictError) return errorResponse(err.message, 409, "conflict");
  console.error("Unhandled error:", err);
  return errorResponse("Internal server error", 500, "internal_error");
}

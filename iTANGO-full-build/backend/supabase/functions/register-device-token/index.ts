// supabase/functions/register-device-token/index.ts
//
// POST /register-device-token
// Called once on login and whenever Firebase rotates the token
// (onTokenRefresh). Upserts rather than plain-inserts because the same
// device may re-register on every app foreground — treating that as a
// duplicate-key error would be noisy and pointless.

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, CORS_HEADERS } from "../_shared/http.ts";

interface RegisterTokenBody {
  fcm_token: string;
  platform: "ios" | "android";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabase = getUserScopedClient(req);
    const user = await requireAuthenticatedUser(req, supabase);
    const body: RegisterTokenBody = await req.json();

    if (!body.fcm_token) throw new ValidationError("fcm_token is required");

    const { error } = await supabase
      .from("device_tokens")
      .upsert(
        { user_id: user.id, fcm_token: body.fcm_token, platform: body.platform ?? "unknown", last_seen_at: new Date().toISOString() },
        { onConflict: "user_id,fcm_token" },
      );

    if (error) throw error;

    return jsonResponse({ registered: true });
  } catch (err) {
    return handleKnownErrors(err);
  }
});

// supabase/functions/send-push-notification/index.ts
//
// Triggered by a Supabase Database Webhook (Database → Webhooks → on INSERT
// to `notifications`) — NOT called directly by any client. This is
// deliberately decoupled from the SQL triggers that create notification
// rows (migration 014): the trigger's job is "decide this is
// notification-worthy," this function's job is "deliver it," and a slow or
// failed FCM call here never blocks the original INSERT's transaction.
//
// Uses FCM HTTP v1 (the legacy server-key API was shut down by Google in
// June 2024), which requires a service-account OAuth2 flow: sign a JWT with
// the service account's private key, exchange it for an access token, then
// call the v1 send endpoint. Implemented directly via Web Crypto rather than
// a Node-oriented Firebase Admin SDK, since Admin SDK isn't Deno-compatible.

import { getServiceRoleClient, jsonResponse, errorResponse, CORS_HEADERS } from "../_shared/http.ts";

interface WebhookPayload {
  type: "INSERT";
  table: string;
  record: {
    id: string;
    user_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
}

const NOTIFICATION_COPY: Record<string, (payload: Record<string, unknown>) => { title: string; body: string }> = {
  new_message: (p) => ({ title: "New message", body: String(p.preview ?? "You have a new message") }),
  checkin_confirmed: (p) => ({ title: "Checked in! 🎉", body: `You're in at ${p.event_title ?? "the event"} — chat unlocked.` }),
  ticket_confirmed: () => ({ title: "Ticket confirmed", body: "Your ticket is ready — see it in My Tickets." }),
  achievement_earned: (p) => ({ title: "Achievement unlocked 🏆", body: `You earned "${p.name}"` }),
  new_follower: () => ({ title: "New follower", body: "Someone started following you" }),
  friend_request: () => ({ title: "Friend request", body: "You have a new friend request" }),
  voucher_available: () => ({ title: "New voucher", body: "A new perk is waiting in your Voucher Wallet" }),
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const payload: WebhookPayload = await req.json();
    if (payload.table !== "notifications" || payload.type !== "INSERT") {
      return jsonResponse({ skipped: true });
    }

    const notification = payload.record;
    const copyBuilder = NOTIFICATION_COPY[notification.type];
    if (!copyBuilder) {
      // Unmapped notification types are stored in-app but don't push —
      // fail open (skip), not closed, so an unrecognized type never throws.
      return jsonResponse({ skipped: true, reason: "no copy mapping for type" });
    }
    const { title, body } = copyBuilder(notification.payload);

    const supabase = getServiceRoleClient();
    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("fcm_token")
      .eq("user_id", notification.user_id);

    if (error) throw error;
    if (!tokens || tokens.length === 0) return jsonResponse({ skipped: true, reason: "no device tokens" });

    const accessToken = await getFcmAccessToken();
    const projectId = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!).project_id;

    const results = await Promise.allSettled(
      tokens.map((t) => sendFcmMessage(accessToken, projectId, t.fcm_token, title, body, notification.payload)),
    );

    const failures = results.filter((r) => r.status === "rejected");
    if (failures.length > 0) {
      console.error(`${failures.length}/${tokens.length} push deliveries failed`, failures);
    }

    return jsonResponse({ sent: tokens.length - failures.length, failed: failures.length });
  } catch (err) {
    console.error("Push notification delivery error:", err);
    // Return 200 regardless — this is a webhook, and Supabase will retry
    // on non-2xx. A push-delivery failure shouldn't trigger infinite
    // retries against a notification row that already exists; the failure
    // is logged above for monitoring instead.
    return jsonResponse({ error: "delivery_failed" });
  }
});

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<void> {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      },
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`FCM send failed (${response.status}): ${errorBody}`);
  }
}

/** Cached in module scope — access tokens are valid for ~1 hour, no need to re-mint per invocation within that window. */
let cachedToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token;
  }

  const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!);
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const unsignedJwt = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claimSet))}`;
  const signature = await signRs256(unsignedJwt, serviceAccount.private_key);
  const jwt = `${unsignedJwt}.${signature}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(`FCM OAuth token exchange failed: ${await tokenResponse.text()}`);
  }

  const tokenData = await tokenResponse.json();
  cachedToken = { token: tokenData.access_token, expiresAt: Date.now() + tokenData.expires_in * 1000 };
  return cachedToken.token;
}

function base64url(input: string): string {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signRs256(data: string, pemPrivateKey: string): Promise<string> {
  const pemContents = pemPrivateKey
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(data));
  return base64url(String.fromCharCode(...new Uint8Array(signatureBuffer)));
}

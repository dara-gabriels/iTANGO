// supabase/functions/discover-people/index.ts
//
// GET /discover/people?lat=&lng=&vibe_tag=&radius_km=
// Requires authentication — it exposes other users' approximate location
// and profile data.
//
// STATUS (found during full-stack verification): the Flutter mobile client
// currently calls `discover_people` directly via `client.rpc()`, bypassing
// this function entirely. The radius cap below is still correct to keep —
// defense in depth — but it is NOT the layer actually protecting the real
// client; that enforcement was moved into the `discover_people` Postgres
// function itself (migration 020) specifically because this wrapper being
// skippable meant the cap wasn't reliably applied. This function remains
// the documented contract for any future caller that shouldn't talk to
// Postgres RPC directly (e.g. a server-to-server integration).

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, CORS_HEADERS } from "../_shared/http.ts";

const VALID_VIBE_TAGS = ["turnt", "chill", "networking", "dancing", "foodie", "music_lover"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabase = getUserScopedClient(req);
    const user = await requireAuthenticatedUser(req, supabase);

    const url = new URL(req.url);
    const lat = parseFloat(url.searchParams.get("lat") ?? "");
    const lng = parseFloat(url.searchParams.get("lng") ?? "");
    const vibeTag = url.searchParams.get("vibe_tag");
    const radiusKm = parseFloat(url.searchParams.get("radius_km") ?? "5");

    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      throw new ValidationError("lat and lng query params are required");
    }
    if (vibeTag && !VALID_VIBE_TAGS.includes(vibeTag)) {
      throw new ValidationError(`vibe_tag must be one of: ${VALID_VIBE_TAGS.join(", ")}`);
    }
    // Cap the radius server-side regardless of what the client requests —
    // prevents a modified client from pulling a citywide dump of users in one call.
    const cappedRadiusKm = Math.min(radiusKm, 15);

    const { data, error } = await supabase.rpc("discover_people", {
      p_user_id: user.id,
      p_lat: lat,
      p_lng: lng,
      p_vibe_tag: vibeTag,
      p_radius_km: cappedRadiusKm,
      p_limit: 30,
    });

    if (error) throw error;

    return jsonResponse(data);
  } catch (err) {
    return handleKnownErrors(err);
  }
});

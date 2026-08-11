// supabase/functions/nearby-events/index.ts
//
// GET /events/nearby?lat=&lng=&radius_km=&limit=
// Deliberately a thin wrapper: all the actual query logic (PostGIS distance,
// index usage) lives in the `nearby_events` SQL function (database migration
// 011) so it can be reused from other server contexts (e.g. a future
// scheduled digest job) without duplicating query logic in TypeScript.

import { getUserScopedClient, jsonResponse, handleKnownErrors, ValidationError, CORS_HEADERS } from "../_shared/http.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const url = new URL(req.url);
    const lat = parseFloat(url.searchParams.get("lat") ?? "");
    const lng = parseFloat(url.searchParams.get("lng") ?? "");
    const radiusKm = parseFloat(url.searchParams.get("radius_km") ?? "10");
    const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "20", 10), 50);

    if (Number.isNaN(lat) || Number.isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new ValidationError("lat and lng query params are required and must be valid coordinates");
    }

    // Note: this endpoint is intentionally allowed for unauthenticated
    // browsing (public event discovery drives organic growth/SEO on web),
    // so we use the anon-scoped client without requiring a logged-in user —
    // RLS on `events` already restricts to visibility = 'public' for anon.
    const supabase = getUserScopedClient(req);

    const { data, error } = await supabase.rpc("nearby_events", {
      p_lat: lat,
      p_lng: lng,
      p_radius_km: radiusKm,
      p_limit: limit,
    });

    if (error) throw error;

    return jsonResponse(data);
  } catch (err) {
    return handleKnownErrors(err);
  }
});

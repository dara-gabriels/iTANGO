// supabase/functions/checkins/index.ts
//
// POST /checkins
// Verifies presence (QR or geofence), inserts the check_ins row, and relies
// on database triggers (award_energy_for_checkin, join_event_room_on_checkin,
// on_check_in) to handle the side effects — this function does NOT award
// energy score or add chat participants itself, to keep a single source of
// truth in the database rather than duplicating that logic in application
// code (see database/06_energy_score migration).

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, ConflictError, CORS_HEADERS } from "../_shared/http.ts";
import { verifyQrToken } from "./qr.ts";
import { haversineDistanceMeters } from "./geo.ts";

const GEOFENCE_MAX_RADIUS_METERS = 150; // generous enough for large venues, tight enough to deter spoofing from home

interface CheckInBody {
  event_id: string;
  method: "qr" | "geofence" | "manual_organizer";
  qr_token?: string;
  location?: { lat: number; lng: number };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabase = getUserScopedClient(req);
    const user = await requireAuthenticatedUser(req, supabase);
    const body: CheckInBody = await req.json();

    if (!body.event_id || !body.method) {
      throw new ValidationError("event_id and method are required");
    }

    // Fetch the event + venue location once; reused for both QR and geofence paths.
    const { data: event, error: eventError } = await supabase
      .from("events")
      .select("id, status, venues(location)")
      .eq("id", body.event_id)
      .single();

    if (eventError || !event) throw new ValidationError("Event not found");
    if (!["published", "live"].includes(event.status)) {
      throw new ValidationError("Event is not currently open for check-in");
    }

    let verifiedLocation: { lat: number; lng: number } | null = null;

    if (body.method === "qr") {
      if (!body.qr_token) throw new ValidationError("qr_token is required for method=qr");
      const decoded = await verifyQrToken(body.qr_token, Deno.env.get("QR_SIGNING_SECRET")!);
      if (decoded.eventId !== body.event_id || decoded.userId !== user.id) {
        throw new ValidationError("QR token does not match this event/user");
      }
      // QR check-in is trusted at the door (staff scanned it); no distance check required.
    } else if (body.method === "geofence") {
      if (!body.location) throw new ValidationError("location is required for method=geofence");
      const venueLocation = (event as any).venues?.location; // PostGIS point, parsed by PostgREST as GeoJSON
      if (!venueLocation) throw new ValidationError("Event venue has no location on record — use QR check-in instead");

      const distanceMeters = haversineDistanceMeters(
        body.location.lat, body.location.lng,
        venueLocation.coordinates[1], venueLocation.coordinates[0],
      );
      if (distanceMeters > GEOFENCE_MAX_RADIUS_METERS) {
        throw new ValidationError(
          `You appear to be ${Math.round(distanceMeters)}m from the venue — move closer to check in, or ask staff for a QR scan.`,
        );
      }
      verifiedLocation = body.location;
    }
    // method === "manual_organizer" is inserted by a separate organizer-scoped
    // endpoint (not this one), which additionally checks the caller owns the event.

    const { data: checkIn, error: insertError } = await supabase
      .from("check_ins")
      .insert({
        event_id: body.event_id,
        user_id: user.id,
        method: body.method,
        location: verifiedLocation
          ? `SRID=4326;POINT(${verifiedLocation.lng} ${verifiedLocation.lat})`
          : null,
      })
      .select("id")
      .single();

    if (insertError) {
      // unique(event_id, user_id) violation means they already checked in
      if (insertError.code === "23505") {
        throw new ConflictError("You've already checked in to this event");
      }
      throw insertError;
    }

    // Read back the event_room conversation created by the join_event_room_on_checkin
    // trigger, and the energy award just recorded, so the client gets both in one response.
    const { data: conversation } = await supabase
      .from("conversations")
      .select("id")
      .eq("event_id", body.event_id)
      .eq("type", "event_room")
      .single();

    const { data: energyEvent } = await supabase
      .from("energy_score_events")
      .select("delta")
      .eq("source_id", checkIn.id)
      .eq("reason", "event_checkin")
      .single();

    return jsonResponse({
      check_in_id: checkIn.id,
      energy_awarded: energyEvent?.delta ?? 0,
      chat_room_conversation_id: conversation?.id ?? null,
    }, 201);
  } catch (err) {
    return handleKnownErrors(err);
  }
});

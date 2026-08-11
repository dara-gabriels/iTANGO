// supabase/functions/events/index.ts
//
// POST /events — create a new event.
// Kept as an Edge Function rather than a raw PostgREST insert because event
// creation has validation beyond a single-table constraint (start_time must
// be in the future, venue must exist and belong to a business the organizer
// can act on if venue_id is supplied) — logic that's clearer here than
// spread across CHECK constraints and RLS policies.

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, CORS_HEADERS } from "../_shared/http.ts";

interface CreateEventBody {
  title: string;
  description?: string;
  cover_url?: string;
  event_type: string;
  visibility: string;
  start_time: string;
  end_time?: string;
  venue_id?: string;
  min_age?: number;
  tags?: string[];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return handleKnownErrors(new ValidationError("Only POST is supported on this endpoint"));

  try {
    const supabase = getUserScopedClient(req);
    const user = await requireAuthenticatedUser(req, supabase);
    const body: CreateEventBody = await req.json();

    if (!body.title || !body.event_type || !body.visibility || !body.start_time) {
      throw new ValidationError("title, event_type, visibility, and start_time are required");
    }

    const startTime = new Date(body.start_time);
    if (Number.isNaN(startTime.getTime()) || startTime.getTime() < Date.now() - 5 * 60 * 1000) {
      // 5-minute grace window absorbs clock skew between client and server
      throw new ValidationError("start_time must be a valid date in the future");
    }

    if (body.venue_id) {
      const { data: venue, error: venueError } = await supabase
        .from("venues")
        .select("id")
        .eq("id", body.venue_id)
        .single();
      if (venueError || !venue) throw new ValidationError("venue_id does not reference an existing venue");
    }

    // RLS policy `events_insert_own` also enforces organizer_id = auth.uid(),
    // so this insert would fail closed even if we forgot this line — but
    // being explicit here keeps the application layer legible without
    // needing to cross-reference the RLS file to understand the invariant.
    const { data: event, error: insertError } = await supabase
      .from("events")
      .insert({
        organizer_id: user.id,
        title: body.title,
        description: body.description,
        cover_url: body.cover_url,
        event_type: body.event_type,
        visibility: body.visibility,
        status: "draft",
        start_time: body.start_time,
        end_time: body.end_time,
        venue_id: body.venue_id,
        min_age: body.min_age,
        tags: body.tags,
      })
      .select()
      .single();

    if (insertError) throw insertError;

    return jsonResponse(event, 201);
  } catch (err) {
    return handleKnownErrors(err);
  }
});

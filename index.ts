// supabase/functions/staff-checkin/index.ts
//
// POST /staff-checkin
// Distinct from `/checkins` (checkins/index.ts): that function assumes the
// CALLER is the ticket holder checking themselves in (self-service, via
// geofence or their own QR). This function is for the opposite case — an
// organizer or their door staff scans an ATTENDEE'S ticket QR on a
// separate device. The auth model is different: the caller's identity
// (organizer) is unrelated to whose check_ins row gets created (the
// attendee decoded from the QR token), so this needed its own function
// rather than a branch inside `/checkins` — reusing that function would
// mean either weakening its "you can only check yourself in" invariant or
// bolting on a second auth path that's easy to get wrong under time
// pressure (see the design note in mobile/itango's check_in_screen.dart
// for the original reasoning this function completes).

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, ConflictError, CORS_HEADERS } from "../_shared/http.ts";
import { verifyQrToken } from "../checkins/qr.ts";
import { reportError } from "../_shared/sentry.ts";

interface StaffCheckInBody {
  qr_token: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabase = getUserScopedClient(req);
    const staffUser = await requireAuthenticatedUser(req, supabase);
    const body: StaffCheckInBody = await req.json();

    if (!body.qr_token) throw new ValidationError("qr_token is required");

    const decoded = await verifyQrToken(body.qr_token, Deno.env.get("QR_SIGNING_SECRET")!);

    // Verify the caller is either the organizer of this event or an
    // admin/moderator — NOT via a client-supplied claim, via an actual
    // query against events.organizer_id and user_roles, same pattern as
    // every other privileged action in this backend (e.g. admin_ban_user
    // in migration 015).
    const { data: event, error: eventError } = await supabase
      .from("events")
      .select("id, title, organizer_id, status")
      .eq("id", decoded.eventId)
      .single();

    if (eventError || !event) throw new ValidationError("Event not found");

    const { data: isPrivileged } = await supabase.rpc("is_admin_or_moderator", { p_user_id: staffUser.id });
    if (event.organizer_id !== staffUser.id && !isPrivileged) {
      throw new ValidationError("You are not authorized to check attendees into this event");
    }

    if (!["published", "live"].includes(event.status)) {
      throw new ValidationError("This event is not currently open for check-in");
    }

    // Verify the ticket purchase this QR represents is actually paid — a
    // token can be validly signed (issued at purchase time) but the
    // purchase itself may have since been refunded/cancelled.
    const { data: purchase, error: purchaseError } = await supabase
      .from("ticket_purchases")
      .select("id, status, user_id, tickets!inner(event_id)")
      .eq("id", decoded.ticketPurchaseId)
      .single();

    if (purchaseError || !purchase) throw new ValidationError("Ticket not found");
    if (purchase.status !== "paid") throw new ValidationError(`This ticket is ${purchase.status}, not valid for entry`);
    if ((purchase as any).tickets.event_id !== decoded.eventId) throw new ValidationError("Ticket does not match this event");
    if (purchase.user_id !== decoded.userId) throw new ValidationError("Ticket does not match the QR token's holder");

    // Insert the check-in on behalf of the attendee, with verified_by set
    // to the staff member — this is exactly the `manual_organizer`-style
    // attribution the check_ins schema already supports (migration 003),
    // just reached via a scanned QR rather than a manual dashboard action.
    const { data: checkIn, error: insertError } = await supabase
      .from("check_ins")
      .insert({
        event_id: decoded.eventId,
        user_id: decoded.userId,
        method: "qr",
        verified_by: staffUser.id,
      })
      .select("id")
      .single();

    if (insertError) {
      if (insertError.code === "23505") {
        throw new ConflictError("This attendee has already been checked in");
      }
      throw insertError;
    }

    const { data: attendeeProfile } = await supabase
      .from("profiles")
      .select("display_name, username, avatar_url")
      .eq("id", decoded.userId)
      .single();

    return jsonResponse({
      check_in_id: checkIn.id,
      attendee: attendeeProfile,
      event_title: event.title,
    }, 201);
  } catch (err) {
    await reportError(err, { function: "staff-checkin" });
    return handleKnownErrors(err);
  }
});

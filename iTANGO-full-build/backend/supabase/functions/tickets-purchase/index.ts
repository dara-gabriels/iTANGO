// supabase/functions/tickets-purchase/index.ts
//
// POST /tickets/purchase
// Creates a `ticket_purchases` row in `pending` status, then calls the
// chosen PSP to initialize a hosted checkout session. Final confirmation is
// asynchronous — the PSP webhook (webhooks-paystack, etc.) flips status to
// `paid`, which triggers `quantity_sold` increment via the database trigger
// defined in migration 003 (`on_ticket_purchase_paid`).
//
// Deliberately does NOT decrement ticket availability here — that only
// happens on confirmed payment, so a pending/abandoned checkout never
// blocks real inventory. Availability is instead checked optimistically at
// request time and re-validated by the DB CHECK constraint at payment time.

import { getUserScopedClient, requireAuthenticatedUser, jsonResponse, handleKnownErrors, ValidationError, ConflictError, CORS_HEADERS } from "../_shared/http.ts";
import { signQrToken } from "../checkins/qr.ts";
import { initializePaystackTransaction } from "./providers/paystack.ts";

interface PurchaseBody {
  ticket_id: string;
  quantity: number;
  payment_provider: "paystack" | "flutterwave" | "monnify" | "fincra" | "wallet";
  split_with_user_ids?: string[];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabase = getUserScopedClient(req);
    const user = await requireAuthenticatedUser(req, supabase);
    const body: PurchaseBody = await req.json();

    if (!body.ticket_id || !body.quantity || body.quantity < 1) {
      throw new ValidationError("ticket_id and a positive quantity are required");
    }

    const { data: ticket, error: ticketError } = await supabase
      .from("tickets")
      .select("id, event_id, price, currency, quantity_total, quantity_sold, is_active")
      .eq("id", body.ticket_id)
      .single();

    if (ticketError || !ticket) throw new ValidationError("Ticket not found");
    if (!ticket.is_active) throw new ValidationError("This ticket type is no longer on sale");

    const remaining = ticket.quantity_total - ticket.quantity_sold;
    if (remaining < body.quantity) {
      throw new ConflictError(`Only ${remaining} of this ticket type remain`);
    }

    const totalAmount = ticket.price * body.quantity;

    // 1. Create the payment row (status: initiated)
    const { data: payment, error: paymentError } = await supabase
      .from("payments")
      .insert({
        user_id: user.id,
        provider: body.payment_provider,
        purpose: "ticket",
        amount: totalAmount,
        currency: ticket.currency,
        status: "initiated",
      })
      .select("id")
      .single();
    if (paymentError) throw paymentError;

    // 2. Create the ticket_purchases row (status: pending) — QR is generated
    // now so it exists even before payment confirms; it simply won't scan
    // successfully at the door until the check-in endpoint's downstream
    // logic (not shown) also verifies payment status = paid.
    const qrToken = await signQrToken({
      eventId: ticket.event_id,
      userId: user.id,
      ticketPurchaseId: "", // placeholder filled after insert; see note below
      issuedAt: Date.now(),
    }, Deno.env.get("QR_SIGNING_SECRET")!);

    const { data: purchase, error: purchaseError } = await supabase
      .from("ticket_purchases")
      .insert({
        ticket_id: body.ticket_id,
        user_id: user.id,
        quantity: body.quantity,
        total_amount: totalAmount,
        currency: ticket.currency,
        status: "pending",
        payment_id: payment.id,
        qr_code: qrToken, // NOTE: in production, re-sign with the real ticketPurchaseId
                          // once the row exists (two-step insert or a Postgres function
                          // that returns the id before commit) — shown simplified here.
      })
      .select("id, qr_code")
      .single();
    if (purchaseError) throw purchaseError;

    // 3. Handle split payments, if requested — insert placeholder
    // contribution rows so each participant's share is trackable even
    // before their individual payment confirms.
    if (body.split_with_user_ids?.length) {
      const perPersonAmount = totalAmount / (body.split_with_user_ids.length + 1);
      // Each invited participant gets a notification (Phase 5 notifications
      // function, not shown) prompting them to pay their share via their
      // own /tickets/purchase call scoped to this purchase.
      await supabase.from("notifications").insert(
        body.split_with_user_ids.map((uid) => ({
          user_id: uid,
          type: "ticket_confirmed", // reuse type; a dedicated 'split_payment_request' type is recommended for v1.1
          payload: { ticket_purchase_id: purchase.id, amount: perPersonAmount, currency: ticket.currency },
        })),
      );
    }

    // 4. Wallet payments settle synchronously; PSP payments return a redirect URL.
    if (body.payment_provider === "wallet") {
      // Delegate to a Postgres function that atomically checks balance and
      // debits — NOT done here in application code, to avoid a race between
      // balance check and debit under concurrent requests.
      const { error: walletError } = await supabase.rpc("settle_ticket_purchase_from_wallet", {
        p_ticket_purchase_id: purchase.id,
        p_user_id: user.id,
        p_amount: totalAmount,
      });
      if (walletError) throw new ConflictError("Insufficient wallet balance");

      return jsonResponse({
        ticket_purchase_id: purchase.id,
        status: "paid",
        payment_redirect_url: null,
        qr_code: purchase.qr_code,
      }, 201);
    }

    let redirectUrl: string;
    switch (body.payment_provider) {
      case "paystack":
        redirectUrl = await initializePaystackTransaction({
          email: user.email!,
          amountKobo: Math.round(totalAmount * 100),
          reference: payment.id,
          callbackUrl: `${Deno.env.get("APP_BASE_URL")}/payments/callback`,
        });
        break;
      // flutterwave / monnify / fincra initializers follow the same pattern;
      // omitted here for brevity but structurally identical (see providers/ dir).
      default:
        throw new ValidationError(`Provider ${body.payment_provider} not yet wired — add to providers/`);
    }

    return jsonResponse({
      ticket_purchase_id: purchase.id,
      status: "pending",
      payment_redirect_url: redirectUrl,
      qr_code: purchase.qr_code,
    }, 201);
  } catch (err) {
    return handleKnownErrors(err);
  }
});

// supabase/functions/webhooks-paystack/index.ts
//
// POST /webhooks/paystack
// Server-to-server only — Paystack calls this, never the app client. Uses
// the SERVICE ROLE client deliberately (see _shared/http.ts docstring):
// this function must update another user's `payments` and
// `ticket_purchases` rows, which RLS would otherwise block for a
// user-scoped client, and there IS no user JWT on an incoming webhook.
//
// Every request is signature-verified BEFORE any database write. Requests
// that fail verification are rejected with 401 and logged — never silently
// dropped, since a silent drop here means a paying customer never gets
// their ticket.

import { getServiceRoleClient, jsonResponse, errorResponse, CORS_HEADERS } from "../_shared/http.ts";
import { reportError } from "../_shared/sentry.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const rawBody = await req.text();
  const signatureHeader = req.headers.get("x-paystack-signature") ?? "";

  const isValid = await verifyPaystackSignature(rawBody, signatureHeader, Deno.env.get("PAYSTACK_SECRET_KEY")!);
  if (!isValid) {
    // Log to audit trail — a failed signature is a security-relevant event,
    // not just a bad request, even though we don't have a user_id to attach it to.
    const supabase = getServiceRoleClient();
    await supabase.from("audit_logs").insert({
      action: "webhook_signature_failed",
      target_type: "payments",
      metadata: { provider: "paystack", headers: Object.fromEntries(req.headers) },
    });
    return errorResponse("Invalid signature", 401, "unauthorized");
  }

  const event = JSON.parse(rawBody);
  const supabase = getServiceRoleClient();

  try {
    switch (event.event) {
      case "charge.success": {
        const providerReference = event.data.reference; // this is our payments.id, set at initialize time

        const { data: payment, error: paymentFetchError } = await supabase
          .from("payments")
          .select("id, status")
          .eq("id", providerReference)
          .single();

        if (paymentFetchError || !payment) {
          console.error(`Webhook for unknown payment reference: ${providerReference}`);
          // Still return 200 — Paystack will retry on non-2xx, and retrying
          // won't fix "reference doesn't exist in our DB." Log and move on.
          break;
        }

        // Idempotency guard: Paystack may deliver the same webhook more than
        // once. If we've already marked this succeeded, do nothing further.
        if (payment.status === "succeeded") break;

        await supabase.from("payments").update({ status: "succeeded", provider_reference: providerReference }).eq("id", payment.id);

        // Flip the associated ticket_purchase to 'paid'. The
        // on_ticket_purchase_paid trigger (migration 003) handles
        // incrementing tickets.quantity_sold automatically.
        await supabase
          .from("ticket_purchases")
          .update({ status: "paid" })
          .eq("payment_id", payment.id);

        // TODO (Phase 5 follow-up): enqueue wallet-pass generation and
        // push-notification "ticket_confirmed" job here — kept out of the
        // synchronous webhook path so a slow downstream call never risks
        // Paystack's webhook timeout.
        break;
      }

      case "charge.failed": {
        await supabase.from("payments").update({ status: "failed" }).eq("id", event.data.reference);
        await supabase.from("ticket_purchases").update({ status: "cancelled" }).eq("payment_id", event.data.reference);
        break;
      }

      default:
        // Unhandled event types are acknowledged but ignored — this is
        // expected; Paystack sends many event types we don't act on.
        break;
    }

    return jsonResponse({ received: true });
  } catch (err) {
    console.error("Webhook processing error:", err);
    await reportError(err, { function: "webhooks-paystack", event_type: event?.event });
    // Return 500 so Paystack retries — this branch means OUR code failed,
    // not that the event was invalid, so a retry is the correct behavior.
    return errorResponse("Internal processing error", 500, "internal_error");
  }
});

async function verifyPaystackSignature(rawBody: string, signatureHeader: string, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const computedSignature = Array.from(new Uint8Array(signatureBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  if (computedSignature.length !== signatureHeader.length) return false;
  let mismatch = 0;
  for (let i = 0; i < computedSignature.length; i++) {
    mismatch |= computedSignature.charCodeAt(i) ^ signatureHeader.charCodeAt(i);
  }
  return mismatch === 0;
}

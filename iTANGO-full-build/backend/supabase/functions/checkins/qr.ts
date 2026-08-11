// supabase/functions/checkins/qr.ts
//
// QR tickets embed a signed token (HMAC-SHA256), generated at ticket-purchase
// time (see tickets-purchase function) and printed into the QR code image.
// Verifying it here — rather than trusting a plain ticket_purchase_id — means
// a screenshot of someone else's QR can't be reused: the token is bound to
// (event_id, user_id, ticket_purchase_id) and signed, so tampering invalidates it.

export interface QrPayload {
  eventId: string;
  userId: string;
  ticketPurchaseId: string;
  issuedAt: number;
}

export async function verifyQrToken(token: string, secret: string): Promise<QrPayload> {
  const [payloadB64, signature] = token.split(".");
  if (!payloadB64 || !signature) {
    throw new Error("Malformed QR token");
  }

  const expectedSignature = await hmacSha256Hex(payloadB64, secret);
  if (!timingSafeEqual(expectedSignature, signature)) {
    throw new Error("QR token signature invalid — possible tampering");
  }

  const payload = JSON.parse(atob(payloadB64)) as QrPayload;

  const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  if (Date.now() - payload.issuedAt > ONE_YEAR_MS) {
    throw new Error("QR token expired");
  }

  return payload;
}

export async function signQrToken(payload: QrPayload, secret: string): Promise<string> {
  const payloadB64 = btoa(JSON.stringify(payload));
  const signature = await hmacSha256Hex(payloadB64, secret);
  return `${payloadB64}.${signature}`;
}

async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(signatureBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Constant-time string comparison — avoids leaking signature validity via timing. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

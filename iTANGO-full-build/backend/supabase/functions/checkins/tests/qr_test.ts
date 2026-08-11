// backend/supabase/functions/checkins/tests/qr_test.ts
//
// Run via: deno test --allow-env backend/supabase/functions/checkins/tests/qr_test.ts
//
// Tests the actual cryptographic behavior, not just "does it return a
// string" — a QR signing test suite that doesn't try to forge a token is
// not testing the thing that matters about a signing scheme.

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { signQrToken, verifyQrToken } from "../qr.ts";

const TEST_SECRET = "test-secret-do-not-use-in-production";

Deno.test("signs and verifies a valid token round-trip", async () => {
  const payload = {
    eventId: "event-123",
    userId: "user-456",
    ticketPurchaseId: "purchase-789",
    issuedAt: Date.now(),
  };

  const token = await signQrToken(payload, TEST_SECRET);
  const decoded = await verifyQrToken(token, TEST_SECRET);

  assertEquals(decoded.eventId, payload.eventId);
  assertEquals(decoded.userId, payload.userId);
  assertEquals(decoded.ticketPurchaseId, payload.ticketPurchaseId);
});

Deno.test("rejects a token signed with a different secret", async () => {
  const token = await signQrToken(
    { eventId: "event-123", userId: "user-456", ticketPurchaseId: "purchase-789", issuedAt: Date.now() },
    TEST_SECRET,
  );

  await assertRejects(
    () => verifyQrToken(token, "wrong-secret"),
    Error,
    "signature invalid",
  );
});

Deno.test("rejects a token with a tampered payload (bit-flip attack)", async () => {
  const token = await signQrToken(
    { eventId: "event-123", userId: "user-456", ticketPurchaseId: "purchase-789", issuedAt: Date.now() },
    TEST_SECRET,
  );

  const [payloadB64, signature] = token.split(".");
  // Decode, change the userId to someone else's, re-encode — simulating an
  // attacker trying to reuse Alice's ticket QR under Bob's identity by
  // editing the payload without knowing the signing secret.
  const decoded = JSON.parse(atob(payloadB64));
  decoded.userId = "attacker-999";
  const tamperedPayloadB64 = btoa(JSON.stringify(decoded));
  const tamperedToken = `${tamperedPayloadB64}.${signature}`;

  await assertRejects(
    () => verifyQrToken(tamperedToken, TEST_SECRET),
    Error,
    "signature invalid",
  );
});

Deno.test("rejects a malformed token (missing signature segment)", async () => {
  await assertRejects(
    () => verifyQrToken("not-a-real-token", TEST_SECRET),
    Error,
    "Malformed",
  );
});

Deno.test("rejects a token older than one year", async () => {
  const oneYearAndADayAgo = Date.now() - 366 * 24 * 60 * 60 * 1000;
  const token = await signQrToken(
    { eventId: "event-123", userId: "user-456", ticketPurchaseId: "purchase-789", issuedAt: oneYearAndADayAgo },
    TEST_SECRET,
  );

  await assertRejects(
    () => verifyQrToken(token, TEST_SECRET),
    Error,
    "expired",
  );
});

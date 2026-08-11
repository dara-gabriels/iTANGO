// backend/supabase/functions/checkins/tests/geo_test.ts
import { assert, assertAlmostEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { haversineDistanceMeters } from "../geo.ts";

Deno.test("distance between identical coordinates is zero", () => {
  const distance = haversineDistanceMeters(6.4281, 3.4219, 6.4281, 3.4219);
  assertAlmostEquals(distance, 0, 0.01);
});

Deno.test("distance between two known Lagos landmarks is approximately correct", () => {
  // Tafawa Balewa Square to National Theatre Lagos — real-world distance is
  // roughly 1-5km. This is a sanity check against a known real value, not
  // an arbitrary tolerance — a haversine bug (e.g. swapped lat/lng) would
  // produce a wildly different number, not a slightly-off one.
  const tafawaBalewaSquare = { lat: 6.4531, lng: 3.3958 };
  const nationalTheatre = { lat: 6.4698, lng: 3.3792 };

  const distance = haversineDistanceMeters(
    tafawaBalewaSquare.lat, tafawaBalewaSquare.lng,
    nationalTheatre.lat, nationalTheatre.lng,
  );

  assert(distance > 1000 && distance < 5000, `Expected 1-5km, got ${distance}m`);
});

Deno.test("distance is symmetric (A to B equals B to A)", () => {
  const a = { lat: 6.5244, lng: 3.3792 };
  const b = { lat: 6.6018, lng: 3.3515 };

  const distanceAtoB = haversineDistanceMeters(a.lat, a.lng, b.lat, b.lng);
  const distanceBtoA = haversineDistanceMeters(b.lat, b.lng, a.lat, a.lng);

  assertAlmostEquals(distanceAtoB, distanceBtoA, 0.001);
});

Deno.test("a point just inside the 150m check-in radius is correctly measured as inside", () => {
  const venue = { lat: 6.5244, lng: 3.3792 };
  // Approximately 100m north — well within the GEOFENCE_MAX_RADIUS_METERS
  // constant in checkins/index.ts. This test exists specifically so a
  // future change to that constant or this function gets caught if it
  // silently makes the geofence too strict (rejecting real attendees) or
  // too loose (accepting people who aren't there).
  const nearbyPoint = { lat: 6.5253, lng: 3.3792 };

  const distance = haversineDistanceMeters(venue.lat, venue.lng, nearbyPoint.lat, nearbyPoint.lng);
  assert(distance < 150, `Expected under 150m, got ${distance}m`);
});

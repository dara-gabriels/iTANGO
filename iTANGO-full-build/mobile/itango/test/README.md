# mobile/itango/test/ — Test Suite

## Running

```bash
flutter test
```

## Coverage in this pass

| File | Tests |
|---|---|
| `features/auth/auth_controller_test.dart` | Phone OTP state machine: send/verify success paths, and specifically that raw Supabase error text never leaks to the UI (each error-message mapping asserted individually, not just "is an error state") |
| `features/events/purchase_controller_test.dart` | Ticket purchase state machine: PSP redirect path, synchronous wallet settlement path, server-error-message passthrough, network-failure fallback |
| `widgets/itango_gradient_button_test.dart` | The shared brand CTA button: renders label, fires callback exactly once per tap, conditionally renders its icon, and asserts the *actual brand gradient* is applied (not just "some decoration exists") |

## Deliberate gap: `CheckInController` has no unit test

Explained in the comment at the top of `purchase_controller_test.dart`:
`CheckInController.checkIn()` calls `Geolocator.getCurrentPosition()`
directly, which hits a real platform channel. A unit test that doesn't
actually drive that call (e.g. only testing what happens *after* a
response is received) would pass without testing the part that most often
breaks in the real world — location permission denied, location services
off, GPS timeout. The honest options are:

1. Refactor `CheckInController` to accept an injected position-provider function (dependency inversion), making it trivially mockable — the cleaner long-term fix.
2. Write an integration test using `geolocator`'s platform-mocking utilities, which exercises the real code path but needs a device/emulator, not a pure `flutter test` run.

Neither is done in this pass. Shipping a test that only *looks* like it
covers this controller would be worse than this documented gap.

## What else isn't covered yet (Phase 14 scope, not exhaustive here)

- Widget tests for full screens (LoginScreen, EventDetailScreen, etc.) — the
  gradient button test above is a template for the pattern; extending it to
  full screens (with Riverpod provider overrides for each data dependency)
  is mechanical but not yet done for every screen.
- Integration tests (`integration_test/`, already a dependency in
  `pubspec.yaml`) driving a real device/simulator through the full
  discover → buy → check-in → chat loop — the single highest-value test
  this app could have, and the one requiring the most setup (a running
  Supabase instance with seeded test data), so it's appropriately a
  dedicated follow-up rather than squeezed into this pass.

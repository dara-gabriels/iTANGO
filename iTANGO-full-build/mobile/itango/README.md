# iTANGO Mobile (Flutter)

## What's real vs. stubbed

**Real, wired end-to-end:**
- App bootstrap (`main.dart`) — Supabase + Firebase + Sentry init, Riverpod, dark-first theme
- Router with auth-state redirect guard AND `onboarding_completed` enforcement (`core/router/app_router.dart`)
- Phone OTP auth flow — send code, verify code, friendly error mapping (`features/auth/`)
- App shell with the confirmed 5-slot bottom nav, including the inline gradient Create FAB (`features/home/presentation/app_shell.dart`)
- **Home** — calls the real `nearby_events` Postgres RPC, with loading/empty/error states, and a real unread-notification badge on the bell icon
- **Discover** — calls `discover_people` RPC, vibe-tag filter chips backed by the real `vibe_tag_name` enum, "Say Hi" writes a real DM
- **Chats** — Stories row (tappable, opens the real full-screen viewer), Highlights row, Event Rooms list (joined against `room_engagement_snapshots` for the live 🔥 temperature indicator), Direct Messages list
- **Profile** — Passport layout: energy score badge with "Top 5%" cohort check, Voucher Wallet, Achievements grid
- **Event detail → ticket purchase → check-in → event chat** — the full consumer core loop, including the PSP redirect flow and geofence self-check-in (see the design note at the top of `check_in_screen.dart` for why geofence, not QR-scanning, is the correct consumer-app flow)
- **Conversation thread screen** — real Supabase Realtime message stream + composer, **image attachments, voice notes (real recording + playback), emoji reactions, and DM read receipts ("Seen"/"Delivered")**. Media is private (signed URLs, not public links) — see the Storage RLS policy in `database/migrations/018_message_media_storage_rls.sql`.
- **Onboarding** — 4-step flow writing real rows to `profiles` and `user_vibe_tags`
- **Push notifications** — FCM token registration/refresh, real-time in-app notification list, live unread badge
- **Story viewer** — full-screen, auto-advancing, tap-to-navigate, with a working reply-to-DM action
- **Story creator** — camera/gallery capture, caption, "Add to Story" vs. "Save to Highlights" (uploads to the `story-media` Storage bucket — see `devops/scripts/setup-supabase-projects.md` §3 for the one-time bucket setup this depends on)

**Still stubbed:**
- Full Google/Apple sign-in verification end-to-end, and biometric login (`local_auth` is in `pubspec.yaml`, not yet wired to a screen)
- Video attachments in messages (image + voice notes are real; video capture/playback in chat is not)
- Live cross-participant reaction updates (your own reactions update instantly; a reaction added by someone else needs a reload — see the note in `conversation_screen.dart`)

Organizer-side staff QR check-in is real, but lives on the **web** organizer dashboard (`web/itango-web/.../organizer/events/[eventId]/checkin/`), not in this mobile app — a door-staff member scans attendee tickets from a browser, not from the consumer app.

This means the MVP's core social loop — discover, message, buy a ticket, check in, use event chat, post/view stories, see your own status, get onboarded, receive notifications — is functional against the real backend end to end.

## Testing

See `test/README.md` for what's covered (auth state machine, purchase state machine, a widget test for the shared brand button) and — just as importantly — what's a **documented gap rather than a faked test** (`CheckInController` isn't unit-tested because it hits a real platform channel; see that README for why a superficial test there would be worse than no test).

```bash
flutter test
```

## Store submission

See `store-assets/STORE_SUBMISSION_SETUP.md` for the full checklist. Fastlane
lanes exist for both platforms (`android/fastlane/Fastfile`,
`ios/fastlane/Fastfile`) and are wired into `.github/workflows/mobile-release.yml`,
but **cannot run** until real Apple/Google developer accounts and signing
credentials exist — that setup is manual and outside what this build pass
can create on your behalf.

## Native permissions required (not yet added to platform manifests)

Voice notes (`record` package) need microphone permission declared natively —
this build pass added the Dart-side recording code but **not** the platform
manifest entries, since those live in `android/app/src/main/AndroidManifest.xml`
and `ios/Runner/Info.plist`, which aren't part of the Dart source tree this
pass generated:

- **Android**: add `<uses-permission android:name="android.permission.RECORD_AUDIO" />`
- **iOS**: add `NSMicrophoneUsageDescription` with a user-facing reason string (e.g. "iTANGO needs microphone access to record voice notes.")

Without these, `_recorder.hasPermission()` in `conversation_screen.dart` will
always return false and the mic button will silently do nothing — flagging
this explicitly so it isn't a confusing runtime mystery.

## Setup

```bash
flutter pub get
cp .env.example .env   # fill in your Supabase project URL, anon key, Sentry DSN
flutter run
```

## Brand note

The wordmark uses **Playfair Display** (serif) to match the official iTANGO logo; all other UI text uses **Inter**. Brand primary color is deep crimson (`#9E1B23`), reconciled from the logo.

## Next build pass

1. Full Google/Apple sign-in verification end-to-end, plus biometric login
2. Add the native manifest permission entries noted above (microphone), and video attachments in chat
3. `CheckInController` refactor to accept an injected position-provider, enabling a real unit test (see `test/README.md`)
4. Video stories (creator currently supports images only — `image_picker` is wired, video capture/playback is not)
5. Cross-participant live reaction updates (currently requires a reload to see reactions added by other people)

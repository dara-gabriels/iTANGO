# iTANGO Web (Next.js)

## What's real vs. stubbed

**Real, wired end-to-end:**
- Supabase browser + server clients (`src/lib/supabase/`)
- Middleware that refreshes the session cookie and redirects based on auth state (`src/middleware.ts`)
- Phone OTP login page, matching the Flutter app's logic exactly (`src/app/(auth)/login/page.tsx`)
- **Public event detail page as a true Server Component** (`src/app/events/[eventId]/page.tsx`) — this is the architecturally important one: it's server-rendered specifically so search engines and social-link unfurlers (WhatsApp/Twitter previews) see real content, not an empty SPA shell. This is *why* Next.js was chosen over a pure SPA in the original tech stack decision (Master Plan §3/§6) — this page is that decision made concrete.
- **Organizer Dashboard** (`src/app/organizer/`) — events list with aggregate revenue/tickets-sold per event, a create-event form calling the real Phase 5 Edge Function, and a per-event sales/attendee detail page. Ownership is double-checked server-side (not just relying on RLS) before rendering another organizer's numbers — see the comment in `organizer/events/[eventId]/page.tsx`.

**Not yet built:** the authenticated `/home` feed (consumer web experience), business/moderator/admin dashboards (Phase 9 proper), and ticket-type creation UI within the organizer dashboard (flagged explicitly on the event detail page rather than silently missing — tickets can be added via the `tickets` table today).

## Setup

```bash
npm install
cp .env.example .env.local   # fill in Supabase URL + anon key
npm run dev
```

## Brand note

Same reconciliation as the Flutter app: `font-wordmark` (Playfair Display) for the "iTango" logotype and headline moments, `font-sans` (Inter) everywhere else. Brand primary is deep crimson (`#9E1B23`), not the earlier pink/violet.

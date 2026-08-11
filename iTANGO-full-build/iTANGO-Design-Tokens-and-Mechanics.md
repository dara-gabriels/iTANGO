# iTANGO — Design Tokens & Confirmed Product Mechanics
**Source:** Extracted from live Figma Make screens (Onboarding, Home, Discover, Create Event, Chats, Event Chat Room, Profile)
**Purpose:** Ground Phase 3 (Design System) and update Phase 1 (PRD) with what's actually built, not just what was specified.

---

## 1. Confirmed Color Palette

| Token | Approx. Hex | Usage observed |
|---|---|---|
| `color.bg.base` | `#0A0A0F` – `#0D0D14` | App background, near-black with slight blue/purple undertone |
| `color.bg.surface` | `#15151F` – `#1A1A24` | Cards, sheets, modals |
| `color.brand.gradient.start` | `#FF2D8A` (hot pink) | Primary gradient start — CTAs, LIVE badges, FAB |
| `color.brand.gradient.end` | `#8B3DFF` (violet) | Primary gradient end |
| `color.accent.cyan` | `#22D3EE` | Secondary CTA (e.g. "Join Activity" on Happy Hour card), info badges |
| `color.accent.amber` | `#FBBF24` / `#F59E0B` | Currency (₦), streak/energy icon, "HOT" badge |
| `color.accent.emerald` | `#34D399` | "Networking" tag, positive/success states, checked-in confirmation |
| `color.text.primary` | `#FFFFFF` | Headlines, primary labels |
| `color.text.secondary` | `#9CA3AF` – `#A1A1AA` | Timestamps, meta text, placeholders |
| `color.status.live` | `#FF2D55` (red-pink) | "LIVE" pill badges |
| `color.status.warmth.hot` | gradient pink→amber | "On Fire" room-temperature indicator |
| `color.status.warmth.warm` | amber→orange | "Heated" room-temperature indicator |

**Pattern:** iTANGO uses a **dual-gradient system** — pink→violet as the primary brand gradient (CTAs, live indicators, FAB), and a secondary cyan used specifically to differentiate a *second* action on the same screen (e.g., two competing "Join Activity" buttons in different colors so they read as distinct options, not duplicates).

---

## 2. Typography

| Token | Observed style |
|---|---|
| `type.display` | Bold, ~28–32px, tight leading — onboarding headline ("Discover What's Popping Tonight") |
| `type.heading` | Bold, ~18–20px — section titles ("My Events", "Achievements", "Discover People") |
| `type.body` | Regular, ~14–15px, `color.text.secondary` for supporting copy |
| `type.label` | Semibold, ~12–13px, uppercase tracking — field labels ("EVENT NAME", "VENUE"), stat labels |
| `type.numeric` | Bold, tabular — stat counts (127 Events, 342 Friends), currency, energy score |

Font is a rounded/geometric sans (visually consistent with Inter, General Sans, or similar) — recommend **Inter** as the production typeface for cross-platform parity (excellent Flutter + web + Figma support, wide language coverage for Nigerian/African markets).

---

## 3. Component Patterns Confirmed

- **Pill buttons with gradient fill** — primary CTA shape throughout (Next, Say Hi, Join Activity, Create Event)
- **Badge-on-avatar pattern** — every avatar can carry a small corner badge: live-status ring, energy score chip, or verification star
- **Bottom sheet / stepper modals** — Create Event uses a 3-step horizontal progress stepper (Basics → Tickets → Boost) inside a sheet, not a full-screen flow
- **Floating Action Button (FAB)** — persistent pink circular "+" bottom-right, context-aware (creates a post on Home, an event on the Events context)
- **Story ring pattern** — gradient ring around avatar = unviewed story, matches Instagram/Snapchat convention
- **Progress/temperature bars** — thin horizontal gradient bars used for two distinct meanings: (a) onboarding pagination, (b) room "engagement temperature" — same visual language reused for different semantics, worth disambiguating with color in production (pagination = neutral gray/white dots; temperature = pink-to-red gradient)
- **Inline system messages** — green checkmark card ("You're in the room!") for state-change confirmations inside chat, distinct from regular messages

---

## 4. Bottom Navigation (confirmed structure — supersedes brief's "2 tabs")

| Position | Tab | Icon | Purpose |
|---|---|---|---|
| 1 | Home | House | Blended feed: live events near you + social posts |
| 2 | Discover | Compass | Peer discovery — vibe-tag-based people matching |
| 3 | Create (FAB) | + in filled circle | Context-aware create action (event, post, story) |
| 4 | Chats | Speech bubble | DMs + Event Rooms (check-in-gated group chat) + Stories |
| 5 | Profile | Person | Passport-style profile: energy score, wallet, achievements |

**Recommendation:** adopt this 5-tab structure as the source of truth going forward; it's more differentiated than a generic 2-tab Home and it's already designed.

---

## 5. New/Revised Data Entities This Implies (for Phase 4)

Beyond the original schema scope, these screens require:

1. **`energy_scores`** — user_id, current_score, rolling_delta, percentile_rank, computed_at (needs a scheduled recompute job, not just a stored column, since "Top 5% this month" is a cohort-relative rank)
2. **`check_ins`** — user_id, event_id, method (QR/geofence), checked_in_at — this table *gates* access to `event_chat_rooms`, so RLS policy on chat room membership must join against it
3. **`vouchers`** and **`voucher_redemptions`** — issuer (venue/business_id), value, expiry, redemption status — ledgered like payments, not just a flag
4. **`vibe_tags`** — enum-like table (Turnt / Chill / Networking / …), many-to-many with users for the Discover filter counts
5. **`room_engagement_snapshots`** — a Redis-backed rolling metric (messages/min, reactions/min) that periodically persists to Postgres for the "On Fire / Heated" states — this is explicitly a cache-first, not DB-first, data flow
6. **`achievements`** and **`user_achievements`** — badge definitions + earned records (Night Owl, VIP Status, Social Butterfly, etc.)

These are now folded into the Phase 4 database plan rather than being generic "gamification" placeholders.

---

## 6. Immediate Recommendation

Given these assets, the most efficient next step is to **merge Phase 1 and Phase 3 into one working session**: finalize the PRD with these confirmed mechanics (Energy Score, check-in-gated chat, voucher economy) as named, prioritized features, and simultaneously lock the token set above into a real, coded design system (Flutter `ThemeData` + Tailwind config) — since both now have solid ground truth instead of assumptions.

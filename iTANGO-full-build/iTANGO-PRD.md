# iTANGO — Product Requirements Document (PRD)
Version 1.0 | Phase 1: Product Discovery | Status: Draft for approval

---

## 1. Problem Statement

Young, urban Africans (starting with Nigeria) have no single app that answers "what's happening tonight, who's going, and can I get in" — they currently stitch together Instagram stories (discovery), WhatsApp groups (coordination), Twitter/X (buzz), and word of mouth (trust). Eventbrite-style tools exist for ticketing but have no social layer; social apps have no event-commerce layer. iTANGO closes that gap by making the **event** — not the profile or the post — the organizing unit of the social graph.

## 2. Target Users (confirmed by design, refined from brief)

| Persona | Who | Core need |
|---|---|---|
| **The Regular** | 20s, goes out 2–4x/month, already has a friend group | Wants to know what's live *right now* nearby, coordinate with friends, and build status (Energy Score, "Top 5%") |
| **The Connector** | Attends solo or semi-solo, wants to meet people | Uses Discover's vibe tags (Turnt/Chill/Networking) to find compatible people at the same event |
| **The Organizer** | Promoter or small event host | Needs to create, ticket, and market an event, and see live sales/attendee data |
| **The Venue/Business** | Nightclub, lounge, restaurant | Wants foot traffic — funds vouchers, promotes events, claims a business profile |
| **The Verified Regular** | High Energy Score users | Cares about status, badges, and voucher perks — the retention engine |

## 3. Product Pillars (in priority order)

1. **Discover what's live right now** — Home feed blending nearby live events + social posts, with real-time attendance counts.
2. **Prove you were there** — check-in (QR/geofence) is the gate to event chat rooms and to Energy Score gains; this is the core trust mechanic that differentiates iTANGO from a generic event app.
3. **Meet people, safely, by vibe** — Discover screen matches by stated intent (Turnt/Chill/Networking), not swipe-first dating.
4. **Build status** — Energy Score, achievements, "Top 5%" cohort ranking, Voucher Wallet — a visible progression system.
5. **Transact without friction** — ticketing, VIP tables, split payments, vouchers, all through one wallet, across PSPs that actually work in Nigeria.

## 4. MVP Scope (v1) — MoSCoW

### Must Have
- Auth: phone OTP, email, Google, Apple
- Onboarding: interests, nightlife/dating/social preferences, username generation
- Home: live events near you (map-bubble view + list), blended social feed
- Event details, ticket purchase (single PSP integration for v1: Paystack), QR ticket + check-in
- Check-in-gated Event Chat Rooms (group chat, real-time, "attendees only")
- Discover: vibe-tag people browsing, "Say Hi" (non-swipe first contact)
- Profile: passport view, Energy Score (basic formula), stats, achievements (fixed set)
- 1:1 DMs, basic media sharing
- Organizer: create event, manage tickets, view sales (basic dashboard)
- Admin: user management, content moderation queue, event approval
- Push notifications (event reminders, check-in confirmation, new message)

### Should Have
- Stories (24h, image/video)
- Voucher Wallet (issued manually by admin/venue for v1, not yet self-serve for businesses)
- Multi-PSP (add Flutterwave, Apple Pay/Google Pay)
- Room "temperature" live indicator
- Split payments for tickets

### Could Have
- Live streaming
- AI caption generator, AI chat assistant
- Marketplace (merch, drinks pre-order)
- Business self-serve dashboard for promotions/discounts

### Won't Have (v1)
- Full KYC/identity verification for organizers (manual review only in v1)
- Reserved seating maps
- Multi-language support beyond English
- Sponsor management tools

## 5. Success Metrics (North Star + supporting)

**North Star:** Weekly Verified Check-ins (a check-in ties a real person to a real event — the strongest signal of the product delivering its core promise).

| Metric | Target (6 months post-launch, Lagos pilot) |
|---|---|
| Weekly Active Users | 25,000 |
| Weekly verified check-ins | 8,000 |
| Ticket GMV / month | ₦15M+ |
| D30 retention | ≥20% |
| Organizer NPS | ≥40 |
| Check-in → chat-room participation rate | ≥50% |

## 6. Competitive Positioning

| | iTANGO | Eventbrite | Meetup | Tinder | Snapchat |
|---|---|---|---|---|---|
| Event ticketing | ✅ | ✅ | ➖ | ❌ | ❌ |
| Real-time social feed | ✅ | ❌ | ❌ | ❌ | ✅ |
| Presence-verified chat | ✅ | ❌ | ❌ | ❌ | ❌ |
| Vibe-based people discovery | ✅ | ❌ | ➖ | ✅(swipe) | ❌ |
| Loyalty/voucher economy | ✅ | ❌ | ❌ | ❌ | ❌ |
| Africa-first payments | ✅ | ❌ | ❌ | ❌ | ❌ |

## 7. Key Risks & Open Questions

- **Check-in spoofing:** geofence-only check-in can be spoofed by GPS mocking; QR-at-door is more reliable but requires organizer buy-in/hardware (even just a staff phone). *Recommendation: launch with QR-primary, geofence as a secondary confidence signal, not sole gate.*
- **Cold-start liquidity:** Discover and live-crowd-map features need density to feel alive. *Recommendation: launch city-by-city (Lagos first), not nationally, and seed with organizer partnerships before consumer marketing.*
- **Safety on the Discover layer:** even "vibe matching" rather than dating carries real-world meeting risk. Needs: block/report flows, a visible safety-tips surface, and moderation SLAs before this feature goes live — not after.
- **Payment reliability:** confirm Paystack settlement times and dispute process before committing to it as the v1 sole PSP.

## 8. Approval

This PRD defines MVP scope for Phase 1 sign-off. Subsequent phases build against this scope; changes to Must-Have items require re-approval here before backend/schema work begins.

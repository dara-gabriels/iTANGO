# iTANGO Design System — v1.0

## Contents
- `design-tokens.json` — single source of truth. Every color, type scale, spacing value, radius, and gradient used across Flutter and web is defined here first. If you need to change a brand color, change it here, then propagate.
- `flutter/itango_theme.dart` — `ItangoTheme.light` / `ItangoTheme.dark`, `ItangoColors`, `ItangoGradients`, `ItangoSpacing`, `ItangoRadius`, and a reusable `ItangoGradientButton` widget (Flutter has no native gradient-fill button, so this fills that gap using the design's signature pink→violet pill CTA).
- `web/globals.css` — CSS variables for the same tokens, dark-first (`:root` is dark; `[data-theme="light"]` overrides), plus small utility classes (`.btn-gradient-primary`, `.badge-live`, `.story-ring`, `.warmth-bar`) for patterns that repeat across many components.
- `web/tailwind.config.ts` — maps the CSS variables into Tailwind utilities (`bg-brand-primary`, `text-status-live`, `rounded-2xl`, `shadow-glow`, `bg-gradient-primary-cta`, etc.) so Next.js components style consistently without one-off hex values.

## Why dark-first
The confirmed screens (Home, Discover, Chats, Profile) are all dark-mode by default — this is the brand's actual visual identity, not just a mode toggle. Light mode is supported (per the original brief) but treated as the secondary surface/text inversion, while brand gradients and status colors stay fixed across both — that consistency is deliberate: iTANGO's pink→violet gradient and live-red badge are the one visual constant a user should always recognize, in any mode, on any platform.

## Next steps this unlocks
- Flutter: import `itango_theme.dart`, wire `ItangoTheme.dark` into `MaterialApp`, and start building the confirmed screens (Home, Discover, Create Event, Chats, Event Chat Room, Profile) as feature-first modules against these tokens.
- Web: drop `globals.css` into the Next.js app root, add `tailwind.config.ts`, and the same token names are available to the organizer/business/admin/moderator dashboards — keeping visual parity with the mobile app without duplicating design decisions.
- Any new component (voucher card, energy score badge, room-temperature bar) should be built as a token consumer, not a one-off style, so the system stays coherent as Phase 7/8 scale up.

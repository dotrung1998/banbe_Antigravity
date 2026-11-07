# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Guests and independent hosts of small, socially hosted events in Vietnam, with a US pilot. Guests discover events, hold a seat, pay, and attend with a QR ticket. Hosts create events, confirm payments, check guests in, and handle refunds. banbe admins resolve escalated disputes and manage events. Browsing is read-only for guests; personal actions prompt sign-in.

## Product Purpose

banbe lets people find and join small hosted events with confidence that their money and seat are protected, and lets hosts run those events without a payments back office. Success is a guest who books, shows up, and returns, and a host who fills seats and settles cleanly.

## Positioning

Escrow-style ticketing: a 30-minute seat hold and payment window, host confirmation within one hour, QR issuance, a "not found" branch with a temporary dispute chat, and escalation to banbe admins. A generic ticket marketplace does not offer this protected flow for small social events.

## Operating Context

- Two clients share one Supabase backend: a React/Vite web app and a native SwiftUI iOS app (`apps/ios`).
- Flow stages are documented in `.claude/notes/01` to `05` and later notes (refunds 16, Event Detail 52, Home discovery 50).
- Money in VND (US pilot adds per-event timezone and currency, paid USD booking off).
- Notifications are in-app, email, and push (push is blocked on an APNs key).

## Capabilities and Constraints

- Bilingual Vietnamese and English; Vietnamese prevails legally. Layouts must fit longer Vietnamese strings.
- Web and iOS keep feature and token parity; each follows its own platform conventions (native iOS glass, `GlassMenu` on web).
- Feature switches gate rewards, onboarding V2, and retention features; a missing flag means on.
- Policy and legal text is user-supplied (`banbe_User_Policy.md`); bracketed blanks are not to be invented.
- Platform choice and the user/mechanism read above were confirmed by the owner on 2026-10-25.

## Brand Commitments

Lowercase wordmark "banbe". Existing named tokens (clay accent, alert, moss, ink) are canonical per `.claude/notes/06-design-tokens.md` and note 52.

## Evidence on Hand

Real product screens and demo captures in `docs/demo-screenshots`. No customer testimonials or published metrics exist; production usage is very small, so do not fabricate social proof or benchmarks.

## Product Principles

1. Protect money and seats first; every state of the escrow flow must be legible and honest.
2. No dark patterns: coins have no cash value, promo consent defaults off, loss and contrast framing stays truthful.
3. Show real supply honestly; empty states beat padded ones.
4. Web and iOS stay in parity without flattening each platform's native feel.
5. Reduce friction with smart defaults and clear outcome-first CTAs.

## Accessibility & Inclusion

Light and dark themes both supported; reduced motion and Dynamic Type respected; Vietnamese and English at parity.

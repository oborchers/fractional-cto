---
name: speed-is-the-feature
description: This skill should be used when the user is building or reviewing loading states, optimistic UI updates, skeleton screens, code splitting, lazy loading, or performance budgets. Covers perceived speed, bundle size optimization, INP targets, and any work where application responsiveness and perceived latency matter.
version: 1.0.0
---

# Speed Is the Feature

Speed is not an optimization — it is the product. Linear built a billion-dollar company on this insight. Every architectural decision should serve Nielsen's three perception thresholds.

## The Three Thresholds

| Threshold | Perception | Target For |
|-----------|------------|------------|
| **100ms** | Instantaneous — feels caused by the user | Toggles, selections, navigating between loaded views |
| **1 second** | Flow uninterrupted — user feels in control | Page transitions, data loads |
| **10 seconds** | Attention limit — user wants to multitask | Show percent-done indicator or lose them |

## Core Principle: Decouple Feedback from the Network

The UI must respond before the server confirms. This does not require a local-first architecture — it requires separating the feedback loop from network latency.

## Optimistic UI

Update the UI immediately on user action. Reconcile with the server in the background.

**When to use optimistic updates:**
- Simple, binary-like actions (like, toggle, send, favorite)
- Actions with a success rate exceeding 97%
- Client-side validation passes before sending

**Rules:**
- Always handle failure gracefully — revert state and explain what happened
- Validate inputs client-side before the optimistic update
- Never use optimistic UI to mask genuinely slow operations — fix the operation instead

## Skeleton Screens

Skeleton screens beat spinners, but only when done correctly.

**Research findings (Bill Chung):**
- Left-to-right shimmer animation is perceived as shorter than pulsing opacity
- Slow, steady motion beats fast motion
- Skeleton elements must match actual content layout — a skeleton showing only header and footer is functionally a spinner

**When to use which loading indicator:**

| Load Duration | Indicator |
|---------------|-----------|
| < 1.5 seconds | Nothing, or a subtle spinner |
| 1.5–10 seconds | Skeleton screen with shimmer |
| > 10 seconds | Percent-done progress bar |

## Performance Budget

Enforce concrete budgets, not aspirational goals.

**Bundle budget:** Total JavaScript under 200KB gzipped. Code-split by route. Lazy-load modals, charts, and non-critical UI.

**Responsiveness budget:** INP (Interaction to Next Paint) must stay at or below 200ms. This measures responsiveness across all interactions, not just page load. Keep main-thread tasks under 50ms. Break long operations with `requestAnimationFrame` or `scheduler.yield()`.

## Examples

Working implementations in `examples/`:
- **`examples/optimistic-update.md`** — Toggle-favorite pattern with rollback in React, Vue, and Svelte
- **`examples/skeleton-screen.md`** — Shimmer CSS and skeleton components matching content layout
- **`examples/code-splitting.md`** — Route-level splitting and lazy-loading in React, Vue, and SvelteKit

## Review Checklist

When reviewing existing code for speed:

- [ ] Direct-manipulation interactions (toggle, select, tab switch) respond within 100ms
- [ ] Page transitions complete within 1 second
- [ ] Long operations (>10s) show progress indicators
- [ ] Optimistic updates used for high-success-rate actions
- [ ] Failure states gracefully revert optimistic updates
- [ ] Skeleton screens match actual content layout
- [ ] Routes are code-split
- [ ] Non-critical UI is lazy-loaded
- [ ] No main-thread tasks exceed 50ms

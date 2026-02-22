---
name: accessibility
description: This skill should be used when the user is building or reviewing accessibility (a11y), WCAG 2.2 AA compliance, keyboard navigation, focus management, screen reader support, ARIA attributes, color contrast, or SPA accessibility. Covers legal requirements, accessible component primitives, and the unique focus challenges of single-page applications.
version: 1.0.0
---

# Accessibility Is Not a Feature — It Is a Legal Requirement

WCAG 2.2 Level AA is the target — not because it is aspirational, but because it is law. The ADA Title II final rule requires WCAG 2.1 AA compliance for government-facing software. The European Accessibility Act applies to any SaaS accessible to EU citizens. Over 4,000 accessibility lawsuits were filed in 2023 alone.

## Minimum Standards

### Color Contrast
- **4.5:1** for normal text
- **3:1** for large text (18pt+ or 14pt bold)

### Keyboard Operability

Every interactive element must be operable by keyboard alone:

| Key | Action |
|-----|--------|
| **Tab** | Navigate between elements |
| **Enter/Space** | Activate element |
| **Escape** | Close modals, popovers, dropdowns — always |
| **Arrow keys** | Navigate within composite widgets |

**Focus must always be visible.** Many CSS resets strip `:focus` styles — this is a critical accessibility violation. Ensure every focusable element has a visible focus indicator.

## SPA Accessibility

Single-page applications break three browser behaviors that most teams miss entirely. Traditional page loads reset focus, announce the new page title, and reset scroll position. SPAs break all three.

**Mandatory SPA fixes:**

1. **Move focus on route change** — use `tabindex="-1"` on the element receiving programmatic focus
2. **Update the `<title>` tag** on every navigation
3. **Announce route changes** via ARIA live regions
4. **Restore focus on back-button navigation**

**When uncertain where to place focus after navigation, move it to the top of the page — it is always correct.**

## Use Accessible Component Primitives

Do not build modals, dialogs, or dropdown menus from scratch. The edge cases are vast and the failure modes are invisible to sighted developers.

Use libraries like Radix UI (the foundation of shadcn/ui) that handle ARIA attributes, focus management, and keyboard navigation internally.

## Testing

Automated testing catches roughly **30%** of accessibility issues. Manual testing catches the rest.

**Manual testing methods:**
- Screen readers: NVDA (Windows), VoiceOver (macOS/iOS)
- Keyboard-only navigation (unplug the mouse)
- High-contrast mode
- Zoom to 200%

## Examples

Working implementations in `examples/`:
- **`examples/spa-route-change-focus.md`** — Title update, focus management, and ARIA announcements for React Router, Vue Router, and SvelteKit
- **`examples/keyboard-navigation-composite.md`** — Roving tabindex pattern for tab panels, with comparison to Radix UI primitives

## Review Checklist

When reviewing or building for accessibility:

- [ ] Color contrast meets 4.5:1 for normal text, 3:1 for large text
- [ ] Every interactive element is keyboard-operable
- [ ] Tab, Enter/Space, Escape, and Arrow keys behave correctly
- [ ] Focus is always visible on every focusable element
- [ ] CSS resets have not stripped `:focus` styles
- [ ] Route changes move focus appropriately
- [ ] `<title>` tag updates on every navigation
- [ ] Route changes announced via ARIA live regions
- [ ] Back-button navigation restores focus
- [ ] Modals, dialogs, and dropdowns use accessible primitives (not custom-built)
- [ ] Manual testing performed with screen reader and keyboard-only
- [ ] Images have meaningful alt text (or `alt=""` for decorative images)
- [ ] Form inputs have associated labels

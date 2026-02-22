---
name: saas-navigation
description: This skill should be used when the user is building or reviewing sidebar navigation, command palette (Cmd+K), breadcrumbs, organization or workspace switching, multi-tenancy UI, or top bar layout. Covers navigation structure decisions, power-user keyboard patterns, and drill-down navigation.
version: 1.0.0
---

# Don't Make Users Think (About Navigation)

Jakob's Law dominates SaaS navigation: users spend most of their time in other apps and expect yours to work the same way. This is a measurable predictor of adoption speed.

## Primary Navigation: Sidebar

The established pattern for complex SaaS is a **left sidebar for primary navigation** with a top bar for context and utilities.

**When to use sidebar vs. header-only navigation:**

| Use Case | Pattern |
|----------|---------|
| Small number of sections, no secondary hierarchy | Header-only (top) navigation |
| Nested navigation (every real SaaS product) | Left sidebar |

IBM Carbon's guidance is definitive: the moment nested navigation is needed — and every real SaaS product needs it — use a sidebar.

## Command Palette (Cmd+K)

The command palette is the power-user signature of modern SaaS. Linear, Superhuman, Slack, Figma, Notion, Vercel, and GitHub all implement it.

**Essential design rules (from Superhuman's engineering team):**
- The same keyboard shortcut opens the palette from anywhere in the app
- Pressing the shortcut again dismisses it and restores previous focus
- Show keyboard shortcuts next to listed commands to teach power users
- Make the palette context-aware — surface relevant actions based on current view
- Do not conflate search and command palette — if search is a core feature, it exists at the same structural level, not buried inside the palette

## Multi-Tenancy and Org Switching

Three models dominate:

| Model | Example | Description |
|-------|---------|-------------|
| Single account, multiple orgs | GitHub | One user account added to multiple organizations |
| Separate accounts per org | Google | Distinct accounts for each organization |
| Hybrid (single account, multiple workspaces) | Linear, Notion | Single account, multiple workspaces |

**Build for the hybrid model** — it covers the widest range of products.

**Placement:**
- Sidebar header (Notion/Linear pattern)
- Top navigation (GitHub/Vercel pattern)

**Visual differentiation is mandatory.** Use workspace avatars or colors so users switching between workspaces know immediately which context they are in.

## Breadcrumbs

Breadcrumbs are mandatory for any drill-down navigation.

**Rules:**
- If navigating from a parent to a child page, the child must have a clear way back (GitHub Primer)
- Any drill-down page includes a breadcrumb of the full path back to root level, placed above the page title (IBM Carbon)

## Review Checklist

When reviewing or building navigation:

- [ ] Primary navigation uses a left sidebar (unless sections are flat with no nesting)
- [ ] Top bar reserved for context, utilities, and user account
- [ ] Command palette accessible via Cmd+K (or Ctrl+K) from anywhere
- [ ] Command palette is context-aware and shows keyboard shortcuts
- [ ] Search and command palette are not conflated (if search is a core feature)
- [ ] Workspace/org switcher uses visual differentiation (avatars, colors)
- [ ] Every drill-down page has breadcrumbs showing the full path back to root
- [ ] Navigation patterns match what users expect from comparable products

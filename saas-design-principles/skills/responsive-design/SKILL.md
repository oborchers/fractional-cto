---
name: responsive-design
description: This skill should be used when the user is building or reviewing responsive layouts, mobile design, breakpoints, table-to-card patterns, touch targets, collapsible sidebars, or mobile/bottom navigation. Covers the "sacrifice principle" for mobile SaaS, desktop/tablet/mobile breakpoint strategy, and minimum touch target standards.
version: 1.0.0
---

# Responsive Design Means Knowing What to Sacrifice

Over 55% of global web traffic comes from mobile, but complex SaaS on small screens requires deliberate sacrifice, not automatic scaling. The best SaaS products do not replicate their desktop experience on mobile — they extract the subset of functionality that makes sense for the context.

## The Sacrifice Principle

Study how leading products handle this:

- **Linear mobile** focuses on viewing/updating issues and responding to comments. Sprint planning and complex filtering stay desktop-only.
- **Notion mobile** converts multi-column database views to card layouts.
- **Slack mobile** focuses on messaging core — channels, threads, DMs. Complex admin features stay desktop-only.

The question is not "how do we make this fit on mobile?" but **"what subset of functionality makes sense in a mobile context?"**

## Breakpoint Strategy

| Breakpoint | Range | Layout |
|-----------|-------|--------|
| **Desktop** | ≥1024px | Full sidebar, multi-column layouts, complete data tables |
| **Tablet** | 768–1023px | Collapsible sidebar, reduced columns, touch-friendly controls |
| **Mobile** | ≤767px | Bottom navigation, single-column layouts, cards replacing tables |

## Touch Targets

Minimum sizes are non-negotiable:

| Standard | Minimum Size |
|----------|-------------|
| Apple HIG | **44x44px** |
| Material Design | **48x48dp** |

All interactive elements — buttons, links, checkboxes, toggles — must meet these minimums on touch devices.

## Tables on Mobile

Two patterns are necessary in a reusable application — the choice depends on data density and the user's primary task:

### Pattern 1: Card Layout Conversion
Transform each table row into a card. Best for resource lists (orders, customers, products) where users browse and act on individual items.

### Pattern 2: Horizontal Scroll with Frozen Column
Freeze the first column (identifying information) and allow horizontal scrolling. Best for comparison data where column relationships matter.

Shopify Polaris automatically transforms tables into list/card layouts on small screens. On screens below 490px, hide bulk actions unless essential.

## Navigation on Mobile

- Replace the sidebar with **bottom navigation** for primary actions
- Limit bottom navigation to **4–5 items maximum**
- Use a "More" menu for additional items
- Maintain breadcrumbs for drill-down flows, but simplify to show only the parent and current page

## Review Checklist

When reviewing or building responsive layouts:

- [ ] Mobile design deliberately sacrifices non-essential features, not just scales down
- [ ] Desktop uses full sidebar with multi-column layouts
- [ ] Tablet has a collapsible sidebar with reduced columns
- [ ] Mobile uses bottom navigation with single-column layouts
- [ ] All touch targets meet minimum 44x44px (Apple) or 48x48dp (Material)
- [ ] Data tables convert to cards or horizontal-scroll on mobile
- [ ] Card layouts used for browseable resource lists
- [ ] Frozen-column scroll used for comparison data
- [ ] Bulk actions hidden on screens below 490px unless essential
- [ ] Bottom navigation limited to 4–5 items
- [ ] Breadcrumbs simplified on mobile (parent + current only)

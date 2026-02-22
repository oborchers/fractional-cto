---
name: data-tables
description: This skill should be used when the user is building or reviewing data tables, pagination, column alignment, bulk actions, sorting, filtering, row selection, or table-to-card responsive patterns. Covers the pagination vs infinite scroll decision, DataTable vs IndexTable patterns, and column default strategy.
version: 1.0.0
---

# Data Tables Are Where SaaS Products Are Won or Lost

Enterprise SaaS lives and dies by its data tables. The rules are non-negotiable.

## Alignment Rules

| Content Type | Alignment |
|-------------|-----------|
| Text | Left-align |
| Numbers | Right-align |
| Headers | Match content alignment |
| Data columns | Never center-align |

Use monospace or tabular typography for numbers so "$1,111.11" doesn't visually outweigh "$999.99."

## Pagination vs. Infinite Scroll

**Pagination beats infinite scroll for SaaS data tables — always.**

Nielsen Norman Group's research explains why: infinite scroll creates a "lack of landmarks." Users can't remember where items were. With pagination, users remember "it was on page 3, near the top."

**Pogo-sticking** — clicking into a record, then going back — is especially destructive with infinite scroll because users are often returned to the top of the list.

**Pagination rules:**
- Keep pages at **10–20 items**
- Store pagination state in the URL
- Show total item count
- Preserve filters and sorting across pages

## Two Table Types

Shopify Polaris makes a critical distinction:

### DataTable (Static Comparison)
For showing values across categories with summary rows and fixed columns. Read-only comparison view.

### IndexTable (Actionable Resource List)
For orders, customers, products — with row selection, bulk actions, and navigation to detail pages.

Build both patterns. The choice depends on whether users need to act on the data or compare it.

## Column Defaults

Invest heavily in choosing which columns appear by default. Most users never customize.

**Rules:**
- Allow users to show, hide, reorder, and resize columns
- Always provide a prominent **"Reset to defaults"** button
- Good defaults mean most users never need to customize

## Bulk Actions

Show a toolbar when one or more rows are selected.

**Placement options:**
- Replace the header row
- Float at the bottom of the viewport

**Selection options:**
- Support both "select all on this page" and "select all across all pages" as **separate** options
- On mobile screens below 490px, hide bulk actions unless essential — convert tables to card layouts instead

## Examples

Working implementations in `examples/`:
- **`examples/responsive-data-table.md`** — Alignment CSS, URL-based pagination, bulk selection, and table-to-card mobile conversion

## Review Checklist

When reviewing or building data tables:

- [ ] Text is left-aligned, numbers are right-aligned
- [ ] Headers match their content alignment
- [ ] No center-aligned data columns
- [ ] Numbers use monospace or tabular typography
- [ ] Pagination used instead of infinite scroll
- [ ] Pages contain 10–20 items
- [ ] Pagination state stored in the URL
- [ ] Total item count displayed
- [ ] Filters and sorting preserved across pages
- [ ] Column defaults carefully chosen
- [ ] Users can show/hide/reorder/resize columns
- [ ] "Reset to defaults" button is prominent
- [ ] Bulk action toolbar appears on row selection
- [ ] "Select all on this page" and "select all across all pages" are separate options

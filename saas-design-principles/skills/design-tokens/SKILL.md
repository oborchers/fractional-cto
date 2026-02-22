---
name: design-tokens
description: This skill should be used when the user is building or reviewing theming systems, design tokens, dark mode implementation, CSS custom properties, color naming conventions, or theme switching architecture. Covers the three-tier token model (primitive/semantic/component), purpose-based naming, and the DTCG specification.
version: 1.0.0
---

# Design Tokens Make Theming a Non-Event

The industry has converged on a three-tier token architecture. Adopting it correctly means theme switching requires only toggling a class — no component re-renders, no complex logic.

## Three-Tier Token Architecture

### Tier 1: Primitive Tokens
Raw values. The palette.

Examples: `#3B82F6`, `16px`, `600`

### Tier 2: Semantic Tokens
Purpose-driven aliases. The meaning layer.

Examples: `--color-text-primary`, `--color-bg-surface`, `--spacing-md`

### Tier 3: Component Tokens
Scoped references. The component layer.

Examples: `--button-bg`, `--card-border-radius`, `--input-border-color`

## The Critical Naming Rule

**Name tokens by purpose, not appearance.**

| Bad (appearance) | Good (purpose) |
|-----------------|----------------|
| `--color-white` | `--color-bg-surface` |
| `--color-blue-500` | `--color-action-primary` |
| `--font-large` | `--font-heading` |
| `--color-gray-200` | `--color-border-default` |

`--color-bg-surface` works in both light and dark mode. `--color-white` becomes meaningless the moment themes change.

## Theme Switching Architecture

Use CSS custom properties with a class toggle on the root element. CSS variables cascade down, automatically updating every component **without re-rendering the component tree.**

**Implementation pattern:**
1. Define semantic tokens as CSS custom properties
2. Override values in a `.dark` (or `[data-theme="dark"]`) selector
3. Toggle the class/attribute on `<html>` to switch themes
4. No JavaScript re-renders needed

## Dark Mode Implementation

Use the **hybrid approach:**

1. **Detect** system preference with `prefers-color-scheme`
2. **Allow** manual override via a toggle
3. **Store** the preference in `localStorage`
4. **Apply** via a `data-theme` attribute on `<html>`

Consider Twitter's three-option model for apps where users spend long sessions:
- **Default** (light)
- **Dim** (reduced contrast dark)
- **Lights Out** (true black)

## W3C Design Tokens Community Group

The DTCG released the first stable specification (2025.10), backed by Adobe, Amazon, Google, Figma, Shopify, and others. Adopting the DTCG JSON format future-proofs token architecture for cross-platform tooling and design-to-code pipelines.

## Examples

Working implementations in `examples/`:
- **`examples/three-tier-tokens.md`** — Complete CSS custom property system: primitives, semantics, component tokens, and DTCG JSON format
- **`examples/dark-mode-toggle.md`** — Hybrid theme switching with system detection, localStorage persistence, and framework-specific toggles

## Review Checklist

When reviewing or building a token/theming system:

- [ ] Three-tier architecture: primitive, semantic, component tokens
- [ ] All tokens named by purpose, not appearance
- [ ] No color names in token identifiers (no `--white`, `--blue-500`)
- [ ] Theme switching uses CSS custom properties with class/attribute toggle
- [ ] No component re-renders required for theme switching
- [ ] Dark mode detects system preference via `prefers-color-scheme`
- [ ] Manual theme override stored in `localStorage`
- [ ] Theme applied via `data-theme` attribute on `<html>`
- [ ] Long-session apps consider a three-option model (light/dim/dark)
- [ ] DTCG JSON format considered for token definitions

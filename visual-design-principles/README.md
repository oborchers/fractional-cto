# visual-design-principles

A Claude Code plugin that codifies visual design quality — research-backed, opinionated guidance drawn from VisAWI (Moshagen & Thielsch), Gestalt psychology, Refactoring UI, WCAG 2.2, Material Design, Apple HIG, and decades of empirical aesthetics research.

## What It Does

When Claude is working on any visual artifact — websites, landing pages, dashboards, presentations, CVs, documents, or components — the relevant principle skill activates automatically and guides the work with specific, actionable rules and review checklists.

This plugin provides **principles and examples, not boilerplate.** It tells Claude *what* to build and *why*, with code patterns in CSS/HTML, Tailwind, and React showing *how*.

**Cross-media applicability**: While examples use web technologies, every principle includes Cross-Media Notes for presentations, documents, CVs, and other visual media.

## The 11 Principles

| # | Principle | Skill | What It Covers |
|---|-----------|-------|----------------|
| I | Layout & Spatial Structure | `layout-spatial-structure` | 12-column grid, 8px spacing, CSS Grid/Flexbox, Gestalt proximity, F/Z-patterns |
| II | Typography | `typography` | Modular type scales, font pairing, line height/length, 2-3 font families, responsive type |
| III | Color Theory & Application | `color-theory-application` | HSL model, 60-30-10 rule, shade scales, WCAG contrast, dark mode, semantic colors |
| IV | Whitespace & Density | `whitespace-density` | Spacing systems, density spectrum, separation techniques, vertical rhythm |
| V | Visual Hierarchy | `visual-hierarchy` | 3 levers (size/weight/color), 3-tier architecture, CTA design, label-data relationships |
| VI | Consistency & Design Systems | `consistency-design-systems` | Design tokens (primitive→semantic→component), atomic design, token governance |
| VII | Craftsmanship & Polish | `craftsmanship-polish` | Pixel alignment, image optimization, shadows, border-radius, micro-interactions, CLS |
| VIII | Visual Interest & Expression | `visual-interest-expression` | Brand personality, illustrations, motion design, layout variety, template independence |
| IX | Responsive Design | `responsive-design` | Mobile-first, breakpoints, fluid grids, container queries, touch targets |
| X | Accessibility & Inclusive Design | `accessibility-inclusive-design` | WCAG 2.2 AA, contrast ratios, keyboard nav, screen readers, color independence |
| XI | Design Evaluation & Scoring | `design-evaluation-scoring` | 8-dimension scoring framework, anti-pattern detection, evaluation workflow |

## Installation

### Claude Code (via fractional-cto Marketplace)

```bash
/plugin marketplace add oborchers/fractional-cto
/plugin install visual-design-principles@fractional-cto
```

### Local Development

```bash
claude --plugin-dir /path/to/fractional-cto/visual-design-principles
```

## Components

### Skills (12)

One meta-skill (`using-visual-design-principles`) that provides the complete index and 25 quick-reference rules, plus 11 principle skills — each with YAML frontmatter, research-backed rules, cross-media notes, code examples (CSS/Tailwind/React), and review checklists.

### Command (1)

- `/visual-design-principles:design-review` — Review code, screenshots, or visual artifacts against all relevant design principles with 8-dimension scoring

### Agent (1)

- `visual-design-reviewer` — Comprehensive visual design audit with per-dimension 1-5 scoring, total score out of 40, severity-classified findings, and prioritized improvements

### Hook (1)

- `SessionStart` — Injects the meta-skill index into session context on startup, resume, clear, and compact

## The 8-Dimension Scoring Framework

Every visual artifact can be scored across 8 dimensions (1-5 each, 40-point maximum):

| Dimension | Research Alignment | Key Metric |
|-----------|-------------------|------------|
| Layout | Seckler et al. (2015) | >90% edge alignment to grid |
| Typography | Bringhurst, Tim Brown | 45-75 chars/line, modular scale |
| Color | Reinecke et al. (2013) | 60-30-10 distribution, WCAG AA |
| Whitespace | Pracejus et al. (2006) | 30-50% ratio (context-dependent) |
| Hierarchy | Refactoring UI | 3 tiers, one star per screen |
| Consistency | VisAWI Craftsmanship | ≤15 colors, ≤10 spacing values |
| Craftsmanship | VisAWI (α = .94) | CLS < 0.1, 2x images, layered shadows |
| Expression | Lavie & Tractinsky (2004) | Level 2+ template independence |

**Score interpretation**: <16 Poor · 16-23 Below Average · 24-31 Adequate · 32-37 Good · 38-40 Excellent

## The Three Meta-Principles

All eleven principles rest on three foundations:

1. **Structure over style** — Structural clarity (grid, typography, whitespace, hierarchy) drives 80%+ of perceived visual quality. Color and expression are secondary amplifiers.

2. **Systematic over arbitrary** — Design tokens, modular scales, and spacing systems eliminate guesswork. Every value should come from a defined scale.

3. **Measure, don't guess** — The 8-dimension scoring framework makes quality objective and evaluable. Use the scoring rubrics, not subjective opinions.

## License

MIT

---
name: markdown-compression
description: "This skill should be used when the user asks to 'compress markdown', 'shrink this file', 'optimize tokens', 'reduce file size', 'compress instructions', 'make this more concise', 'minimize this prompt', 'compress CLAUDE.md', 'compress ARCHITECTURE.md', 'optimize agent instructions', or wants to reduce token usage in LLM-facing markdown files. Covers lossless structural optimization and lossy semantic compression with section-by-section analysis."
version: 1.0.0
---

# Markdown Compression

Markdown compression reduces token consumption in LLM-facing documentation — agent instructions, CLAUDE.md files, ARCHITECTURE.md files, system prompts, and skill definitions — while preserving the information an LLM needs to operate correctly.

Two modes address different risk tolerances:

| Mode | What Changes | Risk | Best For |
|------|-------------|------|----------|
| **Lossless** | Structure only — whitespace, formatting, redundant syntax | Zero semantic change | Safe first pass on any file |
| **Lossy** | Semantics — rewriting for density, removing filler, consolidating | Information loss possible | Deep compression with review |

Section-by-section compression with user approval at each step is the recommended workflow. The `/compress` command provides a guided session; the skill also activates when compression-related work is detected mid-conversation.

## Core Principle: What LLMs Actually Need

LLM instructions are not prose for humans. Compression targets what LLMs ignore or process redundantly:

**Always safe to remove:**
- Motivational filler ("This is important because...", "Remember to always...")
- Restated information (same rule in introduction and body)
- Hedging language ("You might want to consider...", "It's generally a good idea to...")
- Verbose transitions ("Now that we've covered X, let's move on to Y")
- Excessive examples when one suffices (keep the most distinctive example)
- Markdown decoration that adds no semantic value (unnecessary horizontal rules, decorative headers)
- HTML comments
- Redundant emphasis (bold + caps + exclamation mark conveying the same weight as bold alone)

**Never remove:**
- Specific values, thresholds, and constraints (numbers, limits, exact names)
- Behavioral rules and prohibitions ("NEVER do X", "ALWAYS do Y")
- Tool names, file paths, API endpoints, and identifiers
- Decision logic and conditional branches ("If X then Y, otherwise Z")
- Output format specifications
- Edge case handling instructions
- Cross-references to other files or systems
- YAML frontmatter (preserve exactly as-is)

**Judgment required:**
- Examples — keep if they illustrate an edge case or non-obvious behavior; remove if they restate the obvious
- Context/motivation — keep if it changes behavior ("why" behind a rule); remove if purely informational
- Lists — consolidate items that express the same idea differently; keep all semantically distinct items

## Lossless Mode

Lossless compression changes structure without altering semantics. Apply these transformations:

1. **Normalize whitespace** — collapse multiple blank lines to one, remove trailing spaces, standardize indentation
2. **Simplify formatting** — remove unnecessary horizontal rules, collapse nested emphasis, remove decorative elements
3. **Remove comments** — strip HTML comments and markdown comments that aren't instructions
4. **Consolidate redundant headers** — merge adjacent headers with no content between them
5. **Normalize lists** — standardize bullet markers, remove excessive nesting where flat structure suffices
6. **Trim boilerplate** — remove "Table of Contents" sections that duplicate header structure, remove empty sections

For detailed lossless transformation rules and before/after examples, consult `references/lossless-techniques.md`.

## Lossy Mode

Lossy compression rewrites for semantic density. Apply the compressor-reviewer loop per section:

### Compression Principles

1. **Imperative over descriptive** — "Validate input" not "The system should validate input" not "It's important to make sure that input is validated"
2. **One expression per concept** — if a rule appears in three places, keep the most complete statement and delete the others
3. **Table over prose** — when listing attributes with properties, a table is denser than paragraphs
4. **Inline over nested** — "Use gzip (level 6, min 1KB)" not a paragraph explaining gzip with sub-bullets for level and threshold
5. **Delete implied knowledge** — LLMs know what REST is, what JSON looks like, how try/catch works. Only state what's specific to *this* system
6. **Merge related sections** — if two sections share >50% of their content, merge into one
7. **Preserve structure, compress content** — keep heading hierarchy intact; compress the prose under each heading

### Compressor-Reviewer Loop

For each section:
1. **Section compressor agent** applies lossy principles aggressively — its goal is maximum token reduction
2. **Compression reviewer agent** compares original and compressed versions — catches information loss
3. **User reviews** the diff and approves, edits, or rejects

The reviewer specifically checks for:
- Lost behavioral rules or prohibitions
- Removed specific values/thresholds that change behavior
- Missing edge cases or conditional logic
- Over-generalized instructions that lost precision
- Broken cross-references

For detailed lossy techniques and worked examples, consult `references/lossy-techniques.md`.

## Pre-Analysis

Before compressing, analyze the file structure to determine section boundaries and identify problem areas:

1. **Parse heading hierarchy** — identify all sections by heading level. Choose the split level based on the document: `##` for most files, `###` if `##` sections are very large
2. **Validate structure** — flag skipped heading levels (h1 → h3), sections with no content, ambiguous nesting
3. **Measure sections** — count approximate tokens per section (words * 1.3). This is a rough heuristic; actual tokenizer counts vary by model but this is sufficient for relative comparison
4. **Flag oversized sections** — sections over ~500 tokens are candidates for splitting before compression or for extra attention during lossy compression
5. **Identify redundancy** — sections that repeat information from other sections. Cross-section deduplication is one of the highest-yield lossy techniques

Present the structural analysis as a table to the user before beginning compression. This gives the user a map of the document and sets expectations for where the biggest savings will come from.

## Measuring Results

After compression, report a summary so the user can assess the impact:

- **Original tokens** (approximate: words * 1.3)
- **Compressed tokens**
- **Reduction percentage**
- **Sections modified** vs. sections unchanged
- **Mode used** (lossless or lossy)

The `words * 1.3` heuristic estimates tokens for typical English markdown. Actual token counts depend on the model's tokenizer, but relative reduction percentages are reliable for comparison.

## Reference Files

For detailed techniques and patterns, consult:
- **`references/lossless-techniques.md`** — Complete lossless transformation catalog with before/after examples
- **`references/lossy-techniques.md`** — Lossy compression patterns, judgment heuristics, and information-density techniques

## Example Files

Worked compression sessions in `examples/`:
- **`examples/before-after-lossless.md`** — CLAUDE.md file compressed with lossless mode
- **`examples/before-after-lossy.md`** — Agent instruction file compressed with lossy mode

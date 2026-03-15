---
name: synthesis-and-reporting
description: "This skill should be used when combining research findings from multiple sources or agents, deduplicating overlapping information, resolving conflicts between sources, constructing a narrative from research data, formatting citations and source lists, assessing report quality, or writing the final research document. Covers deduplication strategies, conflict resolution, thematic analysis, narrative construction, citation management, and synthesis anti-patterns."
version: 1.1.0
---

# Synthesis & Report Generation

Retrieval asks "find relevant information." Synthesis asks "make sense of it all." A retrieval system succeeds by returning individually relevant documents. A synthesis system must reconcile those documents into a single coherent narrative where contradictions are resolved, redundancies are eliminated, themes are extracted, and every claim is properly attributed.

Synthesis is where all prior research work converges and where failures in earlier stages compound. An error in retrieval produces one bad source. An error in synthesis propagates that bad source into the final report (arXiv 2508.12752).

## Deduplication

When multiple research workers search overlapping queries, they return overlapping content. Without deduplication, the same fact appears multiple times in different phrasings, inflating token usage and producing bloated reports.

**Three-level deduplication:**

| Level | What | Detection Method |
|-------|------|-----------------|
| **Exact** | Identical text from same source in multiple results | String/hash comparison |
| **Near-duplicate** | Same content with minor wording variations | Jaccard similarity on text shingles |
| **Semantic** | Different text expressing the same meaning | Embedding similarity (cosine > 0.85 threshold) |

**Practical approach:** Before synthesis, group all findings by theme. Within each theme, identify redundant claims and merge them into a single statement citing the strongest source. Preserve all unique nuances — deduplication removes repetition, not detail.

## Conflict Resolution

When sources disagree, do not silently pick one side. Handle conflicts explicitly:

| Conflict Type | Resolution Strategy |
|--------------|-------------------|
| **Factual disagreement** (different numbers for same metric) | Report both values with citations; note the discrepancy; prefer the higher-tier source |
| **Methodological disagreement** (different approaches, different conclusions) | Present both perspectives; explain why results differ |
| **Temporal disagreement** (outdated vs. current information) | Prefer the most recent source; note the evolution |
| **Scope disagreement** (different contexts lead to different findings) | Clarify the scope of each finding; they may both be correct in their context |

**Rule:** Never resolve a conflict by omitting one side. The reader needs to know that disagreement exists.

## Thematic Analysis

Organize findings by theme, not by source. A synthesis that reads "Source A says... Source B says... Source C says..." is not synthesis — it is a list of summaries.

**Process:**
1. Extract all distinct findings from worker documents
2. Cluster findings by theme (what they are about, not where they came from)
3. Within each theme, identify consensus, disagreements, and gaps
4. Write each theme section integrating findings from multiple sources
5. Cite inline as claims are made, not at section boundaries

## Narrative Construction

Structure research output for readability using progressive disclosure:

**Standard research document structure:**

```
# Title

> Research date, source count, scope statement

## Executive Summary (2-3 paragraphs)
Key findings, most important conclusions, major caveats

## Section 1: [Theme]
Findings organized by theme with inline citations

## Section 2: [Theme]
...

## Limitations and Gaps
What could not be verified, what remains uninvestigated

## Sources
Numbered list with full URLs and brief descriptions
```

**Intermediate worker documents** follow a simpler structure:

```
# [Subtopic]

## Findings
- Finding 1 [Source](url)
- Finding 2 [Source](url)

## Sources Consulted
- [Name](url) — brief description of what was found
```

## Citation Management

**Inline citations** — Every factual claim gets an inline citation: `[Source Name](URL)`. Do not batch citations at paragraph end.

**Sources section** — At the document end, list all sources with:
1. Source name/title
2. Full URL
3. Brief description of what information was obtained

**Citation format example:**
```markdown
Research on deep research agent trajectories found that over 57% of
source errors occur in early retrieval stages ([DR-Arena, arXiv
2601.10504](https://arxiv.org/abs/2601.10504)).

## Sources
1. [DR-Arena: A Benchmark for Deep Research](https://arxiv.org/abs/2601.10504) — Evaluation of six deep research agents on multi-hop reasoning and information gathering
```

## Report Quality Checklist

Before finalizing any research document, verify:

- [ ] **Completeness** — Does the report address all aspects of the research query?
- [ ] **Source coverage** — Are findings supported by multiple independent sources where possible?
- [ ] **Citation integrity** — Does every factual claim have an inline citation?
- [ ] **Conflict transparency** — Are disagreements between sources acknowledged?
- [ ] **Gap acknowledgment** — Are limitations and uninvestigated areas stated?
- [ ] **No orphaned claims** — No factual assertions without source attribution?
- [ ] **Numerical accuracy** — Do all numbers match their cited sources exactly?
- [ ] **Qualifier preservation** — Are hedging words from sources preserved in the report?

## Synthesis Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|-------------|----------------|-----|
| **List-of-summaries** | "Source A says X. Source B says Y." — no integration | Organize by theme; weave sources together |
| **Source bias** | Over-representing one source because it was retrieved first | Balance coverage; weight by source tier, not retrieval order |
| **Missing synthesis** | Juxtaposing findings without connecting them | Draw explicit connections, identify patterns |
| **Loss of nuance** | "The study found X" when study actually found "X under conditions Y and Z" | Preserve qualifiers and context from sources |
| **Hallucinated synthesis** | Connecting findings that are not actually related | Each connection must be supported by source evidence |
| **Recency bias** | Over-weighting recent sources when older sources may be more rigorous | Evaluate by source tier, not publication date alone |

## Reference Files

For detailed synthesis patterns, evaluation metrics, and report quality frameworks:
- **`references/synthesis-patterns.md`** — Map-reduce synthesis, iterative refinement, position-bias mitigation, and commercial system approaches

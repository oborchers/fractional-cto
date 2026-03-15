---
name: using-deep-research
description: "This skill should be used when the user asks 'how do I do deep research', 'show me research skills', 'help me research a topic', 'what research methodology should I use', or at the start of any structured web research task. Provides the index of all deep research principle skills and the /research command."
version: 1.1.0
---

# Deep Research Methodology

Structured deep research transforms ad-hoc web searches into a repeatable, hallucination-resistant research pipeline. Without deliberate structure, research agents gravitate toward the first sources found, fail to verify claims, and produce confident reports built on unreliable foundations.

This plugin provides 4 methodology skills and the `/research` command for orchestrated multi-agent research sessions.

## How to Access Skills

Use the `Skill` tool to invoke any skill by name. When invoked, follow the skill's guidance directly.

## Principle Skills

| Skill | Triggers On |
|-------|-------------|
| `deep-research:research-methodology` | Starting any research task — query analysis, decomposition strategies, effort scaling, dynamic replanning, stopping criteria |
| `deep-research:source-evaluation` | Evaluating sources — credibility ranking (T1-T6 tiers), multi-provider search strategy, SEO spam detection, domain-specific source selection |
| `deep-research:hallucination-prevention` | Any research output — hallucination taxonomy, citation verification rules, circuit breaker patterns, confidence scoring, cascading prevention |
| `deep-research:synthesis-and-reporting` | Combining findings — deduplication, conflict resolution, narrative construction, citation formatting, report quality assessment |

## When to Invoke Skills

Invoke a skill when there is even a small chance the work touches one of these areas:

- **Starting research**: Load `research-methodology` to plan decomposition and effort scaling
- **Searching the web**: Load `source-evaluation` to assess what you find
- **Writing any claim**: Load `hallucination-prevention` to verify before stating
- **Combining findings**: Load `synthesis-and-reporting` to merge and cite properly

## The /research Command

For full orchestrated research sessions, use `/research`. The command:
1. Checks web access permissions (one-time setup per project)
2. Analyzes the research query — if too vague, asks 2-3 clarifying questions
3. Decomposes into subtopics based on query complexity (not a fixed number)
4. Spawns parallel `research-worker` agents (Sonnet) — each writes findings with a Verifiable Claims Table
5. Spawns parallel `research-verifier` agents (Sonnet) — each re-fetches sources and checks claims independently
6. Dispatches a `research-synthesizer` agent (Opus) — applies corrections, merges findings, writes final document with Confidence Assessment
7. Preserves intermediate docs and verification reports for traceability

## The Three Meta-Principles

All research skills rest on three foundations:

1. **Every claim needs a source** — No unsourced assertions. If it cannot be cited, it cannot be stated as fact. Flag uncertainty explicitly.

2. **Source quality determines output quality** — 57% of research errors originate in early retrieval. Front-load high-quality sources. Prefer primary sources (T1-T2) over secondary sources.

3. **Verify before synthesizing** — Treat each agent's output as untrusted input. Cross-reference claims between sources. Use deterministic validation where possible.

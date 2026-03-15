---
name: research-methodology
description: "This skill should be used when starting any research task, decomposing a research query, planning research strategy, deciding how many sub-topics to investigate, scaling research effort to query complexity, determining when to stop researching, or dynamically re-planning based on intermediate findings. Covers query analysis, decomposition techniques (Self-Ask, Least-to-Most, DAG-based), effort scaling, plan representations, stopping criteria, and research anti-patterns."
version: 1.1.0
---

# Research Methodology

Effective research requires deliberate planning before execution. Without decomposition, complex queries overwhelm LLMs — the compositionality gap means models answer sub-questions correctly but fail to compose them into correct multi-hop answers, and this gap does not shrink with model scale alone (Press et al., EMNLP 2023).

## Query Analysis

Before decomposing, analyze the query along three dimensions:

**Complexity classification:**

| Level | Characteristics | Example | Approach |
|-------|----------------|---------|----------|
| Simple | Single fact, one source sufficient | "What is the GAIA benchmark?" | Direct search, no decomposition |
| Moderate | 2-4 facets, comparison or analysis | "How does LangGraph compare to CrewAI?" | 2-4 parallel subtopics |
| Complex | Multi-faceted, requires synthesis across domains | "How should we architect a deep research agent?" | Full decomposition with dynamic replanning |

**Scope narrowing:** If a query is vague or overly broad, ask 2-3 clarifying questions before researching. Model this on Claude's desktop deep research flow — refine scope before committing resources.

Questions to consider:
- What specific aspect matters most?
- What is the intended use of this research?
- Are there known constraints (domain, time period, technology)?

## Decomposition Strategies

Decomposition strategy should emerge from the query, not from a preset template. The number of subtopics is a function of query complexity, not a fixed constant.

**Self-Ask pattern** — For multi-hop factual queries. Ask explicit follow-up sub-questions, answer each independently, then compose. Each sub-question becomes a natural insertion point for web search (Press et al., 2023).

**Parallel decomposition** — For queries with independent facets. Identify subtopics that can be researched simultaneously without dependency. ParallelSearch research shows 12.7% improvement on parallelizable questions using only 69.6% of LLM calls versus sequential approaches (Zhao et al., 2025).

**Iterative discovery** — For exploratory queries. Start with broad searches, discover subtopics from results, spawn follow-up searches based on what is found. The plan emerges from the research itself.

**DAG-based decomposition** — For queries with inter-dependent sub-questions. Model decomposition as a directed acyclic graph where some sub-questions depend on answers to others. MindSearch processes 300+ web pages in 3 minutes using this approach (Chen et al., ICLR 2025).

### Choosing a Strategy

| Query Type | Strategy | Why |
|-----------|----------|-----|
| "What is X?" | Direct search | Single-hop, no decomposition needed |
| "Compare X and Y" | Parallel decomposition | Independent facets, search simultaneously |
| "How does X work and what are its implications?" | Iterative discovery | Second part depends on first |
| "Comprehensive survey of X" | DAG-based | Multiple inter-dependent threads |

## Effort Scaling

Match research depth to query complexity. Over-researching simple queries wastes tokens; under-researching complex queries produces shallow results.

| Complexity | Workers | Searches per Worker | Total Effort |
|-----------|---------|-------------------|--------------|
| Simple | 1-2 | 3-5 | Light |
| Moderate | 3-4 | 5-10 | Medium |
| Complex | 5-8 | 10-20 | Heavy |

The number of workers emerges from decomposition — do not prescribe a fixed count before analyzing the query.

## Dynamic Re-Planning

Research plans are hypotheses, not contracts. Re-plan when:

- **Knowledge gaps emerge** — Intermediate results reveal missing information not anticipated in the original plan
- **Assumptions are invalidated** — A planned subtopic turns out to be irrelevant or already well-covered by another subtopic
- **New threads appear** — Discovered information opens important sub-questions not in the original plan
- **Sources conflict** — Contradictions between sources require additional targeted searches to resolve

When re-planning, persist the updated plan externally (not just in context) to survive context window truncation.

## Stopping Criteria

Combine multiple signals — no single criterion is sufficient:

1. **Plan completion** — All planned subtopics have been investigated
2. **Diminishing returns** — New searches yield information already covered
3. **Budget limits** — Maximum searches, tokens, or time reached
4. **Gap check** — Explicit review: "What important aspects remain uninvestigated?"
5. **Sufficiency judgment** — Can the research question be answered with current findings?

Stop when at least 3 of these 5 criteria are satisfied.

## Research Anti-Patterns

| Anti-Pattern | Symptom | Fix |
|-------------|---------|-----|
| **Over-decomposition** | 15+ subtopics for a moderate query | Let complexity drive decomposition, not ambition |
| **Under-decomposition** | Single monolithic search for a complex query | Analyze facets before searching |
| **Plan rigidity** | Following the original plan despite contradicting evidence | Re-plan when assumptions break |
| **Circular decomposition** | Sub-questions that restate the original question | Each sub-question must be independently answerable |
| **Premature depth** | Deep-diving first subtopic before broad coverage | Breadth-first for initial pass, then depth |

## Reference Files

For detailed decomposition techniques and research:
- **`references/decomposition-techniques.md`** — Self-Ask, Least-to-Most, Plan-and-Solve, DAG-based decomposition with examples and research citations

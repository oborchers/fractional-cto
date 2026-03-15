---
name: hallucination-prevention
description: "This skill should be used when producing any research output, verifying claims from web sources, checking citation accuracy, assessing confidence in findings, preventing hallucination cascading across agent boundaries, or reviewing research documents for factual reliability. Covers the hallucination taxonomy (7 types), OWASP ASI08 cascading failures, circuit breaker patterns, citation verification rules, confidence scoring, ground-truth validation, and known limitations of automated verification."
version: 1.1.0
---

# Hallucination Prevention

Hallucination is the single most important engineering concern for research agents. A 5,000-word report with 100 claims at 5% hallucination probability per claim has a 99.4% chance of containing at least one hallucinated claim. Even the best-performing models hallucinate at measurable rates — 0.7% for simple summarization, rising to 5-13% on harder tasks (Vectara Hallucination Leaderboard, 2025). In multi-agent systems, hallucinations compound across agent boundaries (OWASP ASI08).

## Hallucination Taxonomy

Seven distinct hallucination types, ordered by detection difficulty:

| Type | What Happens | Detection | Prevention |
|------|-------------|-----------|------------|
| **Citation hallucination** | Inventing papers, URLs, or authors that do not exist | Easy — verify URL/DOI exists | Never cite a source not actually retrieved and read |
| **Temporal hallucination** | Wrong dates or temporal ordering | Moderate — check against known timelines | Include dates from source text, not from memory |
| **Factual fabrication** | Entirely false statements presented as fact | Moderate — requires external lookup | Only state facts found in retrieved sources |
| **Numerical hallucination** | Fabricated statistics, percentages, counts | Hard — requires finding actual source | Copy numbers verbatim from source; never round or approximate without noting |
| **Attribution hallucination** | Real fact attributed to wrong source | Hard — requires cross-referencing | Track which source produced which claim |
| **Negation hallucination** | Reversing the polarity of a claim | Hard — requires careful reading | Quote or closely paraphrase source language |
| **Conflation hallucination** | Merging details from different sources into one false claim | Very hard — each component may be correct | Maintain per-source notes; do not blend findings until synthesis |

## The Cardinal Rules

These rules are non-negotiable for all research output:

1. **Never cite a source not actually retrieved.** If WebFetch was not called on a URL, that URL cannot appear as a citation.
2. **Copy numbers from sources verbatim.** Do not round, approximate, or "recall" statistics. If the source says "83.7%", write "83.7%", not "approximately 84%".
3. **Preserve qualifiers.** If the source says "may reduce", do not write "reduces". If it says "in a limited study", include that context.
4. **Track provenance per-claim.** Every factual claim in a research document must trace back to a specific source. Orphaned claims (facts with no source) are hallucination candidates.
5. **Flag uncertainty explicitly.** When confidence is low, say "This could not be independently verified" rather than asserting or omitting.

## Circuit Breaker Patterns

Prevent hallucination cascading across agent boundaries:

**Treat each agent's output as untrusted input.** When a research-worker agent returns findings, the synthesizing agent must not assume those findings are correct. Cross-reference key claims against other workers' findings or against the original sources.

**Structured error responses.** When a search or fetch fails, return an explicit error — never let an agent fill in missing data from "memory." A structured gap ("No information found on X") is infinitely better than a fabricated answer.

**Validation gates between pipeline stages.** Before synthesis begins, verify:
- Every cited URL was actually fetched
- Numerical claims match the source text
- Key facts appear in at least 2 independent sources (for critical claims)

## Citation Verification Rules

For citation formatting and management (inline format, Sources section structure), see the `synthesis-and-reporting` skill. This section covers verification of citation accuracy.

**Core principle:** Follow Perplexity's rule: "You are not supposed to say anything that you didn't retrieve."

**Verification checklist for each citation:**
- [ ] URL was actually fetched via WebFetch (not generated from memory)
- [ ] The cited claim actually appears in the fetched content
- [ ] Numbers match the source exactly
- [ ] The source is attributed to the correct author/organization
- [ ] Qualifiers from the source are preserved

## Confidence Scoring

Assign confidence levels to findings and communicate them in the output:

| Level | Criteria | Report Language |
|-------|---------|----------------|
| **High** | Claim appears in 2+ independent T1-T3 sources with consistent numbers (see `source-evaluation` skill for tier definitions) | State directly with citations |
| **Moderate** | Claim appears in 1 T1-T3 source or 2+ T4-T5 sources | "According to [Source]..." |
| **Low** | Single T4+ source, or sources partially conflict | "One source reports... though this could not be independently verified" |
| **Unverified** | No retrieved source supports the claim | Do not include, or explicitly flag as unverified |

**Propagation rule:** When combining findings from multiple agents, confidence of the combined finding equals the lowest confidence of its component claims.

## Ground-Truth Validation

Prefer deterministic validation over LLM-based validation:

| Check Type | Method | Example |
|-----------|--------|---------|
| **URL existence** | HTTP HEAD request | Verify cited URLs return 200 |
| **Date verification** | Parse and compare | Check if stated dates match source dates |
| **Numerical consistency** | String matching | Compare quoted numbers to source text |
| **Cross-reference** | Multi-source comparison | Same fact from independent sources |

LLM-based verification (asking a model "is this true?") is unreliable — models exhibit 17.8-57.3% bias-consistent behavior and high sycophancy rates (up to 58% initial compliance with wrong premises). Use code-based checks wherever possible.

## Verification Pipeline Integration

The `/research` command enforces hallucination prevention through a three-stage pipeline:

1. **Workers** produce findings with a structured Verifiable Claims Table (exact values + verbatim source text)
2. **Verifiers** re-fetch sources independently and check claims (one verifier per worker, in parallel)
3. **Synthesizer** reads both worker docs and verification reports, applying corrections before writing

This architecture addresses three hallucination failure modes:
- **Self-verification failure:** Workers cannot reliably verify their own work due to sycophancy and lost context from incremental writing. Verifiers operate in a fresh context with adversarial instructions.
- **Cascading trust:** The synthesizer previously trusted worker output implicitly. Verification reports make trust explicit and graduated (High/Moderate/Low/Corrected).
- **Missing confidence signals:** The Verifiable Claims table and verification reports feed directly into the Confidence Assessment appendix in the final output.

**Pipeline enforcement of confidence levels:**
- **High:** Claim verified by the verifier AND corroborated by 2+ independent sources
- **Moderate:** Claim verified by the verifier from a single source
- **Low:** Claim could not be verified, or verifier found conflicting information
- **Corrected:** Original claim was incorrect; corrected value from verification

## Known Limitations

Things current automated systems **cannot reliably verify:**
- Whether a source itself is accurate (garbage in, garbage out)
- Subtle semantic errors (correct words, wrong meaning)
- Whether a claim's context changes its truth value
- Claims about very recent events not yet indexed
- Absence of evidence vs. evidence of absence

For high-stakes research, human review of the final output remains essential.

## Reference Files

For detailed hallucination research, OWASP ASI08 analysis, and verification architecture:
- **`references/hallucination-research.md`** — Quantitative hallucination rates, cascading failure mechanics, AgentAsk error taxonomy, and multi-agent consensus patterns

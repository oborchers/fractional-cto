---
name: source-evaluation
description: "This skill should be used when evaluating source credibility, deciding which search results to trust, choosing between search providers, detecting SEO spam or content farms, selecting domain-specific sources (academic, medical, legal, technical), evaluating software packages or libraries, comparing tools or technologies, assessing GitHub repo health, checking adoption metrics, or when research quality depends on retrieval quality. Covers the source credibility taxonomy (T1-T6 tiers), CRAAP framework adaptation, multi-provider search strategy, artifact evaluation framework (health/adoption/authority signals for packages, repos, APIs, standards, technologies), and source quality anti-patterns."
version: 1.1.0
---

# Source Evaluation

Source quality is the primary bottleneck in research agent pipelines. Research on deep research agent trajectories found that over 57% of source errors occur in early retrieval stages, where initial fabrication acts as the primary catalyst for cascading downstream errors (arXiv 2601.22984). A single bad source in the first retrieval round contaminates the entire research trajectory.

## Source Credibility Tiers

Every source encountered during research falls into one of six tiers. Always prefer higher-tier sources and cite the tier when reporting findings.

| Tier | Source Type | Examples | Trust Level |
|------|-----------|----------|-------------|
| **T1 — Primary** | Peer-reviewed journals, official specs, primary datasets | Nature, Science, IEEE, IETF RFCs, W3C specs | Highest |
| **T2 — Institutional** | Government agencies, established research institutions | NIH, WHO, NIST, ACM Digital Library | High |
| **T3 — Expert** | Named expert blogs, conference proceedings, major tech engineering blogs | Anthropic blog, Google Research, NeurIPS/ICML papers | Moderate-High |
| **T4 — Quality Editorial** | Major publications with editorial review | MIT Technology Review, Ars Technica, The Verge | Moderate |
| **T5 — Community** | Well-moderated forums, high-reputation answers | Stack Overflow (high-score), GitHub discussions | Low-Moderate |
| **T6 — Unverified** | Content farms, SEO-optimized articles, anonymous posts, AI-generated content | Medium listicles, affiliate blogs, uncredited tutorials | Do not cite |

**Rule:** Never cite T6 sources. Prefer T1-T3 for factual claims. Use T4-T5 for context and community consensus only.

## The CRAAP Framework — Automated Signals

Adapted from the CRAAP framework (CSU Chico), five dimensions for evaluating sources:

| Dimension | What to Check | Red Flags |
|-----------|--------------|-----------|
| **Currency** | Publication date, last-modified headers | No date visible, information predates major changes in the field |
| **Relevance** | Does it address the specific research question? | Tangential coverage, keyword-stuffed but shallow |
| **Authority** | Who published it? Credentials? | Anonymous author, no institutional affiliation, no citations |
| **Accuracy** | Are claims sourced? Can they be verified? | No inline citations, contradicts known facts, round numbers without source |
| **Purpose** | Is it informing, selling, or persuading? | High ad density, affiliate links, promotional language |

Note: CRAAP evaluates surface features. Use it as an initial filter, not the sole credibility signal (Stanford research found reliance on CRAAP alone makes researchers susceptible to misinformation).

## Multi-Provider Search Strategy

Different search providers excel in different domains. Route queries to the appropriate provider:

| Provider | Best For | Limitations |
|----------|---------|-------------|
| **WebSearch (general)** | Broad topics, recent events, technical documentation | May surface SEO-optimized content |
| **arXiv / Semantic Scholar** | Academic ML/AI research, preprints | Not peer-reviewed, may be superseded |
| **PubMed** | Medical, biomedical, clinical research | Limited to biomedical domain |
| **Official documentation** | API specs, library usage, framework guides | May lag behind actual behavior |
| **GitHub** | Code examples, implementation patterns, issue discussions | Quality varies widely |

**Strategy:** Start with domain-appropriate providers. Use general web search to fill gaps. Cross-reference findings across multiple providers when possible.

## SEO Spam Detection

Red flags that indicate low-quality, SEO-optimized content:

- **Listicle format** with no depth ("Top 10 ways to...")
- **Keyword stuffing** — the search term appears unnaturally often
- **No author attribution** or author has no verifiable expertise
- **High ad-to-content ratio**
- **Recycled/syndicated content** appearing verbatim across multiple domains
- **AI-generated markers** — generic phrasing, lack of specific examples, overly smooth prose
- **Affiliate links** embedded throughout

When a source triggers 2+ red flags, discard it and search for a higher-quality alternative.

## Artifact Evaluation

Research often involves evaluating non-content artifacts — packages, tools, technologies, standards, organizations. These require different signals than content sources. Every artifact has three signal dimensions:

| Dimension | What It Measures | Key Question |
|-----------|-----------------|--------------|
| **Health** | Is it alive and maintained? | When was the last meaningful activity? |
| **Adoption** | Does anyone actually use it? | What are the real usage numbers? |
| **Authority** | Who's behind it and are they credible? | Is this backed by a credible entity? |

### Artifact Types and Key Signals

| Artifact Type | Health Signals | Adoption Signals | Authority Signals |
|---------------|---------------|-----------------|-------------------|
| **Software packages** | Last commit, release frequency, open issue response time | Downloads (npm weekly, PyPI monthly), dependents count | Maintainer reputation, organizational backing, license |
| **GitHub repos** | Commit frequency, PR merge time, stale issue ratio | Stars, forks, contributor count | Bus factor (>1 critical), corporate sponsor, notable users |
| **APIs/Services** | Uptime history, changelog frequency, deprecation notices | Customer logos, integration count, community size | Company funding, revenue stability, enterprise adoption |
| **Standards/Specs** | Last revision date, errata activity | Implementation count, conformance test suites | Standards body status (draft/proposed/standard), industry backing |
| **Technologies** | Release cadence, roadmap activity, CVE response time | Stack Overflow survey ranking, job postings, TIOBE/RedMonk index | Backing organization, governance model, ecosystem size |
| **Architectural patterns** | Recent case studies, active community discussion | Industry adoption breadth, conference talk frequency | Documented at-scale deployments, known failure case studies |
| **People/Authors** | Recent publication activity | Citation count, h-index, follower count | Institutional affiliation, industry role, peer recognition |
| **Companies/Orgs** | Recent funding, hiring activity, product releases | Revenue, customer count, market share | Investor quality, leadership track record, industry awards |
| **Communities** | Messages per week, new member rate | Member count, active member ratio | Moderation quality, notable members, signal-to-noise ratio |
| **Datasets/Benchmarks** | Last update, known issues addressed | Citation count, leaderboard participation | Creator credentials, methodology transparency, peer review |
| **Claims/Statistics** | Date of study, methodology recency | Citation count, replication status | Funding source, sample size, peer review, original source |

### Red Flags by Artifact Type

**Software packages and repos:**
- Last commit >6 months ago with open issues unanswered
- Fewer than 50 stars with no organizational backing
- Single maintainer (bus factor = 1) for critical dependency
- No tests, no CI, no changelog
- License incompatible with intended use

**Technologies and standards:**
- No major release in 12+ months
- Declining Stack Overflow activity trend
- Abandoned by original backing organization
- No conformance test suite (for standards)

**Claims and statistics:**
- No original source cited (circular citation)
- Study funded by party with commercial interest in the outcome
- Sample size <100 for quantitative claims
- No methodology description

**General rule:** When an artifact triggers 2+ red flags, flag it explicitly in the research output. Do not recommend it without noting the risks.

For detailed per-artifact-type evaluation guides and how to check each signal programmatically, consult `references/artifact-signals.md`.

## Retrieval Best Practices

1. **Front-load quality** — The first retrieval round disproportionately determines research quality due to the saturation bottleneck (agents fixate on early results). Start with high-authority sources.
2. **Search iteratively** — Refine search queries based on initial results. First search identifies terminology; second search uses domain-specific terms.
3. **Diversify sources** — Do not rely on a single provider or a single source for any claim. Cross-reference across independent sources.
4. **Verify fetched content** — After WebFetch, scan the content for authority signals (author credentials, citations, publication venue) before incorporating.
5. **Track provenance** — Record which source produced which claim. This metadata is essential for citation and for tracing errors.

## Retrieval Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **Single-provider dependency** | All searches go through one provider | Route by domain; use multiple providers |
| **First-result trust** | Accepting the top search result without evaluation | Evaluate credibility tier before incorporating |
| **Equal credibility** | Treating a blog post the same as a journal paper | Apply tier system; weight higher-tier sources |
| **Ignoring retrieval failures** | Silent fallback when search returns nothing useful | Log the gap; try alternative queries or providers |
| **Breadth without depth** | Fetching 20 URLs but reading none carefully | Fetch fewer sources; read each thoroughly |

## Reference Files

For detailed provider comparison, domain-specific source guides, and artifact evaluation:
- **`references/provider-comparison.md`** — Detailed comparison of search providers with API specifics, rate limits, and optimal use cases
- **`references/artifact-signals.md`** — Per-artifact-type evaluation guides with health/adoption/authority thresholds, how to check each signal, and the quick evaluation checklist

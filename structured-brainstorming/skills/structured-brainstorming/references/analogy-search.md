# Analogy Search

## What It Is

Find the same problem solved in a different domain and transfer the solution pattern. The most creative solutions often come from recognizing that a problem in domain A has already been solved in domain B under a different name.

**Counteracts:** Local search. LLMs explore solutions adjacent to the problem domain. Analogy search forces cross-domain thinking — looking for structural similarities between seemingly unrelated problems.

## Step-by-Step Process

1. **Abstract the problem.** Strip domain-specific language. Turn "how should we handle user session management in our web app?" into "how do systems track and expire temporary access grants?"
2. **Identify the core pattern.** What is the structural essence? Examples:
   - Session management → temporary token with expiry and revocation
   - Rate limiting → resource allocation under scarcity
   - Caching → trading freshness for speed with an invalidation strategy
   - Feature flags → runtime behavior switching with rollback
3. **Search for the pattern in other domains.** Where else does this pattern appear?
   - Other software domains (operating systems, networking, databases, game engines)
   - Physical systems (logistics, manufacturing, biology, economics)
   - Historical solutions (how did pre-digital systems solve this?)
4. **For each analogy found, extract the transferable insight.** What did the other domain learn about this pattern that applies here?
5. **Adapt the insight to the original problem.** What concrete design decision does this analogy suggest?

## Domain Crossing Map

Common problem patterns and where to find analogies:

| Problem Pattern | Look In |
|----------------|---------|
| Scaling / load distribution | Logistics, supply chain, traffic engineering |
| Consistency / conflict resolution | Legal systems, parliamentary procedure, version control |
| Access control / authorization | Physical security, military clearance, library systems |
| Caching / freshness | Grocery supply chain, news syndication, DNS |
| Queue management / prioritization | Hospital triage, airport boarding, CPU scheduling |
| Error recovery / resilience | Aviation safety, power grid design, biological immune systems |
| Migration / transition | Urban planning, biological evolution, language shift |
| Monitoring / alerting | Medical vital signs, industrial SCADA, weather forecasting |

## Application Prompts

- "What is this problem called in [another domain]?"
- "How did [operating systems / networking / databases] solve this?"
- "What's the physical-world equivalent of this problem?"
- "If this weren't software, how would it be solved?"
- "What would a [logistics expert / biologist / economist] recognize in this problem?"

## Using WebSearch for Analogies

When exploring analogies in depth, use WebSearch to find cross-domain solutions:
- Search for the abstracted pattern, not the domain-specific problem
- Example: instead of "microservice communication patterns", search "distributed coordination protocols" or "supply chain communication networks"
- Look for academic papers, conference talks, and blog posts from unexpected domains
- Search for the problem pattern + "lessons from [other domain]"

## Common Pitfalls

- **Surface-level analogies.** "A database is like a filing cabinet" is not useful. The analogy needs to transfer a specific insight about the problem, not just be a metaphor.
- **Not abstracting enough.** If the abstracted problem still contains domain-specific language, keep abstracting. "How do web servers handle concurrent requests" still lives in the software domain. "How do systems with limited resources handle simultaneous demand" opens up logistics, economics, and biology.
- **Single-domain search.** Check at least 3 different domains before settling. The first analogy found is often the most obvious and least creative.
- **Forcing the analogy.** Not every analogy transfers cleanly. If the structural similarity breaks down under scrutiny, acknowledge it and move on rather than stretching the metaphor.

## When to Use

- The problem feels familiar but the standard solutions do not fit
- Looking for creative or unconventional approaches
- The user asks "how do others solve this?"
- Greenfield design where no established pattern exists in the problem domain
- Breaking out of domain-specific tunnel vision

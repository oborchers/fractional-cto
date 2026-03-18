---
name: stress-test-methodology
description: "This skill should be used when the user wants to stress-test a plan, review a plan for gaps, challenge assumptions in a planning document, run adversarial review, apply red-team/blue-team analysis to a plan, or asks 'is my plan sound', 'what am I missing', 'what could go wrong'. Covers the adversarial what-if methodology, verdict system, tool scope selection, and how to interpret stress test results."
version: 0.1.0
---

## Adversarial Plan Review

Adversarial plan review uses two independent agents with different roles to stress-test a planning document:

1. **Red team** (adversarial) -- reads the plan and surrounding artifacts, generates what-if questions targeting gaps, unverified assumptions, edge cases, and failure modes. Operates on local artifacts only to keep questions grounded.

2. **Blue team** (neutral analyst) -- receives the what-if questions and attempts to answer each using the plan, artifacts, and a configurable set of tools. Classifies each answer with a verdict.

The technique works because the agents have separate contexts: the red team generates challenges without knowing the answers, and the blue team answers without knowing which questions are easy or hard. Neither agent is biased toward defending or attacking the plan.

## When to Use

- Before committing to an implementation plan
- Before presenting a business plan or proposal to stakeholders
- After drafting a design document and before sharing it for review
- When you feel a plan is "done" but want to pressure-test it
- When surrounding context is rich enough to ground the analysis (codebase, supporting docs, config files)

## The Verdict System

The blue team classifies each answer:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **ANSWERED** | Plan or artifacts explicitly address the concern, with a quotable reference | No action needed |
| **PARTIALLY ADDRESSED** | Some coverage exists but gaps remain | Strengthen the relevant plan section |
| **NOT COVERED** | The plan has no answer -- genuine gap | Add coverage to the plan |
| **UNCERTAIN** | Cannot determine with available tools -- gap might or might not exist | Expand tool scope or investigate manually |

Focus your iteration on **NOT COVERED** and **UNCERTAIN** items. These are the plan's blind spots.

## Tool Scope

The blue team's tool scope determines how thoroughly it can verify claims:

**Local artifacts only** (Read, Grep, Glob)
- Best when: rich surrounding context (full codebase, detailed docs)
- Limitation: cannot verify claims about external systems, standards, or APIs
- UNCERTAIN verdicts may indicate the plan references things outside the artifacts

**+ Web research** (adds WebSearch, WebFetch)
- Best when: plan references external APIs, standards, benchmarks, or third-party services
- Allows the blue team to check documentation, specs, and industry practices
- Reduces UNCERTAIN verdicts for external dependency questions

**+ System verification** (adds Bash, MCP tools)
- Best when: plan makes assumptions about live systems (API responses, config values, resource limits)
- The blue team can query actual APIs, check live configurations, run diagnostics
- Most powerful -- turns assumptions into verified facts or confirmed gaps
- Requires the referenced systems to be accessible from the current environment

The red team always uses local artifacts only, regardless of scope selection.

## Interpreting Results

A healthy stress test typically shows:
- 40-60% ANSWERED -- the plan covers many concerns
- 10-20% PARTIALLY ADDRESSED -- some areas need strengthening
- 10-20% NOT COVERED -- genuine gaps to fill
- 5-15% UNCERTAIN -- areas needing more investigation

If most questions are ANSWERED, the plan is solid. If most are NOT COVERED, the plan needs significant revision before proceeding.

**Watch for false confidence**: an ANSWERED verdict is only as good as the evidence behind it. Check that ANSWERED items include specific references (plan sections, code paths, config values), not vague reassurances.

## Limitations

- The red team can only challenge what it can see. If critical context is in a separate repo, a Confluence page, or someone's head, the red team cannot generate questions about it.
- The blue team's ANSWERED verdicts depend on its tool scope. A local-only blue team marking something ANSWERED based on a code comment is weaker than a system-verification blue team confirming it against a live API.
- Neither agent understands organizational context (team capacity, political constraints, budget). These factors affect plan feasibility but are invisible to the agents.

## Running a Stress Test

Use the `/stress-test` command:

```
/stress-test path/to/plan.md
```

The command orchestrates the full flow: reads the plan, asks about tool scope, dispatches the red team, then the blue team, and presents a summary with action items.

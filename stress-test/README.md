# stress-test

Adversarial plan review using red-team/blue-team agents. Generates what-if questions that expose gaps in your planning documents, then grounds answers in your actual artifacts.

## How it works

1. **Red team** reads your plan and surrounding artifacts (codebase, docs, configs), generates adversarial what-if questions targeting gaps, unverified assumptions, edge cases, and failure modes
2. **Blue team** takes each what-if question and attempts to answer it using the plan and artifacts, classifying each with a verdict: ANSWERED, PARTIALLY ADDRESSED, NOT COVERED, or UNCERTAIN
3. You get a QA report highlighting exactly where your plan is solid and where it has blind spots

## Configurable tool scope

The blue team's verification power is configurable per session:

- **Local artifacts only** -- reads plan + codebase/docs. Fast, safe, no external calls
- **+ Web research** -- adds WebSearch/WebFetch for checking external API docs, standards, benchmarks
- **+ System verification** -- adds Bash/MCP for querying live APIs, checking configs, running diagnostics

The red team always uses local artifacts only to keep questions grounded.

## Works on any plan type

- Implementation plans (with codebase context)
- Business plans (with financial models, market research)
- Design documents (with existing system architecture)
- Research plans (with prior findings)

The key requirement: surrounding context must exist as local artifacts for the agents to reason against.

## Usage

```bash
/stress-test path/to/plan.md
```

## Components

| Component | Purpose |
|-----------|---------|
| `/stress-test` command | Orchestrates the full red-team/blue-team flow |
| `red-team` agent | Generates adversarial what-if questions (local-only) |
| `blue-team` agent | Answers what-ifs with verdicts and evidence (configurable tools) |
| `stress-test-methodology` skill | When/how to use adversarial plan review, verdict system |

## Installation

```bash
/plugin install stress-test@fractional-cto
```

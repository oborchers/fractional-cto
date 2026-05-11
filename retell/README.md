# retell

Transform Claude Code conversation transcripts into polished, first-person blog posts through an interactive 5-stage pipeline.

## The Problem

Claude Code conversations contain rich stories — creative journeys, architectural decisions, debugging sagas — but they're locked in multi-megabyte JSONL files that are 98% noise (tool results, progress events, file snapshots). A 15 MB conversation typically contains only ~338 KB of signal.

## How It Works

```
Stage 1: PARSE    (script, 0 tokens)   → events.json + manifest.json
Stage 2: TRIAGE   (Sonnet subagent)    → story angles, recommendation, context questions
Stage 3: OUTLINE  (Sonnet subagent)    → sections, beats, quotes, word estimates
Stage 4: DRAFT    (Opus)               → full blog post in first-person voice
Stage 5: POLISH   (Opus)               → revision loop until satisfied
```

**Interactive gates** between every stage — the human decides, the AI recommends.

**Typical cost:** ~$1.78 per blog post. Triage alone (to check if a conversation is worth it) costs ~$0.08.

## Quick Start

```bash
# Install the plugin
claude --plugin-dir /path/to/retell

# Start the pipeline (shows recent conversations to pick from)
/retell:retell

# Or provide a conversation UUID directly
/retell:retell 8c439a20
```

## Components

### Command

- **`/retell:retell [uuid]`** — Main pipeline orchestrator. Without a UUID, shows recent conversations for discovery. With a UUID, runs through all 5 stages interactively.

### Agents

- **triage-analyst** (Sonnet) — Assesses blog-worthiness, proposes 3-5 story angles with a argued recommendation, surfaces context questions for the author
- **outline-architect** (Sonnet) — Structures the post into sections with beat treatments, key quotes, and word count estimates

### Skills

- **conversation-format** — JSONL schema, entry types, signal classification, subagent linking, session boundary detection
- **narrative-craft** — Story arc detection, beat classification, quote handling, first-person voice rules, editorial principles

### Scripts

- **`scripts/parse-conversation.py`** — Stage 1 parser. Deterministic, zero tokens. Transforms raw JSONL into clean event streams.
- **`scripts/preview-conversations.py`** — Discovery tool. Lists recent conversations with blog-worthiness heuristics.

## Key Design Decisions

- **First-person voice is a hard constraint.** All blog posts are written from the author's perspective. Not configurable.
- **The LLM recommends, the human decides.** Every stage presents options and waits for approval.
- **Author context can be injected at any gate.** Backstory, intent, corrections, scope directives — the JSONL contains *what happened*, not *why it matters*.
- **Subagents are loaded on-demand.** Triage reads only the main conversation. Outline loads only the subagents relevant to the chosen angle.
- **One conversation, multiple posts.** The same conversation can yield different blog posts by picking different angles.

## Author Context

The pipeline supports injecting context the JSONL can't capture:

| Type | Example |
|------|---------|
| **Backstory** | "The brainstorming skill was built across 3 prior sessions" |
| **Intent** | "I started this because agencies charge $15K for brand identity" |
| **Audience** | "This is for solo consultants, not designers" |
| **Corrections** | "When I said 'elegant' I didn't mean it literally" |
| **Scope** | "Don't include the URL reverse-engineering tangent" |

## Prerequisites

- Python 3.9+
- Claude Code with plugin support
- Conversation files in `~/.claude/projects/`

## Limitations

- JSONL format is undocumented and may change with Claude Code updates
- Token estimates use a 4-bytes-per-token heuristic (can be off by 30-50%)
- Path encoding is lossy (hyphens in directory names create ambiguity)
- Thinking blocks should be treated as editorial source material, not quoted verbatim

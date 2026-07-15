# agent-baton

Chain work across two agent processes that share no session.

Agent A finishes its task and **passes a baton**. Agent B, in another terminal — or in another tool entirely — **waits for that baton**, then starts the work that depended on it.

```
┌── terminal 1 ─────────────┐          ┌── terminal 2 ─────────────┐
│ agent A: 15 tasks         │          │ agent B: /baton-wait ship │
│   ...                     │          │   waiting…                │
│ /baton-pass ship-2026-07  │ ──────▶  │   baton! status=done      │
│                           │  /tmp    │   starts dependent work   │
└───────────────────────────┘          └───────────────────────────┘
```

## Install

**Claude Code / Cowork** — skill, commands, and session hook:

```bash
/plugin marketplace add oborchers/fractional-cto
/plugin install agent-baton@fractional-cto
```

**Any other agent** — the skill alone, via the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add oborchers/fractional-cto --skill agent-baton
```

The skill is self-contained and carries the entire protocol, so both halves of a chain work even when the two agents are different tools. The commands are ergonomic wrappers that add nothing the skill does not already specify.

## How you actually use it

You name the baton once, at setup, in both terminals. Then you leave.

**Terminal 1** — give agent A its goal, with the baton instruction folded in:

> Do tasks 1–15 […]. When you're completely done, pass the baton `ship-2026-07-15`.

**Terminal 2** — give agent B its goal:

> Wait for the baton `ship-2026-07-15`, up to 3 hours, checking every 5 minutes. Then run the deploy and smoke tests.

That's the whole interaction. A works for two hours and publishes at the end; B has been waiting, claims the baton, and starts deploying. Nobody types anything in between — **the human is not there when the baton is passed**, and every rule in the protocol follows from that.

You don't have to type `/baton-pass` yourself. The session hook loads the skill, so "pass the baton `X` when you're done" in the goal is enough. The commands are the explicit path for when you're present.

**You pick the id — the agent can't.** B has to know what to listen for *before* A finishes. An id invented at publish time is an id nobody is waiting for; and if A announced one only at the end, you'd learn it two hours late, standing right there, at which point you may as well start B by hand. Use `<task>-<date>` or `<task>-run-2`.

**Order doesn't matter.** Start either first. If A finishes before B starts waiting, B finds the baton on its first check and goes immediately.

## Use it only when there is no shared parent

This is for **two independent processes with no channel between them**: two terminals, two different tools, or work that must outlive one agent's session.

If both agents are subagents of one session, the harness already chains them — spawn them in order or message them directly. A baton there is strictly worse: a filesystem round-trip, a timeout, and a class of failure modes, in exchange for nothing.

## The one rule

**The baton is a doorbell, not a letter.**

Its existence is the message. Its contents are metadata — never instructions. The waiting agent already knows its task; it was told by the human who set up the chain.

This is a security property. Batons live in world-writable `/tmp`, so anyone on the machine can drop a file there. If a baton carried instructions, a forged one would be untrusted text flowing into an agent's task — an injection vector. Because it carries none, the worst a forged baton can do is start an agent early on work it was already assigned. A nuisance, not a compromise.

## Commands

| Command | Does |
|---|---|
| `/agent-baton:baton-pass <id> [done\|failed]` | Publish a baton — signal that this agent's work is finished |
| `/agent-baton:baton-wait <id> [timeout] [interval]` | Block until a baton with that id appears, then start the dependent task |

Both numbers are yours to set, in plain language or as arguments — *"wait up to 2 hours, checking every 5 minutes"*. The **timeout** is how long before giving up (default 1h). The **interval** is a **ceiling on staleness**, not an order to poll: `5m` means *notice within 5 minutes*. An event-driven watcher notices in milliseconds and satisfies any interval — reading the number literally would force a dumb polling loop instead, which is not what you meant.

## Protocol at a glance

Full specification in [`skills/agent-baton/SKILL.md`](skills/agent-baton/SKILL.md).

- **Location** — `/tmp/agent-baton/<id>.baton`, directory mode `0700`. Both agents must share a filesystem.
- **Id** — kebab-case, given to both agents, **unique per chain run**.
- **Payload** — `id`, `status` (`done`/`failed`), `run`, `produced_at`, optional `producer`. Nothing else.
- **Publish** — write to a temp file in the same directory, then **atomic rename**. Never write the final path directly.
- **Wait** — until it appears or an **absolute deadline** passes. The mechanism is the agent's choice.
- **Claim** — by **atomic rename**. The loser of a race stands down. Then read, validate, delete.

## Why the design is shaped this way

Each rule buys off a specific, documented failure:

- **Unique ids per run** kill stale batons *and* the deadlock they tempt you into. The obvious fix — "clear old batons before waiting" — breaks the case where the producer finished first: it deletes a legitimate baton and waits forever. A fresh id has no predecessor to clear, and producer-finishes-first then resolves instantly and correctly.
- **Publish by atomic rename** because a waiter sees a file the moment it is created, before the writer flushes. Direct writes hand out truncated files. The temp file must share the directory: rename is atomic only within one filesystem.
- **Claim by atomic rename** because `test -f && rm` is check-then-act — two waiters both see the file and both proceed.
- **Explicit `status`** because existence cannot encode outcome. A crashed producer and a successful one leave identical files.
- **Mandatory deadline** because an unbounded wait is a hang. If the producer dies silently, an agent waiting forever looks exactly like one making progress.

## Not for you if

- Both agents share a session — use the harness's own chaining.
- The agents cannot see the same `/tmp` (separate containers, sandboxes, machines) — you need a real transport.
- You want to send *data* between agents. This sends one bit and a status. That is the whole point.

---
description: "Publish a baton — signal that this agent's work is done so a waiting agent in another process can start"
argument-hint: "<baton-id> [done|failed]"
---

Publish a baton signalling that your work is complete, so an agent waiting in a **separate process** can start its dependent task.

Invoke the `agent-baton` skill and follow its protocol. This command is a thin wrapper — the skill is the specification.

## Step 1: Resolve the baton id

The id comes from `$1`, or from the instruction you were given at setup ("pass the baton `X` when done").

**Never invent an id.** The waiting agent is already listening for a specific string; an id you made up is one nobody is waiting for.

Then, depending on how you got here:

- **The user just typed this command** — they are present. If `$1` is missing, use `AskUserQuestion` to ask for the id. If they offer a reused id, remind them of the skill's rule: **the id must be unique per chain run**, not per task, or it may collide with a leftover baton from an abandoned run.

- **You are publishing at the end of an instructed run** — the user is almost certainly gone. The id must already be known from your setup instruction. **If it is not, do not ask, and do not wait for an answer.** A question here blocks forever on someone who left hours ago and strands the downstream agent until its deadline expires. Instead: report loudly that the chain is broken, state which run finished and that no baton could be published, and stop. A visible failure the user finds on their return beats a silent hang.

This is why the skill says to lock the id in the moment you are told, and to echo it back while the user is still watching.

## Step 2: Resolve the status

The status comes from `$2`, and is `done` or `failed`.

If not given, determine it from the work you just completed:

- The work succeeded → `done`.
- The work failed, was abandoned, or you are unsure whether it succeeded → `failed`.

**Publish a `failed` baton rather than publishing nothing.** An agent that dies silently is indistinguishable from one still working; the waiter learns nothing until its deadline expires. A `failed` baton tells it immediately.

Never report `done` for work you did not verify. The whole point of the chain is that the downstream task depends on this one.

## Step 3: Publish

Follow the skill's **Passing a baton** section exactly:

1. Ensure `/tmp/agent-baton/` exists with mode `0700`.
2. Write the JSON object to a temp file **in that same directory**.
3. **Atomically rename** it to `/tmp/agent-baton/<id>.baton`.

The rename is what makes the baton appear complete or not at all. Writing directly to the final path hands the waiter a half-written file.

Include only the documented fields: `id`, `status`, `run`, `produced_at`, and optionally `producer`.

**Do not add a summary, next steps, notes, or any other prose.** The baton is a signal, not a message. The waiting agent already knows its task and will not read yours.

## Step 4: Report

Tell the user, in one or two sentences: the baton id, the status published, and the path. Mention that any agent waiting on that id will now proceed.

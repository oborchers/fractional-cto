---
description: "Synthesize a dense progress entry for the current branch and append/update it at the configured destination (markdown file, Linear ticket comment, or GitHub issue/PR comment). SHA-based idempotency means safe to re-run between phases."
argument-hint: "[--final] [--destination <type>:<id>] [--style-from <path>] [--ticket <id>]"
---

You are **synthesizing a progress entry** for the current branch and writing it to the configured destination. The output style is codified by the `planning-tools:progress-methodology` skill — one dense paragraph per branch, evidence-rich, with inline sub-markers (`Piggybacked:`, `Verification:`, `Out of scope:`).

This command is **safe to re-run** — SHA-based idempotency means a second run between phases only narrates the new commits; the existing prose is preserved.

**Input:** `$ARGUMENTS`

Parse arguments:
- `--final` → flip the entry to shipped state (prepend `**Shipped <today> via PR #<N>.**`, append `✅` to heading)
- `--destination <type>:<id>` → one-off destination override. Examples: `markdown:<path-to-progress-file>` (any path; the plugin does not assume `context/` or any other directory), `linear:<ticket-id>` (e.g., `linear:AIA-1234`), `github:<owner>/<repo>#<number>` (e.g., `github:oborchers/fractional-cto#42`). Does **not** persist to settings.
- `--style-from <path>` → use the entries in this file as style exemplars instead of pulling from the destination
- `--ticket <id>` → explicit source-ticket override (otherwise auto-detected from branch name)

Read the `planning-tools:progress-methodology` skill **before** Step 1 if you have not seen it this session — it owns the conventions every subsequent step depends on.

---

## Step 1 — Detect git context

Run one bash block. Lift from `/planning-tools:plan-tick` Step 1:

```bash
git rev-parse --is-inside-work-tree || { echo "ERROR: not in a git repo"; exit 1; }
ROOT="$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"
[ -z "$BRANCH" ] && { echo "ERROR: detached HEAD — /planning-tools:plan-progress requires a named branch"; exit 1; }
BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/main >/dev/null && BASE=main
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/master >/dev/null && BASE=master
[ -z "$BASE" ] && BASE=main
MERGE_BASE="$(git merge-base HEAD "$BASE" 2>/dev/null || git merge-base HEAD "origin/$BASE" 2>/dev/null)"
echo "ROOT=$ROOT"
echo "BRANCH=$BRANCH"
echo "BASE=$BASE"
echo "MERGE_BASE=$MERGE_BASE"
```

If not in a git repo or `BRANCH` is empty (detached HEAD), error with the message above and stop.

Compute the **branch slug** (used as the entry-key): strip leading `feature/`, `fix/`, `chore/`, `bugfix/`, `hotfix/`, or `<user>/` prefixes; lowercase; replace `_` and `/` with `-`. Save this as `BRANCH_SLUG`.

---

## Step 2 — Resolve the plan path (optional)

Reuse the discovery from `/planning-tools:plan-tick` Step 2 (branch-match + recency fallback):

1. Glob `*.md` under `$ROOT/context/tickets/`, `$ROOT/docs/plans/`, `$ROOT/.claude/plans/master/`. Filter to files containing `## Implementation Phases`.
2. **1 candidate:** use it.
3. **2+ candidates — branch-match selection** (same normalization as plan-tick): match candidates whose normalized basename is a substring of the normalized branch name. Pick the single match, or most-recently-modified among matches, or fall back to most-recently-modified overall.
4. **0 candidates:** proceed with **no plan**. Warn the user: `No master plan matched branch <BRANCH>. Synthesizing progress from commits + style exemplars only — piggyback detection disabled.`

If a plan is found, read it and extract:
- Phase table rows (Phase number + Scope cell text) — passed to the synthesizer as `phase_scopes[]`
- Plan path — passed to the synthesizer

---

## Step 3 — Read plugin settings

Read `$ROOT/.claude/planning-tools.local.md` if it exists. Parse YAML frontmatter:

```bash
SETTINGS="$ROOT/.claude/planning-tools.local.md"
if [ -f "$SETTINGS" ]; then
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$SETTINGS")
  CONFIGURED_DEST_TYPE=$(echo "$FRONTMATTER" | grep '^progress_destination:' | sed 's/progress_destination: *//' | sed 's/^"\(.*\)"$/\1/')
  CONFIGURED_DEST_ID=$(echo "$FRONTMATTER" | grep '^progress_destination_id:' | sed 's/progress_destination_id: *//' | sed 's/^"\(.*\)"$/\1/')
  CONFIGURED_TICKET_PROVIDER=$(echo "$FRONTMATTER" | grep '^ticket_provider:' | sed 's/ticket_provider: *//' | sed 's/^"\(.*\)"$/\1/')
fi
```

Treat missing values as empty.

---

## Step 4 — Resolve the destination

**Priority order:**

1. **`--destination <type>:<id>` flag** → use it; do not persist.
2. **Configured destination** (from Step 3) → use it.
3. **No saved destination** → prompt via the canonical **binary `AskUserQuestion`** pattern. Probe the repo for an existing PROGRESS file first so the recommendation matches reality.

### Capability filter

Probe environment availability before offering destinations:

- `markdown` — always available.
- `linear` — available iff the Linear MCP tools are loaded (`mcp__linear-server__get_issue` is callable). If not loaded, suppress from the offered list.
- `github` — available iff `gh` is on `PATH` (`command -v gh` returns success).

### Discover existing PROGRESS files

Before recommending a markdown path, probe the repo with a shallow glob (no hardcoded `context/` assumption — the user may keep progress at root, `docs/`, `notes/`, or somewhere else entirely):

```bash
EXISTING_PROGRESS=$(find "$ROOT" -maxdepth 3 -type f \
  \( -iname 'PROGRESS.md' -o -iname 'CHANGELOG.md' -o -iname 'CHANGES.md' \) \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' \
  -print 2>/dev/null | head -5)
```

If one or more matches → pick the **most-recently-modified** (`ls -t`) as the recommended default. If multiple matches exist, mention the others in the printed list so the user can override via `--destination`.

If zero matches → no recommendation can presume a path; the binary prompt's recommended option becomes "Cancel — I'll supply a path via --destination".

### Binary-confirm pattern (per the 4-option cap rule)

Print the available destinations as a plain-text numbered list with one-line hints. The markdown row's hint mentions the **discovered path** (if any), not a hardcoded one:

```
Choose a progress destination:
  1. markdown — Append entries to a project-local markdown file. Discovered: <discovered-path or "no PROGRESS file found in the repo">.
  2. linear — Post entries as comments on a Linear ticket (auto-detected from branch or set via --ticket).
  3. github — Post entries as comments on a GitHub issue or PR.
```

(Omit the rows for unavailable providers.)

Then call `AskUserQuestion` with exactly **two** options. The phrasing of Option 1 branches on whether a PROGRESS file was discovered:

- **If an existing PROGRESS file was discovered:**
  - **Option 1 (recommended):** `"Use existing markdown file at <discovered-path>"` — description: "Save markdown:<discovered-path> as the destination. Future /plan-progress runs skip this prompt."
  - **Option 2:** `"Cancel — I'll specify a different destination"` — description: "Stop now. Re-run /planning-tools:plan-progress --destination <type>:<id> to choose a different option (e.g., linear:AIA-1234, github:org/repo#42, markdown:<your-path>)."

- **If no PROGRESS file was discovered:**
  - **Option 1 (recommended):** `"Cancel — I'll specify a path via --destination"` — description: "Stop now. Re-run /planning-tools:plan-progress --destination markdown:<your-path> with the path where this project keeps progress logs (e.g., markdown:PROGRESS.md at root, markdown:docs/PROGRESS.md, markdown:context/PROGRESS.md — your choice)."
  - **Option 2:** `"Create new file at PROGRESS.md (repo root)"` — description: "Save markdown:PROGRESS.md as the destination and create the file at the repository root. Use this only if you want a fresh PROGRESS.md at the top level — most projects have a conventional location, in which case Cancel and re-run with --destination."

Per the `AskUserQuestion` schema, the harness adds an "Other" path automatically — the user can free-text any path there as well.

On **Proceed (Option 1 with discovered path, OR Option 2 with PROGRESS.md fallback)**: persist the chosen destination to `$ROOT/.claude/planning-tools.local.md`:

```yaml
---
progress_destination: markdown
progress_destination_id: <resolved-path>
---

# planning-tools settings

Generated by /planning-tools:plan-progress on <today>. Edit this file directly to switch
destinations, or run /planning-tools:plan-progress --destination <type>:<id> for a one-off override.
```

Create `.claude/` if it does not exist. After writing, check whether `.claude/*.local.md` is in `$ROOT/.gitignore`. If not, emit an instruction line for the user (do **not** modify `.gitignore` automatically):

```
Note: add `.claude/*.local.md` to .gitignore — this file should not be committed.
```

On **Cancel**: stop with `Cancelled. Re-run with --destination <type>:<id> to skip this prompt — e.g., /planning-tools:plan-progress --destination markdown:<your-progress-path>.`

### No-path-assumption rule

Nothing in this command hardcodes `context/` or any other directory as the progress-file location. The only exception is the fallback `PROGRESS.md` at the **repository root** offered in the no-PROGRESS-discovered branch — and even there, the user must opt in by choosing Option 2; the default (Option 1) is Cancel. The user's project convention drives the path; the plugin discovers, suggests, or asks — it does not assume.

### Parse the destination

After resolution, parse `<type>:<id>` into `DEST_TYPE` and `DEST_ID`. For `markdown`, `DEST_ID` is a file path (relative to `$ROOT` unless absolute). For `linear`, `DEST_ID` is the ticket identifier (`AIA-1234`). For `github`, `DEST_ID` is `<owner>/<repo>#<number>`.

---

## Step 5 — Resolve the source ticket (optional)

**Priority order:**

1. **`--ticket <id>` flag** → use it.
2. **Auto-detect from branch name** — regex-match `BRANCH` for ticket patterns in this order:
   - Linear-style: `[A-Z]{2,6}-\d+` (e.g., `AIA-4174`)
   - GitHub-style: `#\d+` (after a slash, e.g., `feat/#42`)
3. **No flag, no match** → proceed without source ticket. The synthesizer handles missing input gracefully.

If a ticket is resolved:

- Determine the provider from `CONFIGURED_TICKET_PROVIDER` (if set), else from the destination type (if `DEST_TYPE=linear` or `=github`), else infer from the ID format.
- **Fetch via the source adapter** (see the `progress-methodology` skill's adapter contract):
  - `linear`: `mcp__linear-server__get_issue(id)` → title, body, status, url; then `mcp__linear-server__list_comments(issueId)` → **all comments, no cap** (per the comment-fetch policy in `progress-methodology`).
  - `github`: `gh issue view <N> --repo <owner>/<repo> --json title,body,state,url,comments` (or `gh pr view`).
- Assemble `{ title, body, comments[], status, url }` to pass to the synthesizer.

If the required MCP/CLI is unavailable, **fail loudly**: `Linear MCP not loaded — cannot fetch <ticket>. Re-run with --ticket <id> on a session that has the Linear MCP, or omit ticket context.` Do not proceed.

---

## Step 6 — Find the existing entry at the destination

Use the destination adapter's `find_existing_entry(identifier)` (per the `progress-methodology` skill):

### markdown

Read `DEST_ID` (the file path; relative paths resolve under `$ROOT`). If the file does not exist, treat as `no match`. Otherwise grep the file for `<!-- planning-tools:plan-progress entry-key:$BRANCH_SLUG -->`. If found, capture the entry body from the marker line through the next `## ` heading or EOF (whichever comes first). Otherwise, `no match`.

### linear

Call `mcp__linear-server__list_comments(issueId=DEST_ID)`. For each comment body, grep for the marker. If found, capture `{ comment_id, body }`. Otherwise, `no match`.

### github

Call `gh issue view <N> --repo <owner>/<repo> --comments --json comments` (or `gh pr view` if the ID resolves to a PR). For each comment, grep for the marker. If found, capture `{ comment_id, body }` (comment ID from the GitHub REST API node ID). Otherwise, `no match`.

---

## Step 7 — Three-way branch on detection result

| Detection | Action |
|---|---|
| **No match** | Set verdict=`NEW_ENTRY`. No user prompt yet (apply gate handles it). |
| **Match, no `✅`** | Set verdict=`IN_FLIGHT_UPDATE`. No user prompt yet. |
| **Match, has `✅`** | **3-option `AskUserQuestion`** before synthesis: `"Refresh completed entry"` / `"Create new entry"` / `"Cancel"`. On `Refresh` → verdict=`COMPLETED_REFRESH`. On `Create new entry` → verdict=`NEW_ENTRY` (the existing entry stays in place; new entry gets a `-v2` suffix on the entry-key marker to avoid collision). On `Cancel` → stop. |

---

## Step 8 — Fetch style exemplars

If `--style-from <path>` was passed, read that file and use the entries inside as exemplars.

Otherwise:

- **markdown destination:** Read `DEST_ID`. Parse out the 2 most-recent entries (top of file, since entries are prepended). Exclude the in-flight entry currently being updated.
- **linear / github destination:** Look through the prior comments fetched in Step 6. Capture the 2 most-recent comments containing a `planning-tools:plan-progress entry-key:` marker.

If fewer than 1 prior entry is available, fall back to `<plugin>/skills/progress-methodology/examples/sample-entry.md`.

---

## Step 9 — Resolve PR metadata (only if `--final`)

If `--final` was passed, fetch PR metadata:

```bash
gh pr list --head "$BRANCH" --json number,url --limit 1 2>/dev/null
```

If the result is non-empty, capture `pr_number` and `pr_url`. If empty (no PR open for the branch yet), set both to null — the synthesizer will emit `**Shipped <date>.**` without the PR clause.

---

## Step 10 — Dispatch the synthesizer agent

Use the Agent tool with `subagent_type: plan-progress-synthesizer` (sonnet). The agent prompt must include, as separate labeled sections:

- Plan path (or `"none"`)
- Phase scopes (the parsed Scope cells; or `"none"`)
- Branch + base + merge-base
- Commit log (`git log <merge-base>..HEAD --pretty=format:'%h %an %ad%n%s%n%b%n---'`)
- Diff stats (`git diff <merge-base>..HEAD --stat`)
- Diff name-only (`git diff <merge-base>..HEAD --name-only`)
- Existing entry body (or `"none"`)
- Style exemplars (1-3 entries verbatim)
- Source-ticket context block (or `"none"`)
- Destination type (`markdown` / `linear` / `github`)
- Today's date
- `--final` and PR metadata (if applicable)
- Pre-resolved verdict (one of `NEW_ENTRY`, `IN_FLIGHT_UPDATE`, `COMPLETED_REFRESH`)

The agent returns a structured report including the verdict, the entry body verbatim, any low-confidence piggyback notes, and caveats.

---

## Step 11 — Apply gate

**If verdict is `NO_CHANGES`** (entry has `✅`, no new commits): report `Nothing to do — entry is complete and no new commits since last update.` and stop.

**Otherwise**, present the proposed body to the user:

- **For `NEW_ENTRY`:** Print the proposed entry body in a fenced block. Ask via **binary `AskUserQuestion`**: `"Append to <destination>"` / `"Discard"`.
- **For `IN_FLIGHT_UPDATE`:** Print a unified diff of the existing entry vs the new body (use `diff -u` over temp files, or hand-roll a brief diff if `diff` unavailable). Ask via binary `AskUserQuestion`: `"Update <destination>"` / `"Discard"`.
- **For `COMPLETED_REFRESH`:** Print the proposed refreshed body. Ask `"Apply refresh to <destination>"` / `"Discard"`.

Surface any low-confidence `Piggybacked?:` notes from the synthesizer **above** the AskUserQuestion so the user can edit before approving (the user edits the proposed body manually after `Discard`-ing and re-running).

On `Discard`: stop without writing. On approval: proceed to Step 12.

---

## Step 12 — Apply via destination adapter

### markdown

- **NEW_ENTRY:** Prepend the new body to `DEST_ID` (newest-first ordering). Add a trailing `---` separator before the next entry if the file is non-empty. If the file does not exist, create it with the entry as the only content.
- **IN_FLIGHT_UPDATE / COMPLETED_REFRESH:** Use Edit with the existing entry section (marker line through next `## ` or EOF) as `old_string` and the new body as `new_string`. Anchor by entry-key marker for uniqueness.

### linear

- **NEW_ENTRY:** `mcp__linear-server__save_comment(issueId=DEST_ID, body=<new body>)`.
- **IN_FLIGHT_UPDATE / COMPLETED_REFRESH:** `mcp__linear-server__save_comment(id=<existing comment_id>, body=<new body>)` — `save_comment` updates when `id` is supplied.

### github

- **NEW_ENTRY:** `gh issue comment <N> --repo <owner>/<repo> --body <body>` (or `gh pr comment` if the ID is a PR).
- **IN_FLIGHT_UPDATE / COMPLETED_REFRESH:** Update the existing comment via the REST API:
  ```bash
  gh api repos/<owner>/<repo>/issues/comments/<comment-id> -X PATCH -f body="$NEW_BODY"
  ```

For all destinations: write the entry-key marker as the literal first line of the body.

---

## Step 13 — Report

Output a single concluding line summarizing what was applied:

```
<verdict>: <N new commits narrated> → <destination type>:<destination id-or-path> (<url-if-applicable>).
```

If a plan was not matched, also note: `(no plan matched branch; piggyback detection skipped)`.

If `--final` was applied, also note the PR number / URL or `(no PR found)`.

---

## Mandatory Use of AskUserQuestion

The main conversation owns all user interaction. Subagents (the synthesizer) never call `AskUserQuestion`.

- **Step 4 destination prompt** (only if no `--destination` flag and no saved destination) — **binary** confirm.
- **Step 7 completed-entry branch** — **3-option** question (within the 4-option cap, FIXED shape, safe).
- **Step 11 apply gate** — binary confirm per verdict.

Per `[[askuserquestion-4option-cap]]`, never use multi-select with dynamic-length options.

## Strict no-modify rules

- Never edits the master plan. Plan-tick owns phase ticking.
- Never auto-commits or auto-pushes. The user controls when commits happen.
- Never modifies `.gitignore`. Emits a note for the user to do it manually.
- Never silently downgrades destinations. If the configured destination's adapter is unavailable, fails loudly.

## Notes

- This command is **safe to re-run** between phases. SHA-based idempotency ensures only new commits drive new prose; existing SHA citations are preserved verbatim.
- For the canonical style spec, sub-marker order, adapter contracts, and three-way detection rules, see the `planning-tools:progress-methodology` skill.
- For branch + plan matching mechanics, this command lifts directly from `/planning-tools:plan-tick` — same normalization, same fallback chain.

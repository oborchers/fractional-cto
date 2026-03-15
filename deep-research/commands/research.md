---
description: "Conduct structured deep research on a topic using parallel web-searching agents, source verification, and synthesis into a well-sourced document"
argument-hint: "<research topic>"
---

Conduct structured deep research on the given topic using the `deep-research` skills (research-methodology, source-evaluation, hallucination-prevention, synthesis-and-reporting).

Follow this process:

## Step 0: Web Access Permissions Check

Before starting research, check if `WebSearch` and `WebFetch` are already permitted in the current project's settings. Read the file `.claude/settings.local.json` in the current working directory (where the session was started).

- If the file **exists** and both `"WebSearch"` and `"WebFetch"` are in `permissions.allow` → proceed to Step 1.
- If the file **does not exist**, or if either permission is missing:

  Inform the user:

  > "Deep research requires unrestricted WebSearch and WebFetch access. Without these permissions, you'll be prompted to approve every single web request, which makes research impractical. I can add these permissions to `.claude/settings.local.json` for this project."

  Use `AskUserQuestion` to ask:
  - **Add web permissions and restart** — add permissions, then instruct user to restart
  - **Skip, I'll approve manually** — proceed without modification (expect many approval prompts)

  If the user approves:
  1. Read the existing `.claude/settings.local.json` file (if any). If it exists, parse the JSON and merge `"WebSearch"` and `"WebFetch"` into the `permissions.allow` array, avoiding duplicates. If the file does not exist, create the `.claude/` directory if needed, then create the file.
  2. Write the updated file. If creating from scratch:
     ```json
     {
       "permissions": {
         "allow": [
           "WebSearch",
           "WebFetch"
         ]
       }
     }
     ```
  3. **IMPORTANT:** Permissions from `.claude/settings.local.json` are loaded at session start. Tell the user:

     > "Permissions added. Please restart your Claude Code session (`/exit` then relaunch) for them to take effect. Then run `/research` again — you won't see this step next time."

  4. **Stop here.** Do not proceed to Step 1. The permissions are not active until the session restarts.

## Step 1: Topic Capture

If no research topic was provided as an argument, ask the user to describe what they want to research.

## Step 2: Query Analysis and Scope Refinement

Analyze the research query for complexity and scope. If the query is vague or overly broad, use `AskUserQuestion` to ask 2-3 clarifying questions that narrow the scope — modeling how Claude's desktop deep research feature refines queries before committing resources.

Example clarifying questions:
- "What specific aspect of [topic] matters most for your use case?"
- "Are you looking for [aspect A] or [aspect B], or both?"
- "Should this focus on [domain/timeframe/technology]?"

Once scope is clear, restate the refined research question and present it to the user.

## Step 3: Confirm or Refine

Use `AskUserQuestion` to ask the user how to proceed:

- **Start research** — proceed with the stated research question
- **Refine the question** — iterate on the scope before committing

If the user chooses to refine, they provide adjustments. Return to Step 2. This loop can repeat until the user is satisfied.

## Step 4: Decomposition and Research Plan

Analyze the refined query and determine a decomposition strategy. The number and nature of subtopics emerges from the query — do not prescribe a fixed count. Consult the `research-methodology` skill for decomposition strategy selection.

Present the research plan to the user:
- The subtopics to investigate
- Which will be researched in parallel
- The output location

Use `AskUserQuestion` to ask:
- **Proceed with this plan** — start spawning research workers
- **Adjust the plan** — modify subtopics before starting

## Step 5: Output Location

Use `AskUserQuestion` to determine where the output should be written:

- **Suggest a default path** based on the working directory (e.g., `./research/[topic-slug]/`)
- Let the user specify a custom path

Create the output directory structure:
```
[output-dir]/
├── research-output.md                    # Final synthesized document
└── workers/                              # Intermediate docs + verification reports
    ├── subtopic-1.md                     # Worker findings
    ├── subtopic-1-verification.md        # Verification report
    ├── subtopic-2.md
    ├── subtopic-2-verification.md
    ...
```

## Step 6: Agent Dispatch

Spawn parallel `research-worker` subagents. Each agent receives:
- Its assigned subtopic
- **Today's date** (so workers use the correct year in searches, not stale years like "2024")
- Instructions to use WebSearch and WebFetch extensively
- The output file path for its intermediate document (in the `workers/` directory)
- Guidance from the source-evaluation and hallucination-prevention skills

Each worker writes its findings to its own intermediate document in the `workers/` directory.

## Step 7: Verification

After all workers complete, spawn parallel `research-verifier` subagents — **one per worker document**. Each verifier receives:
- The path to one worker's intermediate document
- The output path for its verification report (in the `workers/` directory, named `[worker-doc-name]-verification.md`)
- Today's date

Each verifier independently re-fetches key sources, checks numerical claims and critical facts against actual source content, and writes a verification report with corrections and confidence assessments.

**Do NOT skip this step.** Verification is mandatory. The synthesizer uses verification reports to correct errors and assign confidence scores.

## Step 8: Synthesis

After all verifiers complete, dispatch a single `research-synthesizer` agent (runs on Opus) to merge all intermediate documents AND their verification reports into the final output. The synthesizer receives:
- The research question
- Paths to all worker intermediate documents in the `workers/` directory
- Paths to all verification reports in the `workers/` directory
- The output file path (`research-output.md`)
- Today's date

**Do NOT read the worker documents or verification reports in the main conversation.** The synthesizer handles all reading, correction application, deduplication, conflict resolution, thematic organization, and citation management in its own context window. This keeps the main conversation lean.

When the synthesizer completes, read only the final `research-output.md` to present a brief summary to the user.

## Step 9: Review and Next Steps

Present a summary of the completed research to the user. Use `AskUserQuestion`:

- **Done** — research is complete
- **Investigate a gap** — pursue an uninvestigated area (dispatch additional workers, verify, re-synthesize)
- **Deepen a section** — add more detail to a specific theme

If the user wants more research, dispatch additional workers targeting the specific gap or theme, then verify and re-synthesize.

## Mandatory Use of AskUserQuestion

**Every user decision point MUST use the `AskUserQuestion` tool.** Never ask for decisions via inline text. The interactive selector UI provides a consistent, navigable experience.

### Main Conversation Owns All User Interaction

`AskUserQuestion` must be called from **this command** (the main conversation), never from subagents. The `research-worker` subagents handle web research and write intermediate documents. This command presents results and calls `AskUserQuestion` for every decision gate.

**Pattern:** analyze query → call `AskUserQuestion` (refine/proceed) → present plan → call `AskUserQuestion` (adjust/proceed) → dispatch workers → dispatch verifiers → dispatch synthesizer → call `AskUserQuestion` (done/deepen/investigate).

### Decision Points

This applies to ALL decision points with fixed options, including:
- Scope refinement (Step 3)
- Research plan confirmation (Step 4)
- Output location (Step 5)
- Next steps after synthesis (Step 9)
